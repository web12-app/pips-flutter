import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';
import 'files.dart';

class ChannelsPage extends StatelessWidget {
  const ChannelsPage({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(title: const Text('Channels'), bottom: const TabBar(tabs: [Tab(text: 'Mine'), Tab(text: 'Public')])),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateChannelPage())),
            icon: const Icon(Icons.add), label: const Text('Create'),
          ),
          body: const TabBarView(children: [_MineChannels(), _PublicChannels()]),
        ),
      );
}

class _MineChannels extends StatefulWidget {
  const _MineChannels();
  @override
  State<_MineChannels> createState() => _MineChannelsState();
}

class _MineChannelsState extends State<_MineChannels> {
  Key refresh = UniqueKey();
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        key: refresh,
        future: PipsApi.channelsMine(),
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return const Loading();
          final r = s.data ?? {};
          final list = (r['channels'] ?? r['mine'] ?? const []) as List;
          if (list.isEmpty) return const EmptyState(icon: '📺', text: 'You have no channels yet.');
          return ListView.builder(itemCount: list.length, itemBuilder: (_, i) => _channelTile(context, Map<String, dynamic>.from(list[i] as Map), mine: true, onChanged: () => setState(() => refresh = UniqueKey())));
        },
      );
}

class _PublicChannels extends StatefulWidget {
  const _PublicChannels();
  @override
  State<_PublicChannels> createState() => _PublicChannelsState();
}

class _PublicChannelsState extends State<_PublicChannels> {
  String q = '';
  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(
          decoration: InputDecoration(hintText: 'Search public channels…', prefixIcon: const Icon(Icons.search), filled: true, fillColor: const Color(0xFFF8FAFC), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
          onChanged: (v) => setState(() => q = v),
        )),
        Expanded(child: FutureBuilder<List<dynamic>>(
          future: PipsApi.channelsPublic(q),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Loading();
            final list = (s.data ?? []);
            if (list.isEmpty) return const EmptyState(icon: '📺', text: 'No channels found.');
            return ListView.builder(itemCount: list.length, itemBuilder: (_, i) => _channelTile(context, Map<String, dynamic>.from(list[i] as Map), mine: false, onChanged: () {}));
          },
        )),
      ]);
}

Widget _channelTile(BuildContext context, Map<String, dynamic> c, {required bool mine, required VoidCallback onChanged}) {
  final name = (c['name'] ?? 'channel').toString();
  final id = (c['id'] ?? '').toString();
  final desc = (c['description'] ?? '').toString();
  final files = c['files'] is List ? (c['files'] as List).length : (c['file_count'] ?? 0);
  return ListTile(
    leading: CircleAvatar(backgroundColor: AppTheme.purple, child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(color: Colors.white))),
    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(desc.isEmpty ? '$files files' : '$desc · $files files', maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: mine ? PopupMenuButton<String>(onSelected: (a) async {
      if (a == 'del') {
        final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text('Delete "$name"?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))]));
        if (ok == true) { try { await PipsApi.channelDelete(id); onChanged(); } on ApiException catch (e) { if (context.mounted) toast(context, e.message); } }
      }
    }, itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('Delete channel'))]) : null,
    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChannelPage(id: id, name: name, mine: mine))).then((_) => onChanged()),
  );
}

class CreateChannelPage extends StatefulWidget {
  const CreateChannelPage({super.key});
  @override
  State<CreateChannelPage> createState() => _CreateChannelPageState();
}

class _CreateChannelPageState extends State<CreateChannelPage> {
  final name = TextEditingController(), desc = TextEditingController();
  String? posterId;
  bool busy = false;

  Future<void> create() async {
    setState(() => busy = true);
    try {
      await PipsApi.channelCreate(name.text.trim(), desc.text.trim(), posterId);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) { if (mounted) toast(context, e.message); }
    if (mounted) setState(() => busy = false);
  }

  Future<void> pickPoster() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final f = r?.files.single;
    if (f?.path == null) return;
    try {
      final up = await PipsApi.uploadSingle(File(f!.path!), f.name, 'image/png', 'public', (_) {});
      setState(() => posterId = up['id']?.toString());
    } on ApiException catch (e) { if (mounted) toast(context, e.message); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create channel')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Channel name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: pickPoster, icon: const Icon(Icons.image_outlined), label: Text(posterId == null ? 'Pick poster image (optional)' : 'Poster uploaded ✓')),
          const SizedBox(height: 20),
          FilledButton(onPressed: busy ? null : create, style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)), child: Text(busy ? 'Creating…' : 'Create channel')),
        ]),
      );
}

class ChannelPage extends StatefulWidget {
  final String id, name;
  final bool mine;
  const ChannelPage({super.key, required this.id, required this.name, this.mine = false});
  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  String q = '';
  Key refresh = UniqueKey();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.name), actions: [
          if (widget.mine) IconButton(icon: const Icon(Icons.add_to_photos_outlined), onPressed: () async {
            final idC = TextEditingController(), titleC = TextEditingController();
            final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Add file to channel'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: idC, decoration: const InputDecoration(hintText: 'file_id')), TextField(controller: titleC, decoration: const InputDecoration(hintText: 'Title'))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add'))]));
            if (ok == true) { try { await PipsApi.channelAddFile(widget.id, idC.text.trim(), titleC.text.trim()); setState(() => refresh = UniqueKey()); } on ApiException catch (e) { if (context.mounted) toast(context, e.message); } }
          }),
        ]),
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: TextField(
            decoration: InputDecoration(hintText: 'Search in channel…', prefixIcon: const Icon(Icons.search), filled: true, fillColor: const Color(0xFFF8FAFC), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
            onChanged: (v) => setState(() => q = v),
          )),
          Expanded(child: FutureBuilder<List<dynamic>>(
            key: refresh,
            future: q.isEmpty
                ? PipsApi.channelGet(widget.id).then((r) => (r['files'] ?? const []) as List)
                : PipsApi.channelSearchFiles(widget.id, q),
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const Loading();
              final list = (s.data ?? []);
              if (list.isEmpty) return const EmptyState(icon: '📼', text: 'No files in this channel.');
              return ListView.builder(itemCount: list.length, itemBuilder: (_, i) {
                final f = Map<String, dynamic>.from(list[i] as Map);
                final inner = f['file'] is Map ? Map<String, dynamic>.from(f['file'] as Map) : f;
                final e = Entry(inner);
                final title = (f['title'] ?? '').toString();
                final m = metaFor(e.mime, e.name);
                return ListTile(
                  leading: IconTile(icon: m.icon, bg: m.bg, fg: m.fg),
                  title: Text(title.isEmpty ? e.name : title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(fmtBytes(e.size)),
                  trailing: widget.mine ? IconButton(icon: const Icon(Icons.remove_circle_outline, color: AppTheme.red, size: 20), onPressed: () async { try { await PipsApi.channelRemoveFile(widget.id, e.id); setState(() => refresh = UniqueKey()); } on ApiException catch (ex) { if (context.mounted) toast(context, ex.message); } }) : null,
                  onTap: () => showFileSheet(
                    context, e,
                    () => setState(() => refresh = UniqueKey()),
                    gallery: list.map((f) {
                      final m = Map<String, dynamic>.from(f as Map);
                      return Entry(m['file'] is Map ? Map<String, dynamic>.from(m['file'] as Map) : m);
                    }).toList(),
                  ),
                );
              });
            },
          )),
        ]),
      );
}
