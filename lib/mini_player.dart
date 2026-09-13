import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'models.dart';
import 'services/pip.dart';
import 'widgets.dart';
import 'screens/yt_player.dart';

/// Global navigator key — used by the mini player to float above every page.
final navKey = GlobalKey<NavigatorState>();

/// YouTube-style draggable floating mini video player.
///
/// When the user leaves the watch page while a video plays, the playing
/// [VideoPlayerController] is handed over here instead of being disposed, so
/// audio/video keeps going in a small draggable window. Tap it to reopen the
/// full watch page, drag to move it anywhere, X to close.
class MiniPlayer {
  MiniPlayer._();
  static final MiniPlayer i = MiniPlayer._();

  VideoPlayerController? c;
  Entry? entry;
  String title = '';
  String channelId = '', channelName = '', channelOwner = '';
  String? channelLogoId;
  List<ChanItem> queue = const [];
  Offset pos = const Offset(16, 90);

  OverlayEntry? _entry;
  bool get isActive => _entry != null && c != null;

  /// Takes over a still-initialised controller from the watch page.
  void attach({
    required VideoPlayerController controller,
    required Entry e,
    required String videoTitle,
    String channelId = '',
    String channelName = '',
    String channelOwner = '',
    String? channelLogoId,
    List<ChanItem> queue = const [],
  }) {
    stop(); // never two minis at once
    c = controller;
    entry = e;
    title = videoTitle;
    this.channelId = channelId;
    this.channelName = channelName;
    this.channelOwner = channelOwner;
    this.channelLogoId = channelLogoId;
    this.queue = queue;
    _entry = OverlayEntry(builder: (_) => const _MiniCard());
    try {
      navKey.currentState?.overlay?.insert(_entry!);
    } catch (_) {
      _entry = null;
      c = null;
      entry = null;
    }
  }

  /// Removes the window. Pass disposeController:false when the controller
  /// will be reused somewhere else.
  void stop({bool disposeController = true}) {
    final oe = _entry;
    _entry = null;
    if (oe != null) {
      try {
        oe.remove();
      } catch (_) {}
    }
    final cc = c;
    if (disposeController) {
      c = null;
      entry = null;
      queue = const [];
      if (cc != null) {
        unawaited(Future(() async {
          try {
            await cc.pause();
          } catch (_) {}
          try {
            await cc.dispose();
          } catch (_) {}
        }));
      }
    }
  }

  /// Tap on the mini window → reopen the full watch page at the same spot.
  void expand(BuildContext ctx) {
    final e = entry;
    final t = title;
    final cid = channelId, cname = channelName, cowner = channelOwner, clogo = channelLogoId;
    final q = queue;
    final at = c?.value.position ?? Duration.zero;
    if (e == null) {
      stop();
      return;
    }
    stop(); // controller disposed; the watch page streams fresh and seeks
    try {
      Navigator.of(navKey.currentContext ?? ctx).push(MaterialPageRoute(
        builder: (_) => ChannelVideoPage(
          video: e,
          videoTitle: t,
          channelId: cid,
          channelName: cname,
          channelOwner: cowner,
          channelLogoId: clogo,
          related: q,
          startAt: at,
        ),
      ));
    } catch (_) {}
  }
}

class _MiniCard extends StatefulWidget {
  const _MiniCard();
  @override
  State<_MiniCard> createState() => _MiniCardState();
}

class _MiniCardState extends State<_MiniCard> with WidgetsBindingObserver {
  late Offset _pos = MiniPlayer.i.pos;
  bool dragging = false;
  Timer? _t;
  bool _inPip = false;

  static const double _w = 216;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _t = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// App backgrounded while the mini window is playing → keep the video alive
  /// in a floating Picture-in-Picture window (Android 8+).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = MiniPlayer.i.c;
    if (state == AppLifecycleState.paused) {
      if (c != null && c.value.isInitialized && c.value.isPlaying) {
        PipsPip.enter().then((ok) => _inPip = ok);
      }
    } else if (state == AppLifecycleState.resumed && _inPip) {
      _inPip = false;
      PipsPip.exit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mp = MiniPlayer.i;
    final c = mp.c;
    final size = MediaQuery.of(context).size;
    final h = _w * 9 / 16;
    if (c == null || !c.value.isInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (MiniPlayer.i.isActive) MiniPlayer.i.stop();
      });
      return const SizedBox.shrink();
    }
    final left = _pos.dx.clamp(8.0, (size.width - _w - 8).clamp(8.0, double.infinity));
    final top = _pos.dy.clamp(56.0, (size.height - h - 110).clamp(56.0, double.infinity));
    return Positioned(
      left: left,
      top: top,
      width: _w,
      height: h,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (dragging) return;
          MiniPlayer.i.expand(context);
        },
        onPanStart: (_) => dragging = true,
        onPanUpdate: (d) => setState(() => _pos += d.delta),
        onPanEnd: (_) {
          dragging = false;
          MiniPlayer.i.pos = _pos;
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Stack(fit: StackFit.expand, children: [
            Builder(builder: (_) {
              final sz = c.value.size;
              final vw = sz.width > 0 ? sz.width : 16.0;
              final vh = sz.height > 0 ? sz.height : 9.0;
              return FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: vw,
                  height: vh,
                  child: VideoPlayer(c),
                ),
              );
            }),
              Positioned(
                left: 0, right: 0, top: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 4, 2, 4),
                  decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
                  child: Row(children: [
                    Expanded(
                      child: Text(mp.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                    _miniBtn(icon: c.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, onTap: () {
                      if (c.value.isPlaying) {
                        c.pause();
                      } else {
                        c.play();
                      }
                      if (mounted) setState(() {});
                    }),
                    _miniBtn(icon: Icons.close_rounded, onTap: () => MiniPlayer.i.stop()),
                  ]),
                ),
              ),
              // bottom hairline progress
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: IgnorePointer(
                  child: c.value.duration.inMilliseconds > 0
                      ? LinearProgressIndicator(
                          value: c.value.position.inMilliseconds / c.value.duration.inMilliseconds,
                          minHeight: 2.5,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(AppTheme.red),
                        )
                      : const SizedBox(height: 2.5),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _miniBtn({required IconData icon, required VoidCallback onTap}) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      );
}
