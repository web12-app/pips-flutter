import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';

class ViewerPage extends StatelessWidget {
  final Entry e;
  const ViewerPage({super.key, required this.e});
  @override
  Widget build(BuildContext context) {
    final url = PipsApi.viewUrl(e.id);
    Widget body;
    if (isImage(e.mime, e.name)) {
      body = FutureBuilder<List<int>>(
        future: PipsApi.getBytes(url),
        builder: (_, s) => s.hasData
            ? InteractiveViewer(child: Center(child: Image.memory(Uint8List.fromList(s.data!))))
            : const Loading(),
      );
    } else if (isVideo(e.mime, e.name) || isAudio(e.mime, e.name)) {
      body = _MediaPlayer(url: url, isVideo: isVideo(e.mime, e.name));
    } else if (isTexty(e.mime, e.name)) {
      body = FutureBuilder<String>(
        future: PipsApi.getString(url),
        builder: (_, s) => s.hasData
            ? SingleChildScrollView(padding: const EdgeInsets.all(16), child: SelectableText(s.data!, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)))
            : const Loading(),
      );
    } else {
      body = const EmptyState(icon: '📄', text: 'No preview available for this file.');
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(e.name, overflow: TextOverflow.ellipsis), actions: [
        if (isImage(e.mime, e.name))
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImageEditorPage(e: e)))),
      ]),
      body: body,
    );
  }
}

class _MediaPlayer extends StatefulWidget {
  final String url;
  final bool isVideo;
  const _MediaPlayer({required this.url, required this.isVideo});
  @override
  State<_MediaPlayer> createState() => _MediaPlayerState();
}

class _MediaPlayerState extends State<_MediaPlayer> {
  VideoPlayerController? c;
  String? err;
  @override
  void initState() {
    super.initState();
    c = VideoPlayerController.networkUrl(Uri.parse(widget.url), httpHeaders: PipsApi.authHeaders)
      ..initialize().then((_) => setState(() {})).catchError((e) => setState(() => err = e.toString()));
    c!.setLooping(true);
    c!.play();
  }
  @override
  void dispose() { c?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (err != null) return EmptyState(icon: '⚠️', text: err!);
    if (c == null || !c!.value.isInitialized) return const Loading();
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (widget.isVideo) AspectRatio(aspectRatio: c!.value.aspectRatio, child: VideoPlayer(c!))
      else const Icon(Icons.graphic_eq, size: 96, color: Colors.white54),
      VideoProgressIndicator(c!, allowScrubbing: true, padding: const EdgeInsets.all(12)),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(iconSize: 32, color: Colors.white, icon: const Icon(Icons.replay_10), onPressed: () async { final p = (await c!.position)?.inMilliseconds ?? 0; c!.seekTo(Duration(milliseconds: max(0, p - 10000))); }),
        IconButton(iconSize: 44, color: Colors.white, icon: Icon(c!.value.isPlaying ? Icons.pause_circle : Icons.play_circle), onPressed: () => setState(() => c!.value.isPlaying ? c!.pause() : c!.play())),
        IconButton(iconSize: 32, color: Colors.white, icon: const Icon(Icons.forward_10), onPressed: () async { final p = (await c!.position)?.inMilliseconds ?? 0; c!.seekTo(Duration(milliseconds: p + 10000)); }),
      ]),
    ]);
  }
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
      if (mounted) { toast(context, 'Saved back to Pips cloud'); Navigator.pop(context); }
    } on ApiException catch (ex) { if (mounted) toast(context, ex.message); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Edit image'), actions: [
          TextButton.icon(onPressed: busy ? null : save, icon: const Icon(Icons.save), label: Text(busy ? 'Saving…' : 'Save')),
        ]),
        body: bytes == null ? const Loading() : Column(children: [
          Expanded(child: Center(child: RepaintBoundary(key: key, child: RotatedBox(
            quarterTurns: rot,
            child: Transform.flip(
              flipX: flip,
              child: ColorFiltered(colorFilter: ColorFilter.matrix(_matrix), child: Image.memory(bytes!)),
            ),
          )))),
          Container(color: Colors.white10, padding: const EdgeInsets.all(12), child: SafeArea(child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              IconButton(color: Colors.white, icon: const Icon(Icons.rotate_90_degrees_ccw), onPressed: () => setState(() => rot = (rot + 3) % 4)),
              IconButton(color: Colors.white, icon: const Icon(Icons.flip), onPressed: () => setState(() => flip = !flip)),
              IconButton(color: Colors.white, icon: const Icon(Icons.undo), onPressed: () => setState(() { rot = 0; flip = false; bright = 1; contrast = 1; sat = 1; })),
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
