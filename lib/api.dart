import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pips API client — Dart port of pips-android Api.java.
/// Every endpoint of https://pips-next.vercel.app/api with the {ok}/{ok,data} envelopes.
class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, this.status);
  @override
  String toString() => message;
}

class Progress {
  final int done, total;
  Progress(this.done, this.total);
}

class PipsApi {
  static const String base = 'https://pips-next.vercel.app';
  static const String api = '$base/api';
  static const int singleLimit = 4 * 1024 * 1024;
  static const int chunkSize = 2 * 1024 * 1024;

  static String? session;
  static String? username;

  /// All previously logged-in accounts (multi-account switcher).
  /// Each entry: {'username': '…', 'session': '…'} — newest first.
  static List<Map<String, String>> accounts = [];

  static Future<void> loadSession() async {
    final p = await SharedPreferences.getInstance();
    session = p.getString('pips_session');
    username = p.getString('pips_user');
    accounts = (p.getStringList('pips_accounts') ?? const [])
        .map((s) {
          try {
            return Map<String, String>.from(jsonDecode(s) as Map);
          } catch (_) {
            return <String, String>{};
          }
        })
        .where((m) => (m['session'] ?? '').isNotEmpty)
        .toList();
    if (session != null && session!.isNotEmpty && username != null && username!.isNotEmpty) {
      _upsertAccount(username!, session!);
    }
  }

  static void _upsertAccount(String user, String cookie) {
    accounts.removeWhere((a) => a['username'] == user);
    accounts.insert(0, {'username': user, 'session': cookie});
  }

