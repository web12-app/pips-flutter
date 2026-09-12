import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../services/notifications.dart';
import '../widgets.dart';

class UploadQueue extends ChangeNotifier {
  static final instance = UploadQueue._();
  UploadQueue._();
  final jobs = <UploadJob>[];
  void add(UploadJob j) {
    PipsNotify.i.requestPermission(); // Android 13+ POST_NOTIFICATIONS
    jobs.insert(0, j);
    notifyListeners();
    j.run(notifyListeners);
  }
  void clearFinished() { jobs.removeWhere((j) => j.done || j.failed); notifyListeners(); }
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
            body: jobs.isEmpty
                ? const EmptyState(icon: '⬆️', text: 'Nothing here yet.\nTap + to pick a file.')
                : ListView(padding: const EdgeInsets.all(14), children: [
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE8EEF6))),
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

class UploadSheet extends StatefulWidget {
  final String presetFolder;
  const UploadSheet({super.key, this.presetFolder = ''});
  @override
  State<UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<UploadSheet> {
  String? path, name, mime = 'application/octet-stream';
  int size = 0;
  String vis = 'public', folder = '';
  bool busy = false;

  static const _mimes = {'pdf': 'application/pdf', 'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'mp4': 'video/mp4', 'mp3': 'audio/mpeg', 'zip': 'application/zip', 'txt': 'text/plain', 'json': 'application/json'};

  Future<void> pick() async {
    final r = await FilePicker.platform.pickFiles();
    final f = r?.files.single;
    if (f == null || f.path == null) return;
    setState(() {
      path = f.path; name = f.name; size = f.size;
      final ext = f.name.split('.').last.toLowerCase();
      mime = _mimes[ext] ?? 'application/octet-stream';
    });
  }

  Future<void> upload() async {
    if (path == null) return;
    setState(() => busy = true);
    UploadQueue.instance.add(UploadJob(path: path!, name: name!, mime: mime!, vis: vis, folder: folder, size: size));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Upload to Pips', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: pick,
              child: GlassCard(child: Row(children: [
                const Icon(Icons.add_circle_outline, color: AppTheme.blue),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name ?? 'Tap to choose a file', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(name == null ? 'Any type · ≤4 MB single, chunked above' : '${fmtBytes(size)} · $mime', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ])),
              ])),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                icon: Icon(vis == 'public' ? Icons.public : Icons.lock),
                label: Text(vis == 'public' ? 'Public' : 'Private'),
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
                    hint: const Text('Folder'),
                    items: [const DropdownMenuItem(value: '', child: Text('No folder')), ...folders.map((f) => DropdownMenuItem(value: f, child: Text(f, overflow: TextOverflow.ellipsis)))],
                    onChanged: (v) => setState(() => folder = v ?? ''),
                  );
                },
              )),
            ]),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: busy || path == null ? null : upload,
              icon: const Icon(Icons.upload),
              label: Text(busy ? 'Starting…' : 'Upload'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ]),
        ),
      );
}
