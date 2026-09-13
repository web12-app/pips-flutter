import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';
import 'files.dart';
import 'yt_player.dart';

String? _posterId(Map<String, dynamic> c) {
  final p = c['poster'];
  if (p is! Map) return null;
  final id = p['id'];
  final s = id?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

String _imgMime(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.gif')) return 'image/gif';
  return 'image/png';
}

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
          if (list.isEmpty) return const EmptyState(icon: '📺', text: 'You have no channels yet. Tap Create to start one.');
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
  final count = c['file_count'] is num ? (c['file_count'] as num).toInt() : 0;
  return ListTile(
    leading: ChannelAvatar(fileId: _posterId(c), name: name, radius: 22),
    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(desc.isEmpty ? '$count videos' : '$desc · $count videos', maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: mine ? PopupMenuButton<String>(onSelected: (a) async {
      if (a == 'del') {
        final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text('Delete "$name"?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))]));
        if (ok == true) { try { await PipsApi.channelDelete(id); onChanged(); } on ApiException catch (e) { if (context.mounted) toast(context, e.message); } }
      }
    }, itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('Delete channel'))]) : const Icon(Icons.chevron_right, color: Colors.grey),
    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChannelPage(id: id, name: name))).then((_) => onChanged()),
  );
}

class CreateChannelPage extends StatefulWidget {
  const CreateChannelPage({super.key});
  @override
  State<CreateChannelPage> createState() => _CreateChannelPageState();
}

class _CreateChannelPageState extends State<CreateChannelPage> {
  final name = TextEditingController(), desc = TextEditingController();
  String? posterId, posterPath;
  bool busy = false, upPoster = false;

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
    setState(() { posterPath = f!.path; upPoster = true; });
    try {
      final up = await PipsApi.uploadSingle(File(f!.path!), f.name, _imgMime(f.name), 'public', (_) {});
      setState(() => posterId = up['id']?.toString());
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
      if (mounted) setState(() => posterPath = null);
    }
    if (mounted) setState(() => upPoster = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create channel')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Center(
            child: Column(children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: AppTheme.purple,
                foregroundImage: posterPath != null ? FileImage(File(posterPath!)) : null,
                child: Text(name.text.isEmpty ? '📺' : name.text[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 28)),
              ),
              const SizedBox(height: 8),
              TextButton.icon(onPressed: upPoster ? null : pickPoster, icon: const Icon(Icons.add_a_photo_outlined, size: 18), label: Text(posterPath == null ? 'Choose channel logo' : 'Change logo')),
              if (upPoster) const SizedBox(width: 120, child: LinearProgressIndicator(minHeight: 3)),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Channel name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
          const SizedBox(height: 20),
          FilledButton(onPressed: busy ? null : create, style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)), child: Text(busy ? 'Creating…' : 'Create channel')),
        ]),
      );
}

