import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';

String _fmtDur(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}' : '$m:${s.toString().padLeft(2, '0')}';
}

String _speedLabel(double x) => x.toString().endsWith('.0') ? '${x.toStringAsFixed(0)}×' : '$x×';

enum _DragMode { none, seek, brightness, volume }

/// Advanced custom media player for Pips.
///
/// Gestures (MX-Player style):
///  - tap: show/hide controls
///  - double-tap left/right half: seek -10s / +10s
///  - horizontal drag: scrub with live preview
///  - vertical drag on left half: screen brightness
///  - vertical drag on right half: system volume
/// Extras: playback speed, mute, loop, immersive fullscreen (landscape),
/// playlist sheet with auto-advance.
class AdvancedPlayerView extends StatefulWidget {
  final List<Entry> playlist;
  final int initialIndex;
  final bool audioOnly;
  final bool fullscreen;
  final ValueChanged<bool> onFullscreen;
  final ValueChanged<Entry>? onEntryChanged;
  const AdvancedPlayerView({
    super.key,
    required this.playlist,
    required this.initialIndex,
    required this.audioOnly,
    required this.fullscreen,
    required this.onFullscreen,
    this.onEntryChanged,
  });
  @override
  State<AdvancedPlayerView> createState() => _AdvancedPlayerViewState();
}

class _AdvancedPlayerViewState extends State<AdvancedPlayerView> {
  VideoPlayerController? c;
  int idx = 0;
  String? err;
  bool controls = true;
  bool loopOne = false;
  bool muted = false;
  double speed = 1;
  double? scrub;
  Timer? hide;
  bool loading = false;

  _DragMode mode = _DragMode.none;
  double dragFrom = 0;
  double dragStartX = 0;
  int seekTarget = 0;
  String? bubble;

