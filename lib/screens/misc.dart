import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';
import 'files.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});
  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  Key refresh = UniqueKey();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Trash')),
        body: FutureBuilder<List<dynamic>>(
          key: refresh,
          future: PipsApi.filesTrash(),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Loading();
            final items = (s.data ?? []).map((e) => Entry(Map<String, dynamic>.from(e as Map))).toList();
            if (items.isEmpty) return const EmptyState(icon: '🗑️', text: 'Trash is empty.');
            return ListView.builder(itemCount: items.length, itemBuilder: (_, i) => ListTile(
              leading: const IconTile(icon: Icons.delete_outline, bg: Color(0xFFFEE2E2), fg: AppTheme.red),
              title: Text(items[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(fmtBytes(items[i].size)),
              trailing: Wrap(spacing: 2, children: [
                IconButton(icon: const Icon(Icons.restore, size: 20), tooltip: 'Restore', onPressed: () async { try { await PipsApi.trashRestore(items[i].id); setState(() => refresh = UniqueKey()); } on ApiException catch (e) { if (context.mounted) toast(context, e.message); } }),
                IconButton(icon: const Icon(Icons.delete_forever, size: 20, color: AppTheme.red), tooltip: 'Purge forever', onPressed: () async { try { await PipsApi.trashPurge(items[i].id); setState(() => refresh = UniqueKey()); } on ApiException catch (e) { if (context.mounted) toast(context, e.message); } }),
              ]),
            ));
          },
        ),
      );
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Recent uploads')),
        body: FutureBuilder<List<dynamic>>(
          future: PipsApi.filesRecent(50),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Loading();
            final items = (s.data ?? []).map((e) => Entry(Map<String, dynamic>.from(e as Map))).toList();
            if (items.isEmpty) return const EmptyState(icon: '🕓', text: 'No uploads yet.');
            return ListView.builder(itemCount: items.length, itemBuilder: (_, i) => fileTile(context, items[i], () {}));
          },
        ),
      );
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String q = '';
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search everything…', border: InputBorder.none),
          onChanged: (v) => setState(() => q = v),
        )),
        body: q.isEmpty ? const EmptyState(icon: '🔍', text: 'Type to search your files and channels.') : FutureBuilder<Map<String, dynamic>>(
          future: PipsApi.search(q),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Loading();
            final r = s.data ?? {};
            final files = ((r['files'] ?? r['results'] ?? const []) as List).map((e) => Entry(Map<String, dynamic>.from(e as Map))).toList();
            return ListView(children: [
              if (files.isEmpty && (r['channels'] as List?)?.isNotEmpty != true) const EmptyState(icon: '🔍', text: 'Nothing found.'),
              ...files.map((e) => fileTile(context, e, () {})),
              if ((r['channels'] as List?)?.isNotEmpty == true) ...[
                const SectionTitle('Channels'),
                ...(r['channels'] as List).map((c) { final m = Map<String, dynamic>.from(c as Map); return ListTile(leading: const Icon(Icons.tv), title: Text((m['name'] ?? '').toString())); }),
              ],
            ]);
          },
        ),
      );
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  Key refresh = UniqueKey();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: FutureBuilder<List<dynamic>>(
          key: refresh,
          future: PipsApi.notifications(),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Loading();
            final items = (s.data ?? []);
            if (items.isEmpty) return const EmptyState(icon: '🔔', text: 'No notifications.');
            return ListView.builder(itemCount: items.length, itemBuilder: (_, i) {
              final n = Map<String, dynamic>.from(items[i] as Map);
              final id = (n['id'] ?? '').toString();
              final read = n['read'] == true;
              return ListTile(
                leading: Icon(read ? Icons.notifications_none : Icons.notifications_active, color: read ? Colors.grey : AppTheme.blue),
                title: Text((n['text'] ?? n['message'] ?? '').toString(), style: TextStyle(fontWeight: read ? FontWeight.normal : FontWeight.w600)),
                subtitle: Text(fmtDate(n['created_at']?.toString())),
                onTap: () { if (!read) PipsApi.notificationsRead(id).then((_) => setState(() => refresh = UniqueKey())); },
              );
            });
          },
        ),
      );
}
