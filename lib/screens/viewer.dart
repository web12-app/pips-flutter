import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';
import 'player.dart';

final _imgBytesCache = <String, List<int>>{};

Future<List<int>> _loadImageBytes(String id) async {
  if (_imgBytesCache.length > 80) _imgBytesCache.clear();
  return _imgBytesCache[id] ??= await PipsApi.getBytes(PipsApi.viewUrl(id));
}

/// File viewer.
///
/// - Images: swipeable gallery (left/right) with pinch/double-tap zoom.
/// - Video/Audio: advanced player with playlist (see [AdvancedPlayerView).
/// - Text: monospace preview.
/// Pass [gallery] (sibling file list) to enable swiping between images and
/// video/audio playlists; when omitted the full file list is fetched once.
class ViewerPage extends StatefulWidget {
  final Entry e;
  final List<Entry>? gallery;
  const ViewerPage({super.key, required this.e, this.gallery});
  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  late Entry cur = widget.e;
  List<Entry>? all;
  bool fs = false;

  @override
  void initState() {
    super.initState();
    if (widget.gallery != null && widget.gallery!.isNotEmpty) {
      all = _merge(widget.gallery!);
    } else {
      PipsApi.filesAll().then((raw) {
        if (!mounted) return;
        setState(() => all = _merge(raw.map((x) => Entry(Map<String, dynamic>.from(x as Map))).toList()));
      }).catchError((_) {});
    }
  }

  List<Entry> _merge(List<Entry> list) {
    final seen = <String>{};
    return [widget.e, ...list].where((x) => x.id.isNotEmpty && seen.add(x.id)).toList();
  }

  int _indexOf(List<Entry> list) {
    final i = list.indexWhere((x) => x.id == widget.e.id);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final list = all ?? <Entry>[widget.e];
    final images = list.where((x) => isImage(x.mime, x.name)).toList();
    final videos = list.where((x) => isVideo(x.mime, x.name)).toList();
    final audios = list.where((x) => isAudio(x.mime, x.name)).toList();

    Widget body;
    if (isVideo(cur.mime, cur.name)) {
      body = AdvancedPlayerView(
        playlist: videos,
        initialIndex: _indexOf(videos),
        audioOnly: false,
        fullscreen: fs,
        onFullscreen: (v) => setState(() => fs = v),
        onEntryChanged: (e) => setState(() => cur = e),
      );
    } else if (isAudio(cur.mime, cur.name)) {
      body = AdvancedPlayerView(
        playlist: audios,
        initialIndex: _indexOf(audios),
        audioOnly: true,
        fullscreen: fs,
        onFullscreen: (v) => setState(() => fs = v),
        onEntryChanged: (e) => setState(() => cur = e),
      );
    } else if (isImage(cur.mime, cur.name)) {
      body = _Gallery(images: images, current: cur, onChange: (e) => setState(() => cur = e));
    } else if (isTexty(cur.mime, cur.name)) {
      body = FutureBuilder<String>(
        future: PipsApi.getString(PipsApi.viewUrl(cur.id)),
        builder: (_, s) => s.hasData
            ? SingleChildScrollView(padding: const EdgeInsets.all(16), child: SelectableText(s.data!, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)))
            : const Loading(),
      );
    } else {
      body = const EmptyState(icon: '📄', text: 'No preview available for this file.');
    }

    return PopScope(
      canPop: !fs,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => fs = false);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: fs
            ? null
            : AppBar(title: Text(cur.name, overflow: TextOverflow.ellipsis), actions: [
                if (isImage(cur.mime, cur.name))
                  IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImageEditorPage(e: cur)))),
              ]),
        body: body,
      ),
    );
  }
}

/// Swipeable image gallery — swipe left/right to move through the image list.
class _Gallery extends StatefulWidget {
  final List<Entry> images;
  final Entry current;
  final ValueChanged<Entry> onChange;
  const _Gallery({required this.images, required this.current, required this.onChange});
  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  late PageController pc;
  late int page = _posOf(widget.current);
  bool zoomed = false;

  @override
  void initState() {
    super.initState();
    pc = PageController(initialPage: page);
  }

