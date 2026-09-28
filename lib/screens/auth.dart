import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/material.dart';
import '../api.dart';
import '../device.dart';
import '../services/github.dart';
import '../services/google.dart';
import '../widgets.dart';

/// Login + signup with email/password, "Continue with Google" and
/// "Continue with GitHub" (Firebase), plus a 4-step signup wizard
/// (username -> email+method -> OTP/magic-link verify -> password).
/// "Continue as guest" creates an instant guest_<hex> cloud.
class AuthScreen extends StatefulWidget {
  final VoidCallback onAuthed;
  const AuthScreen({super.key, required this.onAuthed});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool signup = false;
  String? googleEmail; // set when an OAuth-driven (Google/GitHub) signup wizard opens
  String oauthKind = 'google'; // google | github
  final userCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool busy = false, gBusy = false, ghBusy = false, guestBusy = false;
  String? error;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() { busy = true; error = null; });
    try {
      await fn();
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } catch (_) {
      setState(() => error = 'Network error — check your connection.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void login() => _run(() async {
        final j = await PipsApi.login(userCtrl.text.trim(), passCtrl.text);
        final devName = (j['device'] is Map ? (j['device'] as Map)['name'] : null)?.toString();
        widget.onAuthed();
        _loginDeviceAlert(devName ?? Device.name);
      });

  /// Post-login alert: confirms which device this account was just opened on.
  /// The same info also arrives as an in-app notification from the backend.
  void _loginDeviceAlert(String deviceName) {
    final ctx = context;
    if (!ctx.mounted) return;
    showDialog(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('✅ Logged in'),
        content: Text('Device: $deviceName\n\nThis login was recorded. '
            'If you don\'t recognise this device, check Profile → Devices.'),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
      ),
    );
  }

  /// Firebase Google sign-in -> silent Pips login, else prefilled signup.
  Future<void> google() async {
    setState(() { gBusy = true; error = null; });
    try {
      final email = await GoogleAuth.signIn();
      if (email == null) return; // cancelled
      if (await GoogleAuth.tryStoredLogin(email)) {
        widget.onAuthed();
        return;
      }
      if (!mounted) return;
      setState(() { signup = true; googleEmail = email; oauthKind = 'google'; });
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } catch (_) {
      setState(() => error = 'Google sign-in failed. Make sure the Google provider is enabled in the Firebase console (Project pips-cloud).');
    } finally {
      if (mounted) setState(() => gBusy = false);
    }
  }

  /// Firebase GitHub sign-in (WebView bridge) -> silent Pips login, else
  /// prefilled signup.
  Future<void> github() async {
    setState(() { ghBusy = true; error = null; });
    try {
      final r = await GithubAuth.signIn(context);
      if (r == null) return; // closed the WebView
      final email = (r['email'] ?? '').trim();
      if (email.isEmpty) {
        setState(() => error = 'GitHub sign-in did not return a verified email.');
        return;
      }
      if (await GoogleAuth.tryStoredLogin(email)) {
        widget.onAuthed();
        return;
      }
      if (!mounted) return;
      setState(() { signup = true; googleEmail = email; oauthKind = 'github'; });
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } catch (e) {
      setState(() => error = 'GitHub sign-in failed. One-time setup: add pipsx.netlify.app to Firebase Authentication → Settings → Authorized domains. (${e.toString().split("(").first.trim()})');
    } finally {
      if (mounted) setState(() => ghBusy = false);
    }
  }

  /// Firebase anonymous sign-in + instant guest account.
  Future<void> guest() async {
    setState(() { guestBusy = true; error = null; });
    try {
      try { await fa.FirebaseAuth.instance.signInAnonymously(); } catch (_) {}
      await PipsApi.guest();
      if (!mounted) return;
      widget.onAuthed();
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } catch (_) {
      setState(() => error = 'Could not start a guest session — check your connection.');
    } finally {
      if (mounted) setState(() => guestBusy = false);
    }
  }

  void backFromSignup() {
    if (googleEmail != null) GoogleAuth.signOut();
    setState(() { signup = false; googleEmail = null; oauthKind = 'google'; error = null; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [AppTheme.blue, AppTheme.sky, Colors.white], stops: [0, 0.42, 0.42],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Container(
                  width: 92,
                  height: 92,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 18, offset: const Offset(0, 6))],
                  ),
                  child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                ),
                const SizedBox(height: 10),
                const Text('Pips', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white)),
                const Text('Your cloud. Your rules.', style: TextStyle(fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 22),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: signup
                      ? SignupWizard(
                          key: const ValueKey('su'),
                          onDone: widget.onAuthed,
                          onBack: backFromSignup,
                          googleEmail: googleEmail,
                          oauthKind: oauthKind,
                        )
                      : Container(
                          key: const ValueKey('li'),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 24, offset: Offset(0, 8))],
                          ),
                          child: Column(children: [
                            const Text('Welcome back', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                            const SizedBox(height: 14),
                            TextField(
                              controller: userCtrl,
                              decoration: _dec('Username or email', Icons.person_outline),
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: passCtrl,
                              obscureText: true,
                              onSubmitted: (_) => login(),
                              decoration: _dec('Password', Icons.lock_outline),
                            ),
                            if (error != null) ...[
                              const SizedBox(height: 10),
                              Text(error!, style: const TextStyle(color: AppTheme.red, fontSize: 12.5)),
                            ],
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: busy || gBusy || ghBusy || guestBusy ? null : () => _forgot(context),
                                child: const Text('Forgot password?', style: TextStyle(fontSize: 13)),
                              ),
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                onPressed: busy || gBusy || ghBusy || guestBusy ? null : login,
                                child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Log in', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(children: const [
                              Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Text('or continue with', style: TextStyle(color: Colors.grey, fontSize: 12.5)),
                              ),
                              Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                            ]),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  side: const BorderSide(color: Color(0xFFDCE4EE)),
                                  backgroundColor: Colors.white,
                                ),
                                onPressed: busy || gBusy || ghBusy || guestBusy ? null : google,
                                icon: gBusy
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Image.asset('assets/google_g.png', width: 21, height: 21),
                                label: const Text('Continue with Google', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Color(0xFF1F2937))),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  backgroundColor: const Color(0xFF171B21),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: busy || gBusy || ghBusy || guestBusy ? null : github,
                                icon: ghBusy
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : Image.asset('assets/github_mark_w.png', width: 21, height: 21),
                                label: const Text('Continue with GitHub', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: busy || gBusy || ghBusy || guestBusy ? null : guest,
                              child: guestBusy
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Continue as guest', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Colors.grey)),
                            ),
                            const SizedBox(height: 2),
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              const Text('New to Pips?', style: TextStyle(color: Colors.grey, fontSize: 13.5)),
                              TextButton(
                                onPressed: () => setState(() { signup = true; error = null; }),
                                child: const Text('Create account', style: TextStyle(fontWeight: FontWeight.w700)),
                              ),
                            ]),
                          ]),
                        ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      );

  void _forgot(BuildContext context) {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset password'),
        content: TextField(controller: c, decoration: const InputDecoration(hintText: 'Username')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await PipsApi.forgotPassword(c.text.trim());
                if (context.mounted) toast(context, 'Reset email sent (if the account exists).');
              } on ApiException catch (e) {
                if (context.mounted) toast(context, e.message);
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

class SignupWizard extends StatefulWidget {
  final VoidCallback onDone;
  final VoidCallback onBack;
  final String? googleEmail; // non-null -> OAuth-driven signup (Google/GitHub)
  final String oauthKind; // google | github
  const SignupWizard({super.key, required this.onDone, required this.onBack, this.googleEmail, this.oauthKind = 'google'});
  @override
  State<SignupWizard> createState() => _SignupWizardState();
}

class _SignupWizardState extends State<SignupWizard> {
  int step = 0; // 0 username, 1 email+method, 2 verify, 3 password
  String method = 'otp';
  String? tokenHint;
  final userCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final otpCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final pass2Ctrl = TextEditingController();
  bool busy = false;
  String? error;
  Timer? _poll;

  bool get googleMode => widget.googleEmail != null;
  String get providerLabel => widget.oauthKind == 'github' ? 'GitHub' : 'Google';

  @override
  void initState() {
    super.initState();
    if (googleMode) {
      userCtrl.text = GoogleAuth.deriveUsername(widget.googleEmail!);
      emailCtrl.text = widget.googleEmail!;
      method = 'otp';
      step = 1; // username + email come from the verified Google profile
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() { busy = true; error = null; });
    try {
      await fn();
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } catch (_) {
      setState(() => error = 'Network error — check your connection.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void checkUsername() => _run(() async {
        final u = userCtrl.text.trim().toLowerCase();
        if (u.length < 3) throw ApiException('Username must be at least 3 characters.', 0);
        await PipsApi.checkUsername(u);
        setState(() => step = 1);
      });

  void startSignup() => _run(() async {
        final u = userCtrl.text.trim().toLowerCase();
        final r = await PipsApi.signupStart(u, emailCtrl.text.trim(), method);
        setState(() {
          step = 2;
          tokenHint = r['token']?.toString();
        });
        if (method == 'link') _startPolling(u);
      });

  void _startPolling(String u) {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 4), (t) async {
      try {
        final s = await PipsApi.signupStatus(u);
        if (s['verified'] == true && mounted) {
          t.cancel();
          setState(() => step = 3);
        }
      } catch (_) {}
    });
  }

  void verify() => _run(() async {
        await PipsApi.signupVerify(userCtrl.text.trim().toLowerCase(), otpCtrl.text.trim());
        _poll?.cancel();
        setState(() => step = 3);
      });

  void finish() => _run(() async {
        if (passCtrl.text.length < 6) throw ApiException('Password must be at least 6 characters.', 0);
        if (passCtrl.text != pass2Ctrl.text) throw ApiException('Passwords do not match.', 0);
        await PipsApi.signupFinish(userCtrl.text.trim().toLowerCase(), passCtrl.text);
        if (googleMode) {
          await GoogleAuth.remember(widget.googleEmail!, userCtrl.text.trim().toLowerCase(), passCtrl.text);
        }
        widget.onDone();
      });

  @override
  Widget build(BuildContext context) {
    final titles = [
      googleMode ? 'Create account with $providerLabel' : 'Choose a username',
      googleMode ? 'Confirm your $providerLabel email' : 'Your email',
      'Check your inbox',
      'Set a password',
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: step == 0 || (googleMode && step == 1) ? widget.onBack : () => setState(() => step -= 1)),
          Expanded(child: Text(titles[step], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          Text('${step + 1}/4', style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        if (step == 0) ...[
          TextField(controller: userCtrl, decoration: _d('Username (min 3 chars)', Icons.alternate_email)),
          const SizedBox(height: 14),
          _btn('Check availability', checkUsername),
        ] else if (step == 1) ...[
          if (googleMode) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF1F5FF), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                widget.oauthKind == 'github'
                    ? Image.asset('assets/github_mark.png', width: 26, height: 26)
                    : Image.asset('assets/google_g.png', width: 26, height: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(userCtrl.text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    Text(widget.googleEmail!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            const Text('We\'ll verify this email with a one-time code sent to your inbox.', style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5)),
            const SizedBox(height: 14),
          ] else ...[
            TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: _d('Email address', Icons.email_outlined)),
            const SizedBox(height: 14),
            Row(children: [
              _methodChip('OTP code', 'otp'),
              const SizedBox(width: 8),
              _methodChip('Magic link', 'link'),
            ]),
            const SizedBox(height: 14),
          ],
          _btn(googleMode ? 'Send verification code' : 'Send verification', startSignup),
        ] else if (step == 2) ...[
          if (method == 'otp') ...[
            TextField(controller: otpCtrl, keyboardType: TextInputType.number, decoration: _d('6-digit code', Icons.pin_outlined)),
            const SizedBox(height: 14),
            _btn('Verify', verify),
            TextButton(
              onPressed: busy ? null : () => _run(() => PipsApi.resendOtp(userCtrl.text.trim())),
              child: const Text('Resend code'),
            ),
          ] else ...[
            const Text('We emailed you a magic link. Opening it verifies this device — this screen advances automatically.', style: TextStyle(color: Colors.grey, fontSize: 13.5, height: 1.5)),
            if (tokenHint != null && tokenHint!.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText('Dev token: $tokenHint', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            const SizedBox(height: 14),
            const Center(child: CircularProgressIndicator()),
          ],
        ] else ...[
          if (googleMode)
            Text('This password signs you in with one tap next time you use Continue with $providerLabel.', style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5)),
          if (googleMode) const SizedBox(height: 12),
          TextField(controller: passCtrl, obscureText: true, decoration: _d('Password (min 6 chars)', Icons.lock_outline)),
          const SizedBox(height: 12),
          TextField(controller: pass2Ctrl, obscureText: true, onSubmitted: (_) => finish(), decoration: _d('Repeat password', Icons.lock_outline)),
          const SizedBox(height: 14),
          _btn('Create account', finish),
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!, style: const TextStyle(color: AppTheme.red, fontSize: 12.5)),
        ],
      ]),
    );
  }

  InputDecoration _d(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      );

  Widget _methodChip(String label, String m) => ChoiceChip(
        label: Text(label),
        selected: method == m,
        onSelected: (_) => setState(() => method = m),
      );

  Widget _btn(String label, VoidCallback fn) => SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: busy ? null : fn,
          child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      );
}
