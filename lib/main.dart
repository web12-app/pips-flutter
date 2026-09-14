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
final accountsChanged = ValueNotifier(0); // bump to refresh the account switcher

/// Full UI reset — used after switching accounts so every screen re-fetches
/// data for the new user.
void restartShell() {
  navKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const MainShell()),
    (__) => false,
  );
}

// Instantiate early (singleton) to catch the very first link on cold start.
final appLinks = AppLinks();

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
      final nav = navKey.currentState;
      if (nav != null) {
        nav.push(MaterialPageRoute(
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
  // Deep links: uriLinkStream emits the cold-start link too — subscribe first.
  appLinks.uriLinkStream.listen(_handlePipsLink);
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
    final t = p.getString('pips_theme');
    themeMode.value = t == 'light' ? ThemeMode.light : t == 'dark' ? ThemeMode.dark : ThemeMode.system;
  } catch (_) {}
  runApp(const PipsApp());
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
    final hc = HomeColors.of(context);
    final selected = tab == 0 ? 0 : tab + 1; // map page index -> bar slot (skip center)
    return Scaffold(
      body: IndexedStack(index: tab, children: _pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: hc.line),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, 6)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _item(0, 'Home', Icons.home_outlined, Icons.home_rounded, selected == 0),
              _item(1, 'Files', Icons.folder_outlined, Icons.folder_rounded, selected == 1),
              _centerButton(),
              _item(3, 'Photos', Icons.photo_library_outlined, Icons.photo_library, selected == 3),
              _item(4, 'Profile', Icons.person_outline, Icons.person_rounded, selected == 4),
            ],
          ),
        ),
      ),
    );
  }

  /// Icon + label tab — blue filled icon & blue label when active,
  /// grey outlined icon & grey label otherwise (like the reference).
  Widget _item(int slot, String label, IconData inactiveIcon, IconData activeIcon, bool active) {
    final hc = HomeColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onTap(slot),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AppTheme.blueSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(active ? activeIcon : inactiveIcon, size: 24, color: active ? AppTheme.blue : hc.text2),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: active ? AppTheme.blue : hc.text2)),
        ]),
      ),
    );
  }

  /// Raised blue circular + button in the middle (opens the upload sheet).
  Widget _centerButton() => GestureDetector(
        onTap: () => _onTap(2),
        child: Transform.translate(
          offset: const Offset(0, -8),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.blue,
              shape: BoxShape.circle,
              border: Border.all(color: HomeColors.of(context).surface, width: 3),
              boxShadow: [BoxShadow(color: AppTheme.blue.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 5))],
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 30),
          ),
        ),
      );
}
