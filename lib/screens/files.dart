import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';
import 'viewer.dart';
import 'uploads.dart';
import 'misc.dart';

class FilesPage extends StatefulWidget {
  final String initialFilter;
  const FilesPage({super.key, this.initialFilter = ''});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  String q = '', filter = '';
  String sort = 'date'; // date | name | size
  Key refresh = UniqueKey();
  void reload() => setState(() => refresh = UniqueKey());

  @override
  void initState() {
    super.initState();
    filter = widget.initialFilter;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Files'), actions: [
          IconButton(icon: const Icon(Icons.create_new_folder_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FoldersPage()))),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrashPage()))),
        ]),
        body: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: TextField(
            decoration: InputDecoration(hintText: 'Search files', prefixIcon: const Icon(Icons.search), filled: true, fillColor: HomeColors.of(context).surfaceSoft, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
            onChanged: (v) => setState(() => q = v),
          )),
          SizedBox(height: 46, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final f in ['', 'image', 'video', 'audio', 'doc'])
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: FilterChip(
                label: Text(f.isEmpty ? 'All' : f[0].toUpperCase() + f.substring(1)),
                selected: filter == f,
                onSelected: (_) => setState(() => filter = f),
              )),
          ])),
          SizedBox(height: 52, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _pill('Explorer', Icons.explore_rounded, const Color(0xFF7C3AED), const Color(0xFFEDE9FE), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CloudExplorerPage())))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _pill('Upload', Icons.upload_file, const Color(0xFF2563EB), const Color(0xFFDBEAFE), () => showSheet(context, const UploadSheet()))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _pill('Folder', Icons.create_new_folder_outlined, const Color(0xFF059669), const Color(0xFFD1FAE5), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FoldersPage())))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _pill('Scan', Icons.document_scanner_outlined, const Color(0xFF0D9488), const Color(0xFFCCFBF1), _scan)),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: VerticalDivider(width: 12)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _sortChip()),
          ])),
          Expanded(child: FutureBuilder<List<dynamic>>(
            key: refresh,
            future: q.isEmpty
                ? PipsApi.filesAll()
                : PipsApi.search(q, filter.isEmpty ? null : filter).then((r) => r['files'] is List ? r['files'] as List : (r['results'] is List ? r['results'] as List : <dynamic>[])),
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
              final items = (s.data ?? []).map((e) => Entry(Map<String, dynamic>.from(e as Map))).toList();
              if (filter == 'image') items.removeWhere((e) => !isImage(e.mime, e.name) || e.isDb);
              if (filter == 'video') items.removeWhere((e) => !isVideo(e.mime, e.name));
              if (filter == 'audio') items.removeWhere((e) => !isAudio(e.mime, e.name));
              if (filter == 'doc') items.removeWhere((e) => isVideo(e.mime, e.name) || isImage(e.mime, e.name) || isAudio(e.mime, e.name));
              switch (sort) {
                case 'name': items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                case 'size': items.sort((a, b) => b.size.compareTo(a.size));
                default: items.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
              }
              if (items.isEmpty) return const EmptyState(icon: '📭', text: 'No files found.');
              return ListView.builder(itemCount: items.length, itemBuilder: (_, i) => fileTile(context, items[i], reload, gallery: items));
            },
          )),
        ]),
      );
  Widget _pill(String label, IconData icon, Color fg, Color bg, VoidCallback onTap) {
    // Pastel chips read badly on dark surfaces — tint with the icon color instead.
    final b = Theme.of(context).brightness == Brightness.dark ? fg.withValues(alpha: 0.16) : bg;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: b, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: fg),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
      ),
    );
  }

  Widget _sortChip() => ActionChip(
        avatar: const Icon(Icons.sort, size: 16, color: AppTheme.blue),
        label: Text(sort == 'date' ? 'Newest' : (sort == 'name' ? 'Name A-Z' : 'Largest'), style: const TextStyle(fontSize: 12.5)),
        onPressed: () => setState(() => sort = sort == 'date' ? 'name' : (sort == 'name' ? 'size' : 'date')),
      );

  Future<void> _scan() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final f = r?.files.single;
    if (f == null || f.path == null) return;
    const mimes = {'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp', 'heic': 'image/heic'};
    final ext = f.name.split('.').last.toLowerCase();
    UploadQueue.instance.add(UploadJob(
      path: f.path!,
      name: 'scan-${DateTime.now().millisecondsSinceEpoch}.$ext',
      mime: mimes[ext] ?? 'image/jpeg',
      vis: 'private',
      folder: '',
      size: f.size,
    ));
    if (mounted) toast(context, 'Scan queued — uploading as private image.');
  }
}

