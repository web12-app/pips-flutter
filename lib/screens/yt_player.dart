import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../api.dart';
import '../mini_player.dart';
import '../models.dart';
import '../services/pip.dart';
import '../widgets.dart';

String _fmtDur(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}' : '$m:${s.toString().padLeft(2, '0')}';
}

String _speedLabel(double x) => x.toString().endsWith('.0') ? '${x.toStringAsFixed(0)}×' : '$x×';

/// One playable item inside a channel (file + display title). Items coming
/// from the public feed or global search also carry their own channel info.
class ChanItem {
  final Entry e;
  final String title;
  final String addedAt;
  final String channelId, channelName, channelOwner;
  final String? channelLogoId;
  final bool locked;
  final String? thumbId;
  final int durationMs;
  final int views;
  final int likes;
  final int dislikes;
  final String? myVote;
  final String kind; // 'video' | 'reel' | 'post'
  final bool adultOnly; // channel is 18+ — needs age confirmation
  ChanItem({
    required this.e,
    required this.title,
    this.addedAt = '',
    this.channelId = '',
    this.channelName = '',
    this.channelOwner = '',
    this.channelLogoId,
    this.locked = false,
    this.thumbId,
    this.durationMs = 0,
    this.views = 0,
    this.likes = 0,
    this.dislikes = 0,
    this.myVote,
    this.kind = 'video',
    this.adultOnly = false,
  });

  factory ChanItem.fromRaw(Map<String, dynamic> f) {
    final media = f['media'] is Map ? Map<String, dynamic>.from(f['media'] as Map) : <String, dynamic>{};
    final e = Entry(media);
    final t = (f['title'] ?? '').toString();
    final logo = (f['channel_poster_id'] ?? '').toString();
    final thumb = f['thumb'] is Map ? Map<String, dynamic>.from(f['thumb'] as Map) : <String, dynamic>{};
    final tid = (thumb['id'] ?? '').toString();
    final mv = (f['my_vote'] ?? '').toString();
    final kd = (f['kind'] ?? 'video').toString();
    return ChanItem(
      e: e,
      title: t.isEmpty ? e.name : t,
      addedAt: (f['added_at'] ?? '').toString(),
      channelId: (f['channel_id'] ?? '').toString(),
      channelName: (f['channel_name'] ?? '').toString(),
      channelOwner: (f['owner'] ?? '').toString(),
      channelLogoId: logo.isEmpty ? null : logo,
      locked: f['locked'] == true,
      thumbId: tid.isEmpty ? null : tid,
      durationMs: f['duration_ms'] is int ? f['duration_ms'] as int : 0,
      views: f['views'] is int ? f['views'] as int : 0,
      likes: f['likes'] is int ? f['likes'] as int : 0,
      dislikes: f['dislikes'] is int ? f['dislikes'] as int : 0,
      myVote: mv.isEmpty ? null : mv,
      kind: kd == 'reel' ? 'reel' : (kd == 'post' ? 'post' : 'video'),
      adultOnly: f['channel_adult_only'] == true,
    );
  }

  ChanItem copyWith({String? thumbId, int? durationMs, int? views, int? likes, int? dislikes, String? myVote, String? kind, bool? adultOnly}) => ChanItem(
        e: e,
        title: title,
        addedAt: addedAt,
        channelId: channelId,
        channelName: channelName,
        channelOwner: channelOwner,
        channelLogoId: channelLogoId,
        locked: locked,
        thumbId: thumbId ?? this.thumbId,
        durationMs: durationMs ?? this.durationMs,
        views: views ?? this.views,
        likes: likes ?? this.likes,
        dislikes: dislikes ?? this.dislikes,
        myVote: myVote ?? this.myVote,
        kind: kind ?? this.kind,
        adultOnly: adultOnly ?? this.adultOnly,
      );
}

enum _DragMode { none, seek, scroll }

