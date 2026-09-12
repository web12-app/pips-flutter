import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Background-process notifications for Pips.
///
/// Shows an Android status-bar notification with live progress while an
/// upload (or other background job) runs, even when the app is in the
/// background. Every method is fail-safe: it never throws into the caller,
/// so a notification problem can never break an upload.
class PipsNotify {
  PipsNotify._();
  static final PipsNotify i = PipsNotify._();

  static const String _channelId = 'pips_uploads';
  static const String _channelName = 'Uploads';

  final FlutterLocalNotificationsPlugin _p = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _asked = false;
  final Map<String, List<double>> _last = {}; // key -> [lastPct, lastMs]

  /// Initialize the plugin and create the notification channel.
  Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      await _p.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      final android = _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Background upload progress',
        importance: Importance.low,
      ));
      _ready = true;
    } catch (_) {}
  }

  /// Ask for the Android 13+ POST_NOTIFICATIONS runtime permission.
  Future<void> requestPermission() async {
    if (!_ready || _asked || kIsWeb) return;
    _asked = true;
    try {
      await _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    } catch (_) {}
  }

  int _id(String key) => key.hashCode & 0x7fffffff;

  NotificationDetails _details({required bool ongoing, bool withProgress = false, int pct = 0}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelShowBadge: false,
        importance: Importance.low,
        priority: Priority.low,
        onlyAlertOnce: true,
        ongoing: ongoing,
        showProgress: withProgress,
        maxProgress: 100,
        progress: pct,
        category: AndroidNotificationCategory.progress,
      ),
    );
  }

  /// Upload started — shows an indeterminate ongoing notification.
  Future<void> uploadStart(String key, String name) async {
    if (!_ready || kIsWeb) return;
    try {
      await _p.show(_id(key), 'Uploading to Pips', name, _details(ongoing: true));
    } catch (_) {}
  }

  /// Upload progress (0..1). Throttled: only refreshes the notification when
  /// the percentage moved by >= 4% or 2 seconds passed since the last update.
  Future<void> uploadProgress(String key, String name, double fraction) async {
    if (!_ready || kIsWeb) return;
    final pct = (fraction.clamp(0.0, 1.0) * 100).round();
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = _last[key];
    if (prev != null && pct != 100 && (pct - prev[0]) < 4 && (now - prev[1]) < 2000) return;
    _last[key] = [pct.toDouble(), now.toDouble()];
    try {
      await _p.show(_id(key), 'Uploading to Pips', '$name · $pct%', _details(ongoing: true, withProgress: true, pct: pct));
    } catch (_) {}
  }

  /// Upload finished — replaces the progress notification with a final one.
  Future<void> uploadEnd(String key, String name, {required bool ok, String message = ''}) async {
    _last.remove(key);
    if (!_ready || kIsWeb) return;
    try {
      await _p.cancel(_id(key));
      await _p.show(
        _id(key) + 1,
        ok ? 'Upload complete ✓' : 'Upload failed',
        ok ? name : '$name · $message',
        _details(ongoing: false),
      );
    } catch (_) {}
  }
}
