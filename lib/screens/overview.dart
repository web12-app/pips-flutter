import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';
import 'files.dart';
import 'db.dart';
import 'chat.dart';
import 'misc.dart';
import 'channels.dart';
import 'uploads.dart';
import 'yt_player.dart';

/// Home — greeting header, storage, recent files & folders, activity, quick actions.
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});
  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  Key refresh = UniqueKey();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false, // bottom pill bar already sits in its own SafeArea
      child: RefreshIndicator(
        onRefresh: () async => setState(() => refresh = UniqueKey()),
        child: FutureBuilder<List<dynamic>>(
        key: refresh,
        future: Future.wait<dynamic>([PipsApi.account(), PipsApi.filesAll()]),
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return const Loading();
          final account = (s.data?[0] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final all = ((s.data?[1] as List<dynamic>?) ?? const [])
              .map((e) => Entry(Map<String, dynamic>.from(e as Map)))
              .toList()
            ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _header(account),
              const SizedBox(height: 14),
              _searchBar(context),
              const SizedBox(height: 18),
              _videoFeed(),
              Text('Save with Pips', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.grey.shade900)),
              const SizedBox(height: 12),
              _recentCard(context, all),
              const SizedBox(height: 12),
              _activityCard(context, all),
              const SizedBox(height: 6),
              const SectionTitle('Quick actions'),
              _quickActions(context),
              const SectionTitle('Recent files'),
              if (all.isEmpty)
                const EmptyState(icon: '📭', text: 'No files yet — tap + to upload.')
              else
                ...all.take(6).map((e) => fileTile(context, e, () => setState(() => refresh = UniqueKey()), gallery: all)),
            ],
          );
        },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- header
  Widget _header(Map<String, dynamic> account) {
    final user = (account['username'] ?? PipsApi.username ?? 'there').toString();
    final used = (account['storage_used'] is num ? (account['storage_used'] as num) : 0).toDouble();
    final quota = (account['quota'] is num && (account['quota'] as num) > 0 ? (account['quota'] as num) : 2199023255552).toDouble();
    final pct = quota > 0 ? used / quota : 0.0;
    return Row(children: [
      Container(
        width: 46,
        height: 46,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE8EEF6)), boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3)),
        ]),
        child: Image.asset('assets/logo.png', fit: BoxFit.contain),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hi, $user 👋', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text('Storage used ${(pct * 100).toStringAsFixed(1)}% · ${fmtBytes(used.toInt())}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ),
      IconButton(
        tooltip: 'Notifications',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
        icon: const Icon(Icons.notifications_outlined, size: 26),
      ),
    ]);
  }

  // ------------------------------------------------- YouTube-style video feed
  /// Newest videos from all PUBLIC channels — scroll and touch to watch.
  Widget _videoFeed() => FutureBuilder<List<dynamic>>(
        future: PipsApi.channelFeed(),
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return const SizedBox.shrink();
          final raw = (s.data ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
          final items = <ChanItem>[];
          for (final f in raw) {
            final it = ChanItem.fromRaw(f);
            if (it.e.id.isNotEmpty) items.add(it);
          }
          if (items.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.smart_display_rounded, size: 20, color: AppTheme.red),
              const SizedBox(width: 6),
              const Expanded(child: Text('Videos for you', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChannelsPage(initialTab: 1))),
                child: Text('Discover', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
              ),
            ]),
            const SizedBox(height: 8),
            for (final it in items.take(10)) _feedCard(it, items),
            const SizedBox(height: 6),
          ]);
        },
      );

  Widget _feedCard(ChanItem it, List<ChanItem> items) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChannelVideoPage(
        video: it.e,
        videoTitle: it.title,
        channelId: it.channelId,
        channelName: it.channelName,
        channelOwner: it.channelOwner,
        channelLogoId: it.channelLogoId,
        related: items,
      ))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 16:9 thumbnail area (YouTube template)
          Container(
            width: double.infinity,
            height: MediaQuery.of(context).size.width * 9 / 16,
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1F2430), Color(0xFF11141B)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(children: [
              const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 54)),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                  child: Text(fmtBytes(it.e.size), style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 9),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ChannelAvatar(fileId: it.channelLogoId, name: it.channelName, radius: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.25)),
                const SizedBox(height: 3),
                Text('${it.channelName.isNotEmpty ? it.channelName : '@${it.channelOwner}'} · ${fmtDate(it.addedAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- search
  Widget _searchBar(BuildContext context) => GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(color: const Color(0xFFF3F6FA), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.search, color: Colors.grey, size: 21),
            const SizedBox(width: 8),
            Expanded(child: Text('Search files', style: TextStyle(color: Colors.grey.shade500, fontSize: 14))),
            const Icon(Icons.tune, color: Colors.grey, size: 20),
          ]),
        ),
      );

  // ------------------------------------------------- recent files & folders
  Widget _recentCard(BuildContext context, List<Entry> all) {
    final videos = all.where((e) => isVideo(e.mime, e.name)).toList();
    final photos = all.where((e) => isImage(e.mime, e.name) && !e.isDb).toList();
    final projects = all.where((e) => !isVideo(e.mime, e.name) && !isImage(e.mime, e.name)).toList();
    int bytes(List<Entry> l) => l.fold(0, (a, e) => a + e.size);

    Widget tile(IconData icon, Color bg, Color fg, String title, String sub, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              IconTile(icon: icon, bg: bg, fg: fg, size: 36),
              const SizedBox(height: 8),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
            ]),
          ),
        );

    void openFilter(String f) => Navigator.push(context, MaterialPageRoute(builder: (_) => FilesPage(initialFilter: f)));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFC7B9F7), Color(0xFFA78BFA)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Recent Files & Folders', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Color(0xFF3B2F63))),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FilesPage())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(99)),
              child: const Text('See All', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF3B2F63))),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: [
            tile(Icons.backup_outlined, const Color(0xFFDBEAFE), const Color(0xFF2563EB), 'My Backup', '${all.length} files · ${fmtBytes(bytes(all))}', () => openFilter('')),
            tile(Icons.smart_display_outlined, const Color(0xFFFCE7F3), const Color(0xFFDB2777), 'Videos', '${videos.length} · ${fmtBytes(bytes(videos))}', () => openFilter('video')),
            tile(Icons.folder_special_outlined, const Color(0xFFEDE9FE), const Color(0xFF7C3AED), 'Project Files', '${projects.length} · ${fmtBytes(bytes(projects))}', () => openFilter('doc')),
            tile(Icons.photo_outlined, const Color(0xFFECFDF5), const Color(0xFF059669), 'Photos', '${photos.length} · ${fmtBytes(bytes(photos))}', () => openFilter('image')),
          ],
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- activity
  Widget _activityCard(BuildContext context, List<Entry> all) {
    final latest = all.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFDF0B8), Color(0xFFFBE38A)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Recent Activity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Color(0xFF5C4A0A))),
        const SizedBox(height: 2),
        Text('Latest uploads in your cloud show up here.', style: TextStyle(fontSize: 11.5, color: Colors.brown.withValues(alpha: 0.65))),
        const SizedBox(height: 8),
        if (latest.isEmpty)
          Text('Nothing yet — upload your first file.', style: TextStyle(fontSize: 12, color: Colors.brown.withValues(alpha: 0.7)))
        else
          ...latest.map((e) {
            final m = metaFor(e.mime, e.name);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                IconTile(icon: m.icon, bg: m.bg, fg: m.fg, size: 30),
                const SizedBox(width: 8),
                Expanded(child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF4A3B08)))),
                Text(fmtBytes(e.size), style: const TextStyle(fontSize: 11, color: Color(0xFF7A661C))),
              ]),
            );
          }),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFF3B2F63), borderRadius: BorderRadius.circular(99)),
              child: const Text('See All', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- actions
  Widget _quickActions(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        _chip(context, Icons.add_circle_outline, 'Upload', () => showSheet(context, const UploadSheet())),
        _chip(context, Icons.tv_outlined, 'Channels', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChannelsPage()))),
        _chip(context, Icons.folder_outlined, 'Folders', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FoldersPage()))),
        _chip(context, Icons.delete_outline, 'Trash', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrashPage()))),
        _chip(context, Icons.history, 'History', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()))),
        _chip(context, Icons.table_chart_outlined, 'Pips DB', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DbPage()))),
        _chip(context, Icons.forum_outlined, 'Messages', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InboxPage()))),
        _chip(context, Icons.person_search_outlined, 'Find people', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserSearchPage()))),
      ]);

  Widget _chip(BuildContext context, IconData icon, String label, VoidCallback onTap) => ActionChip(
        avatar: Icon(icon, size: 18, color: AppTheme.blue),
        label: Text(label),
        onPressed: onTap,
      );
}
