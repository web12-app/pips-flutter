import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

/// Error from the local you-get server (or a transport failure reaching it).
class LocalYgError implements Exception {
  final String message;
  final bool botCheck;
  final int status;
  LocalYgError(this.message, {this.botCheck = false, this.status = 0});
  @override
  String toString() => message;
}

/// Client for the Pips local you-get server running on THIS phone.
///
/// The server (assets/pips_local/server.py, port 8787) lives inside
/// ReTerminal's Alpine Linux session — a one-time human setup, guided by
/// YtLocalPage. Android apps share the loopback interface, so Pips reaches
/// it with zero permissions. Downloads run on the phone's own (residential)
/// network, which normally clears YouTube's bot check without cookies.
class LocalYg {
  LocalYg._();

  static const int port = 8787;
  static const String token = 'pips-local-yg-2026';
  static const String reTerminalPackage = 'com.rk.terminal';
  static const String reTerminalMain = 'com.rk.terminal.ui.activities.terminal.MainActivity';

  static String get base => 'http://127.0.0.1:$port';

  static Map<String, String> get _h => {'X-Pips-Token': token};

  static Future<Map<String, dynamic>> _req(
      String method, String path, [Map<String, dynamic>? body]) async {
    final req = http.Request(method, Uri.parse('$base$path'));
    req.headers.addAll(_h);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final streamed = await req.send().timeout(const Duration(seconds: 90));
    final resp = await http.Response.fromStream(streamed);
    Map<String, dynamic> j;
    try {
      final d = jsonDecode(resp.body);
      j = d is Map ? Map<String, dynamic>.from(d) : {'ok': false, 'error': 'Bad response'};
    } catch (_) {
      j = {'ok': false, 'error': 'Bad response (${resp.statusCode})'};
    }
    j['status'] = resp.statusCode;
    return j;
  }

