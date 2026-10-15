import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/sale.dart';
import '../services/admin_data.dart';
import '../theme/app_theme.dart';
import '../utils/admin_analytics.dart';
import '../utils/date_format.dart';
import '../widgets/admin_widgets.dart';
import 'admin_client_detail_page.dart';
import 'admin_payment_sheet.dart';
import 'admin_sale_form.dart';
import 'admin_salesman_detail_page.dart';

/// One order in full: stage, salesman payout, client billing and timeline,
/// with quick actions to move it along.
class AdminSaleDetailPage extends StatefulWidget {
  const AdminSaleDetailPage({super.key, required this.saleId});

  final String saleId;

  @override
  State<AdminSaleDetailPage> createState() => _AdminSaleDetailPageState();
}

class _AdminSaleDetailPageState extends State<AdminSaleDetailPage> {
  bool _busy = false;

  Sale? _find(AdminData data) {
    for (final s in data.snapshot.sales) {
      if (s.id == widget.saleId) return s;
    }
    return null;
  }

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

  /// Moves the deal one step along the process. The last step — the client
  /// paying — first records what arrived, so profit is right and the
  /// salesman's payout becomes due.
  Future<void> _advance(AdminData data, Sale sale) async {
    final next = sale.status.next;
    if (next == null) return;
    final body = <String, dynamic>{'leadStatus': next.json};
    if (next == SaleStatus.completed) {
      final payment = await showClientPaymentSheet(context, sale: sale);
      if (payment == null) return;
      body
        ..['clientPaymentStatus'] = ClientPaymentStatus.paid.json
        ..['clientAmountReceived'] = payment.amountReceivedPkr
        ..['removalCost'] = payment.removalCostPkr;
      if (payment.method != null) body['clientPaymentMethod'] = payment.method;
    }
    await _run(
      () => data.updateSale(sale.id, body),
      success: switch (next) {
        SaleStatus.inProgress => 'Removal started',
        SaleStatus.payment => 'Waiting for the client to pay',
        SaleStatus.completed => 'Deal completed — payout is now due',
        _ => null,
      },
    );
  }

  Future<void> _delete(Sale sale) async {
    final data = AdminScope.read(context);
    final ok = await confirmAdminAction(
      context,
      title: 'Delete this sale?',
      message: 'The order for ${sale.businessName} will be removed permanently.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await data.deleteSale(sale.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminError(context, e);
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    final opened = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) showAdminMessage(context, 'Could not open the link');
  }