  int _posOf(Entry e) {
    final i = widget.images.indexWhere((x) => x.id == e.id);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(covariant _Gallery old) {
    super.didUpdateWidget(old);
    if (widget.images.length != old.images.length) {
      final p = _posOf(widget.current);
      if (pc.hasClients && p != (pc.page?.round() ?? p)) pc.jumpToPage(p);
      setState(() => page = p);
    }
  }

  @override
  void dispose() {
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        PageView.builder(
          controller: pc,
          physics: zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
          itemCount: widget.images.length,
          onPageChanged: (i) {
            setState(() {
              page = i;
              zoomed = false;
            });
            widget.onChange(widget.images[i]);
          },
          itemBuilder: (_, i) => _ZoomableImage(
            key: ValueKey(widget.images[i].id),
            e: widget.images[i],
            onZoom: (z) {
              if (zoomed != z) setState(() => zoomed = z);
            },
          ),
        ),
        if (widget.images.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    '${page + 1} / ${widget.images.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
      ]);
}

/// Single gallery page: pinch to zoom, double-tap to zoom in/out.
class _ZoomableImage extends StatefulWidget {
  final Entry e;
  final ValueChanged<bool> onZoom;
  const _ZoomableImage({super.key, required this.e, required this.onZoom});
  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> with SingleTickerProviderStateMixin {
  final tc = TransformationController();
  TapDownDetails? tapDown;
  bool zoomed = false;
  late final Future<List<int>> _fut = _loadImageBytes(widget.e.id);

  @override
  void initState() {
    super.initState();
    tc.addListener(_onChanged);
  }

  void _onChanged() {
    final z = tc.value.getMaxScaleOnAxis() > 1.01;
    if (z != zoomed) {
      setState(() => zoomed = z);
      widget.onZoom(z);
    }
  }

  @override
  void dispose() {
    tc.dispose();
    super.dispose();
  }

  void _doubleTap() {
    if (zoomed) {
      tc.animateTo(Matrix4.identity(), curve: Curves.easeOut, duration: const Duration(milliseconds: 220));
    } else {
      final p = tapDown?.localPosition;
      final m = Matrix4.identity();
      if (p != null) m.translate(-p.dx * 1.5, -p.dy * 1.5);
      m.scale(2.5);
      tc.animateTo(m, curve: Curves.easeOut, duration: const Duration(milliseconds: 220));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<int>>(
        future: _fut,
        builder: (_, s) {
          if (s.hasError) return const EmptyState(icon: '⚠️', text: 'Failed to load image.');
          if (!s.hasData) return const Loading();
          return GestureDetector(
            onDoubleTapDown: (d) => tapDown = d,
            onDoubleTap: _doubleTap,
            child: InteractiveViewer(
              transformationController: tc,
              panEnabled: zoomed,
              scaleEnabled: true,
              minScale: 1.0,
              maxScale: 6.0,
              child: Center(child: Image.memory(Uint8List.fromList(s.data!), fit: BoxFit.contain)),
            ),
          );
        },
      );
}

class ImageEditorPage extends StatefulWidget {
  final Entry e;
  const ImageEditorPage({super.key, required this.e});
  @override
  State<ImageEditorPage> createState() => _ImageEditorPageState();
}

class _ImageEditorPageState extends State<ImageEditorPage> {
  Uint8List? bytes;
  int rot = 0;
  bool flip = false;
  double bright = 1, contrast = 1, sat = 1;
  bool busy = false;
  final key = GlobalKey();

  @override
  void initState() {
    super.initState();
    PipsApi.getBytes(PipsApi.viewUrl(widget.e.id)).then((b) => setState(() => bytes = Uint8List.fromList(b)));
  }

  List<double> get _matrix => [
        contrast * sat, 0, 0, 0, (bright - 1) * 255,
        0, contrast * sat, 0, 0, (bright - 1) * 255,
        0, 0, contrast * sat, 0, (bright - 1) * 255,
        0, 0, 0, 1, 0,
      ];

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final rb = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await rb.toImage(pixelRatio: 2);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/edited-${widget.e.name}.png');
      await f.writeAsBytes(bd!.buffer.asUint8List());
      await PipsApi.uploadSingle(f, 'edited-${widget.e.name}', 'image/png', widget.e.visibility, (_) {});
      if (mounted) {
        toast(context, 'Saved back to Pips cloud');
        Navigator.pop(context);
      }
    } on ApiException catch (ex) {
      if (mounted) toast(context, ex.message);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Edit image'), actions: [
          TextButton.icon(onPressed: busy ? null : save, icon: const Icon(Icons.save), label: Text(busy ? 'Saving…' : 'Save')),
        ]),
        body: bytes == null
            ? const Loading()
            : Column(children: [
                Expanded(
                    child: Center(
                        child: RepaintBoundary(
                            key: key,
                            child: RotatedBox(
                              quarterTurns: rot,
                              child: Transform.flip(
                                flipX: flip,
                                child: ColorFiltered(colorFilter: ColorFilter.matrix(_matrix), child: Image.memory(bytes!)),
                              ),
                            )))),
                Container(
                    color: Colors.white10,
                    padding: const EdgeInsets.all(12),
                    child: SafeArea(
                        child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        IconButton(color: Colors.white, icon: const Icon(Icons.rotate_90_degrees_ccw), onPressed: () => setState(() => rot = (rot + 3) % 4)),
                        IconButton(color: Colors.white, icon: const Icon(Icons.flip), onPressed: () => setState(() => flip = !flip)),
                        IconButton(color: Colors.white, icon: const Icon(Icons.undo), onPressed: () => setState(() {
                              rot = 0;
                              flip = false;
                              bright = 1;
                              contrast = 1;
                              sat = 1;
                            })),
                      ]),
                      _slider('Brightness', bright, (v) => setState(() => bright = v)),
                      _slider('Contrast', contrast, (v) => setState(() => contrast = v)),
                      _slider('Saturation', sat, (v) => setState(() => sat = v)),
                    ]))),
              ]),
      );

  Widget _slider(String label, double v, ValueChanged<double> fn) => Row(children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Expanded(child: Slider(value: v, min: 0.4, max: 1.8, onChanged: fn)),
      ]);
}
