import 'package:flutter/material.dart';

import '../models/sale.dart';
import '../theme/app_theme.dart';
import '../utils/admin_analytics.dart';

/// What the admin records when the client pays.
class ClientPayment {
  const ClientPayment({required this.amountReceivedPkr, required this.removalCostPkr, this.method});

  final double amountReceivedPkr;
  final double removalCostPkr;
  final String? method;
}

const _methods = ['Bank transfer', 'Wise', 'PayPal', 'Cash', 'Other'];

/// Bottom sheet shown at the last step of the process: the client has paid,
/// so capture how much arrived (PKR), how, and what the removal cost — the
/// figures profit is calculated from. Returns null when dismissed.
Future<ClientPayment?> showClientPaymentSheet(BuildContext context, {required Sale sale}) {
  return showModalBottomSheet<ClientPayment>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PaymentSheet(sale: sale),
  );
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.sale});

  final Sale sale;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _received;
  late final TextEditingController _removal;
  String? _method;

  @override
  void initState() {
    super.initState();
    String number(double v) => v == 0 ? '' : (v == v.roundToDouble() ? v.round().toString() : v.toString());
    _received = TextEditingController(text: number(widget.sale.clientAmountReceived));
    _removal = TextEditingController(text: number(widget.sale.removalCost));
    final existing = widget.sale.clientPaymentMethod;
    _method = existing != null && existing.isNotEmpty ? existing : null;
  }

  @override
  void dispose() {
    _received.dispose();
    _removal.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;

  String? _amount(String? v, {required bool required}) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return required ? 'Enter the amount received' : null;
    final n = double.tryParse(text.replaceAll(',', ''));
    if (n == null || n < 0) return 'Enter a valid amount';
    if (required && n == 0) return 'Enter the amount received';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final profit = _num(_received) - _num(_removal) - widget.sale.employeePaymentAmount;
    final methods = {..._methods, ?_method};

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('Client payment received', style: text.headlineSmall),
            const SizedBox(height: 4),
            Text('${widget.sale.businessName} — completing this deal makes the salesman payout due.', style: text.bodyMedium),
            const SizedBox(height: 20),
            TextFormField(
              controller: _received,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount received',
                prefixText: 'PKR ',
                helperText: widget.sale.priceChargedToClient > 0 ? 'Billed ${formatUsd(widget.sale.priceChargedToClient)}' : null,
              ),
              validator: (v) => _amount(v, required: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text('Paid by', style: text.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in methods)
                  ChoiceChip(
                    label: Text(m),
                    selected: _method == m,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _method = _method == m ? null : m),
                    selectedColor: t.accentTint,
                    backgroundColor: t.surface,
                    labelStyle: TextStyle(fontWeight: FontWeight.w600, color: _method == m ? t.accentTextStrong : t.subtle),
                    side: BorderSide(color: _method == m ? t.accent : t.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _removal,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Removal cost (optional)', prefixText: 'PKR '),
              validator: (v) => _amount(v, required: false),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: t.neutralTint, borderRadius: BorderRadius.circular(AppTheme.radius)),
              child: Row(
                children: [
                  Expanded(child: Text('Profit after payout and costs', style: text.bodyMedium)),
                  Text(
                    formatPkr(profit),
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: profit < 0 ? t.danger : t.sageText),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () {
                      if (!_formKey.currentState!.validate()) return;
                      Navigator.pop(
                        context,
                        ClientPayment(amountReceivedPkr: _num(_received), removalCostPkr: _num(_removal), method: _method),
                      );
                    },
                    child: const Text('Complete deal'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
