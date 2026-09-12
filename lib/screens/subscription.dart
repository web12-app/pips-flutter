import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';

/// Subscription — plan picker (Pro / Standard / Free) styled after the Pips design.
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});
  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  int selected = 0;

  static const _plans = [
    (title: 'Pro', sub: '2TB storage · everything unlocked', price: '\$50.00', oldPrice: '\$100.00/month', badge: 'Recommended · For power users! 2TB (50% off)'),
    (title: 'Standard', sub: '500GB storage · best value', price: '\$30.00', oldPrice: '', badge: 'Lowest price · 500GB (100GB)'),
    (title: 'Free Trial', sub: '5GB storage · try Pips free forever', price: '\$0.00', oldPrice: '', badge: 'Free 5GB (trial plan)'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subscription')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFEFF3F8), borderRadius: BorderRadius.circular(99)),
              child: Text('1 of 3 · pick a plan', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 18),
          const Center(child: Text("Choose the plan that's right for you", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19))),
          const SizedBox(height: 4),
          const Center(child: Text('Flexible plans, cancel anytime', style: TextStyle(fontSize: 12.5, color: Colors.grey))),
          const SizedBox(height: 18),
          for (var i = 0; i < _plans.length; i++) _planCard(i),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: _confirm,
              child: const Text('Add to Payment Method', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 10),
          const Center(child: Text('Cancel anytime. No hidden fees.', style: TextStyle(fontSize: 11.5, color: Colors.grey))),
          const SizedBox(height: 18),
          _currentPlanCard(),
        ]),
      ),
    );
  }

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
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open web'))],
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
    return GestureDetector(
      onTap: () => setState(() => selected = i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFF0F7FF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? AppTheme.blue : const Color(0xFFE8EEF6), width: active ? 1.6 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (p.badge.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: active ? AppTheme.blue : const Color(0xFFEFF3F8), borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle, size: 13, color: active ? Colors.white : Colors.grey.shade600),
                const SizedBox(width: 5),
                Flexible(child: Text(p.badge, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: active ? Colors.white : Colors.grey.shade700))),
              ]),
            ),
          Row(children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(shape: BoxShape.circle, color: active ? AppTheme.blue : Colors.transparent, border: Border.all(color: active ? AppTheme.blue : Colors.grey.shade400, width: 2)),
              child: active ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            Text(p.price, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(width: 2),
            Text('/ month', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ]),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.sub, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (p.oldPrice.isNotEmpty)
                Text(p.oldPrice, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, decoration: TextDecoration.lineThrough)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _currentPlanCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE8EEF6))),
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
                  const Text('Your current plan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                  Text('Pips Basic · ${fmtBytes(used)} of ${fmtBytes(quota)} used', style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                ]),
              ),
            ]);
          },
        ),
      );
}