/// YouTube-style channel video page.
///
/// Portrait: the player is pinned on top (16:9), below it the title, the
/// channel row (logo + name) and the "Up next" related list. Swiping UP on
/// the video scrolls the panel down to reveal related videos (YouTube
/// behaviour); swiping DOWN at the very top closes the page back to home.
/// Leaving the page while playing hands the video to the floating mini
/// player. Fullscreen rotates to landscape and hides the panel.
class ChannelVideoPage extends StatefulWidget {
  final Entry video;
  final String videoTitle;
  final String channelId, channelName, channelOwner;
  final String? channelLogoId;
  final List<ChanItem> related;
  final Duration startAt;
  const ChannelVideoPage({
    super.key,
    required this.video,
    required this.videoTitle,
    required this.channelId,
    required this.channelName,
    required this.channelOwner,
    this.channelLogoId,
    required this.related,
    this.startAt = Duration.zero,
  });
  @override
  State<ChannelVideoPage> createState() => _ChannelVideoPageState();
}

class _ChannelVideoPageState extends State<ChannelVideoPage> with WidgetsBindingObserver {
  VideoPlayerController? c;
  late Entry cur = widget.video;
  late String curTitle = widget.videoTitle;
  late List<ChanItem> queue = List.of(widget.related);
  late String curChannelId = widget.channelId;
  late String curChannelName = widget.channelName;
  late String curChannelOwner = widget.channelOwner;
  late String? curChannelLogoId = widget.channelLogoId;
  String? err;
  bool controls = true;
  bool muted = false;
  bool fs = false;
  double speed = 1;
  double? scrub;
  Timer? hide;
  bool loading = false;
  bool handedToMini = false;
  double dismissPx = 0;
  bool seeked = false;

  _DragMode mode = _DragMode.none;
  double dragFrom = 0;
  double dragStartX = 0;
  int seekTarget = 0;
  String? bubble;
  final ScrollController listCtrl = ScrollController();

