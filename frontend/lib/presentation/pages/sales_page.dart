import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/sales_user.dart';
import '../../domain/repositories/lead_repository.dart';

const _allSalesmen = 'All salesmen';

String money(double value) {
  final isNegative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${isNegative ? '-' : ''}\$$buffer.${parts[1]}';
}

(Color, Color, IconData) statusStyle(SaleStatus status) {
  switch (status) {
    case SaleStatus.orderPlaced:
      return (AppTheme.neutral600, AppTheme.neutral100, AppIcons.clock);
    case SaleStatus.clientPaid:
      return (AppTheme.sage700, AppTheme.sage100, AppIcons.checkCircle);
    case SaleStatus.paymentPendingPaypal:
      return (AppTheme.accent700, AppTheme.accent100, AppIcons.alert);
    case SaleStatus.completed:
      return (AppTheme.sage800, AppTheme.sage100, AppIcons.shieldCheck);
  }
}

/// Full CRUD for sale records: a business that converted into a paying
/// client, who sold it, and where the payment stands. Feeds the Sales
/// Dashboard's statistics — every field here is what gets aggregated there.
class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  List<Sale> _sales = [];
  List<SalesUser> _salesmen = [];
  bool _loading = true;
  String? _error;
  String _filterSalesmanId = _allSalesmen;

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _load();
    _loadSalesmen();
  }

  Future<void> _loadSalesmen() async {
    try {
      final salesmen = await _repo.listSalesmen();
      if (!mounted) return;
      setState(() => _salesmen = salesmen);
    } catch (_) {
      // Non-critical — the form just won't offer assignment.
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sales = await _repo.listSales(
        salesmanId: _filterSalesmanId == _allSalesmen ? null : _filterSalesmanId,
      );
      if (!mounted) return;
      setState(() {
        _sales = sales;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openForm({Sale? existing}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _SaleFormDialog(sale: existing, salesmen: _salesmen),
    );
    if (result == true) await _load();
  }

  Future<void> _delete(Sale sale) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this sale?'),
        content: Text('"${sale.businessName}" will be permanently removed. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _repo.deleteSale(sale.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales'),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: AppTheme.neutral100, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _filterSalesmanId,
                icon: const Icon(AppIcons.chevronDown, size: 16, color: AppTheme.subtle),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.ink),
                items: [
                  const DropdownMenuItem(value: _allSalesmen, child: Text(_allSalesmen)),
                  for (final s in _salesmen) DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _filterSalesmanId = v);
                  _load();
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(AppIcons.plus, size: 18),
            label: const Text('New Sale'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.danger)))
                    : _sales.isEmpty
                        ? _EmptyState(onAdd: () => _openForm())
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                            children: [
                              for (final sale in _sales)
                                _SaleCard(
                                  sale: sale,
                                  onEdit: () => _openForm(existing: sale),
                                  onDelete: () => _delete(sale),
                                ),
                            ],
                          ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: AppTheme.accent100, shape: BoxShape.circle),
              child: const Icon(AppIcons.award, size: 30, color: AppTheme.accent700),
            ),
            const SizedBox(height: 16),
            Text('No sales recorded yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Log a converted business — who sold it, what it\'s worth, and where payment stands.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: onAdd, icon: const Icon(AppIcons.plus, size: 18), label: const Text('New Sale')),
          ],
        ),
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.sale, required this.onEdit, required this.onDelete});

  final Sale sale;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final (color, bg, icon) = statusStyle(sale.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sale.businessName, style: Theme.of(context).textTheme.titleMedium),
                    if (sale.reviewLink != null && sale.reviewLink!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => launchUrl(Uri.parse(sale.reviewLink!)),
                        child: Text(
                          sale.reviewLink!,
                          style: const TextStyle(color: AppTheme.faint, fontSize: 12, decoration: TextDecoration.underline),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(onPressed: onEdit, icon: const Icon(AppIcons.copy, size: 17, color: AppTheme.faint)),
              IconButton(onPressed: onDelete, icon: const Icon(AppIcons.trash, size: 17, color: AppTheme.faint)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 13, color: color),
                    const SizedBox(width: 5),
                    Text(sale.status.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                  ],
                ),
              ),
              _InfoChip(icon: AppIcons.users, label: sale.salesmanName ?? 'Unassigned'),
              _InfoChip(icon: AppIcons.tag, label: '${money(sale.price)} price'),
              _InfoChip(icon: AppIcons.tag, label: '${money(sale.salesmanPrice)} to salesman'),
              _InfoChip(icon: AppIcons.trendingUp, label: '${money(sale.profit)} profit'),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppTheme.neutral100, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.subtle),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.subtle)),
        ],
      ),
    );
  }
}