Widget fileTile(BuildContext context, Entry e, VoidCallback onChanged, {List<Entry>? gallery}) {
  final m = e.isDb ? const TypeMeta(Icons.table_chart_rounded, Color(0xFFF3E8FF), Color(0xFF7C3AED)) : metaFor(e.mime, e.name);
  return ListTile(
    leading: IconTile(icon: m.icon, bg: m.bg, fg: m.fg),
    title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
    subtitle: Text('${fmtBytes(e.size)} · ${fmtDate(e.uploadedAt)}${e.visibility == 'private' ? ' · 🔒' : ''}', style: const TextStyle(fontSize: 12)),
    trailing: const Icon(Icons.more_vert, color: Colors.grey),
    onTap: () => showFileSheet(context, e, onChanged, gallery: gallery),
  );
}

Future<void> showFileSheet(BuildContext context, Entry e, VoidCallback onChanged, {List<Entry>? gallery}) async {
  await showSheet(context, FileActions(e: e, onChanged: onChanged, gallery: gallery));
}

class FileActions extends StatelessWidget {
  final Entry e;
  final VoidCallback onChanged;
  final List<Entry>? gallery;
  const FileActions({super.key, required this.e, required this.onChanged, this.gallery});

  Future<void> _do(BuildContext context, Future<void> Function() fn) async {
    Navigator.pop(context);
    try { await fn(); onChanged(); } on ApiException catch (ex) { if (context.mounted) toast(context, ex.message); }
  }

