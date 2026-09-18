import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import '../api.dart';
import '../models.dart' show fmtDate;
import '../widgets.dart';
import 'yt_player.dart';

/// 18+ gate — adult-only channels stay hidden until the viewer confirms an
/// age with a range input. The choice is saved on the device (SharedPreferences)
/// and the selected age can be changed any time from the gate dialog.
const String _kAgeOk = 'pips_age_ok';
const String _kAgeVal = 'pips_age_value';

Future<bool> adultConfirmed() async {
  final p = await SharedPreferences.getInstance();
  return p.getString(_kAgeOk) == '1';
}

Future<int> savedAge() async {
  final p = await SharedPreferences.getInstance();
  final v = int.tryParse(p.getString(_kAgeVal) ?? '') ?? 18;
  return v.clamp(18, 80);
}

Future<void> saveAdultConfirmed(int age) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(_kAgeOk, '1');
  await p.setString(_kAgeVal, '$age');
}

/// Returns true when it is OK to show 18+ content — already confirmed, or the
/// user picks an age on the range input and saves right now.
Future<bool> ensureAdultOk(BuildContext context) async {
  if (await adultConfirmed()) return true;
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _AgeGateDialog(),
  );
  return ok == true;
}

class _AgeGateDialog extends StatefulWidget {
  const _AgeGateDialog();
  @override
  State<_AgeGateDialog> createState() => _AgeGateDialogState();
}

class _AgeGateDialogState extends State<_AgeGateDialog> {
  late int age = 18;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    savedAge().then((v) {
      if (mounted) setState(() => age = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [Text('🔞', style: TextStyle(fontSize: 20)), SizedBox(width: 8), Expanded(child: Text('Adults only (18+)'))]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('This content is restricted. Confirm your age to view this channel and its videos.', style: TextStyle(fontSize: 13, height: 1.4)),
        const SizedBox(height: 14),
        Text('Select your age: $age', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        Slider(
          value: age.toDouble(),
          min: 18,
          max: 80,
          divisions: 62,
          label: '$age',
          activeColor: AppTheme.red,
          onChanged: (v) => setState(() => age = v.round()),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
          onPressed: saving
              ? null
              : () async {
                  setState(() => saving = true);
                  await saveAdultConfirmed(age);
                  if (context.mounted) Navigator.pop(context, true);
                },
          child: Text(saving ? 'Saving…' : 'Save & continue'),
        ),
      ],
    );
  }
}

/// Convenience wrapper — gates a navigation on the 18+ confirmation.
Future<void> gatedNav(BuildContext context, bool adultOnly, VoidCallback go) async {
  if (adultOnly && !await ensureAdultOk(context)) return;
  go();
}

// =================================================================== reels
/// TikTok-style full-screen vertical reel viewer — swipe up/down to move
/// between reels, autoplay with loop, right action rail (like / comment /
/// share / open in player) and the channel row with subscribe.
class ReelsPage extends StatefulWidget {
  final List<ChanItem> reels;
  final int startIndex;
  const ReelsPage({super.key, this.reels = const [], this.startIndex = 0});
  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> {
  late final PageController _pc = PageController(initialPage: widget.startIndex.clamp(0, 1 << 30));
  List<ChanItem> _items = [];
  bool _loading = true;
  int _cur = 0;

  @override
  void initState() {
    super.initState();
    _cur = widget.startIndex;
    if (widget.reels.isNotEmpty) {
      _items = List.of(widget.reels);
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final raw = await PipsApi.channelFeed('', 'reel');
      _items = [for (final x in raw) if (x is Map) ChanItem.fromRaw(Map<String, dynamic>.from(x))].where((i) => i.e.id.isNotEmpty).toList();
    } catch (_) {
      _items = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _open(ChanItem it, int idx) async {
    await gatedNav(context, it.adultOnly, () {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ReelsPage(reels: _items, startIndex: idx)));
    });
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Reels', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? ListView(
              padding: EdgeInsets.zero,
              children: const [
                SkeletonBox(height: 400, radius: 0),
              ],
            )
          : _items.isEmpty
              ? const Center(child: Text('No reels yet — add one from your channel.', style: TextStyle(color: Colors.white70)))
              : PageView.builder(
                  controller: _pc,
                  scrollDirection: Axis.vertical,
                  itemCount: _items.length,
                  onPageChanged: (i) => setState(() => _cur = i),
                  itemBuilder: (_, i) => _ReelTile(
                    item: _items[i],
                    active: i == _cur,
                    onOpenInPlayer: () => _open(_items[i], i),
                  ),
                ),
    );
  }
}

