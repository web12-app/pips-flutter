import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../api.dart';
import '../services/yt_connect.dart';
import '../widgets.dart';

/// Full-screen in-app YouTube login: the user opens YouTube, signs in if
/// asked (best results), and taps "Save cookies" — the app collects the
/// session cookies from the cookie jar and sends them to the Pips server.
class YtConnectPage extends StatefulWidget {
  const YtConnectPage({super.key});
  @override
  State<YtConnectPage> createState() => _YtConnectPageState();
}

class _YtConnectPageState extends State<YtConnectPage> {
  final WebViewController _ctrl = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.transparent)
    ..loadRequest(Uri.parse('https://www.youtube.com'));
  bool busy = false;

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await YtConnect.save();
      if (mounted) toast(context, 'YouTube connected ✓ — video imports will now work');
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = HomeColors.of(context);
    return Scaffold(
      backgroundColor: hc.bg,
      appBar: AppBar(
        backgroundColor: hc.bg,
        foregroundColor: hc.text1,
        elevation: 0,
        title: const Text('YouTube — sign in & connect', style: TextStyle(fontWeight: FontWeight.w700)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton.icon(
            onPressed: busy ? null : _save,
            icon: busy
                ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_circle_outline, size: 18),
            label: Text(busy ? 'Saving…' : 'Save cookies', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.blue)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.blue.withValues(alpha: 0.25)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 16, color: AppTheme.blue),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Sign in to your Google/YouTube account below if asked (works best when signed in). Then tap "Save cookies". The cookies stay private on the Pips server — only the Pips cloud worker can use them.',
              style: TextStyle(fontSize: 12, height: 1.3),
            )),
          ]),
        ),
        Expanded(child: WebViewWidget(controller: _ctrl)),
      ]),
    );
  }
}
