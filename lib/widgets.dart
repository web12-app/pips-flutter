import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'api.dart';
import 'models.dart';

class AppTheme {
  static const blue = Color(0xFF0B6EF0);
  static const sky = Color(0xFF38BDF8);
  static const purple = Color(0xFF8B5CF6);
  static const orange = Color(0xFFF59E0B);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
  static const teal = Color(0xFF14B8A6);

  // Clear base palette (light)
  static const bg = Color(0xFFF5F7FB);
  static const ink = Color(0xFF101828);
  static const inkSoft = Color(0xFF667085);
  static const line = Color(0xFFE9EDF3);
  static const blueSoft = Color(0xFFE8F1FE);
}

/// Adaptive home colors — one clear look in both light and dark mode.
class HomeColors {
  final Color surface;
  final Color surfaceSoft;
  final Color text1;
  final Color text2;
  final Color line;
  final Color tabBg;
  const HomeColors({
    required this.surface,
    required this.surfaceSoft,
    required this.text1,
    required this.text2,
    required this.line,
    required this.tabBg,
  });

  static HomeColors of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const HomeColors(
            surface: Color(0xFF1C1C1E),
            surfaceSoft: Color(0xFF2C2C2E),
            text1: Color(0xFFF2F2F7),
            text2: Color(0xFF98989E),
            line: Color(0xFF38383A),
            tabBg: Color(0xFF2C2C2E),
          )
        : const HomeColors(
            surface: Color(0xFFFFFFFF),
            surfaceSoft: Color(0xFFF2F4F7),
            text1: Color(0xFF101828),
            text2: Color(0xFF667085),
            line: Color(0xFFE9EDF3),
            tabBg: Color(0xFFF2F4F7),
          );
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    duration: const Duration(seconds: 2),
  ));
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    final hc = HomeColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.2, color: hc.text1)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Frosted-glass style card — translucent gradient surface, hairline border,
/// soft shadow. Fully adaptive: light gradient in light mode, dark in dark mode.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final double radius;
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap, this.radius = 18});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hc = HomeColors.of(context);
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: hc.line),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (dark ? const Color(0xFF2C2C2E) : Colors.white).withValues(alpha: 0.92),
            (dark ? const Color(0xFF1C1C1E) : const Color(0xFFF7FAFF)).withValues(alpha: 0.78),
          ],
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.35 : 0.06), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}

class IconTile extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color fg;
  final double size;
  const IconTile({super.key, required this.icon, required this.bg, required this.fg, this.size = 42});
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.28)),
        child: Icon(icon, color: fg, size: size * 0.5),
      );
}

class ProgressBar extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final double height;
  const ProgressBar({super.key, required this.value, this.color = AppTheme.blue, this.height = 7});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: height,
          backgroundColor: const Color(0xFFDBEAFE),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      );
}

Future<T?> showSheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: child,
      ),
    );

class SheetTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  const SheetTile({super.key, required this.icon, required this.color, required this.label, required this.onTap, this.trailing});
  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: IconTile(icon: icon, bg: color.withValues(alpha: 0.14), fg: color, size: 36),
        title: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
        trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      );
}

class EmptyState extends StatelessWidget {
  final String icon, text;
  const EmptyState({super.key, required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(40),
        child: Column(children: [
          Text(icon, style: const TextStyle(fontSize: 44)),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.5)),
        ]),
      );
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
}

// ------------------------------------------------- skeleton shimmer loading
/// Lightweight shimmer sweep (no dependencies) — wrap a placeholder shape.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});
  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF1C1C1E) : const Color(0xFFF1F3F7);
    final hi = dark ? const Color(0xFF303034) : const Color(0xFFFFFFFF);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        final b = Alignment(-1.8 + 2.6 * t, -0.3);
        final e = Alignment(b.x + 1.2, b.y + 0.6);
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => LinearGradient(
            begin: b,
            end: e,
            colors: [base, hi, base],
          ).createShader(r),
          child: widget.child,
        );
      },
    );
  }
}

/// Skeleton rows that mimic the file list — use while cloud data loads.
class SkeletonList extends StatelessWidget {
  final int rows;
  final double rowHeight;
  const SkeletonList({super.key, this.rows = 6, this.rowHeight = 66});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Shimmer(
                child: Container(
                  height: rowHeight,
                  decoration: const BoxDecoration(borderRadius: BorderRadius.all(Radius.circular(14))),
                ),
              ),
            ),
        ],
      );
}

/// Skeleton for a big card (feed, explorer…).
class SkeletonCard extends StatelessWidget {
  final double height;
  const SkeletonCard({super.key, this.height = 220});
  @override
  Widget build(BuildContext context) => SkeletonBox(height: height, radius: 18);
}

