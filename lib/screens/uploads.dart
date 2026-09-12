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
  bool done = false, failed = false;
  UploadJob({required this.path, required this.name, required this.mime, required this.vis, required this.folder, required this.size});

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
          if (doneParts.contains(i)) { progress = min(1, ((i + 1) * PipsApi.chunkSize) / size); notify(); continue; }
          final start = i * PipsApi.chunkSize;
          await PipsApi.uploadChunk(id, i, bytes.sublist(start, min(start + PipsApi.chunkSize, size)));
          progress = min(1, ((i + 1) * PipsApi.chunkSize) / size);
          status = 'Chunk ${i + 1}/$total';
          notify();
          await ntf.uploadProgress(nkey, name, progress); // background notification
        }
        await PipsApi.uploadFinish(id, total, size, name, mime, vis);
      }
      status = 'Done ✓'; done = true;
      await ntf.uploadEnd(nkey, name, ok: true, message: 'Uploaded to Pips cloud');
    } on ApiException catch (e) {
      status = e.message; failed = true;
      await ntf.uploadEnd(nkey, name, ok: false, message: e.message);
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
          return Scaffold(
            appBar: AppBar(title: const Text('Uploads'), actions: [
              TextButton(onPressed: jobs.any((j) => j.done || j.failed) ? UploadQueue.instance.clearFinished : null, child: const Text('Clear finished')),
            ]),
            body: jobs.isEmpty
                ? const EmptyState(icon: '⬆️', text: 'Nothing here yet.\nTap + to pick a file.')
                : ListView.builder(itemCount: jobs.length, itemBuilder: (_, i) {
                    final j = jobs[i];
                    return ListTile(
                      leading: const IconTile(icon: Icons.upload_file, bg: Color(0xFFDBEAFE), fg: AppTheme.blue),
                      title: Text(j.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SizedBox(height: 6),
                        ProgressBar(value: j.progress, color: j.failed ? AppTheme.red : (j.done ? AppTheme.green : AppTheme.blue)),
                        const SizedBox(height: 4),
                        Text('${fmtBytes(j.size)} · ${j.status}', style: TextStyle(fontSize: 11, color: j.failed ? AppTheme.red : Colors.grey)),
                      ]),
                    );
                  }),
          );
        },
      );
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
