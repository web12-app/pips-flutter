import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';
import 'files.dart';
import 'db.dart';
import 'chat.dart';
import 'misc.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        FutureBuilder<Map<String, dynamic>>(
          future: PipsApi.account(),
          builder: (_, s) {
            final a = s.data ?? {};
            final used = (a['storage_used'] is num ? (a['storage_used'] as num) : 0) / 1e9;
            final quota = (a['quota'] is num ? (a['quota'] as num) : 10.9e9) / 1e9;
            final pct = quota > 0 ? used / quota : 0.0;
            return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${used.toStringAsFixed(2)} GB of ${quota.toStringAsFixed(1)} GB', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const Text('Storage used', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
                const Icon(Icons.cloud_done_outlined, color: AppTheme.blue, size: 28),
              ]),
              const SizedBox(height: 10),
              ProgressBar(value: pct),
            ]));
          },
        ),
        const SectionTitle('Quick actions'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _chip(context, Icons.search, 'Search', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage()))),
          _chip(context, Icons.folder_outlined, 'Folders', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FoldersPage()))),
          _chip(context, Icons.delete_outline, 'Trash', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrashPage()))),
          _chip(context, Icons.history, 'History', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()))),
          _chip(context, Icons.table_chart_outlined, 'Pips DB', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DbPage()))),
          _chip(context, Icons.forum_outlined, 'Messages', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InboxPage()))),
          _chip(context, Icons.person_search_outlined, 'Find people', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserSearchPage()))),
          _chip(context, Icons.notifications_outlined, 'Alerts', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage()))),
        ]),
        const SectionTitle('Recent files'),
        FutureBuilder<List<dynamic>>(
          future: PipsApi.filesRecent(6),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Loading();
            final items = (s.data ?? []).map((e) => Entry(Map<String, dynamic>.from(e as Map))).toList();
            if (items.isEmpty) return const EmptyState(icon: '📭', text: 'No recent files.');
            return Column(children: items.map((e) => fileTile(context, e, () {}, gallery: items)).toList());
          },
        ),
      ]);

  Widget _chip(BuildContext context, IconData icon, String label, VoidCallback onTap) => ActionChip(
        avatar: Icon(icon, size: 18, color: AppTheme.blue),
        label: Text(label),
        onPressed: onTap,
      );
}