  // YouTube-style engagement state (mockups): thumbnail, duration, views,
  // like/dislike vote and subscribe — synced from queue items / channel info.
  String? curThumbId;
  int curDurationMs = 0, curViews = 0, curLikes = 0, curDislikes = 0;
  String curAddedAt = '';
  String? curMyVote;
  bool voteBusy = false;
  bool? subOverride;
  int? subsOverride;
  Future<Map<String, dynamic>?>? channelInfo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MiniPlayer.i.stop(); // opening the full page always closes the mini window
    _syncMetaFromQueue();
    channelInfo = _loadChannelInfo();
    _load(cur, title: curTitle);
  }

  /// Pull thumb/duration/views/likes for the CURRENT video out of the queue
  /// (the queue always contains every channel/feed item, including the one
  /// currently playing).
  void _syncMetaFromQueue() {
    final i = queue.indexWhere((x) => x.e.id == cur.id);
    if (i < 0) return;
    final it = queue[i];
    curThumbId = it.thumbId;
    curDurationMs = it.durationMs;
    curViews = it.views;
    curLikes = it.likes;
    curDislikes = it.dislikes;
    curAddedAt = it.addedAt;
    curMyVote = it.myVote;
  }

  Future<Map<String, dynamic>?> _loadChannelInfo() async {
    final cid = widget.channelId;
    if (cid.isEmpty) return null;
    try {
      final r = await PipsApi.channelGet(cid);
      return r['channel'] is Map ? Map<String, dynamic>.from(r['channel'] as Map) : null;
    } catch (_) {
      return null;
    }
  }

  /// Write the current engagement counters back into the queue entry, so the
  /// related list and mini-player handover stay consistent.
  void _syncQueueMeta() {
    final i = _curIdx;
    if (i < 0) return;
    final it = queue[i];
    queue[i] = ChanItem(
      e: it.e,
      title: it.title,
      addedAt: it.addedAt,
      channelId: it.channelId,
      channelName: it.channelName,
      channelOwner: it.channelOwner,
      channelLogoId: it.channelLogoId,
      locked: it.locked,
      thumbId: it.thumbId,
      durationMs: it.durationMs,
      views: it.views,
      likes: curLikes,
      dislikes: curDislikes,
      myVote: curMyVote,
      kind: it.kind,
      adultOnly: it.adultOnly,
    );
  }

  /// YouTube-style like / dislike. Tap the active vote again to remove it.
  Future<void> _vote(String v) async {
    if (voteBusy) return;
    final target = curMyVote == v ? 'none' : v;
    setState(() {
      voteBusy = true;
      if (curMyVote == 'like') curLikes = (curLikes - 1).clamp(0, 1 << 30);
      if (curMyVote == 'dislike') curDislikes = (curDislikes - 1).clamp(0, 1 << 30);
      if (target == 'like') curLikes += 1;
      if (target == 'dislike') curDislikes += 1;
      curMyVote = target == 'none' ? null : target;
    });
    try {
      final r = await PipsApi.channelVote(cur.id, target);
      if (mounted) {
        setState(() {
          if (r['likes'] is int) curLikes = r['likes'] as int;
          if (r['dislikes'] is int) curDislikes = r['dislikes'] as int;
          final mv = (r['my_vote'] ?? '').toString();
          curMyVote = mv.isEmpty ? null : mv;
        });
        _syncQueueMeta();
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => voteBusy = false);
  }

  /// Subscribe / unsubscribe to the channel of the current video.
  Future<void> _toggleSubscribe() async {
    final cid = curChannelId;
    if (cid.isEmpty) return;
    setState(() => voteBusy = true);
    try {
      final r = await PipsApi.channelSubscribe(cid);
      if (mounted) {
        setState(() {
          subOverride = r['subscribed'] == true;
          if (r['subscribers'] is int) subsOverride = r['subscribers'] as int;
        });
        toast(context, subOverride == true ? 'Subscribed to ${curChannelName}' : 'Subscription removed');
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => voteBusy = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    hide?.cancel();
    _applySystemUi(false);
    final cc = c;
    final alive = cc != null && cc.value.isInitialized && err == null;
    if (alive && !handedToMini) {
      // Hand the playing video to the floating mini player — it keeps going.
      MiniPlayer.i.attach(
        controller: cc,
        e: cur,
        videoTitle: curTitle,
        channelId: curChannelId,
        channelName: curChannelName,
        channelOwner: curChannelOwner,
        channelLogoId: curChannelLogoId,
        queue: queue,
      );
      cc.removeListener(_tick);
    } else if (!handedToMini) {
      c?.removeListener(_tick);
      c?.dispose();
    }
    c = null;
    listCtrl.dispose();
    super.dispose();
  }

  /// Background the app while a video is playing → keep it alive in a
  /// floating Picture-in-Picture window (Android 8+). Coming back out of PiP
  /// (or normal resume) restores the full screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cc = c;
    if (state == AppLifecycleState.paused) {
      if (cc != null && cc.value.isInitialized && cc.value.isPlaying && !handedToMini) {
        PipsPip.enter();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (!handedToMini) PipsPip.exit();
    }
  }

  void _applySystemUi(bool fullscreen) {
    try {
      if (fullscreen) {
        SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } catch (_) {}
  }

  void _setFs(bool v) {
    setState(() => fs = v);
    _applySystemUi(v);
    if (v) _poke();
  }

  int get _curIdx => queue.indexWhere((x) => x.e.id == cur.id);

  Future<void> _load(Entry e, {String? title, bool autoplay = true, ChanItem? item}) async {
    if (loading) return;
    loading = true;
    final old = c;
    final nc = VideoPlayerController.networkUrl(
      Uri.parse(PipsApi.viewUrl(e.id)),
      httpHeaders: PipsApi.authHeaders,
    );
    nc.addListener(_tick);
    if (mounted) {
      setState(() {
        c = nc;
        cur = e;
        if (title != null) curTitle = title;
        if (item != null) {
          if (item.channelName.isNotEmpty) {
            curChannelId = item.channelId;
            curChannelName = item.channelName;
            curChannelOwner = item.channelOwner;
            curChannelLogoId = item.channelLogoId;
          }
          curThumbId = item.thumbId;
          curDurationMs = item.durationMs;
          curViews = item.views;
          curLikes = item.likes;
          curDislikes = item.dislikes;
          curAddedAt = item.addedAt;
          curMyVote = item.myVote;
        } else {
          _syncMetaFromQueue();
        }
        err = null;
        scrub = null;
        controls = true;
        seeked = false;
      });
    }
    _poke();
    try {
      await nc.initialize();
      if (mounted) {
        nc.setVolume(muted ? 0 : 1);
        nc.setPlaybackSpeed(speed);
        if (!seeked && widget.startAt > Duration.zero && e.id == widget.video.id) {
          seeked = true;
          try {
            await nc.seekTo(widget.startAt);
          } catch (_) {}
        }
        if (autoplay) unawaited(nc.play());
        setState(() {});
      } else {
        try {
          await nc.dispose();
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) setState(() => err = 'Could not load this video.');
    }
    if (old != null) {
      old.removeListener(_tick);
      try {
        await old.dispose();
      } catch (_) {}
    }
    loading = false;
    if (mounted) {
      setState(() {});
      _scrollTop();
    }
  }

  void _scrollTop() {
    if (!listCtrl.hasClients) return;
    try {
      listCtrl.animateTo(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    } catch (_) {}
  }

  void _tick() {
    if (!mounted) return;
    final v = c?.value;
    if (v == null) return;
    final e = v.errorDescription;
    if (e != null && e.isNotEmpty && err == null) setState(() => err = 'Playback error: $e');
    if (!loading && v.duration > Duration.zero && v.position >= v.duration) {
      final i = _curIdx;
      if (i >= 0 && i < queue.length - 1) {
        final next = queue[i + 1];
        unawaited(_load(next.e, title: next.title));
        return;
      }
    }
    setState(() {});
  }

  void _poke() {
    hide?.cancel();
    if (!controls && mounted) setState(() => controls = true);
    hide = Timer(const Duration(seconds: 4), () {
      if (mounted && c?.value.isPlaying == true) setState(() => controls = false);
    });
  }

  Future<void> _skip(int secs) async {
    final c = this.c;
    if (c == null || !c.value.isInitialized) return;
    final t = (c.value.position.inMilliseconds + secs * 1000).clamp(0, c.value.duration.inMilliseconds).toInt();
    await c.seekTo(Duration(milliseconds: t));
  }

  Future<void> _togglePlay() async {
    final c = this.c;
    if (c == null) return;
    _poke();
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      if (c.value.duration > Duration.zero && c.value.position >= c.value.duration) await c.seekTo(Duration.zero);
      await c.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    setState(() => muted = !muted);
    await c?.setVolume(muted ? 0 : 1);
    _poke();
  }

  Future<void> _speedMenu() async {
    _poke();
    final picked = await showSheet<double>(
      context,
      SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(14), child: Text('Playback speed', style: TextStyle(fontWeight: FontWeight.w800))),
          for (final x in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
            ListTile(
              dense: true,
              title: Text(_speedLabel(x), style: const TextStyle(fontSize: 14)),
              trailing: x == speed ? const Icon(Icons.check, size: 18) : null,
              onTap: () => Navigator.pop(context, x),
            ),
        ]),
      ),
    );
    if (picked != null) {
      setState(() => speed = picked);
      await c?.setPlaybackSpeed(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = this.c;
    final v = c?.value;
    final durMs = v?.duration.inMilliseconds ?? 0;
    final posMs = (scrub ?? (v?.position.inMilliseconds.toDouble() ?? 0)).clamp(0.0, durMs > 0 ? durMs.toDouble() : 1.0).toDouble();

    final core = err != null
        ? _errBox()
        : (c == null || v == null || !v.isInitialized)
            ? const Center(child: CircularProgressIndicator(color: Colors.white70))
            : AspectRatio(aspectRatio: v.aspectRatio <= 0 ? 16 / 9 : v.aspectRatio, child: VideoPlayer(c));

    final stack = Stack(fit: StackFit.expand, children: [
      Container(color: Colors.black, alignment: Alignment.center, child: core),
      if (v != null && v.isBuffering && err == null) const Center(child: CircularProgressIndicator(color: Colors.white54)),
      Positioned.fill(child: _gestures(Container(color: Colors.transparent))),
      IgnorePointer(
        ignoring: !controls,
        child: AnimatedOpacity(
          opacity: controls ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: _controls(v, posMs, durMs),
        ),
      ),
      // Always-visible back action — works from the player, fullscreen and
      // mid-gesture alike (in addition to the system back + swipe-down).
      Positioned(
        top: 10,
        left: 10,
        child: GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 19),
          ),
        ),
      ),
      if (bubble != null)
        Center(
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(24)),
              child: Text(bubble!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
        ),
    ]);

    if (fs) return Scaffold(backgroundColor: Colors.black, body: stack);

    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(children: [
          SizedBox(height: w * 9 / 16, width: double.infinity, child: stack),
          Expanded(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: ListView(controller: listCtrl, padding: const EdgeInsets.only(bottom: 24), children: _panel()),
            ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _panel() {
    final related = <ChanItem>[for (final x in queue) if (x.e.id != cur.id) x];
    final owner = curChannelOwner.isNotEmpty ? curChannelOwner : widget.channelOwner;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(curTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.3)),
      ),
      // YouTube-style metadata line: @handle · views · likes · date
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          '@$owner · ${fmtCompact(curViews)} views'
          '${curLikes > 0 ? ' · ${fmtCompact(curLikes)} likes' : ''}'
          '${curAddedAt.isNotEmpty ? ' · ${fmtDate(curAddedAt)}' : ''}',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
      ),
      // Like / dislike pill + share actions (mock1 row)
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _votePill(),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.share_outlined, size: 17, color: AppTheme.blue),
              label: const Text('Share', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              visualDensity: VisualDensity.compact,
              onPressed: _shareLink,
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.copy_rounded, size: 16, color: AppTheme.teal),
              label: const Text('Copy link', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              visualDensity: VisualDensity.compact,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: shareChannelUrl));
                toast(context, 'Video link copied');
              },
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.widgets_outlined, size: 16, color: AppTheme.blue),
              label: const Text('Embed', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              visualDensity: VisualDensity.compact,
              onPressed: _embedLink,
            ),
          ]),
        ),
      ),
      _channelCard(),
      _CommentsSection(fileId: cur.id),
      const Padding(padding: EdgeInsets.fromLTRB(16, 10, 16, 4), child: Text('Up next', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
      if (related.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No related videos — add more videos to this channel.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ),
      for (final it in related)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: SizedBox(
            width: 120,
            height: 68,
            child: VideoThumb(thumbId: it.thumbId, videoId: it.e.id, durationMs: it.durationMs, fallbackBytes: it.e.size, radius: 8),
          ),
          title: Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          subtitle: Row(children: [
            if (it.channelName.isNotEmpty && it.channelName != curChannelName) ...[
              ChannelAvatar(fileId: it.channelLogoId, name: it.channelName, radius: 8),
              const SizedBox(width: 5),
              Flexible(child: Text(it.channelName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)))]
            else
              Expanded(child: Text('${fmtCompact(it.views)} views${it.addedAt.isNotEmpty ? ' · ${fmtDate(it.addedAt)}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
          ]),
          onTap: () => _load(it.e, title: it.title, item: it),
        ),
    ];
  }

  /// Like / dislike pill — one rounded container, tap again to clear (mock1).
  Widget _votePill() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(17)),
          onTap: voteBusy ? null : () => _vote('like'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Row(children: [
              Icon(curMyVote == 'like' ? Icons.thumb_up_alt_rounded : Icons.thumb_up_outlined, size: 17, color: curMyVote == 'like' ? AppTheme.blue : (dark ? Colors.white : Colors.black87)),
              if (curLikes > 0) ...[
                const SizedBox(width: 5),
                Text(fmtCompact(curLikes), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: dark ? Colors.white : Colors.black87)),
              ],
            ]),
          ),
        ),
        Container(width: 1, height: 18, color: Theme.of(context).dividerColor),
        InkWell(
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(17)),
          onTap: voteBusy ? null : () => _vote('dislike'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Icon(curMyVote == 'dislike' ? Icons.thumb_down_alt_rounded : Icons.thumb_down_outlined, size: 17, color: curMyVote == 'dislike' ? AppTheme.red : (dark ? Colors.white : Colors.black87)),
          ),
        ),
      ]),
    );
  }

  /// Channel row with subscriber count + Subscribe button (mock1/mock2).
  Widget _channelCard() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: FutureBuilder<Map<String, dynamic>?>(
        future: channelInfo,
        builder: (_, s) {
          final ch = s.data;
          final subs = subsOverride ?? (ch != null && ch['subscribers'] is int ? ch['subscribers'] as int : null);
          final subscribed = subOverride ?? (ch != null && ch['subscribed'] == true);
          final mine = ch != null && (ch['owner'] ?? '').toString().isNotEmpty && (ch['owner'] ?? '').toString() == PipsApi.username;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: dark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.6)),
            ),
            child: Row(children: [
              ChannelAvatar(fileId: curChannelLogoId, name: curChannelName, radius: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(curChannelName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  Text(
                    '@${curChannelOwner.isEmpty ? 'channel' : curChannelOwner}${subs != null ? ' · ${fmtCompact(subs)} subscribers' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                  ),
                ]),
              ),
              if (mine)
                Text('Your channel', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade500))
              else
                FilledButton(
                  onPressed: voteBusy ? null : _toggleSubscribe,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    backgroundColor: subscribed ? (dark ? Colors.white24 : Colors.black26) : AppTheme.red,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(subscribed ? 'Subscribed' : 'Subscribe', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                ),
            ]),
          );
        },
      ),
    );
  }

  /// Web channel UI link: https://…/channel/<slug>/<file_id>
  /// Opens the app first on mobile (pips:// deep link), otherwise the
  /// public web channel page with the secure player.
  String get shareChannelUrl {
    final slug = curChannelName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return '${PipsApi.base}/channel/${slug.isEmpty ? 'v' : slug}/${cur.id}';
  }

  /// Share the web channel link — opens the Pips app when installed,
  /// otherwise the public web channel UI (secure short-lived stream).
  Future<void> _shareLink() async {
    try {
      await Share.share(shareChannelUrl, subject: curTitle);
    } catch (_) {
      Clipboard.setData(ClipboardData(text: shareChannelUrl));
      if (mounted) toast(context, 'Link copied');
    }
  }

  /// Share the YouTube-style embeddable player link:
  /// https://pips-next.antideploy.com/embedding/<file_id>
  /// — paste the link into any browser (loads a URL preview in an
  /// iframe-ready page) or the <iframe> code into any page/WebView.
  /// Secure play: public, short-lived signed stream, no download.
  Future<void> _embedLink() async {
    final url = '${PipsApi.base}/embedding/${cur.id}';
    final code = '<iframe src="$url" width="100%" height="580" style="border:0" '
        'allow="autoplay; fullscreen; picture-in-picture" allowfullscreen loading="lazy"></iframe>';
    try {
      await Share.share('$url\n\nEmbed code:\n$code', subject: 'Embed — $curTitle');
    } catch (_) {
      Clipboard.setData(ClipboardData(text: url));
      if (mounted) toast(context, 'Embed link copied');
    }
  }

  Widget _errBox() => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('⚠️', style: TextStyle(fontSize: 34)),
            const SizedBox(height: 8),
            Text(err!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: () => _load(cur, title: curTitle), icon: const Icon(Icons.refresh, size: 18), label: const Text('Retry')),
          ]),
        ),
      );

  Widget _controls(VideoPlayerValue? v, double posMs, int durMs) {
    return Column(children: [
      Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent])),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: SafeArea(
          bottom: false,
          child: Row(children: [
            IconButton(
              icon: Icon(fs ? Icons.fullscreen_exit : Icons.arrow_back),
              color: Colors.white,
              onPressed: () {
                if (fs) {
                  _setFs(false);
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            Expanded(child: Text(curTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          ]),
        ),
      ),
      const Spacer(),
      Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])),
        padding: const EdgeInsets.fromLTRB(8, 26, 8, 4),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Text(_fmtDur(Duration(milliseconds: posMs.toInt())), style: const TextStyle(color: Colors.white, fontSize: 11)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: posMs,
                    min: 0,
                    max: durMs > 0 ? durMs.toDouble() : 1.0,
                    onChanged: (x) => setState(() => scrub = x),
                    onChangeEnd: (x) {
                      unawaited(c?.seekTo(Duration(milliseconds: x.toInt())));
                      setState(() => scrub = null);
                      _poke();
                    },
                  ),
                ),
              ),
              Text(_fmtDur(v?.duration ?? Duration.zero), style: const TextStyle(color: Colors.white, fontSize: 11)),
            ]),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Speed', icon: Text(_speedLabel(speed), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)), color: Colors.white, onPressed: _speedMenu),
                IconButton(tooltip: '-10s', icon: const Icon(Icons.replay_10), color: Colors.white, onPressed: () { _poke(); unawaited(_skip(-10)); }),
                IconButton(
                  tooltip: 'Play / Pause',
                  iconSize: 46,
                  icon: Icon(v != null && v.isPlaying ? Icons.pause_circle : Icons.play_circle),
                  color: Colors.white,
                  onPressed: _togglePlay,
                ),
                IconButton(tooltip: '+10s', icon: const Icon(Icons.forward_10), color: Colors.white, onPressed: () { _poke(); unawaited(_skip(10)); }),
                IconButton(tooltip: 'Mute', icon: Icon(muted ? Icons.volume_off : Icons.volume_up), color: Colors.white, onPressed: _toggleMute),
                IconButton(tooltip: 'Share', icon: const Icon(Icons.share_outlined), color: Colors.white, onPressed: _shareLink),
                IconButton(tooltip: 'Fullscreen', icon: const Icon(Icons.fullscreen), color: Colors.white, onPressed: () => _setFs(true)),
              ]),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _gestures(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (mode != _DragMode.none) return;
        if (controls) {
          hide?.cancel();
          setState(() => controls = false);
        } else {
          _poke();
        }
      },
      onDoubleTap: () {},
      onDoubleTapDown: (d) {
        final w = MediaQuery.of(context).size.width;
        final left = d.localPosition.dx < w / 2;
        _poke();
        unawaited(_skip(left ? -10 : 10));
        setState(() => bubble = left ? '-10s' : '+10s');
        Timer(const Duration(milliseconds: 600), () {
          if (mounted && mode == _DragMode.none) setState(() => bubble = null);
        });
      },
      onHorizontalDragStart: (d) {
        final c = this.c;
        if (c == null || !c.value.isInitialized) return;
        mode = _DragMode.seek;
        dragFrom = c.value.position.inMilliseconds.toDouble();
        dragStartX = d.localPosition.dx;
        seekTarget = c.value.position.inMilliseconds;
      },
      onHorizontalDragUpdate: (d) {
        final c = this.c;
        if (mode != _DragMode.seek || c == null || !c.value.isInitialized) return;
        final total = c.value.duration.inMilliseconds;
        if (total <= 0) return;
        final per = total / (MediaQuery.of(context).size.width * 1.8);
        seekTarget = (dragFrom + (d.localPosition.dx - dragStartX) * per).clamp(0, total).toInt();
        final deltaS = ((seekTarget - dragFrom) / 1000).round();
        setState(() => bubble = '${_fmtDur(Duration(milliseconds: seekTarget))}  (${deltaS >= 0 ? '+' : ''}$deltaS s)');
      },
      onHorizontalDragEnd: (d) {
        if (mode != _DragMode.seek) return;
        mode = _DragMode.none;
        setState(() => bubble = null);
        unawaited(c?.seekTo(Duration(milliseconds: seekTarget)));
        _poke();
      },
      // Swipe up/down on the video → scroll the panel to reveal related videos.
      // At the very top, dragging DOWN closes the page (back to home).
      onVerticalDragStart: (d) {
        mode = _DragMode.scroll;
        dismissPx = 0;
      },
      onVerticalDragUpdate: (d) {
        if (mode != _DragMode.scroll || fs) return;
        if (!listCtrl.hasClients) return;
        if (d.delta.dy > 0 && listCtrl.offset <= 0.5) {
          dismissPx += d.delta.dy;
          if (dismissPx > 40 && bubble != 'Release to close ▼') setState(() => bubble = 'Release to close ▼');
          return;
        }
        final max = listCtrl.position.maxScrollExtent;
        final target = (listCtrl.offset - d.delta.dy).clamp(0.0, max);
        if (target != listCtrl.offset) listCtrl.jumpTo(target);
        if (d.delta.dy < 0 && target > 2) {
          if (bubble != 'Related videos') setState(() => bubble = 'Related videos');
        } else if (bubble == 'Related videos') {
          setState(() => bubble = null);
        }
      },
      onVerticalDragEnd: (d) {
        if (mode != _DragMode.scroll) return;
        mode = _DragMode.none;
        if (dismissPx > 90) {
          setState(() {
            bubble = null;
            dismissPx = 0;
          });
          Navigator.pop(context);
          return;
        }
        dismissPx = 0;
        if (bubble == 'Related videos' || bubble == 'Release to close ▼') {
          Timer(const Duration(milliseconds: 450), () {
            if (mounted && bubble == 'Related videos') setState(() => bubble = null);
          });
          if (mounted && bubble == 'Release to close ▼') setState(() => bubble = null);
        }
      },
      child: child,
    );
  }
}