/// Theme-aware shimmer box.
class SkeletonBox extends StatelessWidget {
  final double? height;
  final double? width;
  final double radius;
  const SkeletonBox({super.key, this.height, this.width, this.radius = 12});
  @override
  Widget build(BuildContext context) {
    final hc = HomeColors.of(context);
    return Shimmer(
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(color: hc.surfaceSoft, borderRadius: BorderRadius.circular(radius)),
      ),
    );
  }
}

/// Full-area skeleton placeholder for loading lists (any screen).
class SkeletonScreen extends StatelessWidget {
  final int rows;
  const SkeletonScreen({super.key, this.rows = 6});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: SkeletonList(rows: rows),
      );
}

final _fileImgCache = <String, List<int>>{};

/// Fetch (and cache) a small cloud file as image bytes — used for channel logos.
Future<Uint8List?> loadFileImage(String? id) async {
  if (id == null || id.isEmpty) return null;
  final hit = _fileImgCache[id];
  if (hit != null) return Uint8List.fromList(hit);
  try {
    final b = await PipsApi.getBytes(PipsApi.viewUrl(id));
    if (_fileImgCache.length > 300) _fileImgCache.remove(_fileImgCache.keys.first);
    _fileImgCache[id] = b;
    return Uint8List.fromList(b);
  } catch (_) {
    return null;
  }
}

// ------------------------------------------------- profile photo (avatar)
final _avatarUrlCache = <String, String>{};
final _avatarBytesCache = <String, List<int>>{};

Future<Uint8List?> _loadAvatarBytes(String url) async {
  final hit = _avatarBytesCache[url];
  if (hit != null) return Uint8List.fromList(hit);
  try {
    final full = url.startsWith('http') ? url : '${PipsApi.base}$url';
    final b = await PipsApi.getBytes(full).timeout(const Duration(seconds: 20));
    if (b.isEmpty) return null;
    if (_avatarBytesCache.length > 40) _avatarBytesCache.clear();
    _avatarBytesCache[url] = b;
    return Uint8List.fromList(b);
  } catch (_) {
    return null;
  }
}

const _avatarColors = [
  Color(0xFF0B6EF0), Color(0xFF8B5CF6), Color(0xFFF59E0B),
  Color(0xFF16A34A), Color(0xFFDC2626), Color(0xFF14B8A6), Color(0xFFDB2777),
];

/// Round profile photo for a user — cloud photo with a coloured letter fallback.
class AvatarTile extends StatelessWidget {
  final String username;
  final double radius;
  final String? name;
  const AvatarTile({super.key, required this.username, this.radius = 20, this.name});
  @override
  Widget build(BuildContext context) {
    final u = username.isEmpty ? '?' : username;
    Color bg() {
      var h = 0;
      for (final r in u.runes) h = (h * 31 + r) & 0x7fffffff;
      return _avatarColors[h % _avatarColors.length];
    }

    Widget fallback([String? who]) => CircleAvatar(
          radius: radius,
          backgroundColor: bg(),
          child: Text((who ?? (name ?? u)).isNotEmpty ? (who ?? (name ?? u))[0].toUpperCase() : '?',
              style: TextStyle(color: Colors.white, fontSize: radius * 0.85, fontWeight: FontWeight.w700)),
        );

    final keyUrl = _avatarUrlCache[u];
    return FutureBuilder<Uint8List?>(
      future: (keyUrl != null
          ? _loadAvatarBytes(keyUrl)
          : PipsApi.avatarUrl(u).then((url) {
              if (url == null) return null;
              _avatarUrlCache[u] = url;
              return _loadAvatarBytes(url);
            })),
      builder: (_, s) {
        final img = s.data;
        if (img != null && img.isNotEmpty) {
          return CircleAvatar(radius: radius, backgroundColor: bg(), foregroundImage: MemoryImage(img));
        }
        return fallback();
      },
    );
  }

  /// Drop the cached photo for a user (call after updating the profile photo).
  static void invalidate(String username) {
    _avatarUrlCache.remove(username);
    _avatarBytesCache.clear();
  }
}

/// Yes/No confirm shown before ANY destructive action in the app.
/// Resolves true only when the user taps "Yes, …".
Future<bool> confirmDelete(
  BuildContext context, {
  String title = 'Delete?',
  String message = 'This cannot be undone.',
  String confirmLabel = 'Yes, delete',
  String cancelLabel = 'No, keep it',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.delete_outline, color: AppTheme.red),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(message, style: const TextStyle(fontSize: 13.5, height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancelLabel, style: const TextStyle(fontWeight: FontWeight.w600))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Round channel logo — cloud poster image with a letter fallback.
class ChannelAvatar extends StatelessWidget {
  final String? fileId;
  final String name;
  final double radius;
  const ChannelAvatar({super.key, this.fileId, required this.name, this.radius = 20});
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: loadFileImage(fileId),
        builder: (_, s) {
          final img = s.data;
          if (img != null) {
            return CircleAvatar(radius: radius, backgroundColor: AppTheme.purple, foregroundImage: MemoryImage(img));
          }
          return CircleAvatar(
            radius: radius,
            backgroundColor: AppTheme.purple,
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(color: Colors.white, fontSize: radius * 0.85, fontWeight: FontWeight.w700)),
          );
        },
      );
}