  Future<void> _download(BuildContext context) async {
    Navigator.pop(context);
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/${e.name}');
      await PipsApi.downloadToFile(PipsApi.downloadUrl(e.id), f, (_) {});
      if (context.mounted) toast(context, 'Downloaded to ${f.path}');
    } on ApiException catch (ex) { if (context.mounted) toast(context, ex.message); }
  }

  Future<void> _shareLink(BuildContext context) async {
    final exp = await showDialog<int>(context: context, builder: (ctx) => SimpleDialog(title: const Text('Link expires in'), children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 3600), child: const Text('1 hour')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 86400), child: const Text('24 hours')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 604800), child: const Text('7 days')),
        ]));
    if (exp == null) return;
    try {
      final r = await PipsApi.signedUrl(e.id, exp);
      final url = r['url']?.toString() ?? r['signed_url']?.toString() ?? '';
      if (url.isNotEmpty) await Share.share(url);
    } on ApiException catch (ex) { if (context.mounted) toast(context, ex.message); }
  }

  Future<void> _sendToChat(BuildContext context) async {
    final c = TextEditingController();
    final to = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Send to user'), content: TextField(controller: c, decoration: const InputDecoration(hintText: 'Username')),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Send'))],
        ));
    if (to == null || to.isEmpty) return;
    await _do(context, () async {
      await PipsApi.sendMessage(to, '', e.id);
      if (context.mounted) toast(context, 'Sent to @$to');
    });
  }

  Future<void> _moveCopy(BuildContext context, bool move) async {
    final folders = await PipsApi.folders();
    if (!context.mounted) return;
    final names = folders.map((f) => f is Map ? (f['name'] ?? f['path'] ?? '').toString() : f.toString()).where((x) => x.isNotEmpty).toList();
    final picked = await showDialog<String>(context: context, builder: (ctx) => SimpleDialog(title: Text(move ? 'Move to folder' : 'Copy to folder'), children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, ''), child: const Text('(root)')),
          ...names.map((n) => SimpleDialogOption(onPressed: () => Navigator.pop(ctx, n), child: Text(n))),
        ]));
    if (picked == null) return;
    await _do(context, () => move ? PipsApi.fileMove(e.id, picked) : PipsApi.fileCopy(e.id, picked));
  }

  String get kindLabel {
    if (e.isDb) return 'Pips DB document';
    switch (typeOf(e.mime, e.name)) {
      case CloudType.image: return 'Image';
      case CloudType.video: return 'Video';
      case CloudType.audio: return 'Audio';
      case CloudType.pdf: return 'PDF document';
      case CloudType.zip: return 'Archive';
      case CloudType.doc: return 'Document';
      case CloudType.design: return 'Design file';
      default: return 'File';
    }
  }

  Widget _propRow(String label, String value, {VoidCallback? onCopy}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 88, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
          Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          if (onCopy != null)
            SizedBox(
              height: 26, width: 26,
              child: IconButton(padding: EdgeInsets.zero, iconSize: 16, icon: const Icon(Icons.copy), onPressed: onCopy),
            ),
        ]),
      );

  Future<void> _properties(BuildContext context) async {
    final m = e.isDb ? const TypeMeta(Icons.table_chart_rounded, Color(0xFFF3E8FF), Color(0xFF7C3AED)) : metaFor(e.mime, e.name);
    await showSheet(
      context,
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Builder(
            builder: (sctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconTile(icon: m.icon, bg: m.bg, fg: m.fg, size: 40),
              const SizedBox(width: 10),
              Expanded(child: Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            ]),
            const SizedBox(height: 6),
            const Divider(),
            _propRow('File ID', e.id, onCopy: () {
              Clipboard.setData(ClipboardData(text: e.id));
              toast(sctx, 'File ID copied');
            }),
            _propRow('Kind', kindLabel),
            _propRow('Type', e.mime.isEmpty ? '—' : e.mime),
            _propRow('Size', '${fmtBytes(e.size)} (${e.size} bytes)'),
            _propRow('Folder', e.folder.isEmpty ? 'Root (/)' : e.folder),
            _propRow('Visibility', e.visibility == 'private' ? 'Private 🔒' : 'Public 🌐'),
            _propRow('Uploaded', fmtDate(e.uploadedAt)),
            _propRow('Version', 'v${e.version}'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: e.id));
                    toast(sctx, 'File ID copied');
                  },
                  icon: const Icon(Icons.copy, size: 17),
                  label: const Text('Copy ID'),
                ),
              ),
              if (!e.isDb) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: PipsApi.viewUrl(e.id)));
                      toast(sctx, 'View link copied');
                    },
                    icon: const Icon(Icons.link, size: 17),
                    label: const Text('Copy link'),
                  ),
                ),
              ],
            ]),
          ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewable = isImage(e.mime, e.name) || isVideo(e.mime, e.name) || isAudio(e.mime, e.name) || isTexty(e.mime, e.name);
    final priv = e.visibility == 'private';
    return SafeArea(child: ListView(shrinkWrap: true, children: [
      ListTile(title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${fmtBytes(e.size)} · ${priv ? 'Private 🔒' : 'Public 🌐'} · v${e.version}')),
      const Divider(),
      if (previewable) SheetTile(icon: Icons.play_circle_outline, color: AppTheme.blue, label: 'Play / View', onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ViewerPage(e: e, gallery: gallery))); }),
      SheetTile(icon: Icons.info_outline, color: AppTheme.teal, label: 'Properties', onTap: () { Navigator.pop(context); _properties(context); }),
      if (isImage(e.mime, e.name) && !e.isDb) SheetTile(icon: Icons.edit_outlined, color: AppTheme.purple, label: 'Edit image', onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ImageEditorPage(e: e))); }),
      SheetTile(icon: Icons.download, color: AppTheme.blue, label: 'Download', onTap: () => _download(context)),
      SheetTile(icon: Icons.link, color: AppTheme.teal, label: 'Share link (time-limited)', onTap: () => _shareLink(context)),
      if (!e.isDb) SheetTile(icon: Icons.send, color: AppTheme.blue, label: 'Send to chat (file_id)', onTap: () => _sendToChat(context)),
      if (!e.isDb) SheetTile(icon: priv ? Icons.public : Icons.lock_outline, color: priv ? AppTheme.green : AppTheme.orange, label: priv ? 'Make public' : 'Make private', onTap: () => _do(context, () => PipsApi.setVisibility(e.id, priv ? 'public' : 'private'))),
      SheetTile(icon: Icons.drive_file_rename_outline, color: AppTheme.orange, label: 'Rename', onTap: () async {
        final c = TextEditingController(text: e.name);
        final n = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Rename'), content: TextField(controller: c), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save'))]));
        if (n != null && n.isNotEmpty) await _do(context, () => PipsApi.filePatch(e.id, {'name': n}));
      }),
      if (!e.isDb) ...[
        SheetTile(icon: Icons.drive_file_move_outline, color: AppTheme.orange, label: 'Move to folder', onTap: () => _moveCopy(context, true)),
        SheetTile(icon: Icons.copy, color: AppTheme.orange, label: 'Copy to folder', onTap: () => _moveCopy(context, false)),
      ],
      SheetTile(icon: Icons.history, color: AppTheme.purple, label: 'Version history & restore', onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => VersionsPage(e: e, onChanged: onChanged))); }),
      SheetTile(icon: Icons.delete_outline, color: AppTheme.red, label: 'Delete', onTap: () async {
        final ok = await confirmDelete(context, title: 'Delete "${e.name}"?', message: 'It moves to trash first — you can restore it later from the trash.', confirmLabel: 'Yes, delete');
        if (ok == true) await _do(context, () => PipsApi.deleteFile(e.id));
      }),
    ]));
  }
}

