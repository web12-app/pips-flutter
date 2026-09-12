import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets.dart';

/// First-launch onboarding: permission pages shown once before login.
///
/// 1. Notifications  — upload progress/completion alerts (POST_NOTIFICATIONS)
/// 2. Files & photos — pick gallery/media/documents for direct upload
/// 3. Playback       — background music/video playback info
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final ctrl = PageController();
  int page = 0;
  bool busy = false;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  static const _pages = [
    (Icons.notifications_active_outlined, AppTheme.blue, 'Stay updated',
        'Allow notifications so Pips can show live upload progress and alert you the moment your files finish uploading — even when the app is in the background.', 'Allow notifications'),
    (Icons.folder_shared_outlined, AppTheme.purple, 'Your files, direct from mobile',
        'Grant file and photo access so you can select images, videos and documents straight from your phone gallery and upload them to your Pips cloud in one tap.', 'Allow file access'),
    (Icons.play_circle_outline, AppTheme.teal, 'Music & video, anywhere',
        'Keep your music and videos playing with smooth in-app playback while uploads continue in the background. Pips handles the rest automatically.', "Let's go"),
  ];

  Future<void> _request() async {
    if (page == 2) return _finish();
    setState(() => busy = true);
    try {
      if (page == 0) {
        await Permission.notification.request();
      } else {
        await Permission.photos.request();
        await Permission.videos.request();
        await Permission.storage.request(); // legacy (< Android 13)
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => busy = false);
    ctrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _finish() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('onboarding_done', true);
    } catch (_) {}
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final p = _pages[page];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Align(
              alignment: Alignment.centerRight,
              child: page == 2
                  ? const SizedBox(height: 48)
                  : TextButton(
                      onPressed: _finish,
                      child: const Text('Skip', style: TextStyle(color: Colors.grey)),
                    ),
            ),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 148,
                  height: 148,
                  decoration: BoxDecoration(color: p.$2.withValues(alpha: 0.13), shape: BoxShape.circle),
                  child: Icon(p.$1, size: 64, color: p.$2),
                ),
                const SizedBox(height: 36),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: i == page ? 22 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: i == page ? AppTheme.blue : const Color(0xFFD6E4F5),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                ]),
                const SizedBox(height: 26),
                Text(p.$3, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                Text(p.$4, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14.5, color: Colors.grey, height: 1.55)),
              ]),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: busy ? null : _request,
                child: busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(p.$5, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            if (page == 2) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => openAppSettings(),
                child: const Text('Manage permissions later in Settings', style: TextStyle(fontSize: 12.5, color: Colors.grey)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
