import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';
import 'viewer.dart';
import 'uploads.dart';
import 'misc.dart';

class FilesPage extends StatefulWidget {
  const FilesPage({super.key});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  String q = '', filter = '';
  Key refresh = UniqueKey();
  void reload() => setState(() => refresh = UniqueKey());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Files'), actions: [
          IconButton(icon: const Icon(Icons.create_new_folder_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FoldersPage()))),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrashPage()))),
        ]),
        body: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: TextField(
            decoration: InputDecoration(hintText: 'Search files', prefixIcon: const Icon(Icons.search), filled: true, fillColor: const Color(0xFFF8FAFC), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
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
          Expanded(child: FutureBuilder<List<dynamic>>(
            key: refresh,
            future: q.isEmpty
                ? PipsApi.filesAll()
                : PipsApi.search(q, filter.isEmpty ? null : filter).then((r) => r['files'] is List ? r['files'] as List : (r['results'] is List ? r['results'] as List : <dynamic>[])),
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const Loading();
              final items = (s.data ?? []).map((e) => Entry(Map<String, dynamic>.from(e as Map))).toList()
                ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
              if (items.isEmpty) return const EmptyState(icon: '📭', text: 'No files found.');
              return ListView.builder(itemCount: items.length, itemBuilder: (_, i) => fileTile(context, items[i], reload));
            },
          )),
        ]),
      );
}

Widget fileTile(BuildContext context, Entry e, VoidCallback onChanged) {
  final m = e.isDb ? const TypeMeta(Icons.table_chart_rounded, Color(0xFFF3E8FF), Color(0xFF7C3AED)) : metaFor(e.mime, e.name);
  return ListTile(
    leading: IconTile(icon: m.icon, bg: m.bg, fg: m.fg),
    title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
    subtitle: Text('${fmtBytes(e.size)} · ${fmtDate(e.uploadedAt)}${e.visibility == 'private' ? ' · 🔒' : ''}', style: const TextStyle(fontSize: 12)),
    trailing: const Icon(Icons.more_vert, color: Colors.grey),
    onTap: () => showFileSheet(context, e, onChanged),
  );
}

Future<void> showFileSheet(BuildContext context, Entry e, VoidCallback onChanged) async {
  await showSheet(context, FileActions(e: e, onChanged: onChanged));
}

class FileActions extends StatelessWidget {
  final Entry e;
  final VoidCallback onChanged;
  const FileActions({super.key, required this.e, required this.onChanged});

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

  @override
  Widget build(BuildContext context) {
    final previewable = isImage(e.mime, e.name) || isVideo(e.mime, e.name) || isAudio(e.mime, e.name) || isTexty(e.mime, e.name);
    final priv = e.visibility == 'private';
    return SafeArea(child: ListView(shrinkWrap: true, children: [
      ListTile(title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${fmtBytes(e.size)} · ${priv ? 'Private 🔒' : 'Public 🌐'} · v${e.version}')),
      const Divider(),
      if (previewable) SheetTile(icon: Icons.play_circle_outline, color: AppTheme.blue, label: 'Play / View', onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ViewerPage(e: e))); }),
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
        final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text('Delete "${e.name}"?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))]));
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
            if (s.connectionState != ConnectionState.done) return const Loading();
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
            if (s.connectionState != ConnectionState.done) return const Loading();
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
                    if (a == 'del') { await PipsApi.deleteFolder(id); setState(() => refresh = UniqueKey()); }
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
            if (s.connectionState != ConnectionState.done) return const Loading();
            final tree = s.data ?? {};
            final entries = (tree[widget.folder] ?? tree[''] ?? const []) as List;
            if (entries.isEmpty) return const EmptyState(icon: '📂', text: 'This folder is empty.');
            final items = entries.map((e) => Entry(Map<String, dynamic>.from(e as Map))).toList();
            return ListView.builder(itemCount: items.length, itemBuilder: (_, i) => fileTile(context, items[i], () => setState(() => refresh = UniqueKey())));
          },
        ),
      );
}
