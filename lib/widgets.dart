import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'api.dart';

class AppTheme {
  static const blue = Color(0xFF0B6EF0);
  static const sky = Color(0xFF38BDF8);
  static const purple = Color(0xFF8B5CF6);
  static const orange = Color(0xFFF59E0B);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
  static const teal = Color(0xFF14B8A6);
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap});
  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0F2FE)),
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
  const SheetTile({super.key, required this.icon, required this.color, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: IconTile(icon: icon, bg: color.withValues(alpha: 0.14), fg: color, size: 36),
        title: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
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

final _fileImgCache = <String, List<int>>{};

/// Fetch (and cache) a small cloud file as image bytes — used for channel logos.
Future<Uint8List?> loadFileImage(String? id) async {
  if (id == null || id.isEmpty) return null;
  final hit = _fileImgCache[id];
  if (hit != null) return Uint8List.fromList(hit);
  try {
    final b = await PipsApi.getBytes(PipsApi.viewUrl(id));
    if (_fileImgCache.length > 80) _fileImgCache.clear();
    _fileImgCache[id] = b;
    return Uint8List.fromList(b);
  } catch (_) {
    return null;
  }
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