class ChannelPage extends StatefulWidget {
  final String id, name;
  const ChannelPage({super.key, required this.id, required this.name});
  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  Key refresh = UniqueKey();
  bool descOpen = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.name)),
        body: FutureBuilder<Map<String, dynamic>>(
          key: refresh,
          future: PipsApi.channelGet(widget.id),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Loading();
            if (s.hasError) return const EmptyState(icon: '⚠️', text: 'Could not load this channel.');
            final ch = s.data?['channel'];
            if (ch is! Map) return const EmptyState(icon: '📺', text: 'Channel not found.');
            return _body(Map<String, dynamic>.from(ch as Map));
          },
        ),
      );

  Widget _body(Map<String, dynamic> ch) {
    final name = (ch['name'] ?? '').toString();
    final desc = (ch['description'] ?? '').toString();
    final owner = (ch['owner'] ?? '').toString();
    final posterId = _posterId(ch);
    final mine = owner.isNotEmpty && owner == PipsApi.username;
    final filesRaw = ch['files'] is List ? (ch['files'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList() : <Map<String, dynamic>>[];
    final items = <ChanItem>[];
    for (final f in filesRaw) {
      final it = ChanItem.fromRaw(f);
      if (it.e.id.isNotEmpty) items.add(it);
    }
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      _header(name, desc, owner, posterId, items.length, mine),
      if (mine)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: FilledButton.icon(
            onPressed: _addVideo,
            icon: const Icon(Icons.video_call_rounded),
            label: const Text('Add video'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
      Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 4), child: Text('Videos', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
      if (items.isEmpty) const EmptyState(icon: '📼', text: 'No videos in this channel yet.'),
      for (final it in items) _videoTile(it, items, mine, posterId, owner, name),
    ]);
  }

  Widget _header(String name, String desc, String owner, String? posterId, int count, bool mine) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ChannelAvatar(fileId: posterId, name: name, radius: 26),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('@$owner · $count videos', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          ])),
          if (mine)
            PopupMenuButton<String>(
              onSelected: (a) async { if (a == 'del') await _delete(); },
              itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('Delete channel'))],
            ),
        ]),
        if (desc.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: GestureDetector(
              onTap: () => setState(() => descOpen = !descOpen),
              child: Text(desc, maxLines: descOpen ? 20 : 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4)),
            ),
          ),
      ]),
    );
  }

  Widget _videoTile(ChanItem it, List<ChanItem> items, bool mine, String? posterId, String owner, String name) {
    final e = it.e;
    final video = isVideo(e.mime, e.name);
    final m = metaFor(e.mime, e.name);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: video
          ? Container(
              width: 104, height: 58,
              decoration: BoxDecoration(color: const Color(0xFF16181D), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 32),
            )
          : IconTile(icon: m.icon, bg: m.bg, fg: m.fg, size: 46),
      title: Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text('${fmtBytes(e.size)}${it.addedAt.isNotEmpty ? ' · ${fmtDate(it.addedAt)}' : ''}', style: const TextStyle(fontSize: 11.5)),
      trailing: mine ? IconButton(icon: const Icon(Icons.remove_circle_outline, color: AppTheme.red, size: 20), onPressed: () => _remove(e.id)) : null,
      onTap: () {
        if (!video) {
          showFileSheet(context, e, () => setState(() => refresh = UniqueKey()));
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChannelVideoPage(
              video: e,
              videoTitle: it.title,
              channelId: widget.id,
              channelName: name,
              channelOwner: owner,
              channelLogoId: posterId,
              related: items,
            ),
          ),
        ).then((_) { if (mounted) setState(() => refresh = UniqueKey()); });
      },
    );
  }

  void _addVideo() {
    showSheet(context, AddVideoSheet(cid: widget.id)).then((v) {
      if (v == true && mounted) setState(() => refresh = UniqueKey());
    });
  }

  Future<void> _remove(String fileId) async {
    try {
      await PipsApi.channelRemoveFile(widget.id, fileId);
      setState(() => refresh = UniqueKey());
    } on ApiException catch (e) { if (mounted) toast(context, e.message); }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text('Delete "${widget.name}"?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))]));
    if (ok == true) {
      try {
        await PipsApi.channelDelete(widget.id);
        if (mounted) Navigator.pop(context);
      } on ApiException catch (e) { if (mounted) toast(context, e.message); }
    }
  }
}

/// Bottom sheet: upload a video from the device (with a title) straight into
/// this channel, or link an already-uploaded file by its ID.
class AddVideoSheet extends StatefulWidget {
  final String cid;
  const AddVideoSheet({super.key, required this.cid});
  @override
  State<AddVideoSheet> createState() => _AddVideoSheetState();
}

class _AddVideoSheetState extends State<AddVideoSheet> {
  final title = TextEditingController();
  final manualId = TextEditingController();
  File? picked;
  String pickedName = '';
  int pickedSize = 0;
  bool manual = false, busy = false;
  double prog = 0;
  String status = '';
  String? err;

