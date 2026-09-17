import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yt_downloader/yt_downloader.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';
import 'yt_webview.dart';

/// "Download on this phone" — the whole pipeline runs INSIDE the app,
/// in the background, with zero manual steps:
///
///   1. Paste a YouTube URL  →  formats fetched automatically
///   2. Pick a quality       →  download starts automatically (video+audio,
///      merged in-app with ffmpeg) with a live JSON progress console
///   3. When done            →  the file streams straight up to Pips cloud
///      (auto-upload on by default, existing chunked upload API)
///
/// No terminal, no other app, no cookies — the video is fetched from this
/// phone's own network, which normally clears YouTube's bot check.
class YtLocalPage extends StatefulWidget {
  final String? initialUrl;
  const YtLocalPage({super.key, this.initialUrl});
  @override
  State<YtLocalPage> createState() => _YtLocalPageState();
}

class _YtLocalPageState extends State<YtLocalPage> {
  final _yt = YtDownloader();
  final _urlCtrl = TextEditingController();
  Timer? _debounce;

  VideoInfo? _info;
  bool _metaBusy = false;
  String? _metaErr;
  bool _metaBot = false;

  DownloadFormat? _format;

  bool _downloading = false;
  double _progress = 0;
  String _phase = '';
  int _localSize = 0;
  String? _localPath;
  String? _dlErr;
  bool _dlBot = false;

  bool _autoUpload = true;
  String vis = 'private';
  bool _uploading = false;
  double _uploadPct = 0;
  String _uploadStatus = '';
  bool _uploaded = false;

  @override
  void initState() {
    super.initState();
    final u = widget.initialUrl ?? '';
    _urlCtrl.text = u;
    _urlCtrl.addListener(_onUrlChanged);
    if (u.isNotEmpty) _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _urlCtrl.removeListener(_onUrlChanged);
    _urlCtrl.dispose();
    super.dispose();
  }

  static bool isYouTube(String raw) {
    final u = Uri.tryParse(raw.trim());
    if (u == null) return false;
    final h = u.host.toLowerCase();
    if (h == 'youtu.be') return u.pathSegments.isNotEmpty;
    if (h == 'youtube.com' || h.endsWith('.youtube.com')) {
      return u.path.startsWith('/watch') ||
          u.path.startsWith('/shorts/') ||
          u.path.startsWith('/embed/') ||
          u.path.startsWith('/live/');
    }
    return false;
  }

  void _onUrlChanged() {
    _debounce?.cancel();
    final url = _urlCtrl.text.trim();
    if (url.isEmpty || !isYouTube(url)) return;
    _debounce = Timer(const Duration(milliseconds: 700), _fetch);
  }