/// One full-screen reel. Owns its video controller; plays only when [active].
class _ReelTile extends StatefulWidget {
  final ChanItem item;
  final bool active;
  final VoidCallback onOpenInPlayer;
  const _ReelTile({required this.item, required this.active, required this.onOpenInPlayer});
  @override
  State<_ReelTile> createState() => _ReelTileState();
}

class _ReelTileState extends State<_ReelTile> {
  VideoPlayerController? _vc;
  bool _ready = false;
  bool _failed = false;
  bool _muted = false;
  bool _voteBusy = false;
  bool? _subscribed;
  int? _subsCount;
  int _likes = 0;
  int _dislikes = 0;
  String? _myVote;

  ChanItem get it => widget.item;

  @override
  void initState() {
    super.initState();
    _likes = it.likes;
    _dislikes = it.dislikes;
    _myVote = it.myVote;
    _init();
  }

  Future<void> _init() async {
    final vc = VideoPlayerController.networkUrl(
      Uri.parse(PipsApi.viewUrl(it.e.id)),
      httpHeaders: PipsApi.authHeaders,
    );
    _vc = vc;
    vc.addListener(_loop);
    try {
      await vc.initialize();
      if (!mounted) {
        try { await vc.dispose(); } catch (_) {}
        return;
      }
      await vc.setLooping(true);
      await vc.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _loop() {
    if (!mounted) return;
    final v = _vc?.value;
    if (v == null) return;
    if (v.errorDescription != null && v.errorDescription!.isNotEmpty && _ready) {
      setState(() { _failed = true; _ready = false; });
    }
  }

  @override
  void didUpdateWidget(covariant _ReelTile old) {
    super.didUpdateWidget(old);
    final vc = _vc;
    if (vc == null || !vc.value.isInitialized) return;
    if (widget.active && !old.active) {
      vc.play();
    } else if (!widget.active && old.active) {
      vc.pause();
    }
  }

  @override
  void dispose() {
    final vc = _vc;
    vc?.removeListener(_loop);
    try { vc?.dispose(); } catch (_) {}
    _vc = null;
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final vc = _vc;
    if (vc == null || !vc.value.isInitialized) return;
    if (vc.value.isPlaying) {
      await vc.pause();
    } else {
      await vc.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _vc?.setVolume(_muted ? 0 : 1);
  }

  Future<void> _vote(String v) async {
    if (_voteBusy) return;
    final target = _myVote == v ? 'none' : v;
    setState(() {
      _voteBusy = true;
      if (_myVote == 'like') _likes = (_likes - 1).clamp(0, 1 << 30);
      if (_myVote == 'dislike') _dislikes = (_dislikes - 1).clamp(0, 1 << 30);
      if (target == 'like') _likes += 1;
      if (target == 'dislike') _dislikes += 1;
      _myVote = target == 'none' ? null : target;
    });
    try {
      final r = await PipsApi.channelVote(it.e.id, target);
      if (mounted) {
        setState(() {
          if (r['likes'] is int) _likes = r['likes'] as int;
          if (r['dislikes'] is int) _dislikes = r['dislikes'] as int;
          final mv = (r['my_vote'] ?? '').toString();
          _myVote = mv.isEmpty ? null : mv;
        });
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => _voteBusy = false);
  }

  Future<void> _subscribe() async {
    final cid = it.channelId;
    if (cid.isEmpty) return;
    try {
      final r = await PipsApi.channelSubscribe(cid);
      if (mounted) {
        setState(() {
          _subscribed = r['subscribed'] == true;
          if (r['subscribers'] is int) _subsCount = r['subscribers'] as int;
        });
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _share() async {
    final slug = it.channelName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    final url = '${PipsApi.base}/channel/${slug.isEmpty ? 'v' : slug}/${it.e.id}';
    try {
      await Share.share(url, subject: it.title);
    } catch (_) {
      if (mounted) toast(context, 'Share unavailable — link: $url');
    }
  }

  void _comments() {
    showSheet(context, _ReelCommentsSheet(fileId: it.e.id));
  }

  @override
  Widget build(BuildContext context) {
    final vc = _vc;
    return Stack(fit: StackFit.expand, children: [
      Container(color: Colors.black),
      if (_ready && vc != null)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlay,
          onDoubleTap: () => _vote('like'),
          child: Center(child: AspectRatio(aspectRatio: vc.value.aspectRatio <= 0 ? 9 / 16 : vc.value.aspectRatio, child: VideoPlayer(vc))),
        )
      else if (_failed)
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('⚠️', style: TextStyle(fontSize: 30)),
            const SizedBox(height: 8),
            const Text('Could not load this reel.', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () { setState(() { _failed = false; _ready = false; }); _init(); },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ]),
        )
      else
        const Center(child: CircularProgressIndicator(color: Colors.white70)),
      if (_ready && vc != null && !vc.value.isPlaying)
        const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 72)),
      // top-right mute
      Positioned(
        top: 12,
        right: 12,
        child: IconButton(
          tooltip: _muted ? 'Unmute' : 'Mute',
          onPressed: _toggleMute,
          style: IconButton.styleFrom(backgroundColor: Colors.black38),
          icon: Icon(_muted ? Icons.volume_off : Icons.volume_up, color: Colors.white, size: 20),
        ),
      ),
      // right action rail
      Positioned(
        right: 10,
        bottom: 110,
        child: Column(children: [
          _railBtn(
            icon: _myVote == 'like' ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: _myVote == 'like' ? AppTheme.red : Colors.white,
            label: fmtCompact(_likes),
            onTap: _voteBusy ? null : () => _vote('like'),
          ),
          _railBtn(icon: Icons.comment_rounded, color: Colors.white, label: 'Comments', onTap: _comments),
          _railBtn(icon: Icons.share_rounded, color: Colors.white, label: 'Share', onTap: _share),
          _railBtn(icon: Icons.open_in_full_rounded, color: Colors.white, label: 'Watch', onTap: widget.onOpenInPlayer),
        ]),
      ),
      // bottom channel info
      Positioned(
        left: 14,
        right: 78,
        bottom: 34,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ChannelAvatar(fileId: it.channelLogoId, name: it.channelName, radius: 16),
            const SizedBox(width: 9),
            Expanded(
              child: GestureDetector(
                onTap: widget.onOpenInPlayer,
                child: Text(
                  '${it.channelName.isNotEmpty ? it.channelName : '@${it.channelOwner}'}${_subsCount != null ? ' · ${fmtCompact(_subsCount!)} subscribers' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14, shadows: [Shadow(blurRadius: 6, color: Colors.black54)]),
                ),
              ),
            ),
            FilledButton(
              onPressed: _subscribe,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                backgroundColor: _subscribed == true ? Colors.white24 : AppTheme.red,
                foregroundColor: Colors.white,
              ),
              child: Text(_subscribed == true ? 'Subscribed' : 'Subscribe', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            it.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3, shadows: [Shadow(blurRadius: 6, color: Colors.black54)]),
          ),
          const SizedBox(height: 4),
          Text(
            '${fmtCompact(it.views)} views${it.addedAt.isNotEmpty ? ' · ${fmtDate(it.addedAt)}' : ''}${it.adultOnly ? ' · 18+' : ''}',
            style: const TextStyle(color: Colors.white70, fontSize: 11.5),
          ),
        ]),
      ),
      // thin progress line
      if (_ready && vc != null)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: vc,
            builder: (_, v, __) {
              final dur = v.duration.inMilliseconds;
              final p = dur > 0 ? (v.position.inMilliseconds / dur).clamp(0.0, 1.0) : 0.0;
              return LinearProgressIndicator(value: p, minHeight: 2.2, backgroundColor: Colors.white24, color: Colors.white);
            },
          ),
        ),
    ]);
  }

  Widget _railBtn({required IconData icon, required Color color, required String label, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 26),
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Comments bottom sheet for reels (list + add box + like/dislike per comment).
class _ReelCommentsSheet extends StatefulWidget {
  final String fileId;
  const _ReelCommentsSheet({required this.fileId});
  @override
  State<_ReelCommentsSheet> createState() => _ReelCommentsSheetState();
}

class _ReelCommentsSheetState extends State<_ReelCommentsSheet> {
  Key refresh = UniqueKey();
  final ctrl = TextEditingController();
  bool sending = false;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Future<void> post() async {
    final text = ctrl.text.trim();
    if (text.isEmpty || sending) return;
    if (PipsApi.username == null || PipsApi.username!.isEmpty) {
      if (mounted) toast(context, 'Login to join the conversation.');
      return;
    }
    setState(() => sending = true);
    try {
      await PipsApi.channelAddComment(widget.fileId, text);
      ctrl.clear();
      if (mounted) setState(() => refresh = UniqueKey());
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final hc = HomeColors.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.66,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text('Comments', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: hc.text1)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              AvatarTile(username: PipsApi.username ?? '?', radius: 15),
              const SizedBox(width: 9),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: hc.surfaceSoft, borderRadius: BorderRadius.circular(22), border: Border.all(color: hc.line)),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        onSubmitted: (_) => post(),
                        decoration: const InputDecoration(border: InputBorder.none, hintText: 'Add a comment…', isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 10)),
                      ),
                    ),
                    IconButton(
                      icon: sending
                          ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send, size: 17, color: AppTheme.blue),
                      onPressed: sending ? null : post,
                    ),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              key: refresh,
              future: PipsApi.channelComments(widget.fileId).catchError((_) => <dynamic>[]),
              builder: (_, s) {
                if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                final list = s.data ?? const [];
                if (list.isEmpty) return Center(child: Text('No comments yet — be the first.', style: TextStyle(fontSize: 12.5, color: hc.text2)));
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final m = Map<String, dynamic>.from(list[i] as Map);
                    final user = (m['user'] ?? '').toString();
                    final myVote = (m['my_vote'] ?? '').toString();
                    final likes = m['likes'] is num ? (m['likes'] as num).toInt() : 0;
                    final dislikes = m['dislikes'] is num ? (m['dislikes'] as num).toInt() : 0;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        AvatarTile(username: user, radius: 15),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(user.isEmpty ? 'guest' : '@$user', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                            Text((m['text'] ?? '').toString(), style: TextStyle(fontSize: 13, color: hc.text1, height: 1.35)),
                            Row(children: [
                              _cVote(context, Icons.thumb_up_outlined, likes, myVote == 'like', AppTheme.blue, () async {
                                try {
                                  await PipsApi.channelVoteComment(widget.fileId, (m['id'] ?? '').toString(), 'like');
                                  if (mounted) setState(() => refresh = UniqueKey());
                                } on ApiException catch (e) {
                                  if (mounted) toast(context, e.message);
                                }
                              }),
                              const SizedBox(width: 14),
                              _cVote(context, Icons.thumb_down_outlined, dislikes, myVote == 'dislike', AppTheme.red, () async {
                                try {
                                  await PipsApi.channelVoteComment(widget.fileId, (m['id'] ?? '').toString(), 'dislike');
                                  if (mounted) setState(() => refresh = UniqueKey());
                                } on ApiException catch (e) {
                                  if (mounted) toast(context, e.message);
                                }
                              }),
                            ]),
                          ]),
                        ),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _cVote(BuildContext context, IconData icon, int n, bool active, Color c, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: active ? c : HomeColors.of(context).text2),
            const SizedBox(width: 4),
            Text('$n', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: active ? c : HomeColors.of(context).text2)),
          ]),
        ),
      );
}

