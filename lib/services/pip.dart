import 'package:flutter/services.dart';

/// Android Picture-in-Picture bridge.
///
/// When the app goes to the background while a video is playing, the watch
/// page calls [enter] so Android keeps the activity alive in a small floating
/// window — the video keeps playing over any other app.
///
/// On devices below Android 8.0 (API 26) PiP is unavailable and every call
/// simply resolves to false / no-op, so callers need no version checks.
class PipsPip {
  static const MethodChannel _ch = MethodChannel('pips/pip');

  static Future<bool> enter() async {
    try {
      final ok = await _ch.invokeMethod<bool>('enter');
      return ok ?? false;
    } catch (_) {
      // Unavailable (API < 26), OEM skin rejected it, or channel not wired —
      // fall back silently: audio keeps playing via the in-app mini player.
      return false;
    }
  }

  static Future<void> exit() async {
    try {
      await _ch.invokeMethod('exit');
    } catch (_) {
      /* best effort */
    }
  }
}