  static String _videoMime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.mkv')) return 'video/x-matroska';
    if (n.endsWith('.webm')) return 'video/webm';
    if (n.endsWith('.mov')) return 'video/quicktime';
    if (n.endsWith('.m3u8') || n.endsWith('.m3u')) return 'application/vnd.apple.mpegurl';
    return 'video/mp4';
  }

  Future<void> pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.video);
    final f = r?.files.single;
    if (f?.path == null) return;
    setState(() {
      picked = File(f!.path!);
      pickedName = f.name;
      pickedSize = f.size;
      manual = false;
      if (title.text.isEmpty) title.text = f.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    });
  }

  Future<void> submit() async {
    if (busy) return;
    setState(() { busy = true; prog = 0; status = 'Uploading…'; err = null; });
    try {
      String fid;
      if (manual) {
        fid = manualId.text.trim();
        if (fid.isEmpty) throw ApiException('Enter a file ID first.', 0);
      } else {
        final f = picked;
        if (f == null) throw ApiException('Choose a video first.', 0);
        final mime = _videoMime(pickedName);
        if (pickedSize <= PipsApi.singleLimit) {
          final up = await PipsApi.uploadSingle(f, pickedName, mime, 'public', (_) { if (mounted) setState(() => prog = 1); });
          fid = (up['id'] ?? '').toString();
        } else {
          final bytes = await f.readAsBytes();
          final init = await PipsApi.uploadInit(pickedName, pickedSize);
          fid = (init['id'] ?? '').toString();
          final total = (pickedSize + PipsApi.chunkSize - 1) ~/ PipsApi.chunkSize;
          for (var i = 0; i < total; i++) {
            final start = i * PipsApi.chunkSize;
            await PipsApi.uploadChunk(fid, i, bytes.sublist(start, min(start + PipsApi.chunkSize, pickedSize)));
            if (mounted) {
              setState(() {
                prog = min(1, ((i + 1) * PipsApi.chunkSize) / pickedSize);
                status = 'Uploading chunk ${i + 1}/$total';
              });
            }
          }
          await PipsApi.uploadFinish(fid, total, pickedSize, pickedName, mime, 'public');
        }
        if (fid.isEmpty) throw ApiException('Upload failed — no file id returned.', 0);
      }
      await PipsApi.channelAddFile(widget.cid, fid, title.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() { err = e.message; busy = false; status = ''; });
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Add video to channel', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            if (!manual && picked == null) ...[
              SheetTile(icon: Icons.video_library_rounded, color: AppTheme.blue, label: 'Choose video from device', onTap: pick),
              SheetTile(icon: Icons.tag, color: AppTheme.purple, label: 'Add existing file by ID', onTap: () => setState(() => manual = true)),
            ] else ...[
              if (manual && picked == null) ...[
                TextField(controller: manualId, decoration: const InputDecoration(labelText: 'File ID', border: OutlineInputBorder())),
                TextButton(onPressed: () => setState(() => manual = false), child: const Text('Pick from device instead')),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFF0F9FF), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.videocam, size: 18, color: AppTheme.blue),
                      const SizedBox(width: 8),
                      Expanded(child: Text(pickedName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      Text(fmtBytes(pickedSize), style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                    ]),
                    if (busy) ...[
                      const SizedBox(height: 8),
                      ProgressBar(value: prog),
                      const SizedBox(height: 4),
                      Text(status, style: const TextStyle(fontSize: 11)),
                    ],
                  ]),
                ),
                if (!busy) TextButton(onPressed: pick, child: const Text('Choose a different video')),
              ],
              const SizedBox(height: 10),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Video title', border: OutlineInputBorder())),
            ],
            if (err != null) ...[
              const SizedBox(height: 8),
              Text(err!, style: const TextStyle(color: AppTheme.red, fontSize: 12.5)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : submit,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
                child: Text(busy ? 'Adding…' : 'Add to channel'),
              ),
            ),
          ]),
        ),
      );
}