// =================================================================== shelf
/// Horizontal "Reels" shelf for the home page — 9:16 cards, opens the viewer.
class ReelsShelf extends StatefulWidget {
  const ReelsShelf({super.key});
  @override
  State<ReelsShelf> createState() => _ReelsShelfState();
}

class _ReelsShelfState extends State<ReelsShelf> {
  late Future<List<dynamic>> _f = PipsApi.channelFeed('', 'reel');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _f,
      builder: (_, s) {
        if (s.connectionState != ConnectionState.done) {
          return SizedBox(
            height: 190,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              children: const [SkeletonBox(width: 118, height: 186, radius: 14), SizedBox(width: 10), SkeletonBox(width: 118, height: 186, radius: 14), SizedBox(width: 10), SkeletonBox(width: 118, height: 186, radius: 14)],
            ),
          );
        }
        final items = <ChanItem>[
          for (final x in (s.data ?? const []))
            if (x is Map) ChanItem.fromRaw(Map<String, dynamic>.from(x))
        ].where((i) => i.e.id.isNotEmpty).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.movie_filter_rounded, size: 19, color: AppTheme.purple),
            const SizedBox(width: 6),
            const Expanded(child: Text('Reels', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReelsPage())),
              child: Text('View all', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: HomeColors.of(context).text2)),
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final it = items[i];
                return GestureDetector(
                  onTap: () => gatedNav(context, it.adultOnly, () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ReelsPage(reels: items, startIndex: i)));
                  }),
                  child: Container(
                    width: 118,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: const Color(0xFF16181D)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(fit: StackFit.expand, children: [
                        VideoThumb(thumbId: it.thumbId, videoId: it.e.id, durationMs: it.durationMs, fallbackBytes: it.e.size, radius: 14),
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: Padding(
                            padding: const EdgeInsets.all(7),
                            child: Text(
                              it.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, height: 1.2, shadows: [Shadow(blurRadius: 5, color: Colors.black87)]),
                            ),
                          ),
                        ),
                        const Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.vertical_align_center_rounded, color: Colors.white70, size: 15),
                          ),
                        ),
                        if (it.adultOnly)
                          Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(color: AppTheme.red, borderRadius: BorderRadius.circular(6)),
                                child: const Text('18+', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}
