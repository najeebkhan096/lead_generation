import 'package:flutter/material.dart';

import '../services/admin_data.dart';
import '../theme/app_theme.dart';
import '../utils/admin_analytics.dart';
import '../widgets/admin_sale_tile.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/page_header.dart';
import 'admin_payouts_page.dart';
import 'admin_sale_detail_page.dart';
import 'admin_salesman_detail_page.dart';
import 'admin_users_page.dart';

/// Landing tab: what needs attention, the pipeline, top salesmen and the
/// latest orders.
class AdminOverviewPage extends StatelessWidget {
  const AdminOverviewPage({super.key, required this.onOpenTab});

  /// Switches the bottom bar to another tab (Salesmen, Sales, Clients).
  final ValueChanged<int> onOpenTab;

  static const int salesmenTab = 1;
  static const int salesTab = 2;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Overview',
            subtitle: 'Sales, salesmen and clients at a glance',
            trailing: IconButton.filledTonal(
              tooltip: 'Refresh',
              onPressed: () => AdminScope.read(context).load(),
              icon: const Icon(AppIcons.refresh, size: 18),
            ),
          ),
          Expanded(
            child: AdminLoadGate(
              builder: (context, data) => _Body(data: data, onOpenTab: onOpenTab),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.data, required this.onOpenTab});

  final AdminData data;
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final snap = data.snapshot;
    final o = snap.overall;
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final unassigned = snap.unassigned.length;
    final recent = snap.sales.take(5).toList();
    final top = snap.salesmen.where((s) => s.rollup.total > 0).take(3).toList()
      ..sort((a, b) => b.rollup.completed.compareTo(a.rollup.completed));

    final attention = <Widget>[
      if (snap.pendingApprovals > 0)
        _AttentionRow(
          icon: AppIcons.userCheck,
          title: '${snap.pendingApprovals} ${snap.pendingApprovals == 1 ? 'account is' : 'accounts are'} awaiting approval',
          action: 'Review',
          onTap: () => pushAdminPage(context, const AdminUsersPage()),
        ),
      if (o.payablePkr > 0)
        _AttentionRow(
          icon: AppIcons.wallet,
          title: '${formatPkr(o.payablePkr)} in payouts due to salesmen',
          action: 'Pay out',
          onTap: () => pushAdminPage(context, const AdminPayoutsPage()),
        ),
      if (unassigned > 0)
        _AttentionRow(
          icon: AppIcons.clipboardList,
          title: '$unassigned ${unassigned == 1 ? 'sale has' : 'sales have'} no salesman assigned',
          action: 'View',
          onTap: () => onOpenTab(AdminOverviewPage.salesTab),
        ),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        if (data.error != null || data.warning != null) ...[
          AdminCard(
            child: Row(
              children: [
                Icon(AppIcons.alert, size: 18, color: t.danger),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    data.error != null ? 'Showing the last loaded data. ${data.error}' : data.warning!,
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (attention.isNotEmpty) ...[
          for (final a in attention) ...[a, const SizedBox(height: 10)],
          const SizedBox(height: 4),
        ],
        KpiGrid(tiles: [
          KpiTile(label: 'Ongoing sales', value: '${o.ongoing}', icon: AppIcons.clock, tone: Tone.accent, caption: '${o.removal} in removal · ${o.awaitingPayment} to pay', onTap: () => onOpenTab(AdminOverviewPage.salesTab)),
          KpiTile(label: 'Completed', value: '${o.completed}', icon: AppIcons.circleCheck, tone: Tone.success, caption: '${(o.completionRate * 100).round()}% completion'),
          KpiTile(label: 'Salesmen', value: '${snap.salesmen.where((s) => s.user.approved).length}', icon: AppIcons.users, tone: Tone.neutral, caption: '${snap.clients.length} clients', onTap: () => onOpenTab(AdminOverviewPage.salesmenTab)),
          KpiTile(label: 'Profit', value: formatPkr(o.profitPkr), icon: AppIcons.trendingUp, tone: Tone.success, caption: 'Billed ${formatUsd(o.billedUsd)}'),
        ]),
        const SectionHeader(title: 'Pipeline'),
        AdminCard(
          child: Column(
            children: [
              SegmentBar(segments: [
                (o.locked, Tone.neutral),
                (o.removal, Tone.accent),
                (o.awaitingPayment, Tone.deep),
                (o.completed, Tone.success),
                (o.cancelled, Tone.danger),
              ]),
              const SizedBox(height: 12),
              LegendRow(label: 'Deal locked', value: '${o.locked}', tone: Tone.neutral),
              LegendRow(label: 'Removal', value: '${o.removal}', tone: Tone.accent),
              LegendRow(label: 'Awaiting payment', value: '${o.awaitingPayment}', tone: Tone.deep),
              LegendRow(label: 'Completed', value: '${o.completed}', tone: Tone.success),
              LegendRow(label: 'Cancelled', value: '${o.cancelled}', tone: Tone.danger),
            ],
          ),
        ),
        const SectionHeader(title: 'Payouts'),
        AdminCard(
          onTap: () => pushAdminPage(context, const AdminPayoutsPage()),
          child: Column(
            children: [
              DetailRow(label: 'Due now (completed, unpaid)', value: formatPkr(o.payablePkr), valueColor: o.payablePkr > 0 ? t.accentText : null, bold: true),
              DetailRow(label: 'Expected (ongoing orders)', value: formatPkr(o.expectedPkr)),
              DetailRow(label: 'Paid out', value: formatPkr(o.paidPkr), valueColor: t.sageText),
            ],
          ),
        ),
        if (top.isNotEmpty) ...[
          SectionHeader(title: 'Top salesmen', actionLabel: 'See all', onAction: () => onOpenTab(AdminOverviewPage.salesmenTab)),
          for (final s in top) ...[
            AdminCard(
              onTap: () => pushAdminPage(context, AdminSalesmanDetailPage(userId: s.user.id)),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  PersonAvatar(name: s.user.name, photoUrl: s.user.photoURL, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.user.name, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${s.rollup.ongoing} ongoing · ${s.rollup.total} total', style: text.bodySmall),
                      ],
                    ),
                  ),
                  StatusPill(label: '${s.rollup.completed} completed', tone: Tone.success),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
        SectionHeader(title: 'Recent sales', actionLabel: snap.sales.length > 5 ? 'See all' : null, onAction: () => onOpenTab(AdminOverviewPage.salesTab)),
        if (recent.isEmpty)
          const AdminCard(child: Center(child: Text('No sales recorded yet.')))
        else
          for (final s in recent) ...[
            AdminSaleTile(sale: s, onTap: () => pushAdminPage(context, AdminSaleDetailPage(saleId: s.id))),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.icon, required this.title, required this.action, required this.onTap});

  final IconData icon;
  final String title;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return Material(
      color: t.accentTint,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: t.accentText),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: text.titleSmall?.copyWith(color: t.accentTextStrong))),
              const SizedBox(width: 8),
              Text(action, style: TextStyle(color: t.accentTextStrong, fontWeight: FontWeight.w700)),
              Icon(AppIcons.chevronRight, size: 18, color: t.accentTextStrong),
            ],
          ),
        ),
      ),
    );
  }
}