  @override
  void initState() {
    super.initState();
    idx = widget.initialIndex.clamp(0, widget.playlist.length - 1).toInt();
    _load(idx);
    try {
      VolumeController.instance.showSystemUI = false;
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant AdvancedPlayerView old) {
    super.didUpdateWidget(old);
    if (widget.fullscreen != old.fullscreen) {
      _applySystemUi(widget.fullscreen);
      if (widget.fullscreen) _poke();
    }
  }

  void _applySystemUi(bool fs) {
    try {
      if (fs) {
        SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    hide?.cancel();
    _applySystemUi(false);
    try {
      unawaited(ScreenBrightness().resetApplicationScreenBrightness());
    } catch (_) {}
    c?.removeListener(_tick);
    c?.dispose();
    super.dispose();
  }

  Future<void> _load(int i, {bool autoplay = true}) async {
    if (loading || i < 0 || i >= widget.playlist.length) return;
    loading = true;
    final old = c;
    final nc = VideoPlayerController.networkUrl(
      Uri.parse(PipsApi.viewUrl(widget.playlist[i].id)),
      httpHeaders: PipsApi.authHeaders,
    );
    nc.addListener(_tick);
    if (mounted) {
      setState(() {
        c = nc;
        idx = i;
        err = null;
        scrub = null;
        speed = 1;
        muted = false;
        controls = true;
      });
    }
    widget.onEntryChanged?.call(widget.playlist[i]);
    _poke();
    try {
      await nc.initialize();
      if (mounted) {
        nc.setLooping(loopOne);
        nc.setVolume(muted ? 0 : 1);
        if (autoplay) unawaited(nc.play());
        setState(() {});
      } else {
        try {
          await nc.dispose();
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) setState(() => err = 'Could not load this media.');
    }
    if (old != null) {
      old.removeListener(_tick);
      try {
        await old.dispose();
      } catch (_) {}
    }
    loading = false;
    if (mounted) setState(() {});
  }

  void _tick() {
    if (!mounted) return;
    final v = c?.value;
    if (v == null) return;
    final e = v.errorDescription;
    if (e != null && e.isNotEmpty && err == null) setState(() => err = 'Playback error: $e');
    if (!loopOne &&
        v.duration > Duration.zero &&
        v.position >= v.duration &&
        idx < widget.playlist.length - 1 &&
        !loading) {
      unawaited(_load(idx + 1));
      return;
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

  Future<void> _toggleLoop() async {
    setState(() => loopOne = !loopOne);
    await c?.setLooping(loopOne);
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

  Future<void> _openPlaylist() async {
    _poke();
    await showSheet(
      context,
      SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(children: [
              const Icon(Icons.queue_music, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Playlist — ${widget.playlist.length} items', style: const TextStyle(fontWeight: FontWeight.w800))),
            ]),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (var i = 0; i < widget.playlist.length; i++)
                  ListTile(
                    dense: true,
                    selected: i == idx,
                    leading: Text('${i + 1}', style: TextStyle(color: i == idx ? Theme.of(context).colorScheme.primary : Colors.grey, fontWeight: FontWeight.w700)),
                    title: Text(widget.playlist[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    subtitle: Text(fmtBytes(widget.playlist[i].size), style: const TextStyle(fontSize: 11)),
                    trailing: i == idx ? const Icon(Icons.play_arrow, size: 18) : null,
                    onTap: () {
                      Navigator.pop(context);
                      _load(i);
                    },
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (err != null) return _error(context);
    final c = this.c;
    if (c == null || !c.value.isInitialized) return const Loading();
    final v = c.value;
    final durMs = v.duration.inMilliseconds;
    final posMs = (scrub ?? v.position.inMilliseconds.toDouble()).clamp(0.0, durMs > 0 ? durMs.toDouble() : 1.0).toDouble();

    return Stack(children: [
      Positioned.fill(
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: widget.audioOnly
              ? _audioArt()
              : AspectRatio(aspectRatio: v.aspectRatio <= 0 ? 16 / 9 : v.aspectRatio, child: VideoPlayer(c)),
        ),
      ),
      if (v.isBuffering) const Center(child: CircularProgressIndicator(color: Colors.white70)),
      Positioned.fill(child: _gestures(Container(color: Colors.transparent))),
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
      IgnorePointer(
        ignoring: !controls,
        child: AnimatedOpacity(
          opacity: controls ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Stack(children: [
            if (widget.fullscreen)
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent])),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: SafeArea(
                    bottom: false,
                    child: Row(children: [
                      IconButton(icon: const Icon(Icons.close_fullscreen), color: Colors.white, onPressed: () => widget.onFullscreen(false)),
                      Expanded(child: Text(widget.playlist[idx].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ),
              ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
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
                              unawaited(c.seekTo(Duration(milliseconds: x.toInt())));
                              setState(() => scrub = null);
                              _poke();
                            },
                          ),
                        ),
                      ),
                      Text(_fmtDur(v.duration), style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ]),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (widget.playlist.length > 1)
                          IconButton(tooltip: 'Playlist', icon: const Icon(Icons.queue_music), color: Colors.white, onPressed: _openPlaylist),
                        IconButton(
                          tooltip: 'Speed',
                          icon: Text(_speedLabel(speed), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                          color: Colors.white,
                          onPressed: _speedMenu,
                        ),
                        IconButton(tooltip: '-10s', icon: const Icon(Icons.replay_10), color: Colors.white, onPressed: () { _poke(); unawaited(_skip(-10)); }),
                        IconButton(
                          tooltip: 'Play / Pause',
                          iconSize: 46,
                          icon: Icon(v.isPlaying ? Icons.pause_circle : Icons.play_circle),
                          color: Colors.white,
                          onPressed: _togglePlay,
                        ),
                        IconButton(tooltip: '+10s', icon: const Icon(Icons.forward_10), color: Colors.white, onPressed: () { _poke(); unawaited(_skip(10)); }),
                        IconButton(tooltip: 'Mute', icon: Icon(muted ? Icons.volume_off : Icons.volume_up), color: Colors.white, onPressed: _toggleMute),
                        IconButton(tooltip: 'Loop', icon: Icon(loopOne ? Icons.repeat_one : Icons.repeat), color: loopOne ? Theme.of(context).colorScheme.primary : Colors.white, onPressed: _toggleLoop),
                        IconButton(
                          tooltip: widget.fullscreen ? 'Exit fullscreen' : 'Fullscreen',
                          icon: Icon(widget.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                          color: Colors.white,
                          onPressed: () => widget.onFullscreen(!widget.fullscreen),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _audioArt() => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(28)),
          child: const Icon(Icons.graphic_eq, size: 80, color: Color(0xFF059669)),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            widget.playlist[idx].name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
      ]);

  Widget _error(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('⚠️', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 10),
            Text(err!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, children: [
              if (idx > 0)
                OutlinedButton.icon(onPressed: () => _load(idx - 1), icon: const Icon(Icons.skip_previous, size: 18), label: const Text('Prev')),
              OutlinedButton.icon(onPressed: () => _load(idx), icon: const Icon(Icons.refresh, size: 18), label: const Text('Retry')),
              if (idx < widget.playlist.length - 1)
                OutlinedButton.icon(onPressed: () => _load(idx + 1), icon: const Icon(Icons.skip_next, size: 18), label: const Text('Next')),
            ]),
          ]),
        ),
      );

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
      onVerticalDragStart: (d) async {
        final w = MediaQuery.of(context).size.width;
        if (d.localPosition.dx < w / 2) {
          mode = _DragMode.brightness;
          var start = 0.5;
          try {
            start = await ScreenBrightness().application;
          } catch (_) {}
          dragFrom = start;
        } else {
          mode = _DragMode.volume;
          var start = 0.5;
          try {
            start = await VolumeController.instance.getVolume();
          } catch (_) {}
          dragFrom = start;
        }
        if (mounted) setState(() {});
      },
      onVerticalDragUpdate: (d) {
        if (mode != _DragMode.brightness && mode != _DragMode.volume) return;
        final h = MediaQuery.of(context).size.height;
        final val = (dragFrom + (-d.delta.dy / (h * 0.5))).clamp(0.0, 1.0).toDouble();
        if (mode == _DragMode.brightness) {
          try {
            unawaited(ScreenBrightness().setApplicationScreenBrightness(val));
          } catch (_) {}
          setState(() => bubble = 'Brightness ${(val * 100).round()}%');
        } else {
          try {
            unawaited(VolumeController.instance.setVolume(val));
          } catch (_) {}
          setState(() => bubble = 'Volume ${(val * 100).round()}%');
        }
      },
      onVerticalDragEnd: (d) {
        if (mode != _DragMode.brightness && mode != _DragMode.volume) return;
        mode = _DragMode.none;
        setState(() => bubble = null);
        _poke();
      },
      child: child,
    );
  }
}
