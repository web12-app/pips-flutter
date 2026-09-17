import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_youtube_downloader/flutter_youtube_downloader.dart';
import '../api.dart';
import '../models.dart';
import '../services/notifications.dart';
import '../widgets.dart';
import 'yt_connect_page.dart';
import 'yt_local_page.dart';

class UploadQueue extends ChangeNotifier {
  static final instance = UploadQueue._();
  UploadQueue._();
  final jobs = <UploadJob>[];
  final imports = <ServerImport>[];
  Timer? _importTimer;

  void add(UploadJob j) {
    PipsNotify.i.requestPermission(); // Android 13+ POST_NOTIFICATIONS
    jobs.insert(0, j);
    notifyListeners();
    j.run(notifyListeners);
  }

  void clearFinished() { jobs.removeWhere((j) => j.done || j.failed); notifyListeners(); }

  /// Track a server-side URL import and poll its status until done/failed.
  void trackImport(ServerImport im) {
    PipsNotify.i.requestPermission();
    imports.insert(0, im);
    notifyListeners();
    _pollImports();
  }

  void removeImport(ServerImport im) {
    imports.remove(im);
    notifyListeners();
  }

  void _pollImports() {
    if (_importTimer != null) return;
    _importTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final active = imports.where((i) => i.active).toList();
      if (active.isEmpty) {
        _importTimer?.cancel();
        _importTimer = null;
        return;
      }
      var changed = false;
      for (final im in active) {
        try {
          final f = await PipsApi.fileInfo(im.id);
          final st = (f['import_status'] ?? '').toString();
          if (st == 'done') {
            im
              ..status = 'done'
              ..size = int.tryParse('${f['size'] ?? 0}') ?? im.size;
            final n = (f['name'] ?? '').toString();
            if (n.isNotEmpty) im.name = n; // worker renames to the video title
            changed = true;
          } else if (st == 'failed') {
            final msg = f['import_error'];
            im
              ..status = 'failed'
              ..error = (msg is String && msg.isNotEmpty) ? msg : 'Import failed';
            changed = true;
          } else if (im.size == 0) {
            final s = int.tryParse('${f['size'] ?? 0}') ?? 0;
            if (s > 0) {
              im.size = s;
              changed = true;
            }
          }
        } catch (_) {}
      }
      if (changed) notifyListeners();
    });
  }
}

/// A server-side URL import queued on the Pips backend — the backend worker
/// fetches the file from the source URL, so the import keeps running even if
/// the app is closed or the phone goes offline. kind: 'url' (any file URL) or
/// 'youtube' (yt-dlp download at best quality, filed in its own title folder).
class ServerImport {
  final String id;
  final String kind;
  String name;
  int size;
  String status; // importing | done | failed
  String? error;

  /// Source URL (for YouTube imports — used by "Download on this phone").
  final String? url;
  ServerImport({required this.id, required this.name, required this.size, required this.status, this.error, this.kind = 'url', this.url});
  bool get active => status == 'importing';
}