  @override
  Widget build(BuildContext context) {
    final data = AdminScope.of(context);
    final sale = _find(data);
    if (sale == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: AppIcons.searchX, title: 'Sale not found', message: 'This order was removed or is no longer available.'),
      );
    }
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final salesman = (sale.salesmanName ?? '').trim();
    final paid = sale.employeePaymentStatus == EmployeePaymentStatus.paid;
    final salesmanUser = data.snapshot.users.where((u) => u.id == sale.salesmanId).firstOrNull;
    final client = data.snapshot.clients.where((c) => c.name.toLowerCase() == sale.businessName.trim().toLowerCase()).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sale details'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(AppIcons.edit),
            onPressed: _busy ? null : () => showAdminSaleForm(context, sale: sale),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: Icon(AppIcons.trash, color: t.danger),
            onPressed: _busy ? null : () => _delete(sale),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Text(sale.businessName, style: text.headlineMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill(label: sale.status.label, tone: toneOfStatus(sale.status)),
                StatusPill(label: salesman.isEmpty ? 'Unassigned' : salesman, tone: Tone.neutral, icon: AppIcons.user),
              ],
            ),
            if (sale.paymentsArchived) ...[
              const SizedBox(height: 16),
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(AppIcons.history, size: 18, color: t.subtle),
                        const SizedBox(width: 8),
                        Text('Earlier order', style: text.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The client and amounts are kept, but this order\'s payments are not counted in payouts, billing or profit.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => _run(() => data.updateSale(sale.id, {'paymentsArchived': false}), success: 'Payments are counted again'),
                      child: const Text('Count its payments again'),
                    ),
                  ],
                ),
              ),
            ],
            const SectionHeader(title: 'Progress'),
            AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProcessStepper(status: sale.status),
                  if (sale.status.next != null) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _advance(data, sale),
                      icon: const Icon(AppIcons.check, size: 18),
                      label: Text(sale.status.advanceLabel!),
                    ),
                  ],
                  if (sale.status == SaleStatus.completed)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('The client has paid. The salesman payout is now due.', style: text.bodySmall),
                    ),
                  if (sale.status == SaleStatus.cancelled)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('This deal was cancelled. Pick a stage below to reopen it.', style: text.bodySmall),
                    ),
                ],
              ),
            ),
            const SectionHeader(title: 'Set stage manually'),
            _StageSelector(
              current: sale.status,
              onSelected: (s) => _run(() => data.updateSale(sale.id, {'leadStatus': s.json})),
            ),
            const SectionHeader(title: 'Salesman payout'),
            AdminCard(
              child: Column(
                children: [
                  DetailRow(label: 'Amount', value: formatPkr(sale.employeePaymentAmount), bold: true),
                  DetailRow(label: 'Status', value: paid ? 'Paid' : 'Pending', valueColor: paid ? t.sageText : t.accentText),
                  if (!paid && sale.employeePaymentAmount > 0 && !sale.paymentsArchived) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _run(
                          () => data.updateSale(sale.id, {'employeePaymentStatus': EmployeePaymentStatus.paid.name}),
                          success: 'Payout marked as paid',
                        ),
                        icon: const Icon(AppIcons.circleCheck, size: 18),
                        label: const Text('Mark payout as paid'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SectionHeader(title: 'Client billing'),
            AdminCard(
              child: Column(
                children: [
                  DetailRow(label: 'Price charged', value: formatUsd(sale.priceChargedToClient)),
                  DetailRow(label: 'Client payment', value: sale.clientPaymentStatus.label),
                  if ((sale.clientPaymentMethod ?? '').isNotEmpty) DetailRow(label: 'Paid by', value: sale.clientPaymentMethod!),
                  DetailRow(label: 'Amount received', value: formatPkr(sale.clientAmountReceived)),
                  DetailRow(label: 'Removal cost', value: formatPkr(sale.removalCost)),
                  const Divider(height: 20),
                  DetailRow(
                    label: 'Profit',
                    value: formatPkr(sale.profit),
                    valueColor: sale.profit < 0 ? t.danger : t.sageText,
                    bold: true,
                  ),
                ],
              ),
            ),
            if (sale.reviewLink != null && sale.reviewLink!.isNotEmpty) ...[
              const SectionHeader(title: 'Review link'),
              AdminCard(
                onTap: () => _openLink(sale.reviewLink!),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(sale.reviewLink!, style: TextStyle(color: t.accentText, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Icon(AppIcons.externalLink, size: 18, color: t.faint),
                  ],
                ),
              ),
            ],
            const SectionHeader(title: 'Timeline'),
            AdminCard(
              child: Column(
                children: [
                  DetailRow(label: 'Created', value: formatDateTime(sale.createdAt) ?? '—'),
                  DetailRow(label: 'Last updated', value: formatDateTime(sale.updatedAt) ?? '—'),
                ],
              ),
            ),
            const SectionHeader(title: 'Related'),
            if (client != null)
              _LinkRow(
                icon: AppIcons.handshake,
                title: 'Client: ${client.name}',
                subtitle: '${client.rollup.total} ${client.rollup.total == 1 ? 'order' : 'orders'} in total',
                onTap: () => pushAdminPage(context, AdminClientDetailPage(clientName: client.name)),
              ),
            if (salesmanUser != null) ...[
              const SizedBox(height: 10),
              _LinkRow(
                icon: AppIcons.user,
                title: 'Salesman: ${salesmanUser.name}',
                subtitle: 'View their sales and stats',
                onTap: () => pushAdminPage(context, AdminSalesmanDetailPage(userId: salesmanUser.id)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The four steps of a deal. Cancelled deals show every step as not done.
class _ProcessStepper extends StatelessWidget {
  const _ProcessStepper({required this.status});

  final SaleStatus status;

  static const _steps = [
    (SaleStatus.newSale, 'Deal\nlocked'),
    (SaleStatus.inProgress, 'Removal'),
    (SaleStatus.payment, 'Payment'),
    (SaleStatus.completed, 'Completed'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cancelled = status == SaleStatus.cancelled;
    final current = _steps.indexWhere((s) => s.$1 == status);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _Line(active: !cancelled && i <= current && i > 0, visible: i > 0)),
                    _Dot(
                      state: cancelled
                          ? _StepState.todo
                          : status == SaleStatus.completed || i < current
                              ? _StepState.done
                              : i == current
                                  ? _StepState.current
                                  : _StepState.todo,
                    ),
                    Expanded(child: _Line(active: !cancelled && i < current, visible: i < _steps.length - 1)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _steps[i].$2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                    color: !cancelled && i <= current ? t.ink : t.faint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

enum _StepState { done, current, todo }

class _Dot extends StatelessWidget {
  const _Dot({required this.state});

  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final filled = state != _StepState.todo;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (state) {
          _StepState.done => t.sage,
          _StepState.current => t.accent,
          _StepState.todo => t.surface,
        },
        border: Border.all(color: filled ? Colors.transparent : t.border, width: 2),
      ),
      child: switch (state) {
        _StepState.done => Icon(AppIcons.check, size: 15, color: t.onFill),
        _StepState.current => Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: t.onFill))),
        _StepState.todo => null,
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.active, required this.visible});

  final bool active;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(height: 2, color: !visible ? Colors.transparent : (active ? t.sage : t.border));
  }
}

class _StageSelector extends StatelessWidget {
  const _StageSelector({required this.current, required this.onSelected});

  final SaleStatus current;
  final ValueChanged<SaleStatus> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in SaleStatus.values)
          ChoiceChip(
            label: Text(s.label),
            selected: s == current,
            showCheckmark: false,
            onSelected: s == current ? null : (_) => onSelected(s),
            selectedColor: t.accent,
            labelStyle: TextStyle(
              fontWeight: FontWeight.w600,
              color: s == current ? t.onFill : t.subtle,
            ),
            backgroundColor: t.surface,
            side: BorderSide(color: s == current ? t.accent : t.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
          ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return AdminCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          IconHolder(icon: icon, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(subtitle, style: text.bodySmall),
              ],
            ),
          ),
          Icon(AppIcons.chevronRight, size: 18, color: t.faint),
        ],
      ),
    );
  }
}
