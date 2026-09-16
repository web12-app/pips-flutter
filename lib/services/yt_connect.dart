import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../api.dart';

/// A cookies.txt the user EXPLICITLY picked. The content is only read when
/// it is about to be uploaded — never rendered, never logged.
class PickedCookieFile {
  final String name;
  final int size;
  final Future<String> read;
  PickedCookieFile(this.name, this.size, this.read);
}

/// Consent-first YouTube cookies:
///
/// The user picks a cookies.txt file themselves, Pips validates and stores
/// it (private owner file, encrypted at rest), and the background import
/// worker uses it — through a short-lived signed URL — to get past
/// YouTube's bot check.
///
/// This app never reads the phone's browser cookie jar or the YouTube app's
/// private cookie database. The explicitly picked file is the only cookie
/// source. (An earlier version harvested the in-app webview cookie jar;
/// that path was removed on purpose.)
class YtConnect {
  /// Has the owner already connected cookies?
  static Future<bool> connected() async {
    try {
      final d = await PipsApi.ytCookiesStatus();
      return d['connected'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Open the platform file picker for a cookies.txt.
  /// Returns null when the user cancels.
  static Future<PickedCookieFile?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select your cookies.txt',
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    final f = result?.files?.first;
    if (f == null) return null;
    final size = (f.size is int) ? f.size as int : 0;
    if (f.path != null) {
      final path = f.path!;
      return PickedCookieFile(f.name, size, () => File(path).readAsString());
    }
    // web: no path — the bytes were returned directly
    final bytes = f.bytes;
    if (bytes == null) return null;
    return PickedCookieFile(f.name, size, () async => utf8.decode(bytes));
  }

  /// Validate lightly + save to the server. Throws with a user message.
  static Future<void> save(String text, {required bool oneTime}) async {
    if (text.length < 100) {
      throw 'That file looks too small to be a cookies.txt.';
    }
    final lines = text.split('\n');
    final real = lines.where((l) => l.trim().isNotEmpty && !l.startsWith('#')).toList();
    if (real.isEmpty || !real.any((l) => l.split('\t').length >= 7)) {
      throw 'That does not look like a Netscape cookies.txt file.';
    }
    await PipsApi.saveYtCookies(text, oneTime: oneTime);
  }
}