// =================================================================== comments
String _whenOf(String at) {
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
    if (diff.inDays == 1) return 'yesterday';
    return '${months[d.month - 1]} ${d.day}';
  } catch (_) {
    return at;
  }
}

/// YouTube-style comments block under the video: add a comment, like/dislike
/// each one, and a "More" button when there are more than the first page.
class _CommentsSection extends StatefulWidget {
  final String fileId;
  const _CommentsSection({required this.fileId});
  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  Key refresh = UniqueKey();
  final ctrl = TextEditingController();
  bool sending = false;
  int visible = 20;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Future<void> post() async {
    final text = ctrl.text.trim();
    if (text.isEmpty || sending) return;
    if (PipsApi.username == null || PipsApi.username!.isEmpty) {
      toast(context, 'Login to join the conversation.');
      return;
    }
    setState(() => sending = true);
    try {
      await PipsApi.channelAddComment(widget.fileId, text);
      ctrl.clear();
      setState(() => refresh = UniqueKey());
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final hc = HomeColors.of(context);
    return FutureBuilder<List<dynamic>>(
      key: refresh,
      future: PipsApi.channelComments(widget.fileId).catchError((_) => <dynamic>[]),
      builder: (_, s) {
        if (s.connectionState != ConnectionState.done) return const SizedBox.shrink();
        final comments = (s.data ?? []).take(visible).toList();
        final total = s.data?.length ?? 0;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('$total comment${total == 1 ? '' : 's'}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: hc.text1)),
          ),
          // add-a-comment row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              AvatarTile(username: PipsApi.username ?? '?', radius: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: hc.surfaceSoft,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: hc.line),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        onSubmitted: (_) => post(),
                        decoration: InputDecoration(border: InputBorder.none, hintText: 'Add a comment…', isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 10)),
                      ),
                    ),
                    IconButton(
                      icon: sending
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send, size: 18, color: AppTheme.blue),
                      onPressed: sending ? null : post,
                    ),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          if (comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text('No comments yet — be the first.', style: TextStyle(fontSize: 12.5, color: hc.text2)),
            )
          else
            for (final raw in comments) _CommentRow(m: Map<String, dynamic>.from(raw as Map), onVote: (mid, vote) async {
              try {
                await PipsApi.channelVoteComment(widget.fileId, mid, vote);
                if (mounted) setState(() => refresh = UniqueKey());
              } on ApiException catch (e) {
                if (mounted) toast(context, e.message);
              }
            }),
          if (total > visible)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextButton(
                onPressed: () => setState(() => visible += 20),
                child: Text('More (${total - visible} more comments)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppTheme.blue)),
              ),
            ),
        ]);
      },
    );
  }
}

