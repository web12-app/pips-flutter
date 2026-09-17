import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../api.dart';
import '../models.dart';
import '../services/local_yg.dart';
import '../widgets.dart';
import 'yt_connect_page.dart';
import 'yt_webview.dart';

/// "Download on this phone" — the local you-get pipeline:
///
///   1. One-time setup (guided): ReTerminal's Alpine session runs
///      assets/pips_local/server.py → 127.0.0.1:8787
///   2. Paste a YouTube URL → /meta (title + qualities, live JSON)
///   3. Pick a quality → /download → live JSON progress console
///   4. /file/<id> streams the mp4 straight into the Pips cloud upload
///      (chunked, existing API — no new server endpoints)
class YtLocalPage extends StatefulWidget {
  final String? initialUrl;
  const YtLocalPage({super.key, this.initialUrl});
  @override
  State<YtLocalPage> createState() => _YtLocalPageState();
}

class _YtLocalPageState extends State<YtLocalPage> {
  final _urlCtrl = TextEditingController();
  Timer? _poll;
  Timer? _jobPoll;

  Map<String, dynamic>? _health;

  Map<String, dynamic>? _meta;
  bool _metaBusy = false;
  String? _metaErr;

  String? _itag;

  String? _jobId;
  Map<String, dynamic> _job = {};
  bool _downloading = false;
  String? _jobErr;
  bool _jobBot = false;

  bool _uploading = false;
  double _uploadPct = 0;
  String _uploadStatus = '';
  String vis = 'private';
  bool _uploaded = false;