  static Future<void> _persistAccounts() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('pips_accounts', accounts.map((a) => jsonEncode(a)).toList());
  }

  static Future<void> _saveSession(String? s, String? user) async {
    final p = await SharedPreferences.getInstance();
    session = s;
    username = user;
    if (s == null) {
      await p.remove('pips_session');
      await p.remove('pips_user');
      if (user != null) {
        accounts.removeWhere((a) => a['username'] == user);
        await _persistAccounts();
      }
    } else {
      await p.setString('pips_session', s);
      await p.setString('pips_user', user ?? '');
      if (user != null && user.isNotEmpty) {
        _upsertAccount(user, s);
        await _persistAccounts();
      }
    }
  }

  /// Instantly switch to a previously logged-in account (no re-login).
  static Future<void> switchAccount(String user) async {
    final a = accounts.firstWhere((x) => x['username'] == user, orElse: () => const <String, String>{});
    if ((a['session'] ?? '').isEmpty) throw ApiException('Account not found on this device.', 0);
    await _saveSession(a['session'], user);
  }

  /// Remove a saved account from the switcher (its session is discarded).
  static Future<void> removeAccount(String user) async {
    accounts.removeWhere((a) => a['username'] == user);
    await _persistAccounts();
  }

  static Map<String, String> get _headers => {
        if (session != null && session!.isNotEmpty) 'Cookie': 'pips_session=$session',
        'User-Agent': 'PipsApp/3.11 (Flutter)',
      };

  static Map<String, String> get authHeaders => _headers;

  static ApiException _err(String body, int status) {
    try {
      final j = jsonDecode(body);
      final err = j is Map ? j['error'] : null;
      if (err is String && err.isNotEmpty) return ApiException(err, status);
      if (err is Map) {
        return ApiException(err['message'] ?? err['code'] ?? 'Request failed', status);
      }
    } catch (_) {}
    const m = {401: 'Please login to continue.', 403: 'Not allowed.', 404: 'Not found.', 413: 'Too large — use chunked upload.', 429: 'Too many requests — slow down.'};
    return ApiException(m[status] ?? 'Request failed ($status).', status);
  }

  static Future<String> _exec(String method, String url, {Object? body, Map<String, String>? extraHeaders}) async {
    try {
      final req = http.Request(method, Uri.parse(url));
      req.headers.addAll(_headers);
      if (extraHeaders != null) req.headers.addAll(extraHeaders);
      if (body is String) {
        req.body = body;
      } else if (body is List<int>) {
        req.bodyBytes = body;
      }
      final streamed = await req.send().timeout(const Duration(seconds: 120));
      final resp = await http.Response.fromStream(streamed);
      if (!resp.statusCode.toString().startsWith('2')) throw _err(resp.body, resp.statusCode);
      return resp.body;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Network error — check your connection.', 0);
    }
  }

  static Map<String, dynamic> _json(String raw) {
    if (raw.isEmpty) return {};
    try {
      final j = jsonDecode(raw);
      if (j is Map && j['data'] is Map) return Map<String, dynamic>.from(j['data']);
      if (j is Map) return Map<String, dynamic>.from(j);
    } catch (_) {}
    return {};
  }

  static List<dynamic> _arr(String raw) {
    try {
      final t = raw.trim();
      final j = jsonDecode(t);
      if (j is List) return j;
      if (j is Map && j['data'] is List) return j['data'];
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>> _req(String method, String url, [Map<String, dynamic>? body]) async =>
      _json(await _exec(method, url, body: body == null ? null : jsonEncode(body), extraHeaders: {'Content-Type': 'application/json'}));

  static String enc(String s) => Uri.encodeQueryComponent(s);

  // ---------------------------------------------------------------- auth
  static Future<Map<String, dynamic>> me() => _req('GET', '$api/me');

  static Future<void> login(String user, String pass) async {
    final resp = await http.post(Uri.parse('$api/login'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'username': user, 'password': pass}));
    if (!resp.statusCode.toString().startsWith('2')) throw _err(resp.body, resp.statusCode);
    final cookie = _extractSession(resp.headers['set-cookie'] ?? '');
    if (cookie == null) throw ApiException('No session returned — try again.', 0);
    await _saveSession(cookie, user.toLowerCase());
  }

  static String? _extractSession(String setCookie) {
    for (final part in setCookie.split(';')) {
      final p = part.trim();
      if (p.startsWith('pips_session=')) {
        final v = p.substring('pips_session='.length);
        if (v.isNotEmpty && v != '""') return v;
      }
    }
    return null;
  }

  static Future<void> logout() async {
    try { await _req('POST', '$api/logout', {}); } catch (_) {}
    await _saveSession(null, null);
  }

  /// Creates an instant guest account (after Firebase anonymous sign-in) and
  /// signs into it — same Set-Cookie flow as [login].
  static Future<void> guest() async {
    final resp = await http.post(Uri.parse('$api/guest'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({}));
    if (!resp.statusCode.toString().startsWith('2')) throw _err(resp.body, resp.statusCode);
    final cookie = _extractSession(resp.headers['set-cookie'] ?? '');
    if (cookie == null) throw ApiException('No session returned — try again.', 0);
    final j = _json(resp.body);
    await _saveSession(cookie, (j['username'] ?? 'guest').toString());
  }

  static Future<Map<String, dynamic>> checkUsername(String u) => _req('GET', '$api/account/check?username=${enc(u)}');
  static Future<Map<String, dynamic>> signupStart(String u, String email, String method) =>
      _req('POST', '$api/signup/start', {'username': u, 'email': email, 'method': method});
  static Future<Map<String, dynamic>> signupVerify(String u, String otp) =>
      _req('POST', '$api/verify', {'username': u, 'otp': otp});
  static Future<Map<String, dynamic>> signupConfirm(String u, String token) =>
      _req('POST', '$api/signup/confirm', {'username': u, 'token': token});
  static Future<Map<String, dynamic>> signupStatus(String u) => _req('GET', '$api/signup/status?username=${enc(u)}');
  static Future<void> resendOtp(String u) => _req('POST', '$api/verify/resend', {'username': u});

  static Future<void> signupFinish(String user, String pass) async {
    final resp = await http.post(Uri.parse('$api/signup/finish'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'username': user, 'password': pass}));
    if (!resp.statusCode.toString().startsWith('2')) throw _err(resp.body, resp.statusCode);
    final cookie = _extractSession(resp.headers['set-cookie'] ?? '');
    await _saveSession(cookie, user.toLowerCase());
  }

  static Future<void> forgotPassword(String u) => _req('POST', '$api/password/forgot', {'username': u});

  // ---------------------------------------------------------------- account
  static Future<Map<String, dynamic>> account() => _req('GET', '$api/account');
  static Future<Map<String, dynamic>> createKey(String label) => _req('POST', '$api/account/key', {'label': label});
  static Future<void> revokeKey(String id) => _req('POST', '$api/account/key/revoke', {'id': id});

  // ---------------------------------------------------------------- files & folders
  static Future<List<dynamic>> files() async => _arr(await _exec('GET', '$api/files'));
  static Future<List<dynamic>> filesAll() async => _arr(await _exec('GET', '$api/files/all'));
  static Future<List<dynamic>> filesRecent(int limit) async => _arr(await _exec('GET', '$api/files/recent?limit=${limit < 1 ? 1 : limit}'));
  static Future<Map<String, dynamic>> filesTree([String? folder]) =>
      _req('GET', '$api/files/tree${folder != null && folder.isNotEmpty ? '?folder=${enc(folder)}' : ''}');
  static Future<List<dynamic>> filesTrash() async => _arr(await _exec('GET', '$api/files/trash'));

  /// Queue a server-side import: the backend fetches `url` in the background
  /// and stores the file in Pips cloud — safe to close the app right after.
  /// Returns the pending entry ({id, name, size, import_status: importing}).
  static Future<Map<String, dynamic>> importUrl(String url, {String vis = 'public'}) =>
      _req('POST', '$api/v1/files/import-url', {'url': url, 'visibility': vis});

  /// Full metadata for one file (includes import_status while importing).
  static Future<Map<String, dynamic>> fileInfo(String id) =>
      _req('GET', '$api/files/info?id=${enc(id)}');

  static Future<void> trashRestore(String id) => _req('POST', '$api/files/trash/restore', {'id': id});
  static Future<void> trashPurge(String id) => _req('POST', '$api/files/trash/purge', {'id': id});
  static Future<Map<String, dynamic>> search(String q, [String? type]) =>
      _req('GET', '$api/v1/search?q=${enc(q)}&per_page=50${type != null && type.isNotEmpty ? '&type=${enc(type)}' : ''}');
  static Future<void> setVisibility(String id, String vis) => _req('POST', '$api/visibility', {'id': id, 'visibility': vis});
  static Future<void> deleteFile(String id) => _req('POST', '$api/delete', {'id': id});

  static Future<List<dynamic>> folders() async {
    final r = await _req('GET', '$api/v1/folders');
    return r['folders'] is List ? r['folders'] : [];
  }
  static Future<Map<String, dynamic>> createFolder(String path) => _req('POST', '$api/v1/folders', {'path': path});
  static Future<void> renameFolder(String id, String name) => _req('PATCH', '$api/v1/folders/$id', {'name': name});
  static Future<void> deleteFolder(String id) => _req('DELETE', '$api/v1/folders/$id');

  static Future<Map<String, dynamic>> fileGet(String id) => _req('GET', '$api/v1/files/$id');
  static Future<Map<String, dynamic>> filePatch(String id, Map<String, dynamic> changes) => _req('PATCH', '$api/v1/files/$id', changes);
  static Future<Map<String, dynamic>> fileCopy(String id, String folder) => _req('POST', '$api/v1/files/$id/copy', {'folder': folder});
  static Future<Map<String, dynamic>> fileMove(String id, String folder) => _req('POST', '$api/v1/files/$id/move', {'folder': folder});
  static Future<List<dynamic>> versions(String id) async {
    final r = await _req('GET', '$api/v1/files/$id/versions');
    return r['versions'] is List ? r['versions'] : [];
  }
  static Future<void> restoreVersion(String id, int v) => _req('POST', '$api/v1/files/$id/restore', {'version': v});
  static Future<Map<String, dynamic>> signedUrl(String id, int expires) => _req('POST', '$api/v1/files/$id/signed-url', {'expires': expires});

  static String viewUrl(String id) => '$api/view?id=$id';
  static String downloadUrl(String id) => '$api/download?id=$id';
  static String versionDownloadUrl(String id, int v) => '$api/v1/files/$id/versions/$v/download';

  // ---------------------------------------------------------------- Pips DB
  static Future<List<dynamic>> dbFiles() async => _arr(await _exec('GET', '$api/db/files'));
  static Future<Map<String, dynamic>> dbCreate(String name, String content, String vis) =>
      _req('POST', '$api/db/create', {'name': name, 'content': content, 'visibility': vis});
  static Future<String> dbRead(String id) async {
    final r = await _req('GET', '$api/db/read?id=${enc(id)}');
    final lines = r['lines'];
    if (lines is! List) return '';
    return lines.map((e) => e.toString()).join('\n');
  }
  static Future<void> dbWrite(String id, String content) => _req('POST', '$api/db/write', {'id': id, 'content': content});
  static Future<void> dbEditLine(String id, int line, String action, String text) =>
      _req('POST', '$api/db/edit', {'id': id, 'line': line, 'action': action, 'text': text});
  static Future<void> dbMove(String id, String path) => _req('POST', '$api/db/move', {'id': id, 'path': path});
  static Future<void> dbRemove(String id) => _req('POST', '$api/db/remove', {'id': id});
  static Future<void> dbRestore(String id, int v) => _req('POST', '$api/v1/db/$id/restore', {'version': v});

  // ---------------------------------------------------------------- social & notifications
  static Future<List<dynamic>> socialUsers([String q = '']) async {
    final r = await _req('GET', '$api/social/users?q=${enc(q)}');
    return r['users'] is List ? r['users'] : [];
  }
  static Future<void> follow(String u) => _req('POST', '$api/social/follow', {'username': u});
  static Future<void> unfollow(String u) => _req('POST', '$api/social/unfollow', {'username': u});
  static Future<List<dynamic>> inbox() async {
    final r = await _req('GET', '$api/social/inbox');
    return r['inbox'] is List ? r['inbox'] : [];
  }
  static Future<List<dynamic>> chat(String peer) async {
    final r = await _req('GET', '$api/social/chat?with=${enc(peer)}');
    return r['messages'] is List ? r['messages'] : [];
  }
  static Future<Map<String, dynamic>> sendMessage(String to, String text, [String? fileId]) =>
      _req('POST', '$api/social/message', {'to': to, 'text': text, if (fileId != null && fileId.isNotEmpty) 'file_id': fileId});
  static Future<void> like(String peer, String msgId) => _req('POST', '$api/social/like', {'with': peer, 'id': msgId});

  /// Profile photo of [username] (7-day signed URL) or null when unset.
  static Future<String?> avatarUrl(String username) async {
    try {
      final r = await _req('GET', '$api/social/avatar?username=${enc(username)}');
      final u = (r['url'] ?? '').toString();
      return u.isEmpty ? null : u;
    } on ApiException {
      return null;
    }
  }

  /// Set/replace my profile photo from an image file (≤ 5 MB).
  static Future<Map<String, dynamic>> setAvatar(File f, String name, String mime) async {
    final bytes = await f.readAsBytes();
    final req = http.MultipartRequest('POST', Uri.parse('$api/social/avatar'));
    req.headers.addAll(_headers);
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: name, contentType: MediaType.parse(mime.isEmpty ? 'image/png' : mime)));
    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    if (!resp.statusCode.toString().startsWith('2')) throw _err(resp.body, resp.statusCode);
    return _json(resp.body);
  }
  static Future<List<dynamic>> notifications() async {
    final r = await _req('GET', '$api/notifications');
    return r['notifications'] is List ? r['notifications'] : [];
  }
  static Future<void> notificationsRead([String? id]) => _req('POST', '$api/notifications/read', {if (id != null) 'id': id});
  static Future<void> report(String message) => _req('POST', '$api/report', {'message': message});

  // ---------------------------------------------------------------- channels (Terabox-style public collections)
  static Future<Map<String, dynamic>> channelsMine() => _req('GET', '$api/channels/mine');
  static Future<List<dynamic>> channelsPublic([String q = '']) async {
    final r = await _req('GET', '$api/channels/public?q=${enc(q)}');
    return r['channels'] is List ? r['channels'] : [];
  }
  static Future<Map<String, dynamic>> channelGet(String cid) => _req('GET', '$api/channels/${enc(cid)}');
  static Future<Map<String, dynamic>> channelCreate(String name, String description, [String? posterFileId]) =>
      _req('POST', '$api/channels/create', {'name': name, 'description': description, if (posterFileId != null && posterFileId.isNotEmpty) 'poster_file_id': posterFileId});
  static Future<Map<String, dynamic>> channelPatch(String cid, Map<String, dynamic> changes) => _req('PATCH', '$api/channels/${enc(cid)}', changes);
  static Future<void> channelDelete(String cid) => _req('DELETE', '$api/channels/${enc(cid)}');
  static Future<Map<String, dynamic>> channelAddFile(String cid, String fileId, [String title = '', String description = '']) =>
      _req('POST', '$api/channels/${enc(cid)}/files', {'file_id': fileId, 'title': title, 'description': description});
  static Future<void> channelRemoveFile(String cid, String fileId) => _req('DELETE', '$api/channels/${enc(cid)}/files/${enc(fileId)}');
  static Future<Map<String, dynamic>> channelPatchFile(String cid, String fileId, Map<String, dynamic> changes) =>
      _req('PATCH', '$api/channels/${enc(cid)}/files/${enc(fileId)}', changes);

  /// Watch history of a channel video (who + when) — owner only.
  static Future<List<dynamic>> channelFileViews(String cid, String fileId) async {
    final r = await _req('GET', '$api/channels/${enc(cid)}/files/${enc(fileId)}/views');
    return r['views'] is List ? r['views'] : [];
  }

  // ---------------------------------------------------------------- comments
  static Future<List<dynamic>> channelComments(String fileId) async {
    final r = await _req('GET', '$api/channels/files/${enc(fileId)}/comments');
    return r['comments'] is List ? r['comments'] : [];
  }

  static Future<Map<String, dynamic>> channelAddComment(String fileId, String text) =>
      _req('POST', '$api/channels/files/${enc(fileId)}/comments', {'text': text});

  /// Toggle a like/dislike on a comment. vote = 'like' | 'dislike'.
  static Future<Map<String, dynamic>> channelVoteComment(String fileId, String mid, String vote) =>
      _req('POST', '$api/channels/files/${enc(fileId)}/comments/${enc(mid)}/vote', {'vote': vote});
  static Future<List<dynamic>> channelSearchFiles(String cid, String q) async {
    final r = await _req('GET', '$api/channels/${enc(cid)}/search?q=${enc(q)}');
    return r['files'] is List ? r['files'] : [];
  }
  static Future<List<dynamic>> channelsGlobalFileSearch(String q) async {
    final r = await _req('GET', '$api/channels/search_files?q=${enc(q)}');
    return r['files'] is List ? r['files'] : [];
  }
  /// YouTube-style home feed: newest videos across all public channels.
  static Future<List<dynamic>> channelFeed([String q = '']) async {
    final r = await _req('GET', '$api/channels/feed?q=${enc(q)}');
    return r['videos'] is List ? r['videos'] : [];
  }

  // ---------------------------------------------------------------- uploads
  /// Single-shot upload (<= 4 MB) with progress.
  static Future<Map<String, dynamic>> uploadSingle(File f, String name, String mime, String vis, void Function(Progress) cb) async {
    final bytes = await f.readAsBytes();
    final req = http.MultipartRequest('POST', Uri.parse('$api/upload'));
    req.headers.addAll(_headers);
    req.fields['visibility'] = vis;
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: name, contentType: MediaType.parse(mime)));
    final streamed = await req.send();
    final done = bytes.length;
    cb(Progress(done, done));
    final resp = await http.Response.fromStream(streamed);
    if (!resp.statusCode.toString().startsWith('2')) throw _err(resp.body, resp.statusCode);
    return _json(resp.body);
  }

  static Future<Map<String, dynamic>> uploadInit(String name, int size) => _req('POST', '$api/upload/init', {'name': name, 'size': size});
  static Future<Set<int>> uploadStatus(String id) async {
    final r = await _req('GET', '$api/upload/status?id=${enc(id)}');
    final parts = r['parts_done'];
    return parts is List ? parts.map((e) => (e as num).toInt()).toSet() : {};
  }
  static Future<Map<String, dynamic>> uploadChunk(String id, int index, List<int> chunk) async {
    final req = http.MultipartRequest('POST', Uri.parse('$api/upload/chunk'));
    req.headers.addAll(_headers);
    req.fields['id'] = id;
    req.fields['index'] = '$index';
    req.files.add(http.MultipartFile.fromBytes('chunk', chunk, filename: 'part-$index'));
    final resp = await http.Response.fromStream(await req.send());
    if (!resp.statusCode.toString().startsWith('2')) throw _err(resp.body, resp.statusCode);
    return _json(resp.body);
  }
  static Future<Map<String, dynamic>> uploadFinish(String id, int chunks, int size, String name, String mime, String vis) =>
      _req('POST', '$api/upload/finish', {'id': id, 'chunks': chunks, 'size': size, 'name': name, 'mime': mime, 'visibility': vis});

  static Future<List<int>> getBytes(String url) async {
    final resp = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 120));
    if (!resp.statusCode.toString().startsWith('2')) throw _err(resp.body, resp.statusCode);
    return resp.bodyBytes;
  }

  static Future<String> getString(String url) async => utf8.decode(await getBytes(url));

  static Future<File> downloadToFile(String url, File out, void Function(Progress) cb) async {
    final req = http.Request('GET', Uri.parse(url))..headers.addAll(_headers);
    final streamed = await req.send();
    if (!streamed.statusCode.toString().startsWith('2')) {
      // Surface the server's error message (e.g. secure-play videos in
      // public channels return 403 "downloads are disabled").
      var msg = 'Download failed (${streamed.statusCode}).';
      try {
        final body = await streamed.stream.bytesToString();
        final j = json.decode(body);
        if (j is Map && j['error'] is String && (j['error'] as String).isNotEmpty) {
          msg = j['error'] as String;
        }
      } catch (_) {}
      throw ApiException(msg, streamed.statusCode);
    }
    final sink = out.openWrite();
    int done = 0;
    try {
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        done += chunk.length;
        cb(Progress(done, streamed.contentLength ?? 0));
      }
    } finally {
      await sink.close();
    }
    return out;
  }
}

/// tiny mime parser to avoid extra deps
class DiolessMime {
  static dynamic parse(String mime) => mime; // http package accepts MediaType via http_parser; keep string fallback
}
