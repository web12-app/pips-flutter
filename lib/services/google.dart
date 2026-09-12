import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';

/// Google sign-in via Firebase, bridged to a Pips account.
///
/// The Pips backend is username/password based (signup requires an emailed
/// OTP), so after the Firebase Google sign-in succeeds we:
///  1. look for Pips credentials captured during a previous Google-driven
///     signup (stored under `gpw_<email>`) and log in silently if found;
///  2. otherwise open the signup wizard prefilled with the Google profile —
///     the one-time OTP arrives in the Gmail inbox — and capture the chosen
///     password so every later "Continue with Google" is one tap.
class GoogleAuth {
  GoogleAuth._();
  static final GoogleSignIn _gs = GoogleSignIn(scopes: ['email', 'profile']);

  static String pwKey(String email) => 'gpw_${email.toLowerCase().trim()}';

  /// Username derived from the email (backend allows [A-Za-z0-9_-]{3,32}).
  static String deriveUsername(String email) {
    var u = email.split('@').first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '-');
    while (u.startsWith('-')) {
      u = u.substring(1);
    }
    if (u.length < 3) u = 'pips-$u';
    if (u.length > 30) u = u.substring(0, 30);
    return u;
  }

  /// Runs the Google sign-in + Firebase credential exchange.
  /// Returns the verified Google email, or null when cancelled/unavailable.
  static Future<String?> signIn() async {
    final user = await _gs.signIn();
    if (user == null) return null; // user closed the chooser
    final ga = await user.authentication;
    final cred = fa.GoogleAuthProvider.credential(accessToken: ga.accessToken, idToken: ga.idToken);
    await fa.FirebaseAuth.instance.signInWithCredential(cred);
    return user.email;
  }

  /// Silent Pips login with credentials stored by a previous Google signup.
  static Future<bool> tryStoredLogin(String email) async {
    final p = await SharedPreferences.getInstance();
    final pass = p.getString(pwKey(email));
    final user = p.getString('${pwKey(email)}_user');
    if (pass == null || pass.isEmpty || user == null || user.isEmpty) return false;
    try {
      await PipsApi.login(user, pass);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Remember the Pips credentials created through a Google-driven signup.
  static Future<void> remember(String email, String username, String pass) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(pwKey(email), pass);
    await p.setString('${pwKey(email)}_user', username);
  }

  static Future<void> signOut() async {
    try {
      await _gs.signOut();
    } catch (_) {}
    try {
      await fa.FirebaseAuth.instance.signOut();
    } catch (_) {}
  }
}
