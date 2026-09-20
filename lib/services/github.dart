import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../api.dart';
import '../widgets.dart';
import 'google.dart';

/// GitHub sign-in via the Firebase console GitHub provider (pips-cloud).
///
/// firebase_auth has no native GitHub UI on Android, so we open a WebView that
/// runs the standard Firebase JS **redirect** flow on
/// https://pips-next.antideploy.com/github-auth.html — that page uses the exact
/// GitHub OAuth app configured in the Firebase console, then hands the
/// verified GitHub email back to the app over the `pips-auth://` scheme.
/// The verified email is bridged to a Pips account exactly like Google:
/// silent login when stored credentials exist, else the prefilled signup
/// wizard (one-time OTP into that inbox).
class GithubAuth {
  GithubAuth._();

  /// Opens the GitHub bridge. Returns {'email': …, 'name': …} on success,
  /// null when the user closed the WebView.
  static Future<Map<String, String>?> signIn(BuildContext context) {
    return Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(builder: (_) => const GithubWebViewPage()),
    );
  }

  /// Silent Pips login with credentials stored by a previous GitHub signup.
  static Future<bool> tryStoredLogin(String email) => GoogleAuth.tryStoredLogin(email);

  /// Remember the Pips credentials created through a GitHub-driven signup.
  static Future<void> remember(String email, String username, String pass) =>
      GoogleAuth.remember(email, username, pass);
}

class GithubWebViewPage extends StatefulWidget {
  const GithubWebViewPage({super.key});
  @override
  State<GithubWebViewPage> createState() => _GithubWebViewPageState();
}

class _GithubWebViewPageState extends State<GithubWebViewPage> {
  late final WebViewController _c;
  int _progress = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B1220))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onNavigationRequest: (req) {
          if (req.url.startsWith('pips-auth://')) {
            if (!_done) {
              _done = true;
              final uri = Uri.parse(req.url);
              final res = <String, String>{
                'email': uri.queryParameters['email'] ?? '',
                'name': uri.queryParameters['name'] ?? '',
              };
              Navigator.pop(context, res);
            }
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse('${PipsApi.base}/github-auth.html'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1220),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Sign in with GitHub',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: _progress < 100
              ? LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 3,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation(AppTheme.blue))
              : const SizedBox(height: 3),
        ),
      ),
      body: WebViewWidget(controller: _c),
    );
  }
}