  /// Health check — null when the server is offline.
  static Future<Map<String, dynamic>?> health() async {
    try {
      final j = await _req('GET', '/health');
      return j['ok'] == true ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// Video metadata (title, duration, available qualities as `itags`).
  static Future<Map<String, dynamic>> meta(String url) async {
    final j = await _req('POST', '/meta', {'url': url});
    if (j['ok'] != true) {
      final err = (j['error'] ?? 'metadata failed').toString();
      throw LocalYgError(err, botCheck: j['bot_check'] == true, status: j['status'] is int ? j['status'] as int : 0);
    }
    final d = j['data'];
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  /// Start a download; returns the job id.
  static Future<String> download(String url, String itag) async {
    final j = await _req('POST', '/download', {'url': url, 'itag': itag});
    if (j['ok'] != true) {
      final err = (j['error'] ?? 'could not start download').toString();
      throw LocalYgError(err, botCheck: j['bot_check'] == true, status: j['status'] is int ? j['status'] as int : 0);
    }
    return (j['job'] ?? '').toString();
  }

  /// Live job state: {status, percent, mb, mbps, size, seconds, tail, log}.
  static Future<Map<String, dynamic>> job(String id) => _req('GET', '/job/$id');

  static Future<void> delete(String id) => _req('GET', '/delete/$id');

  /// Stream the finished file from the server.
  static Future<LocalFileStream> file(String id) async {
    final req = http.Request('GET', Uri.parse('$base/file/$id'))..headers.addAll(_h);
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    if (!streamed.statusCode.toString().startsWith('2')) {
      String msg = 'file not ready (${streamed.statusCode})';
      try {
        final b = await streamed.stream.bytesToString();
        final d = jsonDecode(b);
        if (d is Map && d['error'] is String && (d['error'] as String).isNotEmpty) {
          msg = d['error'] as String;
        }
      } catch (_) {}
      throw LocalYgError(msg, status: streamed.statusCode);
    }
    return LocalFileStream(streamed.stream, streamed.contentLength ?? 0);
  }
}

/// Pull-based wrapper over the /file stream (a single-subscription stream):
/// keeps one live subscription, buffers events, and hands out exactly the
/// number of bytes requested (e.g. 2 MB upload chunks) without losing
/// leftovers.
class LocalFileStream {
  final int size;
  final BytesBuilder _buf = BytesBuilder(copy: true);
  final List<Completer<void>> _waiters = [];
  StreamSubscription<List<int>>? _sub;
  bool _done = false;
  Object? _err;
  int read = 0;
  bool closed = false;

  LocalFileStream(Stream<List<int>> stream, this.size) {
    _sub = stream.listen(
      (c) {
        _buf.add(c);
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
      onError: (Object e) {
        _err = e;
        _wake();
      },
      cancelOnError: true,
    );
  }

  void _wake() {
    while (_waiters.isNotEmpty) {
      final w = _waiters.removeAt(0);
      if (!w.isCompleted) w.complete();
    }
  }

  /// Exactly [count] bytes, or the remaining bytes on EOF.
  Future<List<int>> nextBytes(int count) async {
    while (_buf.length < count) {
      if (_done || _err != null) break;
      final w = Completer<void>();
      _waiters.add(w);
      await w.future;
    }
    if (_buf.isEmpty) {
      if (_err != null) throw LocalYgError('connection closed: $_err');
      if (!closed) throw LocalYgError('connection closed before the file finished');
    }
    final all = _buf.takeBytes();
    final part = all.length >= count ? all.sublist(0, count) : all;
    if (all.length > count) _buf.add(all.sublist(count));
    read += part.length;
    return part;
  }

  double get progress => size > 0 ? read / size : 0;

  Future<void> close() async {
    if (closed) return;
    closed = true;
    try {
      await _sub?.cancel();
    } catch (_) {}
  }
}

/// One-time ephemeral HTTP server on 127.0.0.1:8788 that hands the bundled
/// setup files (server.py + setup.sh) to the phone's ReTerminal session over
/// the shared loopback — no shared storage, no permissions.
class SetupFileServer {
  static const int port = 8788;
  HttpServer? _srv;
  final Map<String, String> _files = {};
  bool _starting = false;

  bool get running => _srv != null;
  static String get url => 'http://127.0.0.1:$port';

  Future<void> start() async {
    if (_srv != null || _starting) return;
    _starting = true;
    try {
      _files['server.py'] = await rootBundle.loadString('assets/pips_local/server.py');
      _files['setup.sh'] = await rootBundle.loadString('assets/pips_local/setup.sh');
      _srv = await HttpServer.bind(InternetAddress.loopbackIPv4, port, shared: false);
      _srv!.listen(_handle, onError: (_) {});
    } finally {
      _starting = false;
    }
  }

  void _handle(HttpRequest req) {
    final name = req.uri.pathSegments.isEmpty ? '' : req.uri.pathSegments.last;
    final body = _files[name];
    final out = req.response;
    if (body == null) {
      out.statusCode = 404;
      out.close();
      return;
    }
    out.statusCode = 200;
    out.headers.contentType = name.endsWith('.py')
        ? ContentType('text', 'x-python')
        : name.endsWith('.sh')
            ? ContentType('text', 'x-shellscript')
            : ContentType.text;
    out.write(body);
    out.close();
  }

  Future<void> stop() async {
    try {
      await _srv?.close(force: true);
    } catch (_) {}
    _srv = null;
  }
}

/// Launches ReTerminal (if installed) so the user can run the one-time setup
/// in its Alpine session. Returns false when it is not installed.
Future<bool> openReTerminal() async {
  if (!Platform.isAndroid) return false;
  try {
    final p = await Process.start('am', [
      'start',
      '-n',
      '${LocalYg.reTerminalPackage}/${LocalYg.reTerminalMain}',
    ]);
    final outFut = (p.stdout.transform(utf8.decoder)).join();
    final errFut = (p.stderr.transform(utf8.decoder)).join();
    final code = await p.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => 0);
    final err = await errFut.timeout(const Duration(seconds: 2), onTimeout: () => '');
    final out = await outFut.timeout(const Duration(seconds: 2), onTimeout: () => '');
    if (code != 0 || err.contains('Error') || out.contains('Error')) return false;
    return true;
  } catch (_) {
    return false;
  }
}