class VersionsPage extends StatelessWidget {
  final Entry e;
  final VoidCallback onChanged;
  const VersionsPage({super.key, required this.e, required this.onChanged});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Versions — ${e.name}', overflow: TextOverflow.ellipsis)),
        body: FutureBuilder<List<dynamic>>(
          future: PipsApi.versions(e.id),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
            final vs = s.data ?? [];
            if (vs.isEmpty) return const EmptyState(icon: '🕓', text: 'No older versions.');
            return ListView.builder(itemCount: vs.length, itemBuilder: (_, i) {
              final v = Map<String, dynamic>.from(vs[i] as Map);
              final vnum = v['version'] is num ? (v['version'] as num).toInt() : i + 1;
              return ListTile(
                leading: const IconTile(icon: Icons.history, bg: Color(0xFFF5F3FF), fg: AppTheme.purple),
                title: Text('Version $vnum'),
                subtitle: Text(fmtDate(v['created_at']?.toString())),
                trailing: Wrap(spacing: 4, children: [
                  IconButton(icon: const Icon(Icons.download, size: 20), onPressed: () async {
                    try { await PipsApi.downloadToFile(PipsApi.versionDownloadUrl(e.id, vnum), File('${(await getTemporaryDirectory()).path}/${e.name}.v$vnum'), (_) {}); if (context.mounted) toast(context, 'Downloaded v$vnum'); } on ApiException catch (ex) { if (context.mounted) toast(context, ex.message); }
                  }),
                  if (vnum != e.version) IconButton(icon: const Icon(Icons.restore, size: 20), onPressed: () async {
                    try { await PipsApi.restoreVersion(e.id, vnum); onChanged(); if (context.mounted) toast(context, 'Restored v$vnum'); } on ApiException catch (ex) { if (context.mounted) toast(context, ex.message); }
                  }),
                ]),
              );
            });
          },
        ),
      );
}

class FoldersPage extends StatefulWidget {
  const FoldersPage({super.key});
  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  Key refresh = UniqueKey();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Folders'), actions: [
          IconButton(icon: const Icon(Icons.explore_outlined), tooltip: 'Open in Explorer', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CloudExplorerPage()))),
          IconButton(icon: const Icon(Icons.create_new_folder_outlined), onPressed: () async {
            final c = TextEditingController();
            final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('New folder'), content: TextField(controller: c, decoration: const InputDecoration(hintText: 'Folder name')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Create'))]));
            if (name != null && name.isNotEmpty) {
              try { await PipsApi.createFolder(name); setState(() => refresh = UniqueKey()); } on ApiException catch (ex) { if (context.mounted) toast(context, ex.message); }
            }
          }),
        ]),
        body: FutureBuilder<List<dynamic>>(
          key: refresh,
          future: PipsApi.folders(),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
            final items = (s.data ?? []);
            if (items.isEmpty) return const EmptyState(icon: '📁', text: 'No folders yet.');
            return ListView.builder(itemCount: items.length, itemBuilder: (_, i) {
              final f = Map<String, dynamic>.from(items[i] as Map);
              final name = (f['name'] ?? f['path'] ?? 'folder').toString();
              final id = (f['id'] ?? '').toString();
              return ListTile(
                leading: const IconTile(icon: Icons.folder_rounded, bg: Color(0xFFFEF3C7), fg: Color(0xFFD97706)),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: PopupMenuButton<String>(onSelected: (a) async {
                  try {
                    if (a == 'del') {
                      final ok = await confirmDelete(context, title: 'Delete folder "$name"?', message: 'Files inside stay safe — only the folder is removed.', confirmLabel: 'Yes, delete');
                      if (!ok) return;
                      await PipsApi.deleteFolder(id);
                      setState(() => refresh = UniqueKey());
                    }
                    if (a == 'ren') {
                      final c = TextEditingController(text: name);
                      final n = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Rename folder'), content: TextField(controller: c), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save'))]));
                      if (n != null && n.isNotEmpty) { await PipsApi.renameFolder(id, n); setState(() => refresh = UniqueKey()); }
                    }
                  } on ApiException catch (ex) { if (context.mounted) toast(context, ex.message); }
                }, itemBuilder: (_) => const [PopupMenuItem(value: 'ren', child: Text('Rename')), PopupMenuItem(value: 'del', child: Text('Delete'))]),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FolderPage(folder: name))),
              );
            });
          },
        ),
      );
}