  final SetupFileServer _files = SetupFileServer();
  bool _filesOn = false;
  bool _filesBusy = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = widget.initialUrl ?? '';
    _check();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _jobPoll?.cancel();
    _files.stop();
    _urlCtrl.dispose();
    super.dispose();
  }

  bool get _online => _health != null;

  Future<void> _check() async {
    final h = await LocalYg.health();
    if (!mounted) return;
    final was = _online;
    setState(() => _health = h);
    if (!was && h != null) {
      toast(context, 'Local you-get server is online ✓');
    }
  }

  // ------------------------------------------------ setup file server
  Future<void> _toggleFiles() async {
    if (_filesOn) {
      await _files.stop();
      if (mounted) setState(() => _filesOn = false);
      return;
    }
    setState(() => _filesBusy = true);
    try {
      await _files.start();
      if (mounted) setState(() => _filesOn = true);
    } catch (e) {
      if (mounted) toast(context, 'Could not start the file server: $e');
    } finally {
      if (mounted) setState(() => _filesBusy = false);
    }
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) toast(context, '$what copied — paste it in ReTerminal');
  }

  static const _setupCmds = [
    'wget -O /tmp/pips_yg_server.py http://127.0.0.1:8788/server.py',
    'wget -O /tmp/pips-yg-setup.sh http://127.0.0.1:8788/setup.sh',
    'sh /tmp/pips-yg-setup.sh',
  ];

  // ------------------------------------------------ meta / download / job
  Future<void> _fetchMeta() async {
    var url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'https://$url';
    setState(() {
      _metaBusy = true;
      _meta = null;
      _metaErr = null;
      _itag = null;
      _jobId = null;
      _job = {};
      _jobErr = null;
    });
    try {
      final m = await LocalYg.meta(url);
      if (!mounted) return;
      setState(() {
        _meta = m;
        _itag = null;
      });
    } on LocalYgError catch (e) {
      if (mounted) setState(() => _metaErr = e.message);
    } catch (e) {
      if (mounted) setState(() => _metaErr = '$e');
    } finally {
      if (mounted) setState(() => _metaBusy = false);
    }
  }

  void _startJob() {
    final itag = _itag;
    final url = _urlCtrl.text.trim();
    if (itag == null || itag.isEmpty) return;
    setState(() {
      _downloading = true;
      _jobErr = null;
      _jobBot = false;
      _job = {'status': 'starting', 'tail': 'starting you-get …', 'log': <String>[]};
    });
    _jobPoll?.cancel();
    _jobPoll = Timer.periodic(const Duration(seconds: 1), (_) => _pollJob());
    _begin(url, itag);
  }

  Future<void> _begin(String url, String itag) async {
    try {
      final id = await LocalYg.download(url, itag);
      if (!mounted) return;
      setState(() => _jobId = id);
    } on LocalYgError catch (e) {
      if (!mounted) return;
      _jobPoll?.cancel();
      setState(() {
        _downloading = false;
        _jobErr = e.message;
        _jobBot = e.botCheck;
      });
    }
  }

  Future<void> _pollJob() async {
    final id = _jobId;
    if (id == null) return;
    try {
      final j = await LocalYg.job(id);
      if (!mounted) return;
      final st = (j['status'] ?? '').toString();
      setState(() => _job = j);
      if (st != 'running') {
        _jobPoll?.cancel();
        _jobPoll = null;
        setState(() => _downloading = false);
        if (st == 'error') {
          _jobBot = (j['bot_check'] == true) ||
              ((j['tail'] ?? '').toString().toLowerCase().contains('bot'));
        }
      }
    } catch (_) {
      // transient loopback blip — keep polling
    }
  }

  void _cancelJob() {
    _jobPoll?.cancel();
    _jobPoll = null;
    setState(() {
      _downloading = false;
      _jobId = null;
      _job = {};
      _jobErr = null;
      _uploaded = false;
      _uploading = false;
      _uploadPct = 0;
    });
    _check();
  }

  /// Video title, shown as-is…
  String get _title {
    final t = (_meta?['title'] ?? '').toString();
    return t.isEmpty ? 'video' : t;
  }

  /// …and a filesystem-safe form for the cloud folder name.
  String get _safeTitle {
    var t = _title.trim();
    t = t.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length > 80) t = t.substring(0, 80).trim();
    return t.isEmpty ? 'video' : t;
  }

  // ------------------------------------------------ upload to cloud
  Future<void> _upload() async {
    final id = _jobId;
    if (id == null || (_job['status'] ?? '') != 'done') return;
    const name = 'video.mp4';
    final folder = 'YouTube/$_safeTitle';
    setState(() {
      _uploading = true;
      _uploadPct = 0;
      _uploadStatus = 'Preparing upload…';
    });
    LocalFileStream? fs;
    var ok = false;
    String? err;
    try {
      // Open the local file stream first: its Content-Length is the true
      // on-disk size, so the chunk plan matches exactly.
      final stream = await LocalYg.file(id);
      fs = stream;
      final size = stream.size;
      if (size <= 0) throw LocalYgError('file is empty');
      try {
        await PipsApi.createFolder(folder);
      } catch (_) {}
      final init = await PipsApi.uploadInit(name, size);
      final uid = init['id'].toString();
      final total = (size + PipsApi.chunkSize - 1) ~/ PipsApi.chunkSize;
      for (var i = 0; i < total; i++) {
        final want = min(PipsApi.chunkSize, size - i * PipsApi.chunkSize);
        final part = await stream.nextBytes(want);
        await PipsApi.uploadChunk(uid, i, part);
        if (!mounted) return;
        setState(() {
          _uploadPct = stream.progress;
          _uploadStatus = 'Uploading to Pips cloud… ${_fmtBytes(stream.read)} / ${_fmtBytes(size)}';
        });
      }
      await PipsApi.uploadFinish(uid, total, size, name, 'video/mp4', vis);
      ok = true;
    } on ApiException catch (e) {
      err = e.message;
    } catch (e) {
      err = '$e';
    } finally {
      await fs?.close();
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
          _statusCard(),
          if (!_online) ...[
            const SizedBox(height: 12),
            _setupCard(),
          ] else ...[
            const SizedBox(height: 12),
            _urlCard(),
            if (_meta != null || _metaBusy || _metaErr != null) ...[
              const SizedBox(height: 12),
              _metaCard(),
            ],
            if (_jobId != null || _downloading || _jobErr != null) ...[
              const SizedBox(height: 12),
              _jobCard(),
            ],
          ],
        ],
      ),
    );
  }

  Widget _statusCard() {
    final h = _health;
    final online = h != null;
    final ffmpeg = h?['ffmpeg'] == true;
    final cookies = h?['cookies'] == true;
    final yg = (h?['you_get'] ?? '').toString();
    final ygVer = yg.contains('version') ? (yg.split('version').last.trim().split('\n').first) : (yg.isEmpty ? '…' : yg);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (online ? AppTheme.green : const Color(0xFF64748B)).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: (online ? AppTheme.green : const Color(0xFF94A3B8)).withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: (online ? AppTheme.green : const Color(0xFF94A3B8)).withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(online ? Icons.cloud_done : Icons.cloud_off, size: 21,
              color: online ? AppTheme.green : const Color(0xFF64748B)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(online ? 'Local you-get server: ONLINE' : 'Local you-get server: OFFLINE',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14,
                  color: online ? AppTheme.green : const Color(0xFF475569))),
          const SizedBox(height: 2),
          Text(online
              ? 'you-get $ygVer · python ${(h['python'] ?? '').toString()} · ffmpeg ${ffmpeg ? '✓' : '✗ (mp4-only qualities work)'}${cookies ? ' · cookies ✓' : ''}'
              : 'Set it up once in ReTerminal (Alpine) — 3 commands, then every YouTube download runs on your own network.',
              style: const TextStyle(fontSize: 11.5, color: Colors.grey, height: 1.3)),
        ])),
        if (!online)
          FilledButton(
            onPressed: _check,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.blue, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
            ),
            child: const Text('Recheck', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }

  Widget _setupCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.blue.withValues(alpha: 0.22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.terminal, size: 19, color: AppTheme.blue),
          SizedBox(width: 8),
          Text('One-time setup (in ReTerminal)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        ]),
        const SizedBox(height: 10),
        _stepBtn(1, 'Open ReTerminal on this phone'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: FilledButton.icon(
            onPressed: openReTerminal,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.blue, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.rocket_launch, size: 17),
            label: const Text('Open ReTerminal', style: TextStyle(fontWeight: FontWeight.w700)),
          )),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(
            onPressed: _filesBusy ? null : _toggleFiles,
            style: OutlinedButton.styleFrom(
              foregroundColor: _filesOn ? AppTheme.green : AppTheme.blue,
              side: BorderSide(color: (_filesOn ? AppTheme.green : AppTheme.blue).withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(_filesOn ? Icons.wifi_tethering : Icons.wifi_off, size: 17),
            label: Text(_filesOn ? 'Files: ON' : 'Serve setup files', style: const TextStyle(fontWeight: FontWeight.w700)),
          )),
        ]),
        if (_filesOn)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('File server running at ${SetupFileServer.url} — the commands below now work.',
                style: const TextStyle(fontSize: 11.5, color: AppTheme.green, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 12),
        _step(2, const Text('In ReTerminal, switch to the Alpine session, then run:')),
        const SizedBox(height: 8),
        ..._setupCmds.map((c) => _cmdRow(c)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () => _copy(_setupCmds.join('\n'), 'Setup commands'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.blue,
              side: BorderSide(color: AppTheme.blue.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.copy_all, size: 16),
            label: const Text('Copy all commands', style: TextStyle(fontWeight: FontWeight.w700)),
          )),
        ]),
        const SizedBox(height: 12),
        _step(3, const Text('When the health check prints {"ok": true} — tap Recheck. The server stays up as long as ReTerminal does.')),
        const SizedBox(height: 6),
        const Text(
          'Why: downloads then run on your home network instead of a data-centre, so YouTube normally does not bot-check them. Cookies are never read from any browser or app — only an optional cookies.txt you start the server with yourself.',
          style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
        ),
      ]),
    );
  }

  Widget _step(int n, Widget label) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 20, height: 20,
        decoration: const BoxDecoration(color: AppTheme.blue, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(width: 8),
      Expanded(child: Padding(
        padding: const EdgeInsets.only(top: 0),
        child: label,
      )),
    ]);
  }

  Widget _stepBtn(int n, String label) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 20, height: 20,
        decoration: const BoxDecoration(color: AppTheme.blue, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(width: 8),
      Expanded(child:        Text(label, style: const TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600))),
    ]);
  }

  Widget _cmdRow(String cmd) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _copy(cmd, 'Command'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Expanded(child: Text(cmd, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Color(0xFF7DD3FC)))),
          const Icon(Icons.copy, size: 13, color: Color(0xFF64748B)),
        ]),
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
        const Text('YouTube URL', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _urlCtrl,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'https://www.youtube.com/watch?v=…',
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
                onPressed: _metaBusy || _urlCtrl.text.trim().isEmpty ? null : _fetchMeta,
                child: Text(_metaBusy ? '…' : 'Details', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppTheme.blue)),
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
    final m = _meta;
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
            child: Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 10), Text('Fetching with you-get…', style: TextStyle(fontSize: 12, color: Colors.grey))]),
          )
        else if (_metaErr != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_metaErr!, style: const TextStyle(fontSize: 12.5, color: AppTheme.red)),
          )
        else if (m != null) ...[
          const SizedBox(height: 10),
          Text((m['title'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.3)),
          const SizedBox(height: 4),
          Text('${(m['author'] ?? '').toString()} · ${_fmtDur(m['duration'])} · ${_fmtBytes(_num(m['size']))} total',
              style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
          const SizedBox(height: 10),
          const Text('Pick a quality', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final it in (m['itags'] is List ? m['itags'] as List : <dynamic>[]))
              if (it is Map)
                _qualityChip(it, _itag == it['itag'].toString()),
          ]),
          if (_itag != null)
            FilledButton.icon(
              onPressed: _startJob,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.blue, foregroundColor: Colors.white,
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

  Widget _qualityChip(Map it, bool sel) {
    final itag = it['itag'].toString();
    final h = _num(it['height']);
    final label = (it['label'] ?? (h > 0 ? '${h}p' : itag)).toString();
    final size = _num(it['size']);
    final c = h >= 1080 ? AppTheme.blue : (h >= 480 ? AppTheme.teal : Colors.grey);
    return GestureDetector(
      onTap: () => setState(() => _itag = itag),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? c.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? c : const Color(0xFFCBD5E1), width: sel ? 1.6 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (sel) ...[const Icon(Icons.check, size: 13), const SizedBox(width: 4)],
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: sel ? c : const Color(0xFF334155))),
          if (size > 0) ...[const SizedBox(width: 6), Text(_fmtBytes(size), style: const TextStyle(fontSize: 10.5, color: Colors.grey))],
        ]),
      ),
    );
  }

  Widget _jobCard() {
    final st = (_job['status'] ?? '').toString();
    final done = st == 'done';
    final failed = st == 'error' || _jobErr != null;
    final pct = _num(_job['percent']).toDouble();
    final mb = _num(_job['mb']).toDouble();
    final mbps = _num(_job['mbps']).toDouble();
    final secs = _num(_job['seconds']);
    final tail = (_job['tail'] ?? '').toString();
    final logLines = _job['log'] is List ? (_job['log'] as List).map((e) => e.toString()).toList() : <String>[];
    final size = _num(_job['size']);
    final color = failed ? AppTheme.red : (done ? AppTheme.green : AppTheme.blue);
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
            _jobErr != null ? 'Download failed' : (done ? 'Download finished ✓' : 'Downloading on this phone…'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          )),
          if (done) Text(_fmtBytes(size), style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
          if (_downloading)
            IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.grey), tooltip: 'Stop', onPressed: _cancelJob),
        ]),
        if (_jobErr != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_jobErr!, style: const TextStyle(fontSize: 12.5, color: AppTheme.red, height: 1.35)),
          ),
        if (_jobBot)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.red.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.red.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.shield, size: 15, color: AppTheme.red),
                SizedBox(width: 7),
                Text('YouTube bot-check', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppTheme.red)),
              ]),
              const SizedBox(height: 5),
              const Text('This video wants sign-in even from your network. Add your own cookies (you pick the file) and re-run the setup, or retry later from home Wi-Fi.',
                  style: TextStyle(fontSize: 11.5, height: 1.35, color: Colors.grey)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const YtConnectPage())),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                child: const Text('Allow YouTube Cookies', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.blue)),
              ),
            ]),
          ),
        if (!failed) ...[
          const SizedBox(height: 10),
          ProgressBar(value: done ? 1 : (pct / 100).clamp(0, 1), color: color),
          const SizedBox(height: 8),
          Text(
            done
                ? 'Ready to upload'
                : '${pct.toStringAsFixed(0)}% · ${mb.toStringAsFixed(1)} MB${mbps > 0 ? ' · ${mbps.toStringAsFixed(2)} MB/s' : ''} · ${secs}s',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
          if (tail.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('LIVE JSON', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 1)),
                const SizedBox(height: 6),
                SelectableText(
                  _jobJson(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, height: 1.5, color: Color(0xFF86EFAC)),
                ),
                if (logLines.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('LOG', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 1)),
                  const SizedBox(height: 4),
                  SelectableText(
                    logLines.sublist(logLines.length > 8 ? logLines.length - 8 : 0).join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10, height: 1.45, color: Color(0xFF7DD3FC)),
                  ),
                ],
              ]),
            ),
        ],
        if (done && !failed) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              icon: Icon(vis == 'public' ? Icons.public : Icons.lock, size: 16),
              label: Text(vis == 'public' ? 'Public' : 'Private', style: const TextStyle(fontSize: 12.5)),
              onPressed: _uploaded ? null : () => setState(() => vis = vis == 'public' ? 'private' : 'public'),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(
              onPressed: _uploading || _uploaded ? null : _upload,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.green, foregroundColor: Colors.white,
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

  static int _num(dynamic v) => (v is num) ? v.toInt() : 0;

  String _jobJson() {
    final st = (_job['status'] ?? '').toString();
    final pct = _num(_job['percent']).toString();
    final mb = _num(_job['mb']).toString();
    final mbps = _num(_job['mbps']).toString();
    final secs = _num(_job['seconds']).toString();
    final tail = (_job['tail'] ?? '').toString().replaceAll('"', '\\"');
    final size = _num(_job['size']).toString();
    return '{\n'
        '  "job": "${_jobId ?? ''}",\n'
        '  "status": "$st",\n'
        '  "percent": $pct,\n'
        '  "mb": $mb,\n'
        '  "mbps": $mbps,\n'
        '  "size_bytes": $size,\n'
        '  "seconds": $secs,\n'
        '  "tail": "$tail"\n'
        '}';
  }

  String _fmtDur(dynamic d) {
    final s = (d is num) ? d.toInt() : 0;
    if (s <= 0) return '—';
    final m = s ~/ 60, sec = s % 60;
    final h = m ~/ 60;
    return h > 0 ? '${h}h ${m % 60}m' : '${m}m ${sec}s';
  }

  static String _fmtBytes(int b) => fmtBytes(b);
}
