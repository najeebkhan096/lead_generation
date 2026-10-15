import 'package:flutter/material.dart';

import '../models/sale.dart';
import '../services/admin_data.dart';
import '../theme/app_theme.dart';
import '../utils/admin_analytics.dart';
import '../widgets/admin_widgets.dart';
import 'admin_salesman_detail_page.dart';

/// What the business owes each salesman. Completed orders with a pending
/// payout are due now; ongoing orders are only expected.
class AdminPayoutsPage extends StatefulWidget {
  const AdminPayoutsPage({super.key});

  @override
  State<AdminPayoutsPage> createState() => _AdminPayoutsPageState();
}

class _AdminPayoutsPageState extends State<AdminPayoutsPage> {
  String? _busyUserId;

  Future<void> _settle(AdminData data, SalesmanSummary s, List<Sale> due) async {
    final total = due.fold<double>(0, (a, x) => a + x.employeePaymentAmount);
    final ok = await confirmAdminAction(
      context,
      title: 'Mark payouts as paid?',
      message: '${due.length} completed ${due.length == 1 ? 'order' : 'orders'} for ${s.user.name} (${formatPkr(total)}) will be marked as paid.',
      confirmLabel: 'Mark paid',
    );
    if (!ok || !mounted) return;
    setState(() => _busyUserId = s.user.id);
    try {
      await data.markPayoutsPaid(due);
      if (mounted) showAdminMessage(context, '${formatPkr(total)} paid to ${s.user.name}');
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = AdminScope.of(context);
    final snap = data.snapshot;
    final o = snap.overall;
    final t = context.tokens;
    final text = Theme.of(context).textTheme;

    final rows = snap.salesmen.where((s) => s.rollup.payablePkr > 0 || s.rollup.expectedPkr > 0 || s.rollup.paidPkr > 0).toList()
      ..sort((a, b) => b.rollup.payablePkr.compareTo(a.rollup.payablePkr));

    return Scaffold(
      appBar: AppBar(title: const Text('Payouts')),
      body: RefreshIndicator(
        onRefresh: data.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            KpiGrid(tiles: [
              KpiTile(label: 'Due now', value: formatPkr(o.payablePkr), icon: AppIcons.wallet, tone: o.payablePkr > 0 ? Tone.accent : Tone.neutral, caption: 'Completed, unpaid'),
              KpiTile(label: 'Paid out', value: formatPkr(o.paidPkr), icon: AppIcons.banknote, tone: Tone.success, caption: 'Settled to date'),
            ]),
            const SizedBox(height: 12),
            AdminCard(
              child: DetailRow(label: 'Expected from ongoing orders', value: formatPkr(o.expectedPkr)),
            ),
            const SectionHeader(title: 'By salesman'),
            if (rows.isEmpty)
              const EmptyState(icon: AppIcons.wallet, title: 'No payouts yet', message: 'Payouts appear once sales have a salesman payout amount.')
            else
              for (final s in rows) ...[
                _row(context, data, s, t, text),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, AdminData data, SalesmanSummary s, AppTokens t, TextTheme text) {
    final r = s.rollup;
    final due = r.dueSales;
    final busy = _busyUserId == s.user.id;
    return AdminCard(
      onTap: () => pushAdminPage(context, AdminSalesmanDetailPage(userId: s.user.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PersonAvatar(name: s.user.name, photoUrl: s.user.photoURL, size: 40),
              const SizedBox(width: 12),
              Expanded(child: Text(s.user.name, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(formatPkr(r.payablePkr), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: r.payablePkr > 0 ? t.accentText : t.faint)),
            ],
          ),
          const SizedBox(height: 10),
          Text('Paid ${formatPkr(r.paidPkr)} · Expected ${formatPkr(r.expectedPkr)}', style: text.bodySmall),
          if (due.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: busy ? null : () => _settle(data, s, due),
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Mark ${due.length} ${due.length == 1 ? 'order' : 'orders'} as paid'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