/// "13:02" / "1:02:45" — video duration label (YouTube badge style).
/// Returns '' when the duration is unknown.
String fmtDurationMs(int ms) {
  if (ms <= 0) return '';
  final d = Duration(milliseconds: ms);
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// 938 → "938", 1700 → "1.7K", 93000 → "93K", 1200000 → "1.2M" — YouTube
/// style compact counters for views / likes / subscribers.
String fmtCompact(int n) {
  if (n >= 1000000) {
    final v = n / 1000000;
    return '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)}M';
  }
  if (n >= 1000) {
    final v = n / 1000;
    return '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)}K';
  }
  return '$n';
}

// ------------------------------------------------- first-frame posters
/// Videos added WITHOUT a poster (e.g. URL imports) get their FIRST FRAME
/// pulled from the public view URL as an automatic poster. Results are
/// cached for the whole session; extraction is capped at 2 concurrent jobs
/// so a long feed never saturates the network.

final Map<String, Uint8List?> _frameCache = {}; // videoId -> frame bytes (null = tried & failed)
final Map<String, Future<Uint8List?>> _frameJobs = {}; // in-flight dedup
final List<String> _frameWait = []; // FIFO waiting queue
int _frameActive = 0;
const int _kMaxFrameExtracts = 2;

Future<Uint8List?> _firstFrame(String videoId) {
  if (_frameCache.containsKey(videoId)) return Future.value(_frameCache[videoId]);
  final running = _frameJobs[videoId];
  if (running != null) return running;
  final c = Completer<Uint8List?>();
  _frameJobs[videoId] = c.future;
  _frameWait.add(videoId);
  _pumpFrames();
  return c.future;
}

void _pumpFrames() {
  while (_frameActive < _kMaxFrameExtracts && _frameWait.isNotEmpty) {
    final id = _frameWait.removeAt(0);
    final c = _frameJobs[id];
    if (c == null) continue;
    _frameActive++;
    () async {
      Uint8List? bytes;
      try {
        bytes = await VideoThumbnail.thumbnailData(
          video: PipsApi.viewUrl(id),
          imageFormat: ImageFormat.JPEG,
          maxWidth: 640,
          quality: 78,
        );
      } catch (_) {
        bytes = null;
      }
      _frameCache[id] = bytes;
      _frameJobs.remove(id);
      _frameActive--;
      if (!c.isCompleted) c.complete(bytes);
      _pumpFrames();
    }();
  }
}

/// YouTube-style video thumbnail: cloud thumbnail image with a dark
/// placeholder fallback, plus a duration badge (bottom-right) when known.
/// When [videoId] is given and no thumb was set, the video's FIRST FRAME is
/// extracted (cached) and shown as an automatic poster.
/// Parent must give it a fixed size (AspectRatio / SizedBox).
class VideoThumb extends StatelessWidget {
  final String? thumbId;
  final String? videoId;
  final int durationMs;

  /// Shown in the badge when no duration is known (e.g. non-video files).
  final int? fallbackBytes;
  final double radius;
  const VideoThumb({super.key, this.thumbId, this.videoId, this.durationMs = 0, this.fallbackBytes, this.radius = 12});

  String? get _badge {
    if (durationMs > 0) return fmtDurationMs(durationMs);
    if (fallbackBytes != null && fallbackBytes! > 0) return fmtBytes(fallbackBytes!);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hasThumb = thumbId != null && thumbId!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(fit: StackFit.expand, children: [
        Container(color: const Color(0xFF16181D)),
        if (hasThumb)
          FutureBuilder<Uint8List?>(
            future: loadFileImage(thumbId),
            builder: (_, s) {
              final img = s.data;
              if (img != null) return Image.memory(img, fit: BoxFit.cover, gaplessPlayback: true);
              return const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white38, size: 42));
            },
          )
        else if (videoId != null && videoId!.isNotEmpty)
          FutureBuilder<Uint8List?>(
            future: _firstFrame(videoId!),
            builder: (_, s) {
              final img = s.data;
              if (img != null && img.isNotEmpty) {
                return Image.memory(img, fit: BoxFit.cover, gaplessPlayback: true);
              }
              return const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white38, size: 42));
            },
          )
        else
          const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white38, size: 42)),
        if (_badge != null)
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.78), borderRadius: BorderRadius.circular(5)),
              child: Text(_badge!, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
            ),
          ),
      ]),
    );
  }
}