class FolderPage extends StatefulWidget {
  final String folder;
  const FolderPage({super.key, required this.folder});
  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  Key refresh = UniqueKey();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.folder)),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showSheet(context, UploadSheet(presetFolder: widget.folder)),
          icon: const Icon(Icons.upload), label: const Text('Upload here'),
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          key: refresh,
          future: PipsApi.filesTree(widget.folder),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
            final tree = s.data ?? {};
            final entries = (tree[widget.folder] ?? tree[''] ?? const []) as List;
            if (entries.isEmpty) return const EmptyState(icon: '📂', text: 'This folder is empty.');
            final items = entries.map((e) => Entry(Map<String, dynamic>.from(e as Map))).toList();
            return ListView.builder(itemCount: items.length, itemBuilder: (_, i) => fileTile(context, items[i], () => setState(() => refresh = UniqueKey()), gallery: items));
          },
        ),
      );
}

// ================================================================
// Cloud Explorer — Prism-style folder navigation over the Pips cloud.
// Folders first, then ALL files in the current folder (every type
// allowed). Breadcrumbs, rename/delete folders, upload into a folder.
// ================================================================
class CloudExplorerPage extends StatefulWidget {
  final String initialPath;
  const CloudExplorerPage({super.key, this.initialPath = ''});
  @override
  State<CloudExplorerPage> createState() => _CloudExplorerPageState();
}

class _CloudExplorerPageState extends State<CloudExplorerPage> {
  late String path = widget.initialPath;
  Key refresh = UniqueKey();

  void reload() => setState(() => refresh = UniqueKey());
  void go(String p) => setState(() { path = p; refresh = UniqueKey(); });

  List<String> get _segments => path.isEmpty ? const <String>[] : path.split('/');
  String _label(String p) => p.isEmpty ? 'Pips Cloud' : p.split('/').last;

