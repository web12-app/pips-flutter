import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
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
  final int initialTab;
  const ChannelsPage({super.key, this.initialTab = 0});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        initialIndex: initialTab < 0 ? 0 : (initialTab > 1 ? 1 : initialTab),
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
          if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
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
          decoration: InputDecoration(hintText: 'Search public channels…', prefixIcon: const Icon(Icons.search), filled: true, fillColor: HomeColors.of(context).surfaceSoft, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
          onChanged: (v) => setState(() => q = v),
        )),
        Expanded(child: FutureBuilder<List<dynamic>>(
          future: PipsApi.channelsPublic(q),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
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
  final subs = c['subscribers'] is num ? (c['subscribers'] as num).toInt() : 0;
  final meta = '${fmtCompact(subs)} subscribers · $count videos';
  return ListTile(
    leading: ChannelAvatar(fileId: _posterId(c), name: name, radius: 22),
    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(desc.isEmpty ? meta : '$desc · $meta', maxLines: 1, overflow: TextOverflow.ellipsis),
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
  String? posterId, posterPath, bannerId, bannerPath;
  bool busy = false, upPoster = false, upBanner = false;

  Future<void> create() async {
    setState(() => busy = true);
    try {
      await PipsApi.channelCreate(name.text.trim(), desc.text.trim(), posterId, bannerId);
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

  /// Wide channel banner (mock2/mock4) — optional at creation.
  Future<void> pickBanner() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final f = r?.files.single;
    if (f?.path == null) return;
    setState(() { bannerPath = f!.path; upBanner = true; });
    try {
      final up = await PipsApi.uploadSingle(File(f!.path!), f.name, _imgMime(f.name), 'public', (_) {});
      setState(() => bannerId = up['id']?.toString());
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
      if (mounted) setState(() => bannerPath = null);
    }
    if (mounted) setState(() => upBanner = false);
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
              const SizedBox(height: 6),
              // Banner preview (mock2/mock4)
              GestureDetector(
                onTap: upBanner ? null : pickBanner,
                child: Container(
                  width: double.infinity,
                  height: 96,
                  decoration: BoxDecoration(
                    color: const Color(0xFF16181D),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: bannerPath != null
                      ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(File(bannerPath!), fit: BoxFit.cover, width: double.infinity, height: 96))
                      : const Center(child: Icon(Icons.wallpaper_outlined, color: Colors.white24, size: 30)),
                ),
              ),
              const SizedBox(height: 4),
              TextButton.icon(onPressed: upBanner ? null : pickBanner, icon: const Icon(Icons.wallpaper_outlined, size: 18), label: Text(bannerPath == null ? 'Choose channel banner (optional)' : 'Change banner')),
              if (upBanner) const SizedBox(width: 120, child: LinearProgressIndicator(minHeight: 3)),
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
  int tab = 0; // 0 = Videos, 1 = About
  bool? subOverride;
  int? subsOverride;
  bool subBusy = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.name)),
        body: FutureBuilder<Map<String, dynamic>>(
          key: refresh,
          future: PipsApi.channelGet(widget.id),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
            if (s.hasError) return const EmptyState(icon: '⚠️', text: 'Could not load this channel.');
            final ch = s.data?['channel'];
            if (ch is! Map) return const EmptyState(icon: '📺', text: 'Channel not found.');
            return _body(Map<String, dynamic>.from(ch));
          },
        ),
      );

  Widget _body(Map<String, dynamic> ch) {
    final name = (ch['name'] ?? '').toString();
    final desc = (ch['description'] ?? '').toString();
    final owner = (ch['owner'] ?? '').toString();
    final posterId = _posterId(ch);
    final banner = ch['banner'] is Map ? Map<String, dynamic>.from(ch['banner'] as Map) : <String, dynamic>{};
    final bannerId = (banner['id'] ?? '').toString();
    final mine = owner.isNotEmpty && owner == PipsApi.username;
    final filesRaw = ch['files'] is List ? (ch['files'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList() : <Map<String, dynamic>>[];
    final items = <ChanItem>[];
    for (final f in filesRaw) {
      final it = ChanItem.fromRaw(f);
      if (it.e.id.isNotEmpty) items.add(it);
    }
    final subs = subsOverride ?? (ch['subscribers'] is int ? ch['subscribers'] as int : 0);
    final subscribed = subOverride ?? (ch['subscribed'] == true);
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      _header(ch, name, desc, owner, posterId, bannerId, items.length, subs, mine),
      if (mine) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChannelAnalyticsPage(channel: Map<String, dynamic>.of(ch)))),
                icon: const Icon(Icons.insights, size: 18),
                label: const Text('Analytics'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ChannelSettingsPage(channel: Map<String, dynamic>.of(ch))));
                  if (changed == true && mounted) setState(() => refresh = UniqueKey());
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit channel'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: FilledButton.icon(
            onPressed: _addVideo,
            icon: const Icon(Icons.video_call_rounded),
            label: const Text('Add video'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
      ] else
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: FilledButton(
            onPressed: subBusy ? null : () => _toggleSubscribe(ch),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              backgroundColor: subscribed ? Theme.of(context).dividerColor : AppTheme.red,
              foregroundColor: subscribed ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87) : Colors.white,
            ),
            child: Text(subBusy ? '…' : (subscribed ? 'Subscribed' : 'Subscribe'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      // Videos / About tabs (mock2)
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
        child: Row(children: [
          _tabBtn('Videos', 0),
          const SizedBox(width: 8),
          _tabBtn('About', 1),
        ]),
      ),
      if (tab == 0) ...[
        if (items.isEmpty) const EmptyState(icon: '📼', text: 'No videos in this channel yet.'),
        for (final it in items) _videoTile(it, items, mine, posterId, owner, name),
      ] else
        _aboutTab(desc, owner, items, subs),
    ]);
  }

  Widget _tabBtn(String label, int i) {
    final active = tab == i;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => setState(() => tab = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: active ? (dark ? Colors.white.withValues(alpha: 0.13) : Colors.black.withValues(alpha: 0.08)) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: active ? Colors.transparent : Theme.of(context).dividerColor),
        ),
        child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: active ? FontWeight.w800 : FontWeight.w600, color: active ? null : Colors.grey.shade600)),
      ),
    );
  }

  Future<void> _toggleSubscribe(Map<String, dynamic> ch) async {
    final cid = (ch['id'] ?? '').toString();
    if (cid.isEmpty) return;
    setState(() => subBusy = true);
    try {
      final r = await PipsApi.channelSubscribe(cid);
      if (mounted) {
        setState(() {
          subOverride = r['subscribed'] == true;
          if (r['subscribers'] is int) subsOverride = r['subscribers'] as int;
        });
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => subBusy = false);
  }

  Widget _header(Map<String, dynamic> settingsChannel, String name, String desc, String owner, String? posterId, String bannerId, int count, int subs, bool mine) {
    final visibility = (settingsChannel['visibility'] ?? 'public').toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Banner (mock2/mock4) with the avatar overlapping its bottom edge
      Stack(clipBehavior: Clip.none, children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          height: 128,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: bannerId.isNotEmpty
                ? FutureBuilder<Uint8List?>(
                    future: loadFileImage(bannerId),
                    builder: (_, s) => s.data != null
                        ? Image.memory(s.data!, fit: BoxFit.cover, width: double.infinity, height: 128, gaplessPlayback: true)
                        : Container(color: const Color(0xFF16181D)),
                  )
                : Container(
                    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2A1B3D), Color(0xFF16181D)])),
                  ),
          ),
        ),
        Positioned(
          left: 26,
          bottom: -28,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, shape: BoxShape.circle),
            child: ChannelAvatar(fileId: posterId, name: name, radius: 31),
          ),
        ),
      ]),
      const SizedBox(height: 36),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('@$owner · ${fmtCompact(subs)} subscribers · $count videos${mine ? ' · ${visibility == 'private' ? 'Private 🔒' : 'Public 🌐'}' : ''}', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          if (desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GestureDetector(
                onTap: () => setState(() => descOpen = !descOpen),
                child: Text(desc, maxLines: descOpen ? 20 : 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4)),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _videoTile(ChanItem it, List<ChanItem> items, bool mine, String? posterId, String owner, String name) {
    final e = it.e;
    final video = isVideo(e.mime, e.name);
    final m = metaFor(e.mime, e.name);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: video
          ? SizedBox(
              width: 120,
              height: 68,
              child: Stack(children: [
                VideoThumb(thumbId: it.thumbId, durationMs: it.durationMs, fallbackBytes: e.size, radius: 9),
                if (it.locked)
                  Positioned(right: 4, top: 4, child: Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(6)), child: const Icon(Icons.lock, size: 12, color: Colors.white))),
              ]),
            )
          : IconTile(icon: m.icon, bg: m.bg, fg: m.fg, size: 46),
      title: Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(
        video
            ? '${it.locked ? '🔒 Locked · ' : ''}${fmtCompact(it.views)} views${it.addedAt.isNotEmpty ? ' · ${fmtDate(it.addedAt)}' : ''}'
            : '${it.locked ? '🔒 Locked · ' : ''}${fmtBytes(e.size)}${it.addedAt.isNotEmpty ? ' · ${fmtDate(it.addedAt)}' : ''}',
        style: const TextStyle(fontSize: 11.5),
      ),
      trailing: mine
          ? IconButton(
              tooltip: 'Video options',
              icon: const Icon(Icons.more_vert, size: 22),
              onPressed: () => showSheet(context, VideoOptionsSheet(
                cid: widget.id,
                fileId: e.id,
                title: it.title,
                locked: it.locked,
                onPlay: () {
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
                onChanged: () { if (mounted) setState(() => refresh = UniqueKey()); },
              )),
            )
          : null,
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

  /// About tab — stats card + full description (mock2 style).
  Widget _aboutTab(String desc, String owner, List<ChanItem> items, int subs) {
    int views = 0, likes = 0;
    for (final it in items) {
      views += it.views;
      likes += it.likes;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).dividerColor)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Stats', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 10),
            Row(children: [
              _stat(fmtCompact(views), 'Views'),
              _stat(fmtCompact(likes), 'Likes'),
              _stat(fmtCompact(subs), 'Subscribers'),
              _stat('${items.length}', 'Videos'),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).dividerColor)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Description', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 6),
            Text(desc.isEmpty ? 'No description yet.' : desc, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.45)),
            const SizedBox(height: 8),
            Text('Created by @$owner', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          ]),
        ),
      ]),
    );
  }

  Widget _stat(String v, String label) => Expanded(
        child: Column(children: [
          Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ]),
      );


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
  Uint8List? thumbBytes;
  int durationMs = 0;
  bool prepping = false;

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
    unawaited(_prepare(f!.path!));
  }

  /// Grab a poster frame + duration from the picked video (device-side), so
  /// channel cards / feed / related lists show real YouTube-style thumbnails.
  Future<void> _prepare(String path) async {
    if (mounted) setState(() => prepping = true);
    try {
      try {
        final vc = VideoPlayerController.file(File(path));
        await vc.initialize();
        durationMs = vc.value.duration.inMilliseconds;
        try {
          await vc.dispose();
        } catch (_) {}
      } catch (_) {}
      try {
        thumbBytes = await VideoThumbnail.thumbnailData(video: path, imageFormat: ImageFormat.JPEG, maxWidth: 640, quality: 80);
      } catch (_) {
        thumbBytes = null;
      }
    } catch (_) {}
    if (mounted) setState(() => prepping = false);
  }

  Future<void> submit() async {
    if (busy) return;
    setState(() { busy = true; prog = 0; status = 'Uploading…'; err = null; });
    try {
      String fid;
      if (manual) {
        fid = manualId.text.trim();
        if (fid.isEmpty) throw ApiException('Enter a file ID first.', 0);
        await PipsApi.channelAddFile(widget.cid, fid, title.text.trim());
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
        // Poster frame + duration → uploaded as a small public image and
        // linked to the channel video (YouTube-style thumbnails everywhere).
        String? thumbId;
        if (thumbBytes != null && thumbBytes!.isNotEmpty) {
          try {
            final dir = await getTemporaryDirectory();
            final tname = 'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
            final tf = File('${dir.path}/$tname');
            await tf.writeAsBytes(thumbBytes!);
            final tup = await PipsApi.uploadSingle(tf, tname, 'image/jpeg', 'public', (_) {});
            thumbId = (tup['id'] ?? '').toString();
          } catch (_) {
            thumbId = null;
          }
        }
        await PipsApi.channelAddFile(widget.cid, fid, title.text.trim(), '', thumbId, durationMs);
      }
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
                TextButton(onPressed: () => setState(() { manual = false; thumbBytes = null; durationMs = 0; }), child: const Text('Pick from device instead')),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? AppTheme.blue.withValues(alpha: 0.14) : const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      SizedBox(
                        width: 92,
                        height: 52,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: thumbBytes != null
                              ? Image.memory(thumbBytes!, fit: BoxFit.cover, gaplessPlayback: true)
                              : Container(color: const Color(0xFF16181D), child: Center(child: prepping ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded, color: Colors.white38, size: 26))),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(pickedName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text('${fmtBytes(pickedSize)}${durationMs > 0 ? ' · ${fmtDurationMs(durationMs)}' : ''}${prepping ? ' · preparing…' : ''}', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                      ])),
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

/// Owner-only channel settings: rename, description, public/private
/// visibility and delete (with confirmation).
class ChannelSettingsPage extends StatefulWidget {
  final Map<String, dynamic> channel;
  const ChannelSettingsPage({super.key, required this.channel});
  @override
  State<ChannelSettingsPage> createState() => _ChannelSettingsPageState();
}

class _ChannelSettingsPageState extends State<ChannelSettingsPage> {
  late final String cid = (widget.channel['id'] ?? '').toString();
  late final TextEditingController name = TextEditingController(text: (widget.channel['name'] ?? '').toString());
  late final TextEditingController desc = TextEditingController(text: (widget.channel['description'] ?? '').toString());
  late String visibility = ((widget.channel['visibility'] ?? 'public').toString() == 'private') ? 'private' : 'public';
  bool busy = false, deleting = false, upArt = false;

  String? get _logoId {
    final p = widget.channel['poster'];
    if (p is! Map) return null;
    final id = (p['id'] ?? '').toString();
    return id.isEmpty ? null : id;
  }

  String? get _bannerId {
    final b = widget.channel['banner'];
    if (b is! Map) return null;
    final id = (b['id'] ?? '').toString();
    return id.isEmpty ? null : id;
  }

  /// Upload a picked image and attach it as the channel logo (poster) or
  /// banner — mock2/mock4 artwork.
  Future<void> pickArt({required bool banner}) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final f = r?.files.single;
    if (f?.path == null) return;
    setState(() => upArt = true);
    try {
      final up = await PipsApi.uploadSingle(File(f!.path!), f.name, _imgMime(f.name), 'public', (_) {});
      final id = (up['id'] ?? '').toString();
      if (id.isNotEmpty) {
        await PipsApi.channelPatch(cid, {banner ? 'banner_file_id' : 'poster_file_id': id});
        if (mounted) {
          setState(() {
            if (banner) {
              widget.channel['banner'] = {'id': id, 'name': f.name, 'mime': _imgMime(f.name)};
            } else {
              widget.channel['poster'] = {'id': id, 'name': f.name, 'mime': _imgMime(f.name)};
            }
          });
          toast(context, banner ? 'Banner updated' : 'Channel logo updated');
        }
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => upArt = false);
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await PipsApi.channelPatch(cid, {
        'name': name.text.trim(),
        'description': desc.text.trim(),
        'visibility': visibility,
      });
      if (mounted) {
        toast(context, 'Channel settings saved');
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> confirmDelete() async {
    final nameOf = (widget.channel['name'] ?? 'channel').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$nameOf"?'),
        content: const Text('The channel and its video list will be removed for everyone. Your uploaded video files stay in your cloud. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete channel'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => deleting = true);
    try {
      await PipsApi.channelDelete(cid);
      if (mounted) {
        toast(context, 'Channel deleted');
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Channel settings')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          // Artwork row — logo + banner pickers (mock2/mock4)
          Row(children: [
            GestureDetector(
              onTap: upArt ? null : () => pickArt(banner: false),
              child: Stack(children: [
                ChannelAvatar(fileId: _logoId, name: name.text, radius: 30),
                const Positioned(right: 0, bottom: 0, child: CircleAvatar(radius: 11, backgroundColor: AppTheme.blue, child: Icon(Icons.edit, size: 12, color: Colors.white))),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: GestureDetector(
                onTap: upArt ? null : () => pickArt(banner: true),
                child: Stack(children: [
                  Container(
                    height: 76,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16181D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: _bannerId != null
                        ? FutureBuilder<Uint8List?>(
                            future: loadFileImage(_bannerId),
                            builder: (_, s) => s.data != null
                                ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(s.data!, fit: BoxFit.cover, width: double.infinity, height: 76, gaplessPlayback: true))
                                : const Center(child: Icon(Icons.image_outlined, color: Colors.white24)),
                          )
                        : const Center(child: Icon(Icons.image_outlined, color: Colors.white24)),
                  ),
                  const Positioned(right: 8, bottom: 8, child: CircleAvatar(radius: 12, backgroundColor: AppTheme.blue, child: Icon(Icons.edit, size: 13, color: Colors.white))),
                ]),
              ),
            ),
          ]),
          if (upArt) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(minHeight: 3)),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Tap the logo to change it · tap the banner to change it', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ),
          const SizedBox(height: 16),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Channel name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(children: [
              SwitchListTile(
                value: visibility == 'public',
                onChanged: (v) => setState(() => visibility = v ? 'public' : 'private'),
                activeColor: AppTheme.blue,
                title: Text(visibility == 'public' ? 'Public 🌐' : 'Private 🔒', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  visibility == 'public'
                      ? 'Anyone can discover this channel; videos appear in the home feed, search and the web share player.'
                      : 'Hidden from discovery — only you see it, and web share playback is disabled.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : save,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
              child: Text(busy ? 'Saving…' : 'Save settings'),
            ),
          ),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 8),
          Center(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.red, side: const BorderSide(color: AppTheme.red), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
              onPressed: deleting ? null : confirmDelete,
              icon: const Icon(Icons.delete_forever_rounded, size: 20),
              label: Text(deleting ? 'Deleting…' : 'Delete channel'),
            ),
          ),
          const SizedBox(height: 6),
          Center(child: Text('Deleting removes the channel for everyone — video files stay in your cloud.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600))),
        ]),
      );
}

// =================================================================== video options (admin)
/// Bottom sheet opened from the 3-dot icon on a channel video (owner only):
/// play, temporarily lock/unlock, watch history (who + when) and delete.
class VideoOptionsSheet extends StatefulWidget {
  final String cid, fileId, title;
  final bool locked;
  final VoidCallback onPlay;
  final VoidCallback onChanged;
  const VideoOptionsSheet({
    super.key,
    required this.cid,
    required this.fileId,
    required this.title,
    required this.onPlay,
    required this.onChanged,
    this.locked = false,
  });

  @override
  State<VideoOptionsSheet> createState() => _VideoOptionsSheetState();
}

class _VideoOptionsSheetState extends State<VideoOptionsSheet> {
  bool busy = false;
  bool showHistory = false;
  List<dynamic>? history;
  bool loadingHistory = false;

  String _when(String at) {
    try {
      final d = DateTime.parse(at).toLocal();
      final now = DateTime.now();
      final diff = now.difference(d);
      String hms(DateTime x) {
        final h = x.hour == 0 ? 12 : x.hour > 12 ? x.hour - 12 : x.hour;
        return '${h}:${x.minute.toString().padLeft(2, '0')} ${x.hour >= 12 ? 'PM' : 'AM'}';
      }
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
      if (d.year == now.year && d.month == now.month && d.day == now.day) return hms(d);
      if (diff.inDays == 1) return 'yesterday ${hms(d)}';
      return '${months[d.month - 1]} ${d.day}, ${hms(d)}';
    } catch (_) {
      return at;
    }
  }

  Future<void> _toggleLock() async {
    setState(() => busy = true);
    try {
      await PipsApi.channelPatchFile(widget.cid, widget.fileId, {'locked': !widget.locked});
      toast(context, widget.locked ? 'Video unlocked' : 'Video temporarily locked — only you can play it.');
      Navigator.pop(context);
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _loadHistory() async {
    setState(() => loadingHistory = true);
    try {
      history = await PipsApi.channelFileViews(widget.cid, widget.fileId);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => loadingHistory = false);
  }

  Future<void> _delete() async {
    final ok = await confirmDelete(context, title: 'Delete "${widget.title}"?', message: 'It is removed from this channel for everyone. The file stays in your cloud storage.', confirmLabel: 'Yes, delete');
    if (!ok) return;
    setState(() => busy = true);
    try {
      await PipsApi.channelRemoveFile(widget.cid, widget.fileId);
      Navigator.pop(context);
      toast(context, 'Video deleted from channel');
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) {
        toast(context, e.message);
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = HomeColors.of(context);
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Row(children: [
            const Icon(Icons.tune, size: 18, color: AppTheme.blue),
            const SizedBox(width: 8),
            const Text('Video options', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const Spacer(),
            if (busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: hc.text2)),
        ),
        const SizedBox(height: 6),
        SheetTile(
          icon: Icons.play_arrow_rounded,
          color: AppTheme.blue,
          label: 'Play video',
          onTap: () {
            Navigator.pop(context);
            widget.onPlay();
          },
        ),
        SheetTile(
          icon: widget.locked ? Icons.lock_open : Icons.lock_outline,
          color: AppTheme.orange,
          label: widget.locked ? 'Unlock video' : 'Temporarily lock video',
          trailing: widget.locked ? const Text('LOCKED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.orange)) : null,
          onTap: _toggleLock,
        ),
        SheetTile(
          icon: Icons.history,
          color: AppTheme.purple,
          label: showHistory ? 'Hide watch history' : 'Watch history (who + when)',
          onTap: () async {
            setState(() => showHistory = !showHistory);
            if (showHistory && history == null) await _loadHistory();
          },
        ),
        if (showHistory)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 2, 24, 8),
            child: loadingHistory
                ? const SizedBox(height: 30, child: Center(child: CircularProgressIndicator()))
                : (history == null || history!.isEmpty)
                    ? Text('No plays recorded yet.', style: TextStyle(fontSize: 12, color: hc.text2))
                    : SizedBox(
                        height: 190,
                        child: ListView.builder(
                          itemCount: history!.length,
                          itemBuilder: (_, i) {
                            final v = Map<String, dynamic>.from(history![i] as Map);
                            final u = (v['user'] ?? '').toString();
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(children: [
                                AvatarTile(username: u, radius: 13),
                                const SizedBox(width: 8),
                                Expanded(child: Text(u.isEmpty ? 'guest' : '@$u', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                                Text(_when(v['at']?.toString() ?? ''), style: TextStyle(fontSize: 11, color: hc.text2)),
                              ]),
                            );
                          },
                        ),
                      ),
          ),
        const Divider(height: 1),
        SheetTile(
          icon: Icons.delete_outline,
          color: AppTheme.red,
          label: 'Delete video from channel',
          onTap: _delete,
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

// =================================================================== analytics
/// Owner channel analytics (mock4 "Analytics" button): totals, per-video
/// performance and who watched what + when.
class ChannelAnalyticsPage extends StatelessWidget {
  final Map<String, dynamic> channel;
  const ChannelAnalyticsPage({super.key, required this.channel});

  Widget _card(String v, String label, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Text(v, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
          ]),
        ),
      );

  Future<void> _showWatchers(BuildContext context, String cid, ChanItem it) async {
    showSheet(
      context,
      SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(14), child: Text('Watch history', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          ),
          SizedBox(
            height: 300,
            width: double.infinity,
            child: FutureBuilder<List<dynamic>>(
              future: PipsApi.channelFileViews(cid, it.e.id),
              builder: (_, s) {
                if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                final list = s.data ?? [];
                if (list.isEmpty) return const Center(child: Text('No plays recorded yet.', style: TextStyle(fontSize: 12.5)));
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final v = Map<String, dynamic>.from(list[i] as Map);
                    final u = (v['user'] ?? '').toString();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        AvatarTile(username: u, radius: 14),
                        const SizedBox(width: 9),
                        Expanded(child: Text(u.isEmpty ? 'guest' : '@$u', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                        Text(fmtDate(v['at']?.toString()), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cid = (channel['id'] ?? '').toString();
    final name = (channel['name'] ?? '').toString();
    return Scaffold(
      appBar: AppBar(title: Text('Analytics — $name')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: PipsApi.channelGet(cid),
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
          if (s.hasError || s.data?['channel'] is! Map) return const EmptyState(icon: '⚠️', text: 'Could not load analytics.');
          final ch = Map<String, dynamic>.from(s.data!['channel'] as Map);
          final filesRaw = ch['files'] is List ? (ch['files'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList() : <Map<String, dynamic>>[];
          final items = <ChanItem>[];
          for (final f in filesRaw) {
            final it = ChanItem.fromRaw(f);
            if (it.e.id.isNotEmpty) items.add(it);
          }
          int views = 0, likes = 0;
          for (final it in items) {
            views += it.views;
            likes += it.likes;
          }
          final subs = ch['subscribers'] is int ? ch['subscribers'] as int : 0;
          final ranked = items.toList()..sort((a, b) => b.views.compareTo(a.views));
          return ListView(padding: const EdgeInsets.all(12), children: [
            Row(children: [
              _card(fmtCompact(views), 'Total views', AppTheme.blue),
              const SizedBox(width: 10),
              _card(fmtCompact(likes), 'Total likes', AppTheme.green),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _card(fmtCompact(subs), 'Subscribers', AppTheme.purple),
              const SizedBox(width: 10),
              _card('${items.length}', 'Videos', AppTheme.orange),
            ]),
            const SizedBox(height: 14),
            const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 4), child: Text('Videos by views', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            if (items.isEmpty)
              const EmptyState(icon: '📼', text: 'No videos yet.'),
            for (final it in ranked)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: SizedBox(width: 100, height: 56, child: VideoThumb(thumbId: it.thumbId, durationMs: it.durationMs, fallbackBytes: it.e.size, radius: 8)),
                title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: Text('${fmtCompact(it.views)} views · ${fmtCompact(it.likes)} likes', style: const TextStyle(fontSize: 11.5)),
                trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                onTap: () => _showWatchers(context, cid, it),
              ),
          ]);
        },
      ),
    );
  }
}
