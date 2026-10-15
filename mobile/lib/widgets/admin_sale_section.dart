import 'package:flutter/material.dart';

import '../models/sale.dart';
import '../pages/admin_sale_detail_page.dart';
import 'admin_sale_tile.dart';
import 'admin_widgets.dart';
import 'segmented_tab_bar.dart';

/// The orders of one salesman or client split into Ongoing / Completed /
/// Cancelled. Not scrollable itself — place it inside a parent list.
class AdminSaleSection extends StatefulWidget {
  const AdminSaleSection({super.key, required this.sales, this.showClient = true, this.showSalesman = true});

  final List<Sale> sales;
  final bool showClient;
  final bool showSalesman;

  @override
  State<AdminSaleSection> createState() => _AdminSaleSectionState();
}

class _AdminSaleSectionState extends State<AdminSaleSection> with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(length: 3, vsync: this)..addListener(_onTab);

  void _onTab() {
    if (!_controller.indexIsChanging) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTab)
      ..dispose();
    super.dispose();
  }

  List<Sale> _newestFirst(Iterable<Sale> sales) {
    final list = sales.toList();
    list.sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final ongoing = _newestFirst(widget.sales.where((s) => s.status.isOngoing));
    final completed = _newestFirst(widget.sales.where((s) => s.status == SaleStatus.completed));
    final cancelled = _newestFirst(widget.sales.where((s) => s.status == SaleStatus.cancelled));
    final shown = [ongoing, completed, cancelled][_controller.index];
    const emptyText = [
      ('Nothing in progress', 'New and in-progress orders show up here.'),
      ('No completed sales yet', 'Orders appear here once they are delivered.'),
      ('No cancelled orders', 'Cancelled orders are listed here.'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedTabBar(
          controller: _controller,
          labels: ['Ongoing ${ongoing.length}', 'Completed ${completed.length}', 'Cancelled ${cancelled.length}'],
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: AdminCard(
              child: Column(
                children: [
                  Text(emptyText[_controller.index].$1, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(emptyText[_controller.index].$2, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                ],
              ),
            ),
          )
        else
          for (final s in shown) ...[
            AdminSaleTile(
              sale: s,
              showClient: widget.showClient,
              showSalesman: widget.showSalesman,
              onTap: () => pushAdminPage(context, AdminSaleDetailPage(saleId: s.id)),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}