  Future<void> _newFolder() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(path.isEmpty ? 'New folder' : 'New folder in “${_label(path)}”'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'Folder name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await PipsApi.createFolder(path.isEmpty ? name : '$path/$name');
      reload();
    } on ApiException catch (ex) {
      if (mounted) toast(context, ex.message);
    }
  }

  Future<void> _folderMenu(BuildContext context, Map<String, dynamic> f) async {
    final id = (f['id'] ?? '').toString();
    final fp = (f['path'] ?? f['name'] ?? '').toString();
    final name = fp.split('/').last;
    try {
      if (id.isEmpty) return;
      if (_lastMenuAction == 'ren') {
        final c = TextEditingController(text: name);
        final n = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
              title: const Text('Rename folder'),
              content: TextField(controller: c),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
              ],
            ));
        if (n != null && n.isNotEmpty) {
          await PipsApi.renameFolder(id, n);
          reload();
        }
      } else if (_lastMenuAction == 'del') {
        await PipsApi.deleteFolder(id);
        reload();
      }
    } on ApiException catch (ex) {
      if (mounted) toast(context, ex.message);
    }
  }

  String? _lastMenuAction;

  @override
  Widget build(BuildContext context) {
    final hc = HomeColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          if (path.isEmpty) const Icon(Icons.cloud_rounded, size: 20, color: AppTheme.blue),
          if (path.isEmpty) const SizedBox(width: 7),
          Expanded(child: Text(_label(path), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.create_new_folder_outlined), tooltip: 'New folder', onPressed: _newFolder),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showSheet(context, UploadSheet(presetFolder: path)),
        icon: const Icon(Icons.upload),
        label: Text(path.isEmpty ? 'Upload' : 'Upload here'),
      ),
      body: Column(children: [
        if (_segments.isNotEmpty) _breadcrumb(hc),
        Expanded(
          child: FutureBuilder<List<dynamic>>(
            key: refresh,
            future: Future.wait<dynamic>([PipsApi.folders(), PipsApi.filesTree(path)]),
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
              final folders = (s.data?[0] as List<dynamic>?) ?? const <dynamic>[];
              final resp = (s.data?[1] as Map<String, dynamic>?) ?? const <String, dynamic>{};
              final tree = (resp['tree'] is Map ? resp['tree'] : const {}) as Map;
              List<dynamic> entriesFor(String p) {
                final v = p.isEmpty ? (tree[''] ?? tree['root']) : tree[p];
                return v is List ? v : const <dynamic>[];
              }

              // Direct sub-folders of the current path
              final subs = <Map<String, dynamic>>[];
              for (final f in folders) {
                final m = Map<String, dynamic>.from(f as Map);
                final fp = (m['path'] ?? m['name'] ?? '').toString();
                if (fp.isEmpty) continue;
                final direct = path.isEmpty
                    ? fp.split('/').length == 1
                    : fp.startsWith('$path/') && !fp.substring(path.length + 1).contains('/');
                if (direct) subs.add(m);
              }
              subs.sort((a, b) =>
                  ((a['path'] ?? a['name'] ?? '') as String).toLowerCase().compareTo(((b['path'] ?? b['name'] ?? '') as String).toLowerCase()));

              // ALL files inside the current folder — every type allowed
              final files = entriesFor(path)
                  .map((e) => Entry(Map<String, dynamic>.from(e as Map)))
                  .where((e) => e.folder == path)
                  .toList();

              if (subs.isEmpty && files.isEmpty) {
                return EmptyState(
                  icon: '📂',
                  text: path.isEmpty
                      ? 'Your cloud is empty — upload your first file.'
                      : 'This folder is empty. Tap “Upload here” to add files.',
                );
              }

              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                children: [
                  if (subs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                      child: Text('Folders · ${subs.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: hc.text2)),
                    ),
                  for (final f in subs)
                    _folderTile(hc, f, entriesFor((f['path'] ?? f['name'] ?? '').toString())),
                  if (files.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 2),
                      child: Text(path.isEmpty ? 'Files · ${files.length}' : 'Files in “${_label(path)}” · ${files.length}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: hc.text2)),
                    ),
                  for (final e in files) fileTile(context, e, reload, gallery: files),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------ breadcrumb
  Widget _breadcrumb(HomeColors hc) => Container(
        margin: const EdgeInsets.fromLTRB(16, 2, 16, 10),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(color: hc.surfaceSoft, borderRadius: BorderRadius.circular(12)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _crumb(hc, 'Pips Cloud', Icons.home_rounded, ''),
            for (var i = 0; i < _segments.length; i++) ...[
              const Icon(Icons.chevron_right_rounded, size: 14, color: Colors.grey),
              _crumb(hc, _segments[i], Icons.folder_rounded, _segments.sublist(0, i + 1).join('/')),
            ],
          ]),
        ),
      );

  Widget _crumb(HomeColors hc, String label, IconData icon, String target) => GestureDetector(
        onTap: () => go(target),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: target == path ? AppTheme.blueSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13.5, color: target == path ? AppTheme.blue : hc.text2),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: target == path ? AppTheme.blue : hc.text2)),
          ]),
        ),
      );

  // ------------------------------------------------------------ folder row
  Widget _folderTile(HomeColors hc, Map<String, dynamic> f, List<dynamic> filesIn) {
    final fp = (f['path'] ?? f['name'] ?? '').toString();
    final name = fp.split('/').last;
    final n = filesIn.length;
    return ListTile(
      leading: const IconTile(icon: Icons.folder_rounded, bg: Color(0xFFFEF3C7), fg: Color(0xFFD97706)),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Text('$n file${n == 1 ? '' : 's'}', style: const TextStyle(fontSize: 12)),
      trailing: PopupMenuButton<String>(
        tooltip: 'Folder options',
        onSelected: (a) async {
          if (a == 'del') {
            final ok = await confirmDelete(context, title: 'Delete folder "$name"?', message: 'Only the folder is removed — files inside keep their places.', confirmLabel: 'Yes, delete');
            if (!ok) return;
          }
          _lastMenuAction = a;
          _folderMenu(context, f);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'ren', child: Text('Rename')),
          PopupMenuItem(value: 'del', child: Text('Delete')),
        ],
      ),
      onTap: () => go(fp),
    );
  }
}
