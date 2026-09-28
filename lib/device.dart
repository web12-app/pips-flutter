import 'dart:io';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device fingerprint for login security.
///
/// On first launch the app generates a random fingerprint and saves it on the
/// device (SharedPreferences). It NEVER changes across logins or account
/// switches — the same fingerprint is forwarded to every account used on this
/// device, so the backend can tell which device an account was reached from
/// and alert the user about new devices.
class Device {
  static String id = '';
  static String name = '';

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    id = p.getString('pips_device_id') ?? '';
    if (id.isEmpty) {
      final rnd = Random.secure();
      id = 'fp-' + List.generate(24, (_) => '0123456789abcdef'[rnd.nextInt(16)]).join();
      await p.setString('pips_device_id', id);
    }
    name = p.getString('pips_device_name') ?? '';
    if (name.isEmpty) {
      name = await _detectName();
      await p.setString('pips_device_name', name);
    }
  }

  static Future<String> _detectName() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        final rel = (a.version.release ?? '').isEmpty ? '' : ' (Android ${a.version.release})';
        return '${a.brand} ${a.model}$rel'.trim();
      }
      if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        return i.name.isNotEmpty ? i.name : i.model ?? 'iPhone';
      }
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final d = await plugin.deviceInfo;
        return d.data['computerName']?.toString() ?? '${Platform.operatingSystem} device';
      }
    } catch (_) {}
    return 'Pips device';
  }

  /// Headers sent with every API request so the backend can track devices.
  static Map<String, String> get headers => id.isEmpty
      ? const {}
      : {'X-Device-Id': id, 'X-Device-Name': name};
}
