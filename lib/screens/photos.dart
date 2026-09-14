import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';
import 'viewer.dart';

/// Photos — Album & Timeline views over every image in the account.
class PhotosPage extends StatefulWidget {
  const PhotosPage({super.key});
  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> {
  bool albumMode = true;
  Key refresh = UniqueKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photos'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() => refresh = UniqueKey()))],
      ),
      body: Column(children: [
        const SizedBox(height: 8),
        _segmented(),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<List<dynamic>>(
            key: refresh,
            future: PipsApi.filesAll(),
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
              final all = (s.data ?? []).map((e) => Entry(Map<String, dynamic>.from(e as Map))).where((e) => isImage(e.mime, e.name) && !e.isDb).toList()
                ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
              if (all.isEmpty) return const EmptyState(icon: '🖼️', text: 'No photos yet.\nUpload some with the + button.');
              return albumMode ? _albums(context, all) : _timeline(context, all);
            },
          ),
        ),
      ]),
    );
  }

  Widget _segmented() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: HomeColors.of(context).surfaceSoft, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          _seg('Album', Icons.grid_view_rounded, albumMode, () => setState(() => albumMode = true)),
          const SizedBox(width: 4),
          _seg('Timeline', Icons.timeline, !albumMode, () => setState(() => albumMode = false)),
        ]),
      );

  Widget _seg(String label, IconData icon, bool active, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))] : null,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 17, color: active ? AppTheme.blue : Colors.grey),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: active ? AppTheme.blue : Colors.grey)),
            ]),
          ),
        ),
      );

  // ------------------------------------------------------------- albums
  Map<String, List<Entry>> _group(List<Entry> images) {
    final map = <String, List<Entry>>{};
    for (final e in images) {
      final key = e.folder.isEmpty ? 'Unsorted' : e.folder;
      map.putIfAbsent(key, () => []).add(e);
    }
    return map;
  }

  Widget _albums(BuildContext context, List<Entry> images) {
    final groups = _group(images);
    final names = groups.keys.toList()..sort();
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.92),
      itemCount: names.length,
      itemBuilder: (_, i) {
        final name = names[i];
        final items = groups[name]!;
        return _AlbumCard(name: name, items: items);
      },
    );
  }

  // ------------------------------------------------------------- timeline
  Widget _timeline(BuildContext context, List<Entry> images) => GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
        itemCount: images.length,
        itemBuilder: (_, i) => _Thumb(e: images[i], gallery: images, rounded: false),
      );
}

class _AlbumCard extends StatelessWidget {
  final String name;
  final List<Entry> items;
  const _AlbumCard({required this.name, required this.items});

  static const List<List<Color>> _covers = [
    [Color(0xFF93C5FD), Color(0xFF2563EB)],
    [Color(0xFFFCA5A5), Color(0xFFDC2626)],
    [Color(0xFF6EE7B7), Color(0xFF059669)],
    [Color(0xFFFCD34D), Color(0xFFD97706)],
    [Color(0xFFC4B5FD), Color(0xFF7C3AED)],
    [Color(0xFFF9A8D4), Color(0xFFDB2777)],
  ];

  @override
  Widget build(BuildContext context) {
    final hash = name.hashCode.abs();
    final cover = _covers[hash % _covers.length];
    final newest = items.first.uploadedAt;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumDetailPage(album: name, items: items))),
      child: Container(
        decoration: BoxDecoration(color: HomeColors.of(context).surfaceSoft, borderRadius: BorderRadius.circular(18), border: Border.all(color: HomeColors.of(context).line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: cover)),
                      child: const Icon(Icons.photo_library_rounded, color: Colors.white70, size: 42),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(99)),
                        child: Text('${items.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Text('${items.length} photos · ${fmtDate(newest)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AlbumDetailPage extends StatelessWidget {
  final String album;
  final List<Entry> items;
  const AlbumDetailPage({super.key, required this.album, required this.items});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('$album (${items.length})')),
        body: GridView.builder(
          padding: const EdgeInsets.all(4),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
          itemCount: items.length,
          itemBuilder: (_, i) => _Thumb(e: items[i], gallery: items, rounded: false),
        ),
      );
}

/// Network thumbnail that sends the session cookie (private files need it).
class _Thumb extends StatelessWidget {
  final Entry e;
  final List<Entry> gallery;
  final bool rounded;
  const _Thumb({required this.e, required this.gallery, this.rounded = true});

  @override
  Widget build(BuildContext context) {
    final headers = <String, String>{};
    final sess = PipsApi.session;
    if (sess != null && sess.isNotEmpty) headers['Cookie'] = 'pips_session=$sess';
    final img = Image.network(
      PipsApi.viewUrl(e.id),
      headers: headers,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, prog) => prog == null
          ? child
          : Container(color: const Color(0xFFE8EEF6), child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))),
      errorBuilder: (_, __, ___) => Container(color: const Color(0xFFECFDF5), child: const Icon(Icons.image_rounded, color: Color(0xFF059669))),
    );
    final tile = rounded ? ClipRRect(borderRadius: BorderRadius.circular(12), child: img) : img;
    return GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ViewerPage(e: e, gallery: gallery))), child: tile);
  }
}