/// One comment: avatar, user, time, text (expandable with "more"), like/dislike.
class _CommentRow extends StatefulWidget {
  final Map<String, dynamic> m;
  final Future<void> Function(String mid, String vote) onVote;
  const _CommentRow({required this.m, required this.onVote});
  @override
  State<_CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<_CommentRow> {
  bool expanded = false;
  static const _longLen = 160;

  @override
  Widget build(BuildContext context) {
    final hc = HomeColors.of(context);
    final m = widget.m;
    final user = (m['user'] ?? '').toString();
    final text = (m['text'] ?? '').toString();
    final likes = m['likes'] is num ? (m['likes'] as num).toInt() : 0;
    final dislikes = m['dislikes'] is num ? (m['dislikes'] as num).toInt() : 0;
    final myVote = (m['my_vote'] ?? '').toString();
    final long = text.length > _longLen && !expanded;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AvatarTile(username: user, radius: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(user.isEmpty ? 'guest' : '@$user', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              const SizedBox(width: 8),
              Text(_whenOf(m['at']?.toString() ?? ''), style: TextStyle(fontSize: 11, color: hc.text2)),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                long ? '${text.substring(0, _longLen)}…' : text,
                style: TextStyle(fontSize: 13, color: hc.text1, height: 1.35),
              ),
            ),
            if (text.length > _longLen)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => expanded = !expanded),
                  child: Text(expanded ? 'less' : 'more', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppTheme.blue)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onVote((m['id'] ?? '').toString(), 'like'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.thumb_up_outlined, size: 16, color: myVote == 'like' ? AppTheme.blue : hc.text2),
                      const SizedBox(width: 4),
                      Text('$likes', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: myVote == 'like' ? AppTheme.blue : hc.text2)),
                    ]),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onVote((m['id'] ?? '').toString(), 'dislike'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.thumb_down_outlined, size: 16, color: myVote == 'dislike' ? AppTheme.red : hc.text2),
                      const SizedBox(width: 4),
                      Text('$dislikes', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: myVote == 'dislike' ? AppTheme.red : hc.text2)),
                    ]),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}
