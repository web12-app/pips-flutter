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
          if (s.connectionState != ConnectionState.done) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: const [
                SizedBox(height: 46),
                SizedBox(height: 14),
                SkeletonBox(height: 46, radius: 14),
                SizedBox(height: 14),
                SkeletonBox(height: 42, radius: 13),
                SizedBox(height: 18),
                SkeletonCard(height: 240),
                SizedBox(height: 12),
                SkeletonCard(height: 220),
              ],
            );
          }
          final account = (s.data?[0] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final all = ((s.data?[1] as List<dynamic>?) ?? const [])
              .map((e) => Entry(Map<String, dynamic>.from(e as Map)))
              .toList()
            ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
          final hc = HomeColors.of(context);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _header(account),
              const SizedBox(height: 14),
              _searchBar(context),
              const SizedBox(height: 14),
              _quickTabs(context),
              const SizedBox(height: 18),
              _videoFeed(),
              Text('Save with Pips', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: hc.text1)),
              const SizedBox(height: 12),
              _recentCard(context, all),
              const SizedBox(height: 12),
              _activityCard(context, all),
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
    final hc = HomeColors.of(context);
    return Row(children: [
      Container(
        width: 46,
        height: 46,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(color: hc.surface, shape: BoxShape.circle, border: Border.all(color: hc.line), boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3)),
        ]),
        child: Image.asset('assets/logo.png', fit: BoxFit.contain),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hi, $user 👋', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: hc.text1)),
          Text('Storage used ${(pct * 100).toStringAsFixed(1)}% · ${fmtBytes(used.toInt())}', style: TextStyle(fontSize: 12, color: hc.text2)),
        ]),
      ),
      IconButton(
        tooltip: 'Notifications',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
        icon: Icon(Icons.notifications_outlined, size: 25, color: hc.text1),
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
                child: Text('Discover', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: HomeColors.of(context).text2)),
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
          // 16:9 thumbnail area (mock3) — real thumbnail + duration badge
          AspectRatio(
            aspectRatio: 16 / 9,
            child: VideoThumb(thumbId: it.thumbId, videoId: it.e.id, durationMs: it.durationMs, fallbackBytes: it.e.size, radius: 14),
          ),
          const SizedBox(height: 9),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ChannelAvatar(fileId: it.channelLogoId, name: it.channelName, radius: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.25)),
                const SizedBox(height: 3),
                Text('${it.channelName.isNotEmpty ? it.channelName : '@${it.channelOwner}'} · ${fmtCompact(it.views)} views${it.addedAt.isNotEmpty ? ' · ${fmtDate(it.addedAt)}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: HomeColors.of(context).text2)),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- search
  Widget _searchBar(BuildContext context) {
    final hc = HomeColors.of(context);
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(color: hc.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: hc.line)),
        child: Row(children: [
          Icon(Icons.search_rounded, color: hc.text2, size: 20),
          const SizedBox(width: 9),
          Expanded(child: Text('Search files', style: TextStyle(color: hc.text2, fontSize: 14))),
          Icon(Icons.tune_rounded, color: hc.text2, size: 19),
        ]),
      ),
    );
  }

  // ------------------------------------------------- recent files & folders
  Widget _recentCard(BuildContext context, List<Entry> all) {
    final videos = all.where((e) => isVideo(e.mime, e.name)).toList();
    final photos = all.where((e) => isImage(e.mime, e.name) && !e.isDb).toList();
    final projects = all.where((e) => !isVideo(e.mime, e.name) && !isImage(e.mime, e.name)).toList();
    int bytes(List<Entry> l) => l.fold(0, (a, e) => a + e.size);

    final hc = HomeColors.of(context);
    Widget tile(IconData icon, Color bg, Color fg, String title, String sub, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: hc.surfaceSoft, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              IconTile(icon: icon, bg: bg, fg: fg, size: 36),
              const SizedBox(height: 8),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: hc.text1)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: hc.text2)),
            ]),
          ),
        );

    void openFilter(String f) => Navigator.push(context, MaterialPageRoute(builder: (_) => FilesPage(initialFilter: f)));

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Recent Files & Folders', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: hc.text1)),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FilesPage())),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(children: [
                const Text('See All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.blue)),
                Icon(Icons.chevron_right_rounded, size: 17, color: AppTheme.blue.withValues(alpha: 0.8)),
              ]),
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
    final hc = HomeColors.of(context);
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Recent Activity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: hc.text1)),
        const SizedBox(height: 2),
        Text('Latest uploads in your cloud show up here.', style: TextStyle(fontSize: 11.5, color: hc.text2)),
        const SizedBox(height: 8),
        if (latest.isEmpty)
          Text('Nothing yet — upload your first file.', style: TextStyle(fontSize: 12, color: hc.text2))
        else
          ...latest.map((e) {
            final m = metaFor(e.mime, e.name);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                IconTile(icon: m.icon, bg: m.bg, fg: m.fg, size: 30),
                const SizedBox(width: 8),
                Expanded(child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: hc.text1))),
                Text(fmtBytes(e.size), style: TextStyle(fontSize: 11, color: hc.text2)),
              ]),
            );
          }),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage())),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(children: [
                const Text('See All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.blue)),
                Icon(Icons.chevron_right_rounded, size: 17, color: AppTheme.blue.withValues(alpha: 0.8)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // --------------------------------------------- quick links — top tab bar
  /// The quick links live in a top tab bar under the search: a compact,
  /// horizontal-scroll row of tabs. Upload is the primary (filled) tab.
  Widget _quickTabs(BuildContext context) => SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.hardEdge,
          padding: EdgeInsets.zero,
          physics: const BouncingScrollPhysics(),
          children: [
            _tab(context, Icons.add_circle_rounded, 'Upload', primary: true, onTap: () => showSheet(context, const UploadSheet())),
            _tab(context, Icons.tv_rounded, 'Channels', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChannelsPage()))),
            _tab(context, Icons.folder_rounded, 'Folders', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FoldersPage()))),
            _tab(context, Icons.explore_rounded, 'Explorer', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CloudExplorerPage()))),
            _tab(context, Icons.delete_rounded, 'Trash', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrashPage()))),
            _tab(context, Icons.history_rounded, 'History', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()))),
            _tab(context, Icons.table_chart_rounded, 'Pips DB', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DbPage()))),
            _tab(context, Icons.forum_rounded, 'Messages', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InboxPage()))),
            _tab(context, Icons.person_search_rounded, 'Find people', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserSearchPage()))),
          ],
        ),
      );

  Widget _tab(BuildContext context, IconData icon, String label, {bool primary = false, required VoidCallback onTap}) {
    final hc = HomeColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: primary ? AppTheme.blue : hc.tabBg,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16.5, color: primary ? Colors.white : AppTheme.blue),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primary ? Colors.white : hc.text1)),
            ]),
          ),
        ),
      ),
    );
  }
}
