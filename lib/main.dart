import 'package:flutter/material.dart';
import 'api.dart';
import 'widgets.dart';
import 'screens/auth.dart';
import 'screens/overview.dart';
import 'screens/files.dart';
import 'screens/uploads.dart';
import 'screens/channels.dart';
import 'screens/profile.dart';

final authed = ValueNotifier(PipsApi.session != null && PipsApi.session!.isNotEmpty);
final themeMode = ValueNotifier(ThemeMode.system);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PipsApi.loadSession();
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
            valueListenable: authed,
            builder: (_, a, __) => a ? const MainShell() : AuthScreen(onAuthed: () => authed.value = true),
          ),
        ),
      );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: tab, children: const [
          OverviewPage(), FilesPage(), UploadsPage(), ChannelsPage(), ProfilePage(),
        ]),
        floatingActionButton: FloatingActionButton(
          onPressed: () => showSheet(context, const UploadSheet()),
          child: const Icon(Icons.add),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Overview'),
            NavigationDestination(icon: Icon(Icons.folder_copy_outlined), selectedIcon: Icon(Icons.folder_copy), label: 'Files'),
            NavigationDestination(icon: Icon(Icons.upload_outlined), selectedIcon: Icon(Icons.upload), label: 'Uploads'),
            NavigationDestination(icon: Icon(Icons.tv_outlined), selectedIcon: Icon(Icons.tv), label: 'Channels'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      );
}