/// Card shown for server-side URL imports (Uploads tab + Add-new-files sheet).
Widget importCard(BuildContext context, ServerImport im, {VoidCallback? onRemove}) {
  final (icon, color) = _UploadSheetState.iconFor(im.name);
  final tone = im.status == 'failed' ? AppTheme.red : (im.status == 'done' ? AppTheme.green : AppTheme.blue);
  final sub = [
    if (im.size > 0) fmtBytes(im.size),
    im.kind == 'youtube' ? 'YouTube · best quality' : 'from URL',
    im.status == 'importing'
        ? 'Importing on Pips cloud…'
        : im.status == 'done'
            ? 'Imported ✓'
            : (im.error ?? 'Import failed'),
  ].join(' · ');
  return Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: HomeColors.of(context).surfaceSoft, borderRadius: BorderRadius.circular(13), border: Border.all(color: HomeColors.of(context).line)),
    child: Row(children: [
      IconTile(icon: icon, bg: color.withValues(alpha: 0.14), fg: color, size: 36),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(im.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 2),
        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: im.status == 'failed' ? AppTheme.red : Colors.grey)),
        if (im.kind == 'youtube' && (im.status == 'failed' || im.status == 'importing'))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (im.status == 'failed' && (im.error?.toLowerCase().contains('bot') ?? false))
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const YtConnectPage())),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                  child: const Text('Allow YouTube Cookies', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppTheme.blue)),
                ),
              if ((im.url ?? '').isNotEmpty)
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => YtLocalPage(initialUrl: im.url))),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                  child: const Text('Download on this phone', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppTheme.teal)),
                ),
            ]),
          ),
      ])),
      if (im.active)
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
      else ...[
        const SizedBox(width: 6),
        Icon(im.status == 'done' ? Icons.check_circle : Icons.error_outline, size: 19, color: tone),
        if (onRemove != null) ...[
          const SizedBox(width: 6),
          GestureDetector(onTap: onRemove, child: const Icon(Icons.close, size: 18, color: Colors.grey)),
        ],
      ],
    ]),
  );
}

class UploadJob {
  final String path, name, mime, vis, folder;
  final int size;
  double progress = 0;
  String status = 'Uploading…';
  bool done = false, failed = false, cancelled = false;
  DateTime started = DateTime.now();
  UploadJob({required this.path, required this.name, required this.mime, required this.vis, required this.folder, required this.size});

  /// Rough ETA in whole minutes based on elapsed time and progress (null while unknown).
  int? get minutesLeft {
    if (progress <= 0.02 || done || failed) return null;
    final elapsed = DateTime.now().difference(started).inSeconds;
    final total = elapsed / progress;
    final left = ((total - elapsed) / 60).ceil();
    return left < 1 ? 1 : left;
  }

  void cancel() => cancelled = true;

  Future<void> run(void Function() notify) async {
    final nkey = 'up-$path-$name';
    final ntf = PipsNotify.i;
    await ntf.uploadStart(nkey, name);
    try {
      final f = File(path);
      if (size <= PipsApi.singleLimit) {
        await PipsApi.uploadSingle(f, name, mime, vis, (_) { progress = 1; notify(); });
      } else {
        final bytes = await f.readAsBytes();
        final init = await PipsApi.uploadInit(name, size);
        final id = init['id'].toString();
        final total = (size + PipsApi.chunkSize - 1) ~/ PipsApi.chunkSize;
        var doneParts = await PipsApi.uploadStatus(id); // resume support
        for (var i = 0; i < total; i++) {
          if (cancelled) throw ApiException('Cancelled.', 0);
          if (doneParts.contains(i)) { progress = min(1, ((i + 1) * PipsApi.chunkSize) / size); notify(); continue; }
          final start = i * PipsApi.chunkSize;
          await PipsApi.uploadChunk(id, i, bytes.sublist(start, min(start + PipsApi.chunkSize, size)));
          progress = min(1, ((i + 1) * PipsApi.chunkSize) / size);
          status = 'Chunk ${i + 1}/$total';
          notify();
          await ntf.uploadProgress(nkey, name, progress); // background notification
        }
        if (cancelled) throw ApiException('Cancelled.', 0);
        await PipsApi.uploadFinish(id, total, size, name, mime, vis);
      }
      status = 'Done ✓'; done = true;
      await ntf.uploadEnd(nkey, name, ok: true, message: 'Uploaded to Pips cloud');
    } on ApiException catch (e) {
      status = cancelled ? 'Cancelled' : e.message; failed = true;
      await ntf.uploadEnd(nkey, name, ok: false, message: status);
    }
    notify();
  }
}

