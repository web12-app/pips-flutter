import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';

/// Subscription — a premium offer screen: gradient hero, glass plan cards,
/// feature checklists, trust row. Adaptive in light and dark mode.
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});
  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  int selected = 0;

  static const _plans = [
    (
      title: 'Pro',
      sub: '2TB storage · everything unlocked',
      price: '\$50.00',
      oldPrice: '\$100.00/month',
      badge: 'Recommended · For power users! 2TB (50% off)',
      feats: ['2 TB cloud storage', 'Unlimited bandwidth & speed', 'Priority 24/7 support'],
    ),
    (
      title: 'Standard',
      sub: '500GB storage · best value',
      price: '\$30.00',
      oldPrice: '',
      badge: 'Lowest price · 500GB (100GB)',
      feats: ['500 GB cloud storage', 'Fast uploads, all file types', 'Standard support'],
    ),
    (
      title: 'Free Trial',
      sub: '5GB storage · try Pips free forever',
      price: '\$0.00',
      oldPrice: '',
      badge: 'Free 5GB (trial plan)',
      feats: ['5 GB cloud storage', 'Every file type welcome', 'Community support'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hc = HomeColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Subscription'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          // ------------------------------------------------------------ hero
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.blue, AppTheme.purple],
              ),
              boxShadow: [
                BoxShadow(color: AppTheme.blue.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10)),
              ],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
                  child: const Text('1 of 3 · pick a plan', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ]),
              const SizedBox(height: 14),
              const Text('Pips Premium', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 26)),
              const SizedBox(height: 4),
              Text(
                'Choose the plan that’s right for you — flexible plans, cancel anytime.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 13, height: 1.4),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          // ------------------------------------------------------------ plans
          for (var i = 0; i < _plans.length; i++) _planCard(i),
          const SizedBox(height: 8),
          // ------------------------------------------------------------ CTA
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                backgroundColor: AppTheme.blue,
                foregroundColor: Colors.white,
                shadowColor: AppTheme.blue.withValues(alpha: 0.45),
                elevation: 4,
              ),
              onPressed: _confirm,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.lock_outline, size: 16),
                const SizedBox(width: 8),
                Text('Continue to payment · ${_plans[selected].price}/mo',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          // ------------------------------------------------------------ trust
          Row(children: [
            const Spacer(),
            _trust(Icons.shield_outlined, 'Secure checkout'),
            const SizedBox(width: 14),
            _trust(Icons.schedule, 'Cancel anytime'),
            const Spacer(),
          ]),
          const SizedBox(height: 18),
          _currentPlanCard(dark, hc),
        ],
      ),
    );
  }

  Widget _trust(IconData icon, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: HomeColors.of(context).text2),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11.5, color: HomeColors.of(context).text2, fontWeight: FontWeight.w600)),
      ]);

  Future<void> _confirm() async {
    final p = _plans[selected];
    if (selected == 2) {
      toast(context, "You're on the Free plan already — enjoy your 5GB.");
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Switch to ${p.title}?'),
        content: const Text('In-app billing is not wired up yet — plan changes are handled on the web dashboard for now.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open web')),
        ],
      ),
    );
    if (ok == true) {
      // Pips has no billing endpoint yet — surface the web dashboard instead.
      toast(context, 'Plan change: open ${PipsApi.base} on the web to pay.');
    }
  }

  Widget _planCard(int i) {
    final p = _plans[i];
    final active = selected == i;
    final hc = HomeColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => setState(() => selected = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: active ? AppTheme.blue : hc.line, width: active ? 1.8 : 1),
          gradient: active
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.blue.withValues(alpha: dark ? 0.22 : 0.10),
                    AppTheme.blue.withValues(alpha: dark ? 0.05 : 0.02),
                  ],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    (dark ? const Color(0xFF2C2C2E) : Colors.white).withValues(alpha: 0.92),
                    (dark ? const Color(0xFF1C1C1E) : const Color(0xFFF7FAFF)).withValues(alpha: 0.75),
                  ],
                ),
          boxShadow: active
              ? [BoxShadow(color: AppTheme.blue.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 6))]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (p.badge.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: active ? AppTheme.blue : (dark ? const Color(0xFF3A3A3C) : const Color(0xFFEFF3F8)),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.local_fire_department, size: 13, color: active ? Colors.white : (dark ? Colors.white70 : AppTheme.orange)),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(p.badge, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: active ? Colors.white : (dark ? Colors.white70 : Colors.grey.shade700))),
                ),
              ]),
            ),
          Row(children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? AppTheme.blue : Colors.transparent,
                border: Border.all(color: active ? AppTheme.blue : (dark ? Colors.grey.shade500 : Colors.grey.shade400), width: 2),
              ),
              child: active ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(p.title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: hc.text1))),
            Text(p.price, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: active ? AppTheme.blue : hc.text1)),
            const SizedBox(width: 2),
            Text('/ month', style: TextStyle(fontSize: 11, color: hc.text2)),
          ]),
          const SizedBox(height: 10),
          for (final f in p.feats)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                Icon(Icons.check_circle, size: 15, color: active ? AppTheme.blue : AppTheme.green),
                const SizedBox(width: 8),
                Expanded(child: Text(f, style: TextStyle(fontSize: 12.5, color: hc.text2))),
              ]),
            ),
          if (p.oldPrice.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(p.oldPrice, style: TextStyle(fontSize: 11, color: hc.text2, decoration: TextDecoration.lineThrough)),
            ),
        ]),
      ),
    );
  }

  Widget _currentPlanCard(bool dark, HomeColors hc) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: hc.surfaceSoft, borderRadius: BorderRadius.circular(16), border: Border.all(color: hc.line)),
        child: FutureBuilder<Map<String, dynamic>>(
          future: PipsApi.account(),
          builder: (_, s) {
            final a = s.data ?? {};
            final used = (a['storage_used'] is num ? (a['storage_used'] as num) : 0).toInt();
            final quota = (a['quota'] is num ? (a['quota'] as num) : 2199023255552).toInt();
            return Row(children: [
              SizedBox(width: 40, height: 40, child: Image.asset('assets/logo.png', fit: BoxFit.contain)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Your current plan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: hc.text1)),
                  Text('Pips Basic · ${fmtBytes(used)} of ${fmtBytes(quota)} used', style: TextStyle(fontSize: 11.5, color: hc.text2)),
                ]),
              ),
            ]);
          },
        ),
      );
}
