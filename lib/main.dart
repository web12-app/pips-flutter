import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'firebase_options.dart';
import 'mini_player.dart';
import 'services/notifications.dart';
import 'widgets.dart';
import 'screens/auth.dart';
import 'screens/onboarding.dart';
import 'screens/overview.dart';
import 'screens/files.dart';
import 'screens/photos.dart';
import 'screens/profile.dart';
import 'screens/uploads.dart';
import 'screens/yt_player.dart';

final authed = ValueNotifier(PipsApi.session != null && PipsApi.session!.isNotEmpty);
final themeMode = ValueNotifier(ThemeMode.system);
final onboardingDone = ValueNotifier(true); // set from prefs in main()

// ---------------------------------------------------------------- deep links
// Web links point at the Pips app first:
//   pips://channel/<slug>/<video_id>   (from https://…/channel/<slug>/<video_id>)
//   pips://                            (generic app open)
// If the user isn't logged in yet the link is held until auth completes.
Uri? _pendingPipsLink;

void _handlePipsLink(Uri? link) {
  if (link == null || link.scheme != 'pips') return;
  final parts = link.pathSegments;
  if (parts.isEmpty || parts.first != 'channel' || parts.length < 3) return; // pips:// → just open the app
  final slug = Uri.decodeComponent(parts[1]);
  final videoId = Uri.decodeComponent(parts[2]);
  if (!authed.value) {
    _pendingPipsLink = Uri.parse('pips://channel/$slug/$videoId');
    return;
  }
  _openChannelVideoDeepLink(slug, videoId);
}

void _flushPendingPipsLink() {
  final link = _pendingPipsLink;
  if (link == null) return;
  if (!authed.value) return; // still not logged in — keep waiting for onAuthed
  _pendingPipsLink = null;
  final parts = link.pathSegments;
  _openChannelVideoDeepLink(Uri.decodeComponent(parts[1]), Uri.decodeComponent(parts[2]));
}

Future<void> _openChannelVideoDeepLink(String slug, String videoId) async {
  try {
    final res = await PipsApi.channelGet(slug); // backend resolves id, name or slug
    final ch = res['channel'] is Map ? Map<String, dynamic>.from(res['channel'] as Map) : <String, dynamic>{};
    final files = (ch['files'] is List ? ch['files'] as List : const []).cast<Map<String, dynamic>>();
    final match = files.cast<Map<String, dynamic>>().where((f) => (f['file_id'] ?? '').toString() == videoId).firstOrNull;
    if (match == null) return; // video not in this channel (or removed)
    final item = ChanItem.fromRaw(match);
    final poster = ch['poster'];
    final logoId = poster is Map && poster['id'] != null ? poster['id'].toString() : null;
    for (var attempt = 0; attempt < 6; attempt++) {
      final ctx = navKey.currentContext;
      if (ctx != null) {
        Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => ChannelVideoPage(
            video: item.e,
            videoTitle: item.title,
            channelId: (ch['id'] ?? '').toString(),
            channelName: (ch['name'] ?? '').toString(),
            channelOwner: (ch['owner'] ?? '').toString(),
            channelLogoId: logoId,
            related: files.map(ChanItem.fromRaw).toList(),
          ),
        ));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  } catch (_) { /* deep link failure never crashes the app */ }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    // Firebase is optional at launch — never block app start if it fails.
  }
  await PipsNotify.i.init();
  await PipsApi.loadSession();
  try {
    final p = await SharedPreferences.getInstance();
    onboardingDone.value = p.getBool('onboarding_done') ?? false;
  } catch (_) {}
  runApp(const PipsApp());
  // deep links: live links + the one that launched the app
  unawaited(onAppLink().listen(_handlePipsLink));
  unawaited(AppLinks.getInitialLink().then(_handlePipsLink));
  WidgetsBinding.instance.addPostFrameCallback((_) => _flushPendingPipsLink());
}

class PipsApp extends StatelessWidget {
  const PipsApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (_, mode, __) => MaterialApp(
          title: 'Pips',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: AppTheme.blue), scaffoldBackgroundColor: AppTheme.bg),
          darkTheme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: AppTheme.blue, brightness: Brightness.dark), scaffoldBackgroundColor: const Color(0xFF0B0B0D)),
          themeMode: mode,
          navigatorKey: navKey,
          home: ValueListenableBuilder<bool>(
            valueListenable: onboardingDone,
            builder: (_, ob, ___) => !ob
                ? OnboardingScreen(
                    onDone: () async {
                      final p = await SharedPreferences.getInstance();
                      await p.setBool('onboarding_done', true);
                      onboardingDone.value = true;
                    },
                  )
                : ValueListenableBuilder<bool>(
                    valueListenable: authed,
                    builder: (_, a, __) => a
                        ? const MainShell()
                        : AuthScreen(onAuthed: () {
                            authed.value = true;
                            _flushPendingPipsLink();
                          }),
                  ),
          ),
        ),
      );
}

/// Main shell with the floating dark pill bottom bar (Home · Files · + · Photos · Account).
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int tab = 0;

  static const _pages = [OverviewPage(), FilesPage(), PhotosPage(), ProfilePage()];

  void _onTap(int i) {
    if (i == 2) {
      showSheet(context, const UploadSheet());
      return;
    }
    setState(() => tab = i < 2 ? i : i - 1);
  }

  @override
  Widget build(BuildContext context) {
    final selected = tab == 0 ? 0 : tab + 1; // map page index -> bar slot (skip center)
    return Scaffold(
      body: IndexedStack(index: tab, children: _pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF16181D),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _item(0, Icons.home_rounded, selected == 0),
              _item(1, Icons.folder_copy_outlined, selected == 1),
              _centerButton(),
              _item(3, Icons.photo_library_outlined, selected == 3),
              _item(4, Icons.person_outline, selected == 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(int slot, IconData icon, bool active) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onTap(slot),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: active ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(icon, size: 23, color: active ? Colors.white : Colors.white54),
        ),
      );

  Widget _centerButton() => GestureDetector(
        onTap: () => _onTap(2),
        child: Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(color: AppTheme.blue, shape: BoxShape.circle),
          child: const Icon(Icons.add, color: Colors.white, size: 26),
        ),
      );
}