  // ------------------------------------------------ metadata
  Future<void> _fetch() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _metaBusy = true;
      _metaErr = null;
      _metaBot = false;
      _format = null;
      _info = null;
      _localPath = null;
      _uploaded = false;
      _dlErr = null;
    });
    try {
      final info = await _yt.getInfo(url);
      if (!mounted) return;
      setState(() {
        _info = info;
        _metaBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _metaBusy = false;
        _metaErr = msg.length > 220 ? '${msg.substring(0, 220)}…' : msg;
        _metaBot = msg
                .toLowerCase()
                .contains('sign in') ||
            msg.toLowerCase().contains('not a bot') ||
            msg.toLowerCase().contains('login_required') ||
            msg.toLowerCase().contains('bot');
      });
    }
  }

  // ------------------------------------------------ download
  Future<void> _download() async {
    final info = _info;
    final format = _format;
    if (info == null || format == null) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _phase = 'starting…';
      _dlErr = null;
      _dlBot = false;
      _localPath = null;
      _uploaded = false;
      _uploading = false;
      _uploadPct = 0;
    });
    String? path;
    try {
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/pips-${info.videoId}.mp4';
      await info.download(
        format: format,
        outputPath: path,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            _phase = format.needsMerge
                ? (p < 0.45
                    ? 'video stream'
                    : p < 0.9
                        ? 'audio stream'
                        : 'merging (ffmpeg)')
                : 'video stream';
          });
        },
      );
      if (!mounted) return;
      final size = (await File(path).length());
      setState(() {
        _downloading = false;
        _localPath = path;
        _localSize = size;
        _progress = 1;
        _phase = 'done';
      });
      if (_autoUpload) await _upload();
    } catch (e) {
      try {
        if (path != null) await File(path).delete();
      } catch (_) {}
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _downloading = false;
        _dlErr = msg.length > 260 ? '${msg.substring(0, 260)}…' : msg;
        _dlBot = msg
                .toLowerCase()
                .contains('sign in') ||
            msg.toLowerCase().contains('not a bot') ||
            msg.toLowerCase().contains('http 403') ||
            msg.toLowerCase().contains('http 400');
      });
    }
  }

  // ------------------------------------------------ upload to cloud
  String get _safeTitle {
    var t = (_info?.title ?? 'video').trim();
    t = t
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.length > 80) t = t.substring(0, 80).trim();
    return t.isEmpty ? 'video' : t;
  }

  Future<void> _upload() async {
    final path = _localPath;
    if (path == null) return;
    final f = File(path);
    final size = await f.length();
    if (size <= 0) return;
    const name = 'video.mp4';
    final folder = 'YouTube/$_safeTitle';
    setState(() {
      _uploading = true;
      _uploadPct = 0;
      _uploadStatus = 'Preparing upload…';
    });
    var ok = false;
    String? err;
    try {
      try {
        await PipsApi.createFolder(folder);
      } catch (_) {}
      final init = await PipsApi.uploadInit(name, size);
      final uid = init['id'].toString();
      final total = (size + PipsApi.chunkSize - 1) ~/ PipsApi.chunkSize;
      final bytes = await f.readAsBytes();
      for (var i = 0; i < total; i++) {
        final want = min(PipsApi.chunkSize, size - i * PipsApi.chunkSize);
        await PipsApi.uploadChunk(uid, i, bytes.sublist(i * PipsApi.chunkSize, i * PipsApi.chunkSize + want));
        if (!mounted) return;
        final sent = min((i + 1) * PipsApi.chunkSize, size);
        setState(() {
          _uploadPct = (i + 1) / total;
          _uploadStatus = 'Uploading to Pips cloud… ${_fmtBytes(sent)} / ${_fmtBytes(size)}';
        });
      }
      await PipsApi.uploadFinish(uid, total, size, name, 'video/mp4', vis);
      ok = true;
    } on ApiException catch (e) {
      err = e.message;
    } catch (e) {
      err = '$e';
    }
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (ok) {
        _uploadPct = 1;
        _uploadStatus = 'Uploaded ✓ — YouTube/$_safeTitle/video.mp4';
        _uploaded = true;
      } else {
        _uploadStatus = 'Upload failed: $err';
      }
    });
    if (ok) toast(context, 'Uploaded to Pips cloud ✓');
  }

  // ------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final hc = HomeColors.of(context);
    final info = _info;
    final done = _localPath != null;
    return Scaffold(
      backgroundColor: hc.surface,
      appBar: AppBar(
        backgroundColor: hc.surface,
        foregroundColor: hc.text1,
        elevation: 0,
        title: const Row(children: [
          Icon(Icons.phone_android, size: 19, color: AppTheme.blue),
          SizedBox(width: 8),
          Text('Download on this phone', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _urlCard(),
          if (_metaBusy || _metaErr != null || info != null) ...[
            const SizedBox(height: 12),
            _metaCard(),
          ],
          if (_downloading || done || _dlErr != null) ...[
            const SizedBox(height: 12),
            _jobCard(),
          ],
        ],
      ),
    );
  }

  Widget _urlCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HomeColors.of(context).surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HomeColors.of(context).line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('YouTube URL — details load automatically', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _urlCtrl,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'https://www.youtube.com/watch?v=…  or  youtu.be/…',
            isDense: true,
            prefixIcon: const Icon(Icons.link, size: 18),
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(
                onPressed: _urlCtrl.text.trim().isEmpty ? null : () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => YtWebViewPage(url: _urlCtrl.text.trim())));
                },
                child: const Text('Watch', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppTheme.teal)),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: _metaBusy || _urlCtrl.text.trim().isEmpty ? null : _fetch,
                child: const Text('Refresh', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppTheme.blue)),
              ),
              const SizedBox(width: 6),
            ]),
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.blue, width: 1.4)),
          ),
        ),
      ]),
    );
  }

  Widget _metaCard() {
    final info = _info;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HomeColors.of(context).surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HomeColors.of(context).line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.data_object, size: 17, color: AppTheme.blue),
          SizedBox(width: 8),
          Text('Live metadata (JSON)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
        if (_metaBusy)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 10), Text('Fetching formats on this phone…', style: TextStyle(fontSize: 12, color: Colors.grey))]),
          )
        else if (_metaErr != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_metaErr!, style: const TextStyle(fontSize: 12.5, color: AppTheme.red, height: 1.35)),
          ),
          if (_metaBot) _botHint(),
        ]
        else if (info != null) ...[
          const SizedBox(height: 10),
          Text(info.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.3)),
          const SizedBox(height: 10),
          const Text('Pick a quality — download + upload run automatically', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in info.formats.videoWithAudio)
              _qualityChip(f, _format == f),
          ]),
          const SizedBox(height: 10),
          CheckboxListTile(
            value: _autoUpload,
            onChanged: (v) => setState(() => _autoUpload = v ?? true),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto upload to Pips cloud after download', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            activeColor: AppTheme.blue,
          ),
          if (_format != null)
            FilledButton.icon(
              onPressed: _downloading ? null : _download,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download on this phone', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
        ],
      ]),
    );
  }

  Widget _qualityChip(DownloadFormat f, bool sel) {
    final c = (f.height ?? 0) >= 1080
        ? AppTheme.blue
        : (f.height ?? 0) >= 480
            ? AppTheme.teal
            : Colors.grey;
    return GestureDetector(
      onTap: () => setState(() => _format = f),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? c.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? c : const Color(0xFFCBD5E1), width: sel ? 1.6 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (sel) ...[const Icon(Icons.check, size: 13), const SizedBox(width: 4)],
          Text(f.label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: sel ? c : const Color(0xFF334155))),
          if (f.estimatedSize > 0) ...[
            const SizedBox(width: 6),
            Text(_fmtBytes(f.estimatedSize), style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
          ],
        ]),
      ),
    );
  }

  Widget _jobCard() {
    final done = _localPath != null;
    final failed = _dlErr != null;
    final color = failed ? AppTheme.red : (done ? AppTheme.green : AppTheme.blue);
    final est = _format?.estimatedSize ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(failed ? Icons.error_outline : (done ? Icons.check_circle : Icons.downloading), size: 19, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(
            _dlErr != null
                ? 'Download failed'
                : done
                    ? 'Download finished ✓'
                    : 'Downloading on this phone…',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          )),
          if (done) Text(_fmtBytes(_localSize), style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
        ]),
        if (_dlErr != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_dlErr!, style: const TextStyle(fontSize: 12.5, color: AppTheme.red, height: 1.35)),
          ),
          if (_dlBot) _botHint(),
        ],
        if (!failed) ...[
          const SizedBox(height: 10),
          ProgressBar(value: done ? 1 : _progress.clamp(0, 1), color: color),
          const SizedBox(height: 8),
          Text(
            done
                ? 'Ready for upload'
                : '${(_progress * 100).toStringAsFixed(0)}% · ${_phase}${est > 0 ? ' · ${_fmtBytes((est * _progress).round())} / ${_fmtBytes(est)}' : ''}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
          if (!_downloading || done)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('LIVE JSON', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 1)),
                const SizedBox(height: 6),
                SelectableText(
                  _liveJson(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, height: 1.5, color: Color(0xFF86EFAC)),
                ),
              ]),
            ),
        ],
        if (done) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              icon: Icon(vis == 'public' ? Icons.public : Icons.lock, size: 16),
              label: Text(vis == 'public' ? 'Public' : 'Private', style: const TextStyle(fontSize: 12.5)),
              onPressed: _uploaded || _uploading ? null : () => setState(() => vis = vis == 'public' ? 'private' : 'public'),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(
              onPressed: _autoUpload || _uploading || _uploaded ? null : _upload,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _uploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_upload_outlined, size: 17),
              label: Text(_uploaded ? 'Uploaded ✓' : (_uploading ? 'Uploading…' : 'Upload to Pips cloud'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            )),
          ]),
          if (_uploading || _uploaded) ...[
            const SizedBox(height: 8),
            ProgressBar(value: _uploadPct, color: _uploaded ? AppTheme.green : AppTheme.blue),
            const SizedBox(height: 6),
            Text(_uploadStatus, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
          ],
        ],
      ]),
    );
  }

  Widget _botHint() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.3)),
      ),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.shield, size: 15, color: AppTheme.red),
          SizedBox(width: 7),
          Text('YouTube bot-check', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppTheme.red)),
        ]),
        SizedBox(height: 5),
        Text('This video wants sign-in even from your network. Retry later from home Wi-Fi — no cookies are used or needed here.',
            style: TextStyle(fontSize: 11.5, height: 1.35, color: Colors.grey)),
      ]),
    );
  }

  static String _fmtBytes(int b) => fmtBytes(b);

  String _liveJson() {
    final status = _dlErr != null ? 'error' : (_localPath != null ? 'done' : 'running');
    final est = _format?.estimatedSize ?? 0;
    final got = (est * _progress).round();
    return '{\n'
        '  "status": "$status",\n'
        '  "phase": "${_phase.replaceAll('"', "'")}",\n'
        '  "percent": ${(_progress * 100).toStringAsFixed(1)},\n'
        '  "mb": ${(got / 1048576).toStringAsFixed(1)},\n'
        '  "size_bytes": $got,\n'
        '  "quality": "${_format?.label ?? ''}",\n'
        '  "local": "${_localPath ?? ''}"\n'
        '}';
  }
}
