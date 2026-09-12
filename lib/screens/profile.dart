import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../main.dart';
import '../models.dart';
import '../widgets.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _report(BuildContext context) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Report to owner'), content: TextField(controller: c, maxLines: 4, decoration: const InputDecoration(hintText: 'Describe the issue…')), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send'))]));
    if (ok == true) { try { await PipsApi.report(c.text.trim()); if (context.mounted) toast(context, 'Report sent — thank you.'); } on ApiException catch (e) { if (context.mounted) toast(context, e.message); } }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        FutureBuilder<Map<String, dynamic>>(
          future: PipsApi.account(),
          builder: (_, s) {
            final a = s.data ?? {};
            final user = (a['username'] ?? PipsApi.username ?? '').toString();
            final email = (a['email'] ?? '').toString();
            return Column(children: [
              CircleAvatar(radius: 36, backgroundColor: AppTheme.blue, child: Text(user.isEmpty ? '?' : user[0].toUpperCase(), style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold))),
              const SizedBox(height: 10),
              Text('@$user', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              if (email.isNotEmpty) Text(email, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                Chip(label: Text('Files: ${a['file_count'] ?? a['files'] ?? '—'}'), visualDensity: VisualDensity.compact),
                Chip(label: Text('Followers: ${a['followers'] ?? '—'}'), visualDensity: VisualDensity.compact),
                Chip(label: Text('Following: ${a['following'] ?? '—'}'), visualDensity: VisualDensity.compact),
              ]),
            ]);
          },
        ),
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
      ]);
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
