import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';
import 'files.dart';
import 'channels.dart';
import 'yt_player.dart';

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
            if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
            final items = (s.data ?? []).map((e) => Entry(Map<String, dynamic>.from(e as Map))).toList();
            if (items.isEmpty) return const EmptyState(icon: '🗑️', text: 'Trash is empty.');
            return ListView.builder(itemCount: items.length, itemBuilder: (_, i) => ListTile(
              leading: const IconTile(icon: Icons.delete_outline, bg: Color(0xFFFEE2E2), fg: AppTheme.red),
              title: Text(items[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(fmtBytes(items[i].size)),
              trailing: Wrap(spacing: 2, children: [
                IconButton(icon: const Icon(Icons.restore, size: 20), tooltip: 'Restore', onPressed: () async { try { await PipsApi.trashRestore(items[i].id); setState(() => refresh = UniqueKey()); } on ApiException catch (e) { if (context.mounted) toast(context, e.message); } }),
                IconButton(icon: const Icon(Icons.delete_forever, size: 20, color: AppTheme.red), tooltip: 'Purge forever', onPressed: () async {
                  final ok = await confirmDelete(context, title: 'Delete "${items[i].name}" forever?', message: 'This cannot be undone — the file is removed permanently.', confirmLabel: 'Yes, delete forever');
                  if (!ok) return;
                  try { await PipsApi.trashPurge(items[i].id); setState(() => refresh = UniqueKey()); } on ApiException catch (e) { if (context.mounted) toast(context, e.message); }
                }),
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
            if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
            final items = (s.data ?? []).map((e) => Entry(Map<String, dynamic>.from(e as Map))).toList();
            if (items.isEmpty) return const EmptyState(icon: '🕓', text: 'No uploads yet.');
            return ListView.builder(itemCount: items.length, itemBuilder: (_, i) => fileTile(context, items[i], () {}, gallery: items));
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
          decoration: const InputDecoration(hintText: 'Search videos, channels & files…', border: InputBorder.none),
          onChanged: (v) => setState(() => q = v),
        )),
        body: q.trim().length < 2 ? const EmptyState(icon: '🔍', text: 'Type to search your files, videos and channels.') : FutureBuilder<List<dynamic>>(
          future: Future.wait<dynamic>([PipsApi.search(q), PipsApi.channelsGlobalFileSearch(q), PipsApi.channelsPublic(q)]),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
            final r0 = (s.data?[0] as Map<String, dynamic>?) ?? <String, dynamic>{};
            final files = ((r0['files'] ?? r0['results'] ?? const []) as List).map((e) => Entry(Map<String, dynamic>.from(e as Map))).toList();
            final vids = <ChanItem>[
              for (final x in ((s.data?[1] as List<dynamic>?) ?? const []))
                ChanItem.fromRaw(Map<String, dynamic>.from(x as Map)),
            ]..removeWhere((x) => x.e.id.isEmpty);
            final chans = [
              for (final c in ((s.data?[2] as List<dynamic>?) ?? const []))
                Map<String, dynamic>.from(c as Map),
            ];
            if (files.isEmpty && vids.isEmpty && chans.isEmpty) return const EmptyState(icon: '🔍', text: 'Nothing found.');
            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              if (vids.isNotEmpty) ...[
                const SectionTitle('Videos'),
                for (final it in vids) _videoRow(it, vids),
              ],
              if (chans.isNotEmpty) ...[
                const SectionTitle('Channels'),
                for (final c in chans) _channelRow(c),
              ],
              if (files.isNotEmpty) ...[
                const SectionTitle('My files'),
                ...files.map((e) => fileTile(context, e, () {}, gallery: files)),
              ],
            ]);
          },
        ),
      );

  Widget _videoRow(ChanItem it, List<ChanItem> vids) => ListTile(
        leading: Container(
          width: 96, height: 54,
          decoration: BoxDecoration(color: const Color(0xFF16181D), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 30),
        ),
        title: Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        subtitle: Row(children: [
          ChannelAvatar(fileId: it.channelLogoId, name: it.channelName, radius: 8),
          const SizedBox(width: 5),
          Flexible(child: Text(it.channelName.isEmpty ? '@${it.channelOwner}' : it.channelName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
        ]),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChannelVideoPage(
          video: it.e,
          videoTitle: it.title,
          channelId: it.channelId,
          channelName: it.channelName,
          channelOwner: it.channelOwner,
          channelLogoId: it.channelLogoId,
          related: vids,
        ))),
      );

  Widget _channelRow(Map<String, dynamic> c) {
    final name = (c['name'] ?? 'channel').toString();
    final id = (c['id'] ?? '').toString();
    final desc = (c['description'] ?? '').toString();
    final count = c['file_count'] is num ? (c['file_count'] as num).toInt() : 0;
    final poster = c['poster'];
    final posterId = poster is Map ? (poster['id'] ?? '').toString() : '';
    return ListTile(
      leading: ChannelAvatar(fileId: posterId.isEmpty ? null : posterId, name: name, radius: 22),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(desc.isEmpty ? '$count videos' : '$desc · $count videos', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChannelPage(id: id, name: name))),
    );
  }
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
            if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
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