class UploadsPage extends StatelessWidget {
  const UploadsPage({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: UploadQueue.instance,
        builder: (_, __) {
          final jobs = UploadQueue.instance.jobs;
          final active = jobs.where((j) => !j.done && !j.failed).toList();
          final finished = jobs.where((j) => j.done || j.failed).toList();
          final canClear = finished.isNotEmpty;
          return Scaffold(
            appBar: AppBar(title: const Text('File Upload'), actions: [
              TextButton(onPressed: canClear ? UploadQueue.instance.clearFinished : null, child: const Text('Clear finished')),
            ]),
            body: jobs.isEmpty && UploadQueue.instance.imports.isEmpty
                ? const EmptyState(icon: '⬆️', text: 'Nothing here yet.\nTap + to pick a file.')
                : ListView(padding: const EdgeInsets.all(14), children: [
                    if (UploadQueue.instance.imports.isNotEmpty) ...[
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Cloud imports (URL)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Text('${UploadQueue.instance.imports.where((i) => i.active).length} importing', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ]),
                      ...UploadQueue.instance.imports.map((im) => importCard(context, im)),
                      const SizedBox(height: 14),
                    ],
                    if (active.isNotEmpty) ...[
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('In Progress', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Text('${active.length} active', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ]),
                      ...active.map((j) => _jobCard(context, j)),
                    ],
                    if (finished.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text('Completed', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ...finished.map((j) => _jobCard(context, j)),
                    ],
                  ]),
          );
        },
      );

  Widget _jobCard(BuildContext context, UploadJob j) {
    final pct = (j.progress * 100).round();
    final left = j.minutesLeft;
    final color = j.failed ? AppTheme.red : (j.done ? AppTheme.green : AppTheme.blue);
    final sub = [
      fmtBytes(j.size),
      j.status,
      if (!j.done && !j.failed && left != null) 'About $left min left',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: HomeColors.of(context).surfaceSoft, borderRadius: BorderRadius.circular(16), border: Border.all(color: HomeColors.of(context).line)),
      child: Column(children: [
        Row(children: [
          const IconTile(icon: Icons.upload_file, bg: Color(0xFFDBEAFE), fg: AppTheme.blue, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(j.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 3),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: j.failed ? AppTheme.red : Colors.grey)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(j.done ? '✓' : '$pct%', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: color)),
          if (!j.done && !j.failed)
            IconButton(icon: const Icon(Icons.close, size: 19, color: Colors.grey), tooltip: 'Cancel', onPressed: j.cancel),
        ]),
        const SizedBox(height: 8),
        ProgressBar(value: j.progress, color: color),
      ]),
    );
  }
}

/// "Add new files" sheet — dashed drop zone with multi-select from gallery or
/// documents, URL import, per-file cards, then live progress (per the design).
class UploadSheet extends StatefulWidget {
  final String presetFolder;
  const UploadSheet({super.key, this.presetFolder = ''});
  @override
  State<UploadSheet> createState() => _UploadSheetState();
}

class _Pick {
  String path;
  final String name, mime;
  int size;
  _Pick({required this.path, required this.name, required this.size, required this.mime});
}

class _UploadSheetState extends State<UploadSheet> {
  final items = <_Pick>[];
  final urlCtrl = TextEditingController();
  String vis = 'public', folder = '';
  bool busy = false;
  bool extracting = false;
  bool started = false; // after Upload -> live progress view

  @override
  void initState() {
    super.initState();
    urlCtrl.addListener(() { if (mounted) setState(() {}); });
  }

  static const _mimes = {'pdf': 'application/pdf', 'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'gif': 'image/gif', 'webp': 'image/webp', 'heic': 'image/heic', 'heif': 'image/heif', 'avif': 'image/avif', 'mp4': 'video/mp4', 'mov': 'video/quicktime', 'mkv': 'video/x-matroska', 'avi': 'video/x-msvideo', 'webm': 'video/webm', 'm4v': 'video/x-m4v', 'flv': 'video/x-flv', '3gp': 'video/3gpp', 'mpg': 'video/mpeg', 'mpeg': 'video/mpeg', 'wmv': 'video/x-ms-wmv', 'm3u8': 'application/vnd.apple.mpegurl', 'm3u': 'application/vnd.apple.mpegurl', 'mp3': 'audio/mpeg', 'wav': 'audio/wav', 'm4a': 'audio/mp4', 'zip': 'application/zip', 'rar': 'application/vnd.rar', '7z': 'application/x-7z-compressed', 'txt': 'text/plain', 'json': 'application/json', 'csv': 'text/csv', 'doc': 'application/msword', 'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'xls': 'application/vnd.ms-excel', 'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'};

