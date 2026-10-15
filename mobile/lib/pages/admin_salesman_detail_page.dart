import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/sale.dart';
import '../models/sales_user.dart';
import '../services/admin_data.dart';
import '../theme/app_theme.dart';
import '../utils/admin_analytics.dart';
import '../utils/date_format.dart';
import '../widgets/admin_sale_section.dart';
import '../widgets/admin_widgets.dart';
import 'admin_sale_form.dart';

/// One salesman: account status, performance, payouts and every order they
/// have — split into ongoing and completed.
class AdminSalesmanDetailPage extends StatefulWidget {
  const AdminSalesmanDetailPage({super.key, required this.userId});

  final String userId;

  @override
  State<AdminSalesmanDetailPage> createState() => _AdminSalesmanDetailPageState();
}

class _AdminSalesmanDetailPageState extends State<AdminSalesmanDetailPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (success != null && mounted) showAdminMessage(context, success);
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _settle(AdminData data, SalesUser user, List<Sale> payable) async {
    final total = payable.fold<double>(0, (a, s) => a + s.employeePaymentAmount);
    final ok = await confirmAdminAction(
      context,
      title: 'Mark payouts as paid?',
      message: '${payable.length} completed ${payable.length == 1 ? 'order' : 'orders'} for ${user.name}, ${formatPkr(total)} in total, will be marked as paid.',
      confirmLabel: 'Mark paid',
    );
    if (!ok) return;
    await _run(
      () => data.markPayoutsPaid(payable),
      success: '${formatPkr(total)} marked as paid to ${user.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = AdminScope.of(context);
    final user = data.snapshot.users.where((u) => u.id == widget.userId).firstOrNull;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: AppIcons.searchX, title: 'Account not found', message: 'This account is no longer available.'),
      );
    }
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final summary = data.snapshot.salesmen.where((s) => s.user.id == user.id).firstOrNull ??
        SalesmanSummary(user: user, sales: AdminSnapshot.salesOf(user, data.snapshot.sales));
    final r = summary.rollup;
    final payable = r.dueSales;
    final isAdmin = user.role == 'admin';
    final isSelf = user.id == FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Salesman')),
      floatingActionButton: user.approved && !isAdmin
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => showAdminSaleForm(context, presetSalesman: user),
              icon: const Icon(AppIcons.plus),
              label: const Text('Add sale'),
            )
          : null,
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
          children: [
            Row(
              children: [
                PersonAvatar(name: user.name, photoUrl: user.photoURL, size: 60),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: text.headlineSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (user.email != null) Text(user.email!, style: text.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          StatusPill(label: isAdmin ? 'Admin' : 'Salesman', tone: isAdmin ? Tone.accent : Tone.neutral),
                          StatusPill(label: user.approved ? 'Approved' : 'Awaiting approval', tone: user.approved ? Tone.success : Tone.danger),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!user.approved) ...[
              const SizedBox(height: 16),
              AdminCard(
                child: Row(
                  children: [
                    const IconHolder(icon: AppIcons.shieldCheck, size: 40),
                    const SizedBox(width: 12),
                    Expanded(child: Text('This account can\'t sign in to the leads app until approved.', style: text.bodyMedium)),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _run(() => data.setApproved(user, true), success: '${user.name} approved'),
                      child: const Text('Approve'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            KpiGrid(tiles: [
              KpiTile(label: 'Ongoing', value: '${r.ongoing}', icon: AppIcons.clock, tone: Tone.accent, caption: '${r.removal} in removal · ${r.awaitingPayment} to pay'),
              KpiTile(label: 'Completed', value: '${r.completed}', icon: AppIcons.circleCheck, tone: Tone.success, caption: '${(r.completionRate * 100).round()}% completion'),
              KpiTile(label: 'Payable now', value: formatPkr(r.payablePkr), icon: AppIcons.wallet, tone: r.payablePkr > 0 ? Tone.accent : Tone.neutral, caption: '${payable.length} completed unpaid'),
              KpiTile(label: 'Paid out', value: formatPkr(r.paidPkr), icon: AppIcons.banknote, tone: Tone.success, caption: 'Expected ${formatPkr(r.expectedPkr)}'),
            ]),
            if (payable.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _settle(data, user, payable),
                  icon: const Icon(AppIcons.circleCheck, size: 18),
                  label: Text('Mark ${formatPkr(r.payablePkr)} as paid'),
                ),
              ),
            ],
            SectionHeader(title: 'Sales (${r.total})'),
            AdminSaleSection(sales: r.sales, showSalesman: false),
            const SectionHeader(title: 'Account'),
            AdminCard(
              child: Column(
                children: [
                  DetailRow(label: 'Joined', value: formatDate(DateTime.tryParse(user.createdAt ?? '')) ?? '—'),
                  DetailRow(label: 'Last sign-in', value: formatDate(DateTime.tryParse(user.lastLoginAt ?? '')) ?? '—'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _run(
                            () => data.setApproved(user, !user.approved),
                            success: user.approved ? 'Approval revoked' : '${user.name} approved',
                          ),
                          style: user.approved ? OutlinedButton.styleFrom(foregroundColor: t.danger) : null,
                          child: Text(user.approved ? 'Revoke access' : 'Approve'),
                        ),
                      ),
                      if (!isSelf) const SizedBox(width: 12),
                      if (!isSelf)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final next = isAdmin ? 'salesman' : 'admin';
                            final ok = await confirmAdminAction(
                              context,
                              title: isAdmin ? 'Make a salesman?' : 'Make an admin?',
                              message: isAdmin
                                  ? '${user.name} will lose access to the admin console.'
                                  : '${user.name} will be able to manage users, sales and payouts.',
                              confirmLabel: 'Confirm',
                            );
                            if (ok) await _run(() => data.setRole(user, next), success: '${user.name} is now ${next == 'admin' ? 'an admin' : 'a salesman'}');
                          },
                          child: Text(isAdmin ? 'Make salesman' : 'Make admin'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
