import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'firebase_options.dart';
import 'services/notifications.dart';
import 'widgets.dart';
import 'screens/auth.dart';
import 'screens/onboarding.dart';
import 'screens/overview.dart';
import 'screens/files.dart';
import 'screens/photos.dart';
import 'screens/profile.dart';
import 'screens/uploads.dart';

final authed = ValueNotifier(PipsApi.session != null && PipsApi.session!.isNotEmpty);
final themeMode = ValueNotifier(ThemeMode.system);
final onboardingDone = ValueNotifier(true); // set from prefs in main()

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
}

class PipsApp extends StatelessWidget {
  const PipsApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (_, mode, __) => MaterialApp(
          title: 'Pips',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: AppTheme.blue)),
          darkTheme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: AppTheme.blue, brightness: Brightness.dark)),
          themeMode: mode,
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
                    builder: (_, a, __) => a ? const MainShell() : AuthScreen(onAuthed: () => authed.value = true),
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