  static (IconData, Color) iconFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic'].contains(ext)) return (Icons.image_outlined, AppTheme.purple);
    if (['mp4', 'mov', 'mkv', 'avi', 'webm'].contains(ext)) return (Icons.movie_outlined, AppTheme.teal);
    if (['mp3', 'wav', 'm4a', 'flac', 'ogg'].contains(ext)) return (Icons.music_note_outlined, AppTheme.orange);
    if (ext == 'pdf') return (Icons.picture_as_pdf_outlined, AppTheme.red);
    if (['doc', 'docx', 'odt', 'rtf'].contains(ext)) return (Icons.description_outlined, AppTheme.blue);
    if (['xls', 'xlsx', 'csv'].contains(ext)) return (Icons.table_chart_outlined, AppTheme.green);
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) return (Icons.folder_zip_outlined, AppTheme.orange);
    return (Icons.insert_drive_file_outlined, Colors.grey);
  }

  void _addPicked(List<PlatformFile> files) {
    if (files.isEmpty) return;
    var added = 0;
    for (final f in files) {
      if (f.path == null) continue;
      final dup = items.any((e) => e.name == f.name && e.size == f.size);
      if (dup) continue;
      final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
      items.add(_Pick(path: f.path!, name: f.name, size: f.size, mime: _mimes[ext] ?? 'application/octet-stream'));
      added++;
    }
    setState(() {});
    if (mounted && added > 0) toast(context, '$added file${added == 1 ? '' : 's'} added');
  }

  Future<void> pickGallery() async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.media, allowMultiple: true);
      _addPicked(r?.files ?? const []);
    } catch (_) {}
  }

  Future<void> pickDocs() async {
    try {
      final r = await FilePicker.platform.pickFiles(allowMultiple: true);
      _addPicked(r?.files ?? const []);
    } catch (_) {}
  }

  /// True for single-video YouTube links (watch / shorts / embed / live / youtu.be).
  static bool isYouTube(String raw) {
    final u = Uri.tryParse(raw);
    if (u == null) return false;
    final h = u.host.toLowerCase();
    final isYt = h == 'youtube.com' || h.endsWith('.youtube.com') || h == 'youtu.be' || h.endsWith('.youtu.be');
    if (!isYt) return false;
    if (h == 'youtu.be') return u.pathSegments.isNotEmpty;
    final p = u.path;
    return p.startsWith('/watch') || p.startsWith('/shorts/') || p.startsWith('/embed/') || p.startsWith('/live/');
  }

  Future<void> importUrl() async {
    var raw = urlCtrl.text.trim();
    if (raw.isEmpty) return;
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) raw = 'https://$raw';
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.host.contains('.')) {
      toast(context, 'Enter a valid URL.');
      return;
    }
    final isYt = isYouTube(raw);
    setState(() => busy = true);
    try {
      // Server-side import: the backend worker fetches the source in the
      // background and stores the file in Pips cloud — for a YouTube link it
      // downloads the video at best quality (video + audio in one mp4) into a
      // folder named after the video. The phone can go offline right away.
      final entry = await PipsApi.importUrl(raw, vis: vis);
      if (!mounted) return;
      final st = entry['import_status'];
      UploadQueue.instance.trackImport(ServerImport(
        id: (entry['id'] ?? '').toString(),
        name: (entry['name'] ?? 'import').toString(),
        size: int.tryParse('${entry['size'] ?? 0}') ?? 0,
        status: st is String && st.isNotEmpty ? st : 'importing',
        error: entry['import_error'] is String ? entry['import_error'] as String : null,
        kind: isYt ? 'youtube' : 'url',
        url: isYt ? raw : null,
      ));
      setState(() => urlCtrl.clear());
      toast(context, isYt
          ? 'YouTube download queued — best quality, in its own folder. Safe to close the app.'
          : 'Import queued on the server — safe to close the app.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (_) {
      if (mounted) toast(context, 'Could not start that import.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// On-device YouTube extraction via the vendored flutter_youtube_downloader
  /// (NewPipe engine): resolves the watch link to a direct media URL, then
  /// queues a plain server-side import of that URL — no cookies needed.
  Future<void> extractAndImport() async {
    final raw = urlCtrl.text.trim();
    if (raw.isEmpty || extracting) return;
    setState(() => extracting = true);
    try {
      final res = await FlutterYoutubeDownloader.extractYoutubeLink(raw, 18);
      final direct = res is String ? res : '';
      if (!direct.startsWith('http')) {
        if (mounted) {
          toast(context, direct.isEmpty
              ? 'Could not extract a direct link for that video.'
              : 'Extract failed: $direct');
        }
        return;
      }
      // The direct URL is an ordinary https link — the same server-side
      // worker that imports normal URLs can fetch it without yt-dlp.
      final entry = await PipsApi.importUrl(direct, vis: vis);
      if (!mounted) return;
      final st = entry['import_status'];
      UploadQueue.instance.trackImport(ServerImport(
        id: (entry['id'] ?? '').toString(),
        name: (entry['name'] ?? 'YouTube video').toString(),
        size: int.tryParse('${entry['size'] ?? 0}') ?? 0,
        status: st is String && st.isNotEmpty ? st : 'importing',
        error: entry['import_error'] is String ? entry['import_error'] as String : null,
        kind: 'youtube',
        url: raw,
      ));
      setState(() => urlCtrl.clear());
      if (mounted) toast(context, 'Direct link extracted — import queued. Safe to close the app.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (_) {
      if (mounted) toast(context, 'Extraction failed — try the server import instead.');
    } finally {
      if (mounted) setState(() => extracting = false);
    }
  }

  void upload() {
    final ready = items.where((e) => e.path.isNotEmpty).toList();
    if (ready.isEmpty) {
      if (UploadQueue.instance.imports.isNotEmpty) setState(() => started = true);
      return;
    }
    for (final e in ready) {
      UploadQueue.instance.add(UploadJob(path: e.path, name: e.name, mime: e.mime, vis: vis, folder: folder, size: e.size));
    }
    setState(() => started = true);
  }

  @override
  Widget build(BuildContext context) {
    if (started) return _progressView(context);
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Add new files', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 30, height: 30,
                  decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 17, color: Colors.grey),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            _dropZone(),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _pill(Icons.photo_library_outlined, 'Select from Gallery', AppTheme.blue, pickGallery)),
              const SizedBox(width: 10),
              Expanded(child: _pill(Icons.description_outlined, 'Select Documents', AppTheme.purple, pickDocs)),
            ]),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...items.map(_pickCard),
            ],
            if (UploadQueue.instance.imports.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...UploadQueue.instance.imports.map((im) => importCard(context, im, onRemove: im.active ? null : () => UploadQueue.instance.removeImport(im))),
            ],
            const SizedBox(height: 16),
            Row(children: const [
              Expanded(child: Divider(color: Color(0xFFE2E8F0))),
              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('OR', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w700))),
              Expanded(child: Divider(color: Color(0xFFE2E8F0))),
            ]),
            const SizedBox(height: 14),
            const Text('Import YouTube video or file URL', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            const SizedBox(height: 8),
            TextField(
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'youtube.com/watch?v=… or www.example.com/file.pdf',
                prefixIcon: const Icon(Icons.link, size: 19),
                suffixIcon: TextButton(
                  onPressed: busy ? null : importUrl,
                  child: Text(
                    _UploadSheetState.isYouTube(urlCtrl.text.trim()) ? 'Import video' : 'Select',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.blue),
                  ),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.blue, width: 1.4)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.blue, width: 1.4)),
              ),
            ),
            if (_UploadSheetState.isYouTube(urlCtrl.text.trim()))
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.blue.withValues(alpha: 0.25)),
                ),
                child: Column(children: [
                  TextButton(
                    onPressed: extracting ? null : extractAndImport,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (extracting)
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.purple))
                      else
                        const Icon(Icons.bolt, size: 14, color: AppTheme.purple),
                      const SizedBox(width: 5),
                      Text(
                        extracting ? 'Extracting direct URL…' : 'Get direct URL & import (no cookies needed)',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.purple),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  const Row(children: [
                    Icon(Icons.smart_display, size: 15, color: AppTheme.blue),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                      'YouTube: best quality, video + audio in one file, saved in a folder named after the video. Runs in the background — you can close the app.',
                      style: TextStyle(fontSize: 11, height: 1.25),
                    )),
                  ]),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => YtLocalPage(initialUrl: urlCtrl.text.trim()))),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.phone_android, size: 14, color: AppTheme.teal),
                      SizedBox(width: 5),
                      Text('Download on this phone (live JSON)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.teal)),
                    ]),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const YtConnectPage())),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.smart_toy, size: 14, color: AppTheme.blue),
                      SizedBox(width: 5),
                      Text('Allow YouTube Cookies (you pick the cookies.txt)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.blue)),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                icon: Icon(vis == 'public' ? Icons.public : Icons.lock, size: 17),
                label: Text(vis == 'public' ? 'Public' : 'Private', style: const TextStyle(fontSize: 13)),
                onPressed: () => setState(() => vis = vis == 'public' ? 'private' : 'public'),
              )),
              const SizedBox(width: 10),
              Expanded(child: FutureBuilder<List<dynamic>>(
                future: PipsApi.folders(),
                builder: (_, s) {
                  final folders = (s.data ?? []).map((f) => (f is Map ? (f['name'] ?? f['path'] ?? '').toString() : f.toString())).where((e) => e.isNotEmpty).toList();
                  if (folder.isEmpty && widget.presetFolder.isNotEmpty) folder = widget.presetFolder;
                  return DropdownButtonFormField<String>(
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                    initialValue: folder.isEmpty ? null : folder,
                    hint: const Text('Folder', style: TextStyle(fontSize: 13)),
                    items: [const DropdownMenuItem(value: '', child: Text('No folder')), ...folders.map((f) => DropdownMenuItem(value: f, child: Text(f, overflow: TextOverflow.ellipsis)))],
                    onChanged: (v) => setState(() => folder = v ?? ''),
                  );
                },
              )),
            ]),
            const SizedBox(height: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _help,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: const [
                  Icon(Icons.help_outline, size: 17, color: Colors.grey),
                  SizedBox(width: 6),
                  Text('Still need help?', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13), side: const BorderSide(color: Color(0xFFDCE4EE)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(
                onPressed: (items.any((e) => e.path.isNotEmpty) || UploadQueue.instance.imports.isNotEmpty) ? upload : null,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text('Upload${items.isEmpty ? '' : ' (${items.length})'}', style: const TextStyle(fontWeight: FontWeight.w700)),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _dropZone() => GestureDetector(
        onTap: pickDocs,
        child: CustomPaint(
          painter: _DashedRRect(color: const Color(0xFF93B8F5), radius: 14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
            child: Column(children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(color: const Color(0xFFEAF2FE), borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.file_upload_outlined, color: AppTheme.blue, size: 24),
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155)), children: const [
                  TextSpan(text: 'Tap or '),
                  TextSpan(text: 'choose', style: TextStyle(color: AppTheme.blue, fontWeight: FontWeight.w800)),
                  TextSpan(text: ' files to upload', style: TextStyle(fontWeight: FontWeight.w700)),
                ]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 5),
              const Text('Select images, videos, zip, pdf or ms word', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ),
        ),
      );

  Widget _pill(IconData icon, String label, Color color, VoidCallback onTap) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17, color: color),
        label: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 11),
          side: BorderSide(color: color.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  Widget _pickCard(_Pick e) {
    final (icon, color) = iconFor(e.name);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: HomeColors.of(context).surfaceSoft, borderRadius: BorderRadius.circular(13), border: Border.all(color: HomeColors.of(context).line)),
      child: Row(children: [
        IconTile(icon: icon, bg: color.withValues(alpha: 0.14), fg: color, size: 36),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 2),
          Text('${fmtBytes(e.size)} · ready', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ])),
        GestureDetector(
          onTap: () => setState(() => items.remove(e)),
          child: const Icon(Icons.close, size: 18, color: Colors.grey),
        ),
      ]),
    );
  }

  Widget _progressView(BuildContext context) => SafeArea(
        child: AnimatedBuilder(
          animation: UploadQueue.instance,
          builder: (_, __) {
            final jobs = UploadQueue.instance.jobs;
            final active = jobs.where((j) => !j.done && !j.failed).toList();
            final imps = UploadQueue.instance.imports;
            final title = active.isEmpty
                ? 'Importing from URL…'
                : 'Uploading ${active.length} ${active.length == 1 ? 'file' : 'files'}…';
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Hide', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ]),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: jobs.length + imps.length,
                    itemBuilder: (_, i) {
                      if (i < imps.length) return importCard(context, imps[i]);
                      final j = jobs[i - imps.length];
                      final left = j.minutesLeft;
                      final color = j.failed ? AppTheme.red : (j.done ? AppTheme.green : AppTheme.blue);
                      final (icon, ic) = iconFor(j.name);
                      final sub = [
                        fmtBytes(j.size),
                        j.status,
                        if (!j.done && !j.failed && left != null) '$left second${left == 1 ? '' : 's'} left',
                      ].join(' · ');
                      return Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: HomeColors.of(context).surfaceSoft, borderRadius: BorderRadius.circular(13), border: Border.all(color: HomeColors.of(context).line)),
                        child: Column(children: [
                          Row(children: [
                            IconTile(icon: icon, bg: ic.withValues(alpha: 0.14), fg: ic, size: 34),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(j.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                              const SizedBox(height: 2),
                              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: j.failed ? AppTheme.red : Colors.grey)),
                            ])),
                            if (!j.done && !j.failed)
                              GestureDetector(onTap: j.cancel, child: const Icon(Icons.close, size: 17, color: Colors.grey)),
                          ]),
                          const SizedBox(height: 8),
                          ProgressBar(value: j.progress, color: color, height: 5),
                        ]),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13), side: const BorderSide(color: Color(0xFFDCE4EE)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      toast(context, 'Uploads continue in the background — see the Uploads tab.');
                    },
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                  )),
                ]),
              ]),
            );
          },
        ),
      );

  void _help() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Need help with uploads?'),
        content: const Text('Pick files from your gallery or documents, or paste a direct file URL under "Import from URL" — every file type is supported (m3u8 / HLS streams, all video formats, images, audio, documents, archives). URL imports run on the Pips server, so they keep going even if you close the app or go offline. Files larger than 4 MB upload in chunks automatically and continue in the background.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await PipsApi.report('App: upload help requested');
                if (mounted) toast(context, 'Support notified — we will reach out soon.');
              } on ApiException catch (e) {
                if (mounted) toast(context, e.message);
              }
            },
            child: const Text('Contact support'),
          ),
        ],
      ),
    );
  }
}

class _DashedRRect extends CustomPainter {
  final Color color;
  final double radius;
  _DashedRRect({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = color;
    const dash = 6.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, min(d + dash, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRect oldDelegate) => oldDelegate.color != color;
}
