import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../api.dart';
import '../mini_player.dart';
import '../models.dart';
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
  ChanItem({
    required this.e,
    required this.title,
    this.addedAt = '',
    this.channelId = '',
    this.channelName = '',
    this.channelOwner = '',
    this.channelLogoId,
  });

  factory ChanItem.fromRaw(Map<String, dynamic> f) {
    final media = f['media'] is Map ? Map<String, dynamic>.from(f['media'] as Map) : <String, dynamic>{};
    final e = Entry(media);
    final t = (f['title'] ?? '').toString();
    final logo = (f['channel_poster_id'] ?? '').toString();
    return ChanItem(
      e: e,
      title: t.isEmpty ? e.name : t,
      addedAt: (f['added_at'] ?? '').toString(),
      channelId: (f['channel_id'] ?? '').toString(),
      channelName: (f['channel_name'] ?? '').toString(),
      channelOwner: (f['owner'] ?? '').toString(),
      channelLogoId: logo.isEmpty ? null : logo,
    );
  }
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

class _ChannelVideoPageState extends State<ChannelVideoPage> {
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

  @override
  void initState() {
    super.initState();
    MiniPlayer.i.stop(); // opening the full page always closes the mini window
    _load(cur, title: curTitle);
  }

  @override
  void dispose() {
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
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(curTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.3)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text('${fmtBytes(cur.size)} · @${curChannelOwner.isNotEmpty ? curChannelOwner : widget.channelOwner}', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
      ),
      // YouTube-style action chips
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Row(children: [
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
              Clipboard.setData(ClipboardData(text: '${PipsApi.base}/v/${cur.id}'));
              toast(context, 'Video link copied');
            },
          ),
        ]),
      ),
      Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(children: [
          ChannelAvatar(fileId: curChannelLogoId, name: curChannelName, radius: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(curChannelName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              Text('@${curChannelOwner}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
            ]),
          ),
          Icon(Icons.subscriptions_outlined, size: 18, color: Colors.grey.shade500),
        ]),
      ),
      const Padding(padding: EdgeInsets.fromLTRB(16, 10, 16, 4), child: Text('Up next', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
      if (related.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No related videos — add more videos to this channel.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ),
      for (final it in related)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: Container(
            width: 96,
            height: 54,
            decoration: BoxDecoration(color: const Color(0xFF16181D), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 30),
          ),
          title: Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          subtitle: Row(children: [
            if (it.channelName.isNotEmpty && it.channelName != curChannelName) ...[
              ChannelAvatar(fileId: it.channelLogoId, name: it.channelName, radius: 8),
              const SizedBox(width: 5),
              Flexible(child: Text(it.channelName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)))]
            else
              Text(fmtBytes(it.e.size), style: const TextStyle(fontSize: 11)),
          ]),
          onTap: () => _load(it.e, title: it.title, item: it),
        ),
    ];
  }

  /// Share the secure web player link — opens in any browser as an embed
  /// player; the raw file URL never leaks (short-lived signed stream).
  Future<void> _shareLink() async {
    try {
      await Share.share('${PipsApi.base}/v/${cur.id}', subject: curTitle);
    } catch (_) {
      Clipboard.setData(ClipboardData(text: '${PipsApi.base}/v/${cur.id}'));
      if (mounted) toast(context, 'Link copied');
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
