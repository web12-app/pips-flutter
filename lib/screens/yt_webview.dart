import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../widgets.dart';
import 'yt_local_page.dart';

/// Watch ANY YouTube URL in an in-app webview (standard YouTube web player —
/// the user's own browser cookies apply, nothing is extracted). "Download"
/// hands the current video URL to the local phone downloader.
class YtWebViewPage extends StatefulWidget {
  final String url;
  const YtWebViewPage({super.key, this.url = 'https://www.youtube.com'});
  @override
  State<YtWebViewPage> createState() => _YtWebViewPageState();
}

class _YtWebViewPageState extends State<YtWebViewPage> {
  late final WebViewController _c;
  int _progress = 0;
  String _current = '';

  String get _watchUrl {
    var u = widget.url.trim();
    if (u.isEmpty) return 'https://www.youtube.com';
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    return u;
  }

  @override
  void initState() {
    super.initState();
    _current = _watchUrl;
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B1220))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onUrlChange: (change) {
          final u = change.url ?? '';
          if (u.isNotEmpty) setState(() => _current = u);
        },
        onNavigationRequest: (req) {
          if (req.url.startsWith('intent://') || req.url.startsWith('inappbrowser://')) {
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(_watchUrl));
  }

  Future<void> _downloadThis() async {
    var u = _current;
    if (!u.contains('/watch') && !u.contains('/shorts/') && !u.contains('youtu.be/')) {
      u = _watchUrl;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => YtLocalPage(initialUrl: u)));
  }

  @override
  Widget build(BuildContext context) {
    final hc = HomeColors.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1220),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('YouTube', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), tooltip: 'Reload',
              onPressed: () => _c.loadRequest(Uri.parse(_current))),
          IconButton(icon: const Icon(Icons.close, size: 22), onPressed: () => Navigator.pop(context)),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: _progress < 100
              ? LinearProgressIndicator(
                  value: _progress / 100, minHeight: 3,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation(AppTheme.blue))
              : const SizedBox(height: 3),
        ),
      ),
      body: Column(children: [
        Expanded(child: WebViewWidget(controller: _c)),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: const BoxDecoration(color: Color(0xFF0F172A)),
            child: Row(children: [
              Expanded(child: Text(
                _current,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: hc.text2, fontFamily: 'monospace'),
              )),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _downloadThis,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.blue, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  minimumSize: Size.zero,
                ),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Download', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
