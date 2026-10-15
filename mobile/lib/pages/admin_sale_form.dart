import 'package:flutter/material.dart';

import '../models/client_record.dart';
import '../models/sale.dart';
import '../models/sales_user.dart';
import '../services/admin_data.dart';
import '../theme/app_theme.dart';
import '../utils/maps_url.dart';
import '../widgets/admin_widgets.dart';

/// Opens the add / edit order sheet. Returns the saved sale, or null when
/// dismissed. Pass [presetBusiness] / [presetSalesman] to pre-fill a new
/// order from a client or salesman page.
Future<Sale?> showAdminSaleForm(
  BuildContext context, {
  Sale? sale,
  String? presetBusiness,
  SalesUser? presetSalesman,
}) {
  final data = AdminScope.read(context);
  return showModalBottomSheet<Sale>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _SaleForm(data: data, sale: sale, presetBusiness: presetBusiness, presetSalesman: presetSalesman),
  );
}

class _SaleForm extends StatefulWidget {
  const _SaleForm({required this.data, this.sale, this.presetBusiness, this.presetSalesman});

  final AdminData data;
  final Sale? sale;
  final String? presetBusiness;
  final SalesUser? presetSalesman;

  @override
  State<_SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends State<_SaleForm> {
  final _formKey = GlobalKey<FormState>();
  final _focus = FocusNode();
  late final TextEditingController _business;
  late final TextEditingController _mapsUrl;
  late final TextEditingController _payout;
  late final TextEditingController _price;
  late final TextEditingController _received;
  late final TextEditingController _removal;
  late final TextEditingController _method;
  late SaleStatus _status;
  late EmployeePaymentStatus _payoutStatus;
  late ClientPaymentStatus _clientStatus;
  String? _salesmanId;
  bool _saving = false;

  Sale? get _editing => widget.sale;

  @override
  void initState() {
    super.initState();
    final s = widget.sale;
    String number(double? v) => (v == null || v == 0) ? '' : (v == v.roundToDouble() ? v.round().toString() : v.toString());
    _business = TextEditingController(text: s?.businessName ?? widget.presetBusiness ?? '');
    _mapsUrl = TextEditingController();
    _business.addListener(_onBusinessChanged);
    _payout = TextEditingController(text: number(s?.employeePaymentAmount));
    _price = TextEditingController(text: number(s?.priceChargedToClient));
    _received = TextEditingController(text: number(s?.clientAmountReceived));
    _removal = TextEditingController(text: number(s?.removalCost));
    _method = TextEditingController(text: s?.clientPaymentMethod ?? '');
    _status = s?.status ?? SaleStatus.newSale;
    _payoutStatus = s?.employeePaymentStatus ?? EmployeePaymentStatus.pending;
    _clientStatus = s?.clientPaymentStatus ?? ClientPaymentStatus.pending;
    _salesmanId = s?.salesmanId ?? widget.presetSalesman?.id;
  }

  /// The stored client the typed name refers to, if any.
  ClientRecord? get _matchedClient {
    final key = clientNameKey(_business.text);
    if (key.isEmpty) return null;
    for (final c in widget.data.snapshot.clientRecords) {
      if (clientNameKey(c.name) == key) return c;
    }
    return null;
  }

  /// A link is asked for only when the client has none stored yet.
  bool get _needsMapsUrl => _business.text.trim().isNotEmpty && _matchedClient?.hasMapsUrl != true;

  void _onBusinessChanged() => setState(() {});

  @override
  void dispose() {
    _business.removeListener(_onBusinessChanged);
    _focus.dispose();
    for (final c in [_business, _mapsUrl, _payout, _price, _received, _removal, _method]) {
      c.dispose();
    }
    super.dispose();
  }

  List<SalesUser> get _assignable =>
      widget.data.snapshot.users.where((u) => u.role != 'admin' && (u.approved || u.id == _salesmanId)).toList();

  double _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;

  String? _validateAmount(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim().replaceAll(',', ''));
    if (n == null || n < 0) return 'Enter a valid amount';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final salesman = _assignable.where((u) => u.id == _salesmanId).firstOrNull;
    final name = _business.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final matched = _matchedClient;
    final body = <String, dynamic>{
      'businessName': name,
      'salesmanId': salesman?.id,
      'salesmanName': salesman?.name,
      'leadStatus': _status.json,
      'employeePaymentAmount': _num(_payout),
      'employeePaymentStatus': _payoutStatus.name,
      'priceChargedToClient': _num(_price),
      'clientPaymentStatus': _clientStatus.json,
      'clientAmountReceived': _num(_received),
      'removalCost': _num(_removal),
      'clientPaymentMethod': _method.text.trim(),
    };
    setState(() => _saving = true);
    try {
      // A client is its name + Google Maps link: make sure both exist first.
      var client = matched;
      if (client == null || !client.hasMapsUrl) {
        final url = normalizeMapsUrl(_mapsUrl.text)!;
        client = client == null
            ? await widget.data.addClient(name: name, mapsUrl: url)
            : await widget.data.editClient(client.id, mapsUrl: url);
      }
      body
        ..['businessName'] = client.name
        ..['clientId'] = client.id
        ..['reviewLink'] = client.mapsUrl;
      final saved = _editing == null
          ? await widget.data.createSale(body)
          : await widget.data.updateSale(_editing!.id, body);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAdminError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isNew = _editing == null;
    final clientNames = widget.data.snapshot.clients.map((c) => c.name).toList();
    final assignable = _assignable;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(isNew ? 'New sale' : 'Edit sale', style: text.headlineSmall),
            const SizedBox(height: 4),
            Text(isNew ? 'Record an order for a client business.' : 'Update the order, its payout and billing.', style: text.bodyMedium),
            const SizedBox(height: 20),
            _SectionLabel('Order'),
            RawAutocomplete<String>(
              textEditingController: _business,
              focusNode: _focus,
              optionsBuilder: (value) {
                final q = value.text.trim().toLowerCase();
                if (q.isEmpty) return const Iterable<String>.empty();
                return clientNames.where((n) => n.toLowerCase().contains(q) && n.toLowerCase() != q).take(5);
              },
              fieldViewBuilder: (context, controller, focusNode, _) => TextFormField(
                controller: controller,
                focusNode: focusNode,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Client business', hintText: 'Search or type a new name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the business name' : null,
              ),
              optionsViewBuilder: (context, onSelected, options) {
                final t = context.tokens;
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: t.surface,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radius), side: BorderSide(color: t.border)),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220, maxWidth: 480),
                      child: ListView(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: [
                          for (final o in options) ListTile(dense: true, title: Text(o), onTap: () => onSelected(o)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              initialValue: assignable.any((u) => u.id == _salesmanId) ? _salesmanId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Salesman'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
                for (final u in assignable) DropdownMenuItem<String?>(value: u.id, child: Text(u.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _salesmanId = v),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<SaleStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Stage'),
              items: [for (final s in SaleStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            const SizedBox(height: 14),
            if (_needsMapsUrl) ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _mapsUrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Google Maps link',
                  hintText: 'https://maps.app.goo.gl/…',
                  helperText: _matchedClient == null ? 'New client — paste its Google Maps link' : 'This client has no link yet',
                ),
                validator: (v) {
                  if ((v ?? '').trim().isEmpty) return 'Paste the Google Maps link';
                  return normalizeMapsUrl(v) == null ? 'That is not a Google Maps link' : null;
                },
              ),
            ] else if (_matchedClient != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(AppIcons.mapPin, size: 15, color: context.tokens.sageText),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Existing client · Google Maps link saved', style: text.bodySmall)),
                ],
              ),
            ],
            _SectionLabel('Salesman payout'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _payout,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount', prefixText: 'PKR '),
                    validator: _validateAmount,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<EmployeePaymentStatus>(
                    initialValue: _payoutStatus,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [for (final p in EmployeePaymentStatus.values) DropdownMenuItem(value: p, child: Text(p.label))],
                    onChanged: (v) => setState(() => _payoutStatus = v ?? _payoutStatus),
                  ),
                ),
              ],
            ),
            _SectionLabel('Client billing'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Price charged', prefixText: '\$ '),
                    validator: _validateAmount,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<ClientPaymentStatus>(
                    initialValue: _clientStatus,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Payment'),
                    items: [for (final c in ClientPaymentStatus.values) DropdownMenuItem(value: c, child: Text(c.label))],
                    onChanged: (v) => setState(() => _clientStatus = v ?? _clientStatus),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _received,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Received', prefixText: 'PKR '),
                    validator: _validateAmount,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _removal,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Removal cost', prefixText: 'PKR '),
                    validator: _validateAmount,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _method,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Paid by (optional)', hintText: 'Bank transfer, Wise, PayPal…'),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(isNew ? 'Add sale' : 'Save changes'),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Text(label.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: t.faint)),
    );
  }
}
