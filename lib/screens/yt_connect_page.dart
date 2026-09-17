import 'package:flutter/material.dart';
import '../api.dart';
import '../services/yt_connect.dart';
import '../widgets.dart';

/// Consent-first YouTube cookie flow:
///
///   1. "Allow YouTube Cookies" consent screen ("I understand")
///   2. The user EXPLICITLY selects a cookies.txt file
///   3. "Use only for this download" → the server deletes the cookie as
///      soon as the download attempt finishes
///
/// No webview, no cookie-jar reading: the picked file is the only source
/// of cookies.
class YtConnectPage extends StatefulWidget {
  const YtConnectPage({super.key});
  @override
  State<YtConnectPage> createState() => _YtConnectPageState();
}

class _YtConnectPageState extends State<YtConnectPage> {
  static const _steps = ['consent', 'select', 'busy'];
  int _step = 0;
  PickedCookieFile? _file;
  bool _oneTime = true; // default: use only for this download
  String? _error;

  Future<void> _pick() async {
    setState(() => _error = null);
    final f = await YtConnect.pick();
    if (f == null) return; // user cancelled
    setState(() => _file = f);
  }

  Future<void> _continue() async {
    final f = _file;
    if (f == null) return;
    setState(() { _step = 2; _error = null; });
    try {
      await YtConnect.save(await f.read(), oneTime: _oneTime);
      if (!mounted) return;
      toast(context, _oneTime
          ? 'YouTube connected ✓ — cookies will be deleted after this download'
          : 'YouTube connected ✓ — video imports will now work');
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() { _step = 1; _error = e.message; });
    } catch (e) {
      if (mounted) setState(() { _step = 1; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = HomeColors.of(context);
    final step = _steps[_step];
    return Scaffold(
      backgroundColor: hc.surface,
      appBar: AppBar(
        backgroundColor: hc.surface,
        foregroundColor: hc.text1,
        elevation: 0,
        title: Text(step == 'consent' ? 'YouTube Cookies' : 'Select cookies.txt',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        leading: IconButton(icon: const Icon(Icons.arrow_back),
            onPressed: () => _step == 0 ? Navigator.pop(context) : setState(() => _step = 0)),
      ),
      body: step == 'consent' ? _consent() : step == 'select' ? _select() : _busy(),
    );
  }

  Widget _consent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.blue.withValues(alpha: 0.2)),
          ),
          child: const Row(children: [
            Icon(Icons.smart_toy, size: 22, color: AppTheme.blue),
            SizedBox(width: 10),
            Expanded(child: Text(
              'Pips needs YouTube authentication cookies for this download.',
              style: TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w600),
            )),
          ]),
        ),
        const SizedBox(height: 14),
        _bullet('Only the cookies.txt file you pick yourself is used — Pips never reads cookies from your browser or the YouTube app.'),
        _bullet('The file is stored privately in your Pips account; only the Pips cloud worker can read it, and only for the download.'),
        _bullet('“Use only for this download” deletes the cookies as soon as the download finishes.'),
        _bullet('You can delete the cookies at any time (Profile → YouTube Cookies).'),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () => setState(() => _step = 1),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.blue, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('I understand — Allow YouTube Cookies',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ],
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('•', style: TextStyle(color: AppTheme.blue, fontSize: 13)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.35))),
      ]),
    );
  }

  Widget _select() {
    final f = _file;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const Text('Pick the cookies.txt you exported from your browser\n(e.g. with a “cookies.txt” extension while signed in to YouTube).',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.grey),
            maxLines: 4),
        const SizedBox(height: 12),
        InkWell(
          onTap: f == null ? _pick : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.blue.withValues(alpha: f == null ? 0.06 : 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.blue.withValues(alpha: 0.3)),
            ),
            child: f == null
                ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.folder_open, size: 18, color: AppTheme.blue),
                    SizedBox(width: 8),
                    Text('Select cookies.txt', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.blue)),
                  ])
                : Row(children: [
                    const Icon(Icons.description_outlined, size: 18, color: AppTheme.blue),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    if (f.size > 0)
                      Text('${(f.size / 1024).toStringAsFixed(1)} KB',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(width: 6),
                    TextButton(onPressed: _pick, child: const Text('Change', style: TextStyle(color: AppTheme.blue, fontSize: 12))),
                  ]),
          ),
        ),
        CheckboxListTile(
          value: _oneTime,
          onChanged: (v) => setState(() => _oneTime = v ?? true),
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Use only for this download', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          subtitle: const Text('deleted from the server right after it finishes', style: TextStyle(fontSize: 11, color: Colors.grey)),
          activeColor: AppTheme.blue,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: const TextStyle(color: AppTheme.red, fontSize: 12.5)),
          ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: f == null ? null : _continue,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.blue, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ],
    );
  }

  Widget _busy() {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
        SizedBox(height: 12),
        Text('Saving cookies…', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        SizedBox(height: 4),
        Text('validating the file format', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
      ]),
    );
  }
}
