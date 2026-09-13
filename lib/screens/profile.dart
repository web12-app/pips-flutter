import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../main.dart';
import '../models.dart';
import '../widgets.dart';
import 'misc.dart';
import 'subscription.dart';

/// Account — profile, plan card, camera uploads, desktop link, recovery & settings.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _report(BuildContext context) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Report to owner'), content: TextField(controller: c, maxLines: 4, decoration: const InputDecoration(hintText: 'Describe the issue…')), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send'))]));
    if (ok == true) { try { await PipsApi.report(c.text.trim()); if (context.mounted) toast(context, 'Report sent — thank you.'); } on ApiException catch (e) { if (context.mounted) toast(context, e.message); } }
  }

  Future<void> _linkDesktop(BuildContext context) async {
    await showDialog(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Link your desktop'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Open the Pips web dashboard on your desktop and log in with the same account:', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            SelectableText(PipsApi.base, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.blue)),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
        ));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false, // bottom pill bar already sits in its own SafeArea
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
        FutureBuilder<Map<String, dynamic>>(
          future: PipsApi.account(),
          builder: (_, s) {
            final a = s.data ?? {};
            final user = (a['username'] ?? PipsApi.username ?? '').toString();
            final email = (a['email'] ?? '').toString();
            return Column(children: [
              Container(
                width: 84, height: 84,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFEAF4FF), shape: BoxShape.circle, border: Border.all(color: const Color(0xFFBFDBFE), width: 2)),
                child: Image.asset('assets/logo.png', fit: BoxFit.contain),
              ),
              const SizedBox(height: 10),
              Text(user.isEmpty ? 'Account' : '@$user', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              if (email.isNotEmpty) Text(email, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ]);
          },
        ),
        const SizedBox(height: 14),
        _planCard(context),
        const SizedBox(height: 12),
        _optionsCard(context),
        const SizedBox(height: 12),
        Card(child: Column(children: [
          ListTile(leading: const Icon(Icons.key_outlined, color: AppTheme.blue), title: const Text('API keys'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiKeysPage()))),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.brightness_6_outlined, color: AppTheme.orange), title: const Text('Appearance'), trailing: const Icon(Icons.chevron_right), onTap: () => showDialog(context: context, builder: (ctx) => SimpleDialog(title: const Text('Theme'), children: [
                for (final t in [('System', ThemeMode.system), ('Light', ThemeMode.light), ('Dark', ThemeMode.dark)])
                  SimpleDialogOption(onPressed: () { themeMode.value = t.$2; Navigator.pop(ctx); }, child: Text(t.$1)),
              ]))),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.menu_book_outlined, color: AppTheme.teal), title: const Text('Docs'), trailing: const Icon(Icons.open_in_new, size: 16), onTap: () => launchUrl(Uri.parse(PipsApi.base), mode: LaunchMode.externalApplication)),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.flag_outlined, color: AppTheme.red), title: const Text('Report to owner'), onTap: () => _report(context)),
        ])),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFEE2E2), foregroundColor: AppTheme.red, padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: () async { await PipsApi.logout(); authed.value = false; },
          icon: const Icon(Icons.logout),
          label: const Text('Log out'),
        ),
        ]),
      );

  // ------------------------------------------------------------- your plan
  Widget _planCard(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8EEF6))),
        child: Column(children: [
          FutureBuilder<Map<String, dynamic>>(
            future: PipsApi.account(),
            builder: (_, s) {
              final a = s.data ?? {};
              final used = (a['storage_used'] is num ? (a['storage_used'] as num) : 0).toInt();
              final quota = (a['quota'] is num && (a['quota'] as num) > 0 ? (a['quota'] as num) : 2199023255552).toInt();
              final files = a['file_count'] ?? a['files'] ?? 0;
              return Row(children: [
                SizedBox(width: 42, height: 42, child: Image.asset('assets/logo.png', fit: BoxFit.contain)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Text('Your Plan — Pips Basic', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(99)),
                        child: const Text('Free', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF059669))),
                      ),
                    ]),
                    const SizedBox(height: 3),
                    Text('${fmtBytes(used)} of ${fmtBytes(quota)} used · $files files', style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                    const SizedBox(height: 8),
                    ProgressBar(value: quota > 0 ? used / quota : 0),
                  ]),
                ),
              ]);
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16181D), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionPage())),
              child: const Text('Manage Your Plan', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      );

  // ------------------------------------------------------------- options
  Widget _optionsCard(BuildContext context) => Card(child: Column(children: [
        FutureBuilder<bool>(
          future: _cameraPref(),
          builder: (_, s) => SwitchListTile(
            secondary: const IconTile(icon: Icons.photo_camera_outlined, bg: Color(0xFFDBEAFE), fg: AppTheme.blue, size: 38),
            title: const Text('Camera Uploads', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: const Text('Auto-queue new photos for upload (beta)', style: TextStyle(fontSize: 11.5)),
            value: s.data ?? false,
            onChanged: (v) async {
              final p = await SharedPreferences.getInstance();
              await p.setBool('camera_uploads', v);
              if (context.mounted) toast(context, v ? 'Camera uploads on — new photos will queue in background.' : 'Camera uploads off.');
            },
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const IconTile(icon: Icons.desktop_windows_outlined, bg: Color(0xFFEDE9FE), fg: AppTheme.purple, size: 38),
          title: const Text('Link your desktop', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: const Text('Manage uploads from the web dashboard', style: TextStyle(fontSize: 11.5)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _linkDesktop(context),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const IconTile(icon: Icons.restore_from_trash_outlined, bg: Color(0xFFFEF3C7), fg: const Color(0xFFD97706), size: 38),
          title: const Text('Recover deleted files', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: const Text('Restore files from your trash', style: TextStyle(fontSize: 11.5)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrashPage())),
        ),
      ]));

  static Future<bool> _cameraPref() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('camera_uploads') ?? false;
  }
}

class ApiKeysPage extends StatefulWidget {
  const ApiKeysPage({super.key});
  @override
  State<ApiKeysPage> createState() => _ApiKeysPageState();
}

class _ApiKeysPageState extends State<ApiKeysPage> {
  Key refresh = UniqueKey();

  Future<void> createKey() async {
    final c = TextEditingController();
    final label = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('New API key'), content: TextField(controller: c, decoration: const InputDecoration(hintText: 'Label (e.g. "laptop")')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Create'))]));
    if (label == null) return;
    try {
      final r = await PipsApi.createKey(label);
      if (!mounted) return;
      final key = (r['key'] ?? r['token'] ?? '').toString(); // shown ONCE
      await showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Copy your key now'), content: SelectableText(key.isEmpty ? 'Key created.' : key), actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))]));
      setState(() => refresh = UniqueKey());
    } on ApiException catch (e) { if (mounted) toast(context, e.message); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('API keys')),
        floatingActionButton: FloatingActionButton.extended(onPressed: createKey, icon: const Icon(Icons.add), label: const Text('Create')),
        body: FutureBuilder<Map<String, dynamic>>(
          key: refresh,
          future: PipsApi.account(),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Loading();
            final a = s.data ?? {};
            final keys = (a['keys'] ?? a['api_keys'] ?? const []) as List;
            if (keys.isEmpty) return const EmptyState(icon: '🔑', text: 'No API keys yet.');
            return ListView.builder(itemCount: keys.length, itemBuilder: (_, i) {
              final k = Map<String, dynamic>.from(keys[i] as Map);
              final id = (k['id'] ?? '').toString();
              return ListTile(
                leading: const Icon(Icons.key, color: AppTheme.blue),
                title: Text((k['label'] ?? 'key').toString()),
                subtitle: Text(fmtDate(k['created_at']?.toString())),
                trailing: IconButton(icon: const Icon(Icons.delete_outline, color: AppTheme.red), onPressed: () async { try { await PipsApi.revokeKey(id); setState(() => refresh = UniqueKey()); } on ApiException catch (e) { if (context.mounted) toast(context, e.message); } }),
              );
            });
          },
        ),
      );
}
