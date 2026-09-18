import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_youtube_downloader/flutter_youtube_downloader.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';
import 'files.dart';
import 'reels.dart';
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
  final adult = c['adult_only'] == true;
  final meta = '${fmtCompact(subs)} subscribers · $count videos${adult ? ' · 18+' : ''}';
  return ListTile(
    leading: Stack(children: [
      ChannelAvatar(fileId: _posterId(c), name: name, radius: 22),
      if (adult)
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(color: AppTheme.red, borderRadius: BorderRadius.circular(6), border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5)),
            child: const Text('18+', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w800)),
          ),
        ),
    ]),
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
  int tab = 0; // 0 = Videos, 1 = Reels, 2 = Posts, 3 = About
  bool? subOverride;
  int? subsOverride;
  bool subBusy = false;
  bool _adultOk = false;
  Map<String, dynamic>? _ch;
  bool _mine = false;

  @override
  void initState() {
    super.initState();
    adultConfirmed().then((v) {
      if (mounted) setState(() => _adultOk = v);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.name),
          actions: [
            if (_mine)
              IconButton(
                tooltip: 'Channel settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: _openSettings,
              ),
          ],
        ),
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

  /// Settings icon (gear in the app bar) — opens the channel settings page
  /// (edit, banner/logo, adult-only, delete channel).
  Future<void> _openSettings() async {
    final ch = _ch;
    if (ch == null) return;
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ChannelSettingsPage(channel: Map<String, dynamic>.of(ch))));
    if (changed == true && mounted) setState(() => refresh = UniqueKey());
  }

  /// 18+ gate — adult-only channels open public first: nothing is shown
  /// until the viewer confirms an age on the range input.
  Widget _adultGate(String name) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppTheme.red.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Text('🔞', style: TextStyle(fontSize: 40)),
          ),
          const SizedBox(height: 14),
          Text('"$name" is adults only (18+)', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Confirm your age to view this channel and its videos. Your age is saved on this device.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.45)),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13)),
            onPressed: () async {
              final ok = await ensureAdultOk(context);
              if (ok && mounted) setState(() => _adultOk = true);
            },
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Confirm your age'),
          ),
        ]),
      ),
    );
  }

  Widget _body(Map<String, dynamic> ch) {
    final name = (ch['name'] ?? '').toString();
    final desc = (ch['description'] ?? '').toString();
    final owner = (ch['owner'] ?? '').toString();
    final posterId = _posterId(ch);
    final banner = ch['banner'] is Map ? Map<String, dynamic>.from(ch['banner'] as Map) : <String, dynamic>{};
    final bannerId = (banner['id'] ?? '').toString();
    final mine = owner.isNotEmpty && owner == PipsApi.username;
    _ch = ch;
    if (mine != _mine) {
      _mine = mine;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    // split channel content by kind: videos / reels / posts
    final filesRaw = ch['files'] is List ? (ch['files'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList() : <Map<String, dynamic>>[];
    final items = <ChanItem>[];
    final reelItems = <ChanItem>[];
    final posts = <Map<String, dynamic>>[];
    for (final f in filesRaw) {
      final kd = (f['kind'] ?? 'video').toString();
      if (kd == 'post') {
        posts.add(f);
        continue;
      }
      final it = ChanItem.fromRaw(f);
      if (it.e.id.isEmpty) continue;
      if (kd == 'reel') {
        reelItems.add(it);
      } else {
        items.add(it);
      }
    }
    final subs = subsOverride ?? (ch['subscribers'] is int ? ch['subscribers'] as int : 0);
    final subscribed = subOverride ?? (ch['subscribed'] == true);
    final adultOnly = ch['adult_only'] == true;
    // 18+ gate — public first, content only after age confirmation
    if (adultOnly && !_adultOk) return _adultGate(name);
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      _header(ch, name, desc, owner, posterId, bannerId, items.length + reelItems.length, subs, mine),
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
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Settings'),
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
            label: const Text('Add video / reel / post'),
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
      // Videos / Reels / Posts / About tabs — tap a tab to see its content
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.hardEdge,
          child: Row(children: [
            _tabBtn('Videos', 0),
            const SizedBox(width: 8),
            _tabBtn('Reels', 1),
            const SizedBox(width: 8),
            _tabBtn('Posts', 2),
            const SizedBox(width: 8),
            _tabBtn('About', 3),
          ]),
        ),
      ),
      if (tab == 0) ...[
        if (items.isEmpty) const EmptyState(icon: '📼', text: 'No videos in this channel yet.'),
        for (final it in items) _videoTile(it, items, mine, posterId, owner, name),
      ] else if (tab == 1) ...[
        if (reelItems.isEmpty)
          const EmptyState(icon: '🎬', text: 'No reels in this channel yet — add one with "Add video / reel / post".'),
        for (final it in reelItems) _reelTile(it, reelItems),
      ] else if (tab == 2) ...[
        if (posts.isEmpty) const EmptyState(icon: '📝', text: 'No posts yet — share updates with your subscribers.'),
        for (final p in posts.reversed) _postCard(p, mine),
      ] else
        _aboutTab(desc, owner, items, subs),
    ]);
  }

  /// Reel tile in the channel Reels tab — 9:16 card, opens the vertical viewer.
  Widget _reelTile(ChanItem it, List<ChanItem> reels) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(children: [
        GestureDetector(
          onTap: () => gatedNav(context, it.adultOnly, () {
            final idx = reels.indexWhere((x) => x.e.id == it.e.id);
            Navigator.push(context, MaterialPageRoute(builder: (_) => ReelsPage(reels: reels, startIndex: idx < 0 ? 0 : idx)));
          }),
          child: SizedBox(
            width: 86,
            height: 140,
            child: Stack(fit: StackFit.expand, children: [
              VideoThumb(thumbId: it.thumbId, videoId: it.e.id, durationMs: it.durationMs, fallbackBytes: it.e.size, radius: 12),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(6)),
                    child: const Text('Reel', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('${fmtCompact(it.views)} views${it.addedAt.isNotEmpty ? ' · ${fmtDate(it.addedAt)}' : ''}', style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
          ]),
        ),
        const Icon(Icons.vertical_align_center_rounded, size: 20, color: Colors.grey),
      ]),
    );
  }

  /// Channel post card (Posts tab): text + optional image, newest first.
  /// Owner can delete a post from its card.
  Widget _postCard(Map<String, dynamic> p, bool mine) {
    final pid = (p['file_id'] ?? '').toString();
    final text = (p['title'] ?? '').toString();
    final at = (p['added_at'] ?? '').toString();
    final thumb = p['thumb'] is Map ? Map<String, dynamic>.from(p['thumb'] as Map) : <String, dynamic>{};
    final imgId = (thumb['id'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Theme.of(context).dividerColor)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ChannelAvatar(fileId: _posterId(_ch ?? const {}), name: (_ch?['name'] ?? '').toString(), radius: 14),
            const SizedBox(width: 8),
            Expanded(child: Text((_ch?['name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
            Text(fmtDate(at), style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
            if (mine)
              GestureDetector(
                onTap: () async {
                  final ok = await confirmDelete(context, title: 'Delete this post?', message: 'The post is removed for everyone. This cannot be undone.', confirmLabel: 'Delete post');
                  if (ok != true) return;
                  try {
                    await PipsApi.channelRemoveFile(widget.id, pid);
                    if (mounted) {
                      toast(context, 'Post deleted');
                      setState(() => refresh = UniqueKey());
                    }
                  } on ApiException catch (e) {
                    if (mounted) toast(context, e.message);
                  }
                },
                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.delete_outline, size: 17, color: AppTheme.red)),
              ),
          ]),
          const SizedBox(height: 8),
          Text(text.isEmpty ? '(empty post)' : text, style: const TextStyle(fontSize: 13.5, height: 1.4)),
          if (imgId.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: FutureBuilder<Uint8List?>(
                future: loadFileImage(imgId),
                builder: (_, s) => s.data != null
                    ? Image.memory(s.data!, fit: BoxFit.cover, width: double.infinity, height: 180, gaplessPlayback: true)
                    : Container(height: 120, color: const Color(0xFF16181D)),
              ),
            ),
          ],
        ]),
      ),
    );
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
                VideoThumb(thumbId: it.thumbId, videoId: e.id, durationMs: it.durationMs, fallbackBytes: e.size, radius: 9),
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
  final ytLink = TextEditingController();
  bool ytMode = false, fetchingLink = false;
  // content kind: 'video' | 'reel' | 'post' (post = text + optional image)
  String kind = 'video';
  // custom poster (set/change the video poster instead of the auto frame)
  String? customPosterId;
  Uint8List? customPosterBytes;
  String? customPosterPath;

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

  /// flutter_youtube_downloader: extract the direct media URL for the pasted
  /// YouTube link on-device (NewPipe engine), download it to a temp file, then
  /// run the normal device-upload path (thumbnail + duration + channelAddFile).
  Future<void> fetchYt() async {
    if (fetchingLink) return;
    var raw = ytLink.text.trim();
    if (raw.isEmpty) {
      setState(() => err = 'Paste a YouTube link first.');
      return;
    }
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) raw = 'https://$raw';
    setState(() {
      fetchingLink = true;
      err = null;
      prog = 0;
      status = 'Extracting direct link…';
    });
    try {
      final res = await FlutterYoutubeDownloader.extractYoutubeLink(raw, 18);
      final direct = res is String ? res : '';
      if (!direct.startsWith('http')) {
        throw ApiException(direct.isEmpty
            ? 'Could not extract a direct link for that video.'
            : 'Extract failed: $direct', 0);
      }
      if (mounted) setState(() => status = 'Downloading video (360p mp4)…');
      final dir = await getTemporaryDirectory();
      final fname = 'yt_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final f = File('${dir.path}/$fname');
      final client = http.Client();
      try {
        final resp = await client.send(http.Request('GET', Uri.parse(direct))).timeout(const Duration(seconds: 60));
        if (resp.statusCode >= 400) {
          throw ApiException('Direct link fetch failed (HTTP ${resp.statusCode}).', 0);
        }
        final total = resp.contentLength;
        var got = 0;
        final sink = f.openWrite();
        await for (final chunk in resp.stream) {
          got += chunk.length;
          if (mounted && total != null && total > 0) setState(() => prog = got / total);
          sink.add(chunk);
        }
        await sink.close();
      } finally {
        client.close();
      }
      final size = await f.length();
      if (!mounted) return;
      setState(() {
        picked = f;
        pickedName = fname;
        pickedSize = size;
        manual = false;
        ytMode = false;
        if (title.text.isEmpty) title.text = 'YouTube video';
        prog = 0;
        status = '';
      });
      unawaited(_prepare(f.path));
    } on ApiException catch (e) {
      if (mounted) setState(() => err = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => err = 'Extraction failed — try "Add existing file by ID" or the server import instead.');
      }
    } finally {
      if (mounted) setState(() => fetchingLink = false);
    }
  }

  /// Custom poster / post image — upload the picked picture now so it can be
  /// linked as thumb_file_id (upload-time custom poster setting).
  Future<void> pickCustomPoster() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final f = r?.files.single;
    if (f?.path == null) return;
    setState(() { customPosterPath = f!.path; err = null; });
    try {
      final up = await PipsApi.uploadSingle(File(f!.path!), f.name, _imgMime(f.name), 'public', (_) {});
      final id = (up['id'] ?? '').toString();
      if (id.isEmpty) throw ApiException('Upload failed — try again.', 0);
      final bytes = await File(f.path!).readAsBytes();
      if (mounted) setState(() { customPosterId = id; customPosterBytes = bytes; });
    } on ApiException catch (e) {
      if (mounted) {
        toast(context, e.message);
        setState(() { customPosterPath = null; customPosterId = null; customPosterBytes = null; });
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> submit() async {
    if (busy) return;
    setState(() { busy = true; prog = 0; status = 'Uploading…'; err = null; });
    try {
      String fid;
      if (kind == 'post') {
        // text post: no media file, optional image rides along as thumb
        final text = title.text.trim();
        if (text.isEmpty) throw ApiException('Write the post text first.', 0);
        await PipsApi.channelAddFile(widget.cid, '', text, '', customPosterId, 0, 'post');
        if (mounted) Navigator.pop(context, true);
        return;
      }
      if (manual) {
        fid = manualId.text.trim();
        if (fid.isEmpty) throw ApiException('Enter a file ID first.', 0);
        await PipsApi.channelAddFile(widget.cid, fid, title.text.trim(), '', customPosterId, 0, kind);
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
        // Poster: custom poster wins, else the auto-extracted first frame +
        // duration → uploaded as a small public image and linked to the
        // channel video (YouTube-style thumbnails everywhere).
        String? thumbId;
        if (customPosterId != null && customPosterId!.isNotEmpty) {
          thumbId = customPosterId;
        } else if (thumbBytes != null && thumbBytes!.isNotEmpty) {
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
        await PipsApi.channelAddFile(widget.cid, fid, title.text.trim(), '', thumbId, durationMs, kind);
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
            const Text('Add to channel', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            // content kind: Video / Reel / Post
            Row(children: [
              _kindChip('video', Icons.smart_display_outlined, 'Video', AppTheme.blue),
              const SizedBox(width: 8),
              _kindChip('reel', Icons.movie_filter_rounded, 'Reel', AppTheme.purple),
              const SizedBox(width: 8),
              _kindChip('post', Icons.notes_rounded, 'Post', AppTheme.teal),
            ]),
            const SizedBox(height: 12),
            if (kind == 'post') ...[
              TextField(
                controller: title,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Post text', hintText: 'Share an update with your subscribers…', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              SheetTile(
                icon: Icons.image_outlined,
                color: AppTheme.purple,
                label: customPosterId == null ? 'Add image (optional)' : 'Change image',
                onTap: pickCustomPoster,
              ),
              if (customPosterBytes != null) _posterPreview(),
            ] else if (!manual && picked == null) ...[
              SheetTile(icon: Icons.video_library_rounded, color: AppTheme.blue, label: 'Choose video from device', onTap: pick),
              SheetTile(icon: Icons.tag, color: AppTheme.purple, label: 'Add existing file by ID', onTap: () => setState(() { manual = true; ytMode = false; })),
              SheetTile(icon: Icons.smart_display_outlined, color: AppTheme.teal, label: 'From YouTube link (auto-upload)', onTap: () => setState(() => ytMode = !ytMode)),
              if (ytMode) ...[
                const SizedBox(height: 4),
                TextField(
                  controller: ytLink,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'YouTube link', hintText: 'youtube.com/watch?v=…', prefixIcon: Icon(Icons.link, size: 19), border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                if (fetchingLink) ...[
                  ProgressBar(value: prog),
                  const SizedBox(height: 4),
                  Text(status, style: const TextStyle(fontSize: 11)),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: fetchingLink ? null : fetchYt,
                    icon: fetchingLink
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_rounded, size: 17),
                    label: Text(fetchingLink ? 'Fetching video…' : 'Get direct URL & add', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
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
              const SizedBox(height: 8),
              // custom poster setting at upload time
              SheetTile(
                icon: Icons.image_outlined,
                color: AppTheme.purple,
                label: customPosterId == null ? 'Set custom poster (optional)' : 'Change custom poster',
                onTap: pickCustomPoster,
              ),
              if (customPosterBytes != null) _posterPreview(),
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
                child: Text(busy ? (kind == 'post' ? 'Posting…' : 'Adding…') : (kind == 'post' ? 'Publish post' : 'Add to channel')),
              ),
            ),
          ]),
        ),
      );

  Widget _kindChip(String k, IconData icon, String label, Color c) {
    final active = kind == k;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() { kind = k; err = null; }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? c.withValues(alpha: 0.13) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? c : Theme.of(context).dividerColor, width: active ? 1.6 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: active ? c : Colors.grey),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: active ? c : Colors.grey)),
          ]),
        ),
      ),
    );
  }

  Widget _posterPreview() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: customPosterPath != null
              ? Image.file(File(customPosterPath!), fit: BoxFit.cover, width: double.infinity, height: 130)
              : (customPosterBytes != null ? Image.memory(customPosterBytes!, fit: BoxFit.cover, width: double.infinity, height: 130, gaplessPlayback: true) : const SizedBox.shrink()),
        ),
        Positioned(
          right: 6,
          top: 6,
          child: GestureDetector(
            onTap: () => setState(() { customPosterId = null; customPosterBytes = null; customPosterPath = null; }),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ]),
    );
  }
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
  late bool adultOnly = widget.channel['adult_only'] == true;
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
        'adult_only': adultOnly,
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
              const Divider(height: 1),
              SwitchListTile(
                value: adultOnly,
                onChanged: (v) => setState(() => adultOnly = v),
                activeColor: AppTheme.red,
                title: const Text('Adults only (18+) 🔞', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Opens public, but viewers must confirm their age (range input) before the channel and its videos are shown. Hidden from the home feed until the age is saved on their device.', style: TextStyle(fontSize: 12)),
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

  Future<void> _changePoster() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final f = r?.files.single;
    if (f?.path == null) return;
    setState(() => busy = true);
    try {
      final up = await PipsApi.uploadSingle(File(f!.path!), f.name, _imgMime(f.name), 'public', (_) {});
      final id = (up['id'] ?? '').toString();
      if (id.isEmpty) throw ApiException('Upload failed — try again.', 0);
      await PipsApi.channelPatchFile(widget.cid, widget.fileId, {'thumb_file_id': id});
      if (mounted) {
        toast(context, 'Poster updated');
        Navigator.pop(context);
        widget.onChanged();
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => busy = false);
  }

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
          icon: Icons.image_outlined,
          color: AppTheme.purple,
          label: 'Change poster (custom thumbnail)',
          trailing: busy ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)) : null,
          onTap: () {
            if (!busy) _changePoster();
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
                leading: SizedBox(width: 100, height: 56, child: VideoThumb(thumbId: it.thumbId, videoId: it.e.id, durationMs: it.durationMs, fallbackBytes: it.e.size, radius: 8)),
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