class _SaleFormDialog extends StatefulWidget {
  const _SaleFormDialog({this.sale, required this.salesmen});

  final Sale? sale;
  final List<SalesUser> salesmen;

  @override
  State<_SaleFormDialog> createState() => _SaleFormDialogState();
}

class _SaleFormDialogState extends State<_SaleFormDialog> {
  late final _businessController = TextEditingController(text: widget.sale?.businessName ?? '');
  late final _linkController = TextEditingController(text: widget.sale?.reviewLink ?? '');
  late final _priceController = TextEditingController(text: widget.sale == null ? '' : widget.sale!.price.toStringAsFixed(2));
  late final _salesmanPriceController =
      TextEditingController(text: widget.sale == null ? '' : widget.sale!.salesmanPrice.toStringAsFixed(2));
  String? _salesmanId;
  late SaleStatus _status = widget.sale?.status ?? SaleStatus.orderPlaced;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _salesmanId = widget.sale?.salesmanId;
  }

  @override
  void dispose() {
    _businessController.dispose();
    _linkController.dispose();
    _priceController.dispose();
    _salesmanPriceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final businessName = _businessController.text.trim();
    if (businessName.isEmpty) {
      setState(() => _error = 'Business name is required');
      return;
    }
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    final salesmanPrice = double.tryParse(_salesmanPriceController.text.trim()) ?? 0;
    final salesman = widget.salesmen.where((s) => s.id == _salesmanId).firstOrNull;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = context.read<LeadRepository>();
      if (widget.sale == null) {
        await repo.createSale(
          businessName: businessName,
          reviewLink: _linkController.text.trim().isEmpty ? null : _linkController.text.trim(),
          salesmanId: salesman?.id,
          salesmanName: salesman?.name,
          price: price,
          salesmanPrice: salesmanPrice,
          status: _status,
        );
      } else {
        await repo.updateSale(
          widget.sale!.id,
          businessName: businessName,
          reviewLink: _linkController.text.trim().isEmpty ? null : _linkController.text.trim(),
          salesmanId: salesman?.id,
          salesmanName: salesman?.name,
          price: price,
          salesmanPrice: salesmanPrice,
          status: _status,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.sale == null ? 'New Sale' : 'Edit Sale'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _businessController,
                decoration: const InputDecoration(labelText: 'Business name'),
                enabled: !_saving,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _linkController,
                decoration: const InputDecoration(labelText: 'Review link', hintText: 'https://...'),
                enabled: !_saving,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _salesmanId,
                decoration: const InputDecoration(labelText: 'Salesman'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
                  for (final s in widget.salesmen) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: _saving ? null : (v) => setState(() => _salesmanId = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      decoration: const InputDecoration(labelText: 'Price', prefixText: '\$'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_saving,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _salesmanPriceController,
                      decoration: const InputDecoration(labelText: 'Salesman price', prefixText: '\$'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_saving,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SaleStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [for (final s in SaleStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
                onChanged: _saving ? null : (v) => setState(() => _status = v ?? _status),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12.5)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.surface))
              : Text(widget.sale == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}
