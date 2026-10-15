import 'package:flutter/material.dart';

import '../models/sale.dart';
import '../services/admin_data.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_sale_tile.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/page_header.dart';
import '../widgets/search_field.dart';
import '../widgets/segmented_tab_bar.dart';
import 'admin_sale_detail_page.dart';
import 'admin_sale_form.dart';

/// Every order in the business, split into Ongoing / Completed / Cancelled,
/// searchable and filterable by salesman. Add a sale from here.
class AdminSalesPage extends StatefulWidget {
  const AdminSalesPage({super.key});

  @override
  State<AdminSalesPage> createState() => _AdminSalesPageState();
}

class _AdminSalesPageState extends State<AdminSalesPage> with SingleTickerProviderStateMixin {
  static const _unassigned = '__unassigned__';

  late final TabController _tabs = TabController(length: 3, vsync: this)..addListener(_onTab);
  final _search = TextEditingController();
  String _query = '';
  String? _salesmanFilter; // a user id, _unassigned, or null for everyone

  void _onTab() {
    if (!_tabs.indexIsChanging) setState(() {});
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTab)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  bool _matches(Sale s) {
    if (_salesmanFilter == _unassigned) {
      if (s.salesmanId != null || (s.salesmanName ?? '').trim().isNotEmpty) return false;
    } else if (_salesmanFilter != null && s.salesmanId != _salesmanFilter) {
      return false;
    }
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return s.businessName.toLowerCase().contains(q) || (s.salesmanName ?? '').toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final data = AdminScope.of(context);
    return Stack(
      children: [
        SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(title: 'Sales', subtitle: 'Track every order from new to completed'),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: SearchField(
                  controller: _search,
                  value: _query,
                  hintText: 'Search client or salesman',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(child: AdminLoadGate(builder: (context, d) => _content(context, d))),
            ],
          ),
        ),
        Positioned(
          right: 20,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'admin-add-sale',
            onPressed: data.loadedOnce ? () => showAdminSaleForm(context) : null,
            icon: const Icon(AppIcons.plus),
            label: const Text('Add sale'),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, AdminData data) {
    final snap = data.snapshot;
    final scoped = snap.sales.where(_matches).toList();
    final ongoing = scoped.where((s) => s.status.isOngoing).toList();
    final completed = scoped.where((s) => s.status == SaleStatus.completed).toList();
    final cancelled = scoped.where((s) => s.status == SaleStatus.cancelled).toList();
    final shown = [ongoing, completed, cancelled][_tabs.index];
    final salesmen = snap.users.where((u) => u.role != 'admin').toList();
    final hasUnassigned = snap.unassigned.isNotEmpty;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
      children: [
        SegmentedTabBar(
          controller: _tabs,
          labels: ['Ongoing ${ongoing.length}', 'Completed ${completed.length}', 'Cancelled ${cancelled.length}'],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(label: 'Everyone', selected: _salesmanFilter == null, onTap: () => setState(() => _salesmanFilter = null)),
              if (hasUnassigned)
                _FilterChip(label: 'Unassigned', selected: _salesmanFilter == _unassigned, onTap: () => setState(() => _salesmanFilter = _unassigned)),
              for (final u in salesmen)
                _FilterChip(label: u.name, selected: _salesmanFilter == u.id, onTap: () => setState(() => _salesmanFilter = u.id)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (shown.isEmpty)
          EmptyState(
            icon: snap.sales.isEmpty ? AppIcons.clipboardList : AppIcons.searchX,
            title: snap.sales.isEmpty ? 'No sales yet' : 'Nothing here',
            message: snap.sales.isEmpty
                ? 'Add the first sale with the button below.'
                : (_query.isNotEmpty || _salesmanFilter != null)
                    ? 'No ${['ongoing', 'completed', 'cancelled'][_tabs.index]} sales match your filters.'
                    : 'No ${['ongoing', 'completed', 'cancelled'][_tabs.index]} sales.',
          )
        else
          for (final s in shown) ...[
            AdminSaleTile(sale: s, onTap: () => pushAdminPage(context, AdminSaleDetailPage(saleId: s.id))),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        selectedColor: t.accentTint,
        backgroundColor: t.surface,
        labelStyle: TextStyle(fontWeight: FontWeight.w600, color: selected ? t.accentTextStrong : t.subtle),
        side: BorderSide(color: selected ? t.accent : t.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
      ),
    );
  }
}
