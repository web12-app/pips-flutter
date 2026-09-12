import 'package:flutter/material.dart';

String uid() => '${DateTime.now().millisecondsSinceEpoch}${1000 + (DateTime.now().microsecond % 9000)}';

String fmtBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

String fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

String timeAgo(DateTime t) {
  final s = DateTime.now().difference(t).inSeconds;
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60}m ago';
  if (s < 86400) return '${s ~/ 3600}h ago';
  return '${s ~/ 86400}d ago';
}

class CloudType {
  static const folder = 'folder';
  static const pdf = 'pdf';
  static const zip = 'zip';
  static const doc = 'doc';
  static const audio = 'audio';
  static const video = 'video';
  static const image = 'image';
  static const design = 'design';
  static const other = 'other';
}

bool isImage(String mime, String name) => mime.startsWith('image/') || ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic'].any(name.toLowerCase().endsWith);
bool isVideo(String mime, String name) => mime.startsWith('video/') || ['.mp4', '.mkv', '.webm', '.mov', '.avi'].any(name.toLowerCase().endsWith);
bool isAudio(String mime, String name) => mime.startsWith('audio/') || ['.mp3', '.wav', '.ogg', '.m4a', '.flac'].any(name.toLowerCase().endsWith);
bool isTexty(String mime, String name) =>
    mime.startsWith('text/') || mime.contains('json') || mime.contains('javascript') ||
    ['.txt', '.md', '.json', '.csv', '.log', '.xml', '.html', '.js', '.py', '.dart', '.java', '.kt', '.c', '.cpp', '.sh', '.yaml', '.yml'].any(name.toLowerCase().endsWith);

String typeOf(String mime, String name) {
  if (isImage(mime, name)) return CloudType.image;
  if (isVideo(mime, name)) return CloudType.video;
  if (isAudio(mime, name)) return CloudType.audio;
  if (mime == 'application/pdf' || name.toLowerCase().endsWith('.pdf')) return CloudType.pdf;
  if (name.toLowerCase().endsWith('.zip') || name.toLowerCase().endsWith('.rar') || name.toLowerCase().endsWith('.7z')) return CloudType.zip;
  if (['.doc', '.docx', '.txt', '.md', '.rtf'].any(name.toLowerCase().endsWith)) return CloudType.doc;
  if (name.toLowerCase().endsWith('.fig') || name.toLowerCase().endsWith('.sketch') || name.toLowerCase().endsWith('.psd')) return CloudType.design;
  return CloudType.other;
}

class TypeMeta {
  final IconData icon;
  final Color bg;
  final Color fg;
  const TypeMeta(this.icon, this.bg, this.fg);
}

TypeMeta metaFor(String mime, String name) {
  switch (typeOf(mime, name)) {
    case CloudType.image: return const TypeMeta(Icons.image_rounded, Color(0xFFECFDF5), Color(0xFF059669));
    case CloudType.video: return const TypeMeta(Icons.video_file_rounded, Color(0xFFFCE7F3), Color(0xFFDB2777));
    case CloudType.audio: return const TypeMeta(Icons.audio_file_rounded, Color(0xFFD1FAE5), Color(0xFF059669));
    case CloudType.pdf: return const TypeMeta(Icons.picture_as_pdf_rounded, Color(0xFFFEE2E2), Color(0xFFDC2626));
    case CloudType.zip: return const TypeMeta(Icons.folder_zip_rounded, Color(0xFFE0E7FF), Color(0xFF4F46E5));
    case CloudType.doc: return const TypeMeta(Icons.description_rounded, Color(0xFFDBEAFE), Color(0xFF2563EB));
    case CloudType.design: return const TypeMeta(Icons.palette_rounded, Color(0xFFF5F3FF), Color(0xFF7C3AED));
    default: return const TypeMeta(Icons.insert_drive_file_rounded, Color(0xFFF1F5F9), Color(0xFF64748B));
  }
}

TypeMeta folderMeta() => const TypeMeta(Icons.folder_rounded, Color(0xFFFEF3C7), Color(0xFFD97706));

/// a file/folder entry from the pips API
class Entry {
  final Map<String, dynamic> raw;
  Entry(this.raw);
  String get id => (raw['id'] ?? '').toString();
  String get name => (raw['name'] ?? 'file').toString();
  String get mime => (raw['mime'] ?? '').toString();
  int get size => raw['size'] is num ? (raw['size'] as num).toInt() : 0;
  String get visibility => (raw['visibility'] ?? 'public').toString();
  String get folder => (raw['folder'] ?? '').toString();
  String get uploadedAt => (raw['uploaded_at'] ?? '').toString();
  bool get isDb => id.startsWith('db-');
  int get version => raw['version'] is num ? (raw['version'] as num).toInt() : 1;
}
