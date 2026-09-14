import 'dart:io';
import 'package:flutter/services.dart';
import '../api.dart';

/// Collects YouTube/Google cookies from the phone's webview cookie jar and
/// saves them to the Pips server (private owner file). The background import
/// worker then uses them (via a short-lived signed URL) to get past
/// YouTube's bot check — so YouTube video imports work from the server.
class YtConnect {
  static const MethodChannel _ch = MethodChannel('pips/youtube');

  static bool get supported => Platform.isAndroid;

  /// Has the owner already connected cookies?
  static Future<bool> connected() async {
    try {
      final d = await PipsApi.ytCookiesStatus();
      return d['connected'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Reads the shared cookie jar and returns a Netscape cookies.txt body
  /// covering youtube.com + google.com domains.
  static Future<String> collectNetscape() async {
    final domains = <String, String>{
      'https://www.youtube.com': '.youtube.com',
      'https://www.google.com': '.google.com',
    };
    final lines = <String>[
      '# Netscape HTTP Cookie File',
      '# Collected by Pips app on ${DateTime.now().toUtc()}',
    ];
    final exp = DateTime.now().add(const Duration(days: 365 * 2)).millisecondsSinceEpoch ~/ 1000;
    var count = 0;
    for (final e in domains.entries) {
      String header = '';
      try {
        header = (await _ch.invokeMethod<String>('cookieHeader', {'url': e.key})) ?? '';
      } catch (_) {
        header = '';
      }
      for (final part in header.split(';')) {
        final t = part.trim();
        final i = t.indexOf('=');
        if (i <= 0) continue;
        final k = t.substring(0, i);
        final v = t.substring(i + 1);
        if (k.isEmpty) continue;
        lines.add('${e.value}\tTRUE\t/\tTRUE\t$exp\t$k\t$v');
        count++;
      }
    }
    if (count == 0) throw 'No cookies found — open YouTube in the page (and sign in if asked), then try again.';
    return lines.join('\n') + '\n';
  }

  /// Collect from the jar and save to the server. Throws with a user message on failure.
  static Future<int> save() async {
    if (!supported) throw 'Cookie collection works on Android.';
    final text = await collectNetscape();
    await PipsApi.saveYtCookies(text);
    return text.length;
  }
}
