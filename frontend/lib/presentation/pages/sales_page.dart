import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/sales_user.dart';
import '../../domain/repositories/lead_repository.dart';

const _allSalesmen = 'All salesmen';

String _formatAmount(double value) {
  final isNegative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${isNegative ? '-' : ''}$buffer.${parts[1]}';
}

/// USD — what clients are billed.
String usd(double value) => '\$${_formatAmount(value)}';

/// PKR — everything on the operations side (employee payout, client amount
/// actually received after conversion, removal cost, profit). Deliberately
/// a different formatter from [usd] so the two currencies are never
/// visually confusable, let alone summed together.
String pkr(double value) => 'PKR ${_formatAmount(value)}';

(Color, Color, IconData) leadStatusStyle(LeadStatus status) {
  switch (status) {
    case LeadStatus.newLead:
      return (AppTheme.neutral600, AppTheme.neutral100, AppIcons.sparkles);
    case LeadStatus.inProgress:
      return (AppTheme.accent700, AppTheme.accent100, AppIcons.zap);
    case LeadStatus.completed:
      return (AppTheme.sage800, AppTheme.sage100, AppIcons.shieldCheck);
    case LeadStatus.cancelled:
      return (AppTheme.neutral600, AppTheme.neutral100, AppIcons.close);
  }
}

(Color, Color) clientPaymentStyle(ClientPaymentStatus status) {
  switch (status) {
    case ClientPaymentStatus.pending:
      return (AppTheme.neutral600, AppTheme.neutral100);
    case ClientPaymentStatus.paid:
    case ClientPaymentStatus.received:
      return (AppTheme.sage700, AppTheme.sage100);
    case ClientPaymentStatus.stuck:
      return (AppTheme.danger, AppTheme.accent100);
    case ClientPaymentStatus.inProcess:
      return (AppTheme.accent700, AppTheme.accent100);
  }
}

(Color, Color) employeePaymentStyle(EmployeePaymentStatus status) {
  return status == EmployeePaymentStatus.paid
      ? (AppTheme.sage700, AppTheme.sage100)
      : (AppTheme.neutral600, AppTheme.neutral100);
}

/// Sales hub: an "Overview" tab (rollup statistics — USD revenue, PKR
/// profit/costs, a lead-status funnel, payment-status breakdowns, a
/// per-salesman leaderboard) and a "Manage" tab (full CRUD on individual
/// sale records — client billing in USD, employee payout/costs in PKR,
/// three independent status tracks). One shared salesman filter drives
/// both tabs at once.
class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);
  List<SalesUser> _salesmen = [];
  bool _loadingSalesmen = true;
  String? _salesmenError;
  String _filterSalesmanId = _allSalesmen;

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _loadSalesmen();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSalesmen() async {
    setState(() {
      _loadingSalesmen = true;
      _salesmenError = null;
    });
    try {
      final salesmen = await _repo.listSalesmen();
      if (!mounted) return;
      setState(() {
        _salesmen = salesmen;
        _loadingSalesmen = false;
      });
    } catch (e) {
      // Surfaced (not swallowed) — an empty "assign to salesman" dropdown
      // with no explanation is impossible to debug from the UI alone.
      if (!mounted) return;
      setState(() {
        _loadingSalesmen = false;
        _salesmenError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final salesmanId = _filterSalesmanId == _allSalesmen ? null : _filterSalesmanId;
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
                  if (v != null) setState(() => _filterSalesmanId = v);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Overview'), Tab(text: 'Manage'), Tab(text: 'Team')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OverviewTab(salesmanId: salesmanId),
          _ManageTab(
            salesmanId: salesmanId,
            salesmen: _salesmen,
            salesmenError: _salesmenError,
            onRetryLoadSalesmen: _loadSalesmen,
          ),
          _TeamTab(
            salesmen: _salesmen,
            loading: _loadingSalesmen,
            error: _salesmenError,
            onRetry: _loadSalesmen,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview tab
// ---------------------------------------------------------------------------

class _OverviewTab extends StatefulWidget {
  const _OverviewTab({required this.salesmanId});

  final String? salesmanId;

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  SalesStats? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _OverviewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.salesmanId != widget.salesmanId) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stats = await context.read<LeadRepository>().getSalesStats(salesmanId: widget.salesmanId);
      if (!mounted) return;
      setState(() {
        _stats = stats;
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

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final filtered = widget.salesmanId != null;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: AppTheme.danger)),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: _load, icon: const Icon(AppIcons.refresh, size: 18), label: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (stats == null || stats.totalSales == 0) return const _EmptyStatsState();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          sliver: SliverList.list(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _KpiRow(stats: stats),
                      const SizedBox(height: 24),
                      _LeadStatusFunnelCard(stats: stats),
                      const SizedBox(height: 24),
                      _PaymentStatusCard(stats: stats),
                      if (!filtered && stats.bySalesman.length > 1) ...[
                        const SizedBox(height: 24),
                        _LeaderboardCard(salesmen: stats.bySalesman),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyStatsState extends StatelessWidget {
  const _EmptyStatsState();

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
              child: const Icon(AppIcons.trendingUp, size: 30, color: AppTheme.accent700),
            ),
            const SizedBox(height: 16),
            Text('No sales data yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Statistics show up here once sales are logged on the Manage tab.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.stats});

  final SalesStats stats;

  @override
  Widget build(BuildContext context) {
    final completedCount = stats.byLeadStatus[LeadStatus.completed]?.count ?? 0;
    final completionRate = stats.totalSales > 0 ? (completedCount / stats.totalSales * 100).round() : 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 5
            : constraints.maxWidth >= 560
                ? 3
                : 2;
        final tiles = [
          _KpiTile('Total Sales', '${stats.totalSales}', AppIcons.tag, AppTheme.accent700, AppTheme.accent100),
          _KpiTile('Revenue (client)', usd(stats.totalRevenueUsd), AppIcons.trendingUp, AppTheme.sage700, AppTheme.sage100),
          _KpiTile('Profit (PKR)', pkr(stats.totalProfitPkr), AppIcons.award, AppTheme.sage800, AppTheme.sage100),
          _KpiTile('Employee Payout', pkr(stats.totalEmployeePayoutPkr), AppIcons.users, AppTheme.subtle, AppTheme.neutral100),
          _KpiTile('Completion Rate', '$completionRate%', AppIcons.shieldCheck, AppTheme.accent700, AppTheme.accent100),
        ];
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tiles.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 100,
          ),
          itemBuilder: (context, i) => tiles[i],
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile(this.label, this.value, this.icon, this.color, this.background);

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: background, shape: BoxShape.circle),
            child: Icon(icon, size: 15, color: color),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppTheme.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.faint), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Deal-stage funnel — bar length encodes count. Every status pairs its
/// color with an icon + label (never color alone), matching the rest of
/// this app's muted palette, which doesn't clear strict CVD-separation on
/// its own.
class _LeadStatusFunnelCard extends StatelessWidget {
  const _LeadStatusFunnelCard({required this.stats});

  final SalesStats stats;

  @override
  Widget build(BuildContext context) {
    final maxCount = LeadStatus.values.fold<int>(
      1,
      (m, s) => (stats.byLeadStatus[s]?.count ?? 0) > m ? stats.byLeadStatus[s]!.count : m,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.barChart, size: 16, color: AppTheme.accent700),
              const SizedBox(width: 8),
              Text('Leads by stage', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 18),
          for (final status in LeadStatus.values)
            _CountBarRow(
              label: status.label,
              count: stats.byLeadStatus[status]?.count ?? 0,
              maxCount: maxCount,
              style: leadStatusStyle(status),
            ),
        ],
      ),
    );
  }
}

class _CountBarRow extends StatelessWidget {
  const _CountBarRow({required this.label, required this.count, required this.maxCount, required this.style});

  final String label;
  final int count;
  final int maxCount;
  final (Color, Color, IconData) style;

  @override
  Widget build(BuildContext context) {
    final (color, _, icon) = style;
    final fraction = maxCount > 0 ? count / maxCount : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Row(
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 14,
                      width: constraints.maxWidth,
                      decoration: BoxDecoration(color: AppTheme.neutral100, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      height: 14,
                      width: constraints.maxWidth * fraction,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 30,
            child: Text('$count', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.ink)),
          ),
        ],
      ),
    );
  }
}

/// Two compact side-by-side status breakdowns — client payment (USD side)
/// and employee payment (PKR side) — as chip grids rather than full bar
/// charts, since these are secondary to the lead-stage funnel above.
class _PaymentStatusCard extends StatelessWidget {
  const _PaymentStatusCard({required this.stats});

  final SalesStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.tag, size: 16, color: AppTheme.accent700),
              const SizedBox(width: 8),
              Text('Payment status', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 16),
          Text('Client payment (USD)', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.faint)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final status in ClientPaymentStatus.values)
                _StatusChip(
                  label: '${status.label}: ${stats.byClientPaymentStatus[status]?.count ?? 0}',
                  colors: clientPaymentStyle(status),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Employee payment (PKR)', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.faint)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final status in EmployeePaymentStatus.values)
                _StatusChip(
                  label: '${status.label}: ${stats.byEmployeePaymentStatus[status]?.count ?? 0}',
                  colors: employeePaymentStyle(status),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.colors});

  final String label;
  final (Color, Color) colors;

  @override
  Widget build(BuildContext context) {
    final (color, bg) = colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({required this.salesmen});

  final List<SalesmanBreakdown> salesmen;

  @override
  Widget build(BuildContext context) {
    final maxRevenue = salesmen.fold<double>(1, (m, s) => s.revenueUsd > m ? s.revenueUsd : m);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.award, size: 16, color: AppTheme.accent700),
              const SizedBox(width: 8),
              Text('Salesman leaderboard', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Ranked by client revenue (USD). Bar length is revenue — a single hue, since this compares one measure across people, not identity.',
            style: TextStyle(fontSize: 11.5, color: AppTheme.faint),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < salesmen.length; i++) _LeaderboardRow(rank: i + 1, entry: salesmen[i], maxRevenue: maxRevenue),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.rank, required this.entry, required this.maxRevenue});

  final int rank;
  final SalesmanBreakdown entry;
  final double maxRevenue;

  @override
  Widget build(BuildContext context) {
    final fraction = maxRevenue > 0 ? entry.revenueUsd / maxRevenue : 0.0;
    final completionRate = entry.count > 0 ? (entry.completedCount / entry.count * 100).round() : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 22,
                child: Text('#$rank', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.faint)),
              ),
              Expanded(
                child: Text(entry.salesmanName, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.ink)),
              ),
              Text(
                '${entry.count} sale${entry.count == 1 ? '' : 's'} · $completionRate% completed · ${pkr(entry.profitPkr)} profit',
                style: const TextStyle(fontSize: 11.5, color: AppTheme.faint),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 90,
                child: Text(
                  usd(entry.revenueUsd),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 8,
                    width: constraints.maxWidth,
                    decoration: BoxDecoration(color: AppTheme.neutral100, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    height: 8,
                    width: constraints.maxWidth * fraction,
                    decoration: BoxDecoration(color: AppTheme.accent500, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manage tab
// ---------------------------------------------------------------------------

class _ManageTab extends StatefulWidget {
  const _ManageTab({
    required this.salesmanId,
    required this.salesmen,
    this.salesmenError,
    required this.onRetryLoadSalesmen,
  });

  final String? salesmanId;
  final List<SalesUser> salesmen;
  final String? salesmenError;
  final VoidCallback onRetryLoadSalesmen;

  @override
  State<_ManageTab> createState() => _ManageTabState();
}

class _ManageTabState extends State<_ManageTab> {
  List<Sale> _sales = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ManageTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.salesmanId != widget.salesmanId) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sales = await context.read<LeadRepository>().listSales(salesmanId: widget.salesmanId);
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
      builder: (_) => _SaleFormDialog(sale: existing, salesmen: widget.salesmen),
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
      await context.read<LeadRepository>().deleteSale(sale.id);
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.danger)))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    children: [
                      if (widget.salesmenError != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(color: AppTheme.accent100, borderRadius: BorderRadius.circular(AppTheme.radius)),
                          child: Row(
                            children: [
                              const Icon(AppIcons.alert, size: 16, color: AppTheme.accent700),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Couldn\'t load salesmen — the "assign to" dropdown will be empty. ${widget.salesmenError}',
                                  style: const TextStyle(fontSize: 12.5, color: AppTheme.accent700, fontWeight: FontWeight.w600),
                                ),
                              ),
                              TextButton(onPressed: widget.onRetryLoadSalesmen, child: const Text('Retry')),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ] else if (widget.salesmen.isEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(color: AppTheme.neutral100, borderRadius: BorderRadius.circular(AppTheme.radius)),
                          child: const Row(
                            children: [
                              Icon(AppIcons.users, size: 16, color: AppTheme.subtle),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'No salesmen registered yet — sales can still be logged, just unassigned. Salesmen appear once someone signs into the mobile app.',
                                  style: TextStyle(fontSize: 12.5, color: AppTheme.subtle, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: () => _openForm(),
                          icon: const Icon(AppIcons.plus, size: 18),
                          label: const Text('New Sale'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_sales.isEmpty)
                        const _EmptySalesState()
                      else
                        for (final sale in _sales)
                          _SaleCard(
                            sale: sale,
                            onEdit: () => _openForm(existing: sale),
                            onDelete: () => _delete(sale),
                          ),
                    ],
                  ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team tab
// ---------------------------------------------------------------------------

/// Every salesman (mobile app account, role `salesman` — see
/// mobile/lib/services/auth_service.dart) available to assign sales to.
/// Read-only: the roster grows automatically as people sign into the
/// mobile app, there's nothing to manage here beyond visibility into who's
/// actually registered — useful on its own, and to sanity-check why the
/// "assign to" dropdown might be empty.
class _TeamTab extends StatelessWidget {
  const _TeamTab({required this.salesmen, required this.loading, this.error, required this.onRetry});

  final List<SalesUser> salesmen;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, style: const TextStyle(color: AppTheme.danger), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(AppIcons.refresh, size: 18), label: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (salesmen.isEmpty) {
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
                child: const Icon(AppIcons.users, size: 30, color: AppTheme.accent700),
              ),
              const SizedBox(height: 16),
              Text('No salesmen yet', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              const Text(
                'Salesmen appear here automatically once someone signs into the mobile app — nothing to set up.',
                style: TextStyle(fontSize: 13, color: AppTheme.faint),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            Text(
              '${salesmen.length} salesm${salesmen.length == 1 ? 'an' : 'en'} registered',
              style: const TextStyle(fontSize: 12.5, color: AppTheme.faint, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final s in salesmen)
              _SalesmanCard(
                salesman: s,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => _SalesmanDetailPage(salesman: s)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SalesmanCard extends StatelessWidget {
  const _SalesmanCard({required this.salesman, required this.onTap});

  final SalesUser salesman;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.accent100,
                  backgroundImage: (salesman.photoURL != null && salesman.photoURL!.isNotEmpty)
                      ? NetworkImage(salesman.photoURL!)
                      : null,
                  child: (salesman.photoURL == null || salesman.photoURL!.isEmpty)
                      ? Text(
                          salesman.name.trim().isEmpty ? '?' : salesman.name.trim()[0].toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.accent700),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        salesman.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (salesman.email != null && salesman.email!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          salesman.email!,
                          style: const TextStyle(fontSize: 12, color: AppTheme.faint),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (salesman.lastLoginAt != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Active ${_timeAgo(salesman.lastLoginAt!)}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.faint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                const Icon(AppIcons.chevronRight, size: 16, color: AppTheme.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Salesman detail page
// ---------------------------------------------------------------------------

/// Per-salesman tallies computed client-side from their raw [Sale] list —
/// no separate backend endpoint, since [LeadRepository.listSales] already
/// supports filtering by `salesmanId` and this view only ever needs one
/// salesman's rows at a time.
class _SalesmanTally {
  _SalesmanTally(List<Sale> sales)
      : totalSales = sales.length,
        newCount = sales.where((s) => s.leadStatus == LeadStatus.newLead).length,
        inProgressCount = sales.where((s) => s.leadStatus == LeadStatus.inProgress).length,
        completedCount = sales.where((s) => s.leadStatus == LeadStatus.completed).length,
        cancelledCount = sales.where((s) => s.leadStatus == LeadStatus.cancelled).length,
        totalBilledUsd = sales.fold<double>(0, (a, s) => a + s.priceChargedToClient),
        amountOwed = sales
            .where((s) => s.employeePaymentStatus == EmployeePaymentStatus.pending)
            .fold<double>(0, (a, s) => a + s.employeePaymentAmount),
        amountPaid = sales
            .where((s) => s.employeePaymentStatus == EmployeePaymentStatus.paid)
            .fold<double>(0, (a, s) => a + s.employeePaymentAmount),
        totalClientReceived = sales.fold<double>(0, (a, s) => a + s.clientAmountReceived),
        totalRemovalCost = sales.fold<double>(0, (a, s) => a + s.removalCost),
        totalProfit = sales.fold<double>(0, (a, s) => a + s.profit),
        clientPendingCount = sales.where((s) => s.clientPaymentStatus == ClientPaymentStatus.pending).length,
        clientStuckCount = sales.where((s) => s.clientPaymentStatus == ClientPaymentStatus.stuck).length;

  final int totalSales;
  final int newCount;
  final int inProgressCount;
  final int completedCount;
  final int cancelledCount;
  final double totalBilledUsd;

  /// Employee payout still owed — sum of [Sale.employeePaymentAmount] where
  /// [EmployeePaymentStatus] is still pending.
  final double amountOwed;

  /// Employee payout already paid out.
  final double amountPaid;
  final double totalClientReceived;
  final double totalRemovalCost;
  final double totalProfit;
  final int clientPendingCount;
  final int clientStuckCount;
}

class _SalesmanDetailPage extends StatefulWidget {
  const _SalesmanDetailPage({required this.salesman});

  final SalesUser salesman;

  @override
  State<_SalesmanDetailPage> createState() => _SalesmanDetailPageState();
}

class _SalesmanDetailPageState extends State<_SalesmanDetailPage> with SingleTickerProviderStateMixin {
  List<Sale> _sales = [];
  bool _loading = true;
  String? _error;
  late final TabController _tabController = TabController(length: 3, vsync: this)..addListener(_onTabChanged);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  // Drives a plain filtered list below the TabBar (not a TabBarView) — this
  // whole page is one CustomScrollView, and a TabBarView needs its own
  // bounded height that doesn't play well nested inside another scroll
  // view. `indexIsChanging` skips the extra rebuild mid-swipe-free tap
  // animation; only the settled index matters here.
  void _onTabChanged() {
    if (!_tabController.indexIsChanging) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sales = await context.read<LeadRepository>().listSales(salesmanId: widget.salesman.id);
      if (!mounted) return;
      setState(() {
        _sales = sales;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.salesman.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: const TextStyle(color: AppTheme.danger), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(onPressed: _load, icon: const Icon(AppIcons.refresh, size: 18), label: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _sales.isEmpty
                  ? Center(
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
                            Text('No sales yet', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 6),
                            Text(
                              '${widget.salesman.name} isn\'t assigned to any sale yet.',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final tally = _SalesmanTally(_sales);
    final completionRate = tally.totalSales > 0 ? (tally.completedCount / tally.totalSales * 100).round() : 0;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          sliver: SliverList.list(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: AppTheme.accent100,
                            backgroundImage: (widget.salesman.photoURL != null && widget.salesman.photoURL!.isNotEmpty)
                                ? NetworkImage(widget.salesman.photoURL!)
                                : null,
                            child: (widget.salesman.photoURL == null || widget.salesman.photoURL!.isEmpty)
                                ? Text(
                                    widget.salesman.name.trim().isEmpty ? '?' : widget.salesman.name.trim()[0].toUpperCase(),
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.accent700),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.salesman.name,
                                  style: Theme.of(context).textTheme.titleLarge,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (widget.salesman.email != null && widget.salesman.email!.isNotEmpty)
                                  Text(
                                    widget.salesman.email!,
                                    style: const TextStyle(fontSize: 13, color: AppTheme.faint),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          if (widget.salesman.lastLoginAt != null) ...[
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'Active ${_timeAgo(widget.salesman.lastLoginAt!)}',
                                style: const TextStyle(fontSize: 12, color: AppTheme.faint),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SalesmanKpiRow(tally: tally, completionRate: completionRate),
                      const SizedBox(height: 24),
                      _PayoutCard(salesmanName: widget.salesman.name, tally: tally),
                      const SizedBox(height: 24),
                      _SalesmanFunnelCard(tally: tally),
                      const SizedBox(height: 24),
                      _SalesTabSection(controller: _tabController, sales: _sales),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Ongoing (new + in progress) / Completed / Cancelled, each with its own
/// count in the tab label — a plain `TabBar` driving a filtered list
/// underneath rather than a `TabBarView`, since this whole page is one
/// `CustomScrollView` and a `TabBarView` needs its own bounded height that
/// doesn't nest cleanly inside another scroll view.
class _SalesTabSection extends StatelessWidget {
  const _SalesTabSection({required this.controller, required this.sales});

  final TabController controller;
  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    final ongoing = sales.where((s) => s.leadStatus == LeadStatus.newLead || s.leadStatus == LeadStatus.inProgress).toList();
    final completed = sales.where((s) => s.leadStatus == LeadStatus.completed).toList();
    final cancelled = sales.where((s) => s.leadStatus == LeadStatus.cancelled).toList();
    final buckets = [ongoing, completed, cancelled];
    final selected = buckets[controller.index];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabBar(
            controller: controller,
            labelColor: AppTheme.accent700,
            unselectedLabelColor: AppTheme.faint,
            indicatorColor: AppTheme.accent500,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: [
              Tab(text: 'Ongoing (${ongoing.length})'),
              Tab(text: 'Completed (${completed.length})'),
              Tab(text: 'Cancelled (${cancelled.length})'),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: selected.isEmpty
                ? _EmptyTabState(label: const ['ongoing', 'completed', 'cancelled'][controller.index])
                : Column(children: [for (final sale in selected) _SaleCard(sale: sale)]),
          ),
        ],
      ),
    );
  }
}

class _EmptyTabState extends StatelessWidget {
  const _EmptyTabState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text('No $label sales.', style: const TextStyle(fontSize: 13, color: AppTheme.faint)),
      ),
    );
  }
}

class _SalesmanKpiRow extends StatelessWidget {
  const _SalesmanKpiRow({required this.tally, required this.completionRate});

  final _SalesmanTally tally;
  final int completionRate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 5
            : constraints.maxWidth >= 560
                ? 3
                : 2;
        final tiles = [
          _KpiTile('Total Sales', '${tally.totalSales}', AppIcons.tag, AppTheme.accent700, AppTheme.accent100),
          _KpiTile('Revenue Billed', usd(tally.totalBilledUsd), AppIcons.trendingUp, AppTheme.sage700, AppTheme.sage100),
          _KpiTile('Profit (PKR)', pkr(tally.totalProfit), AppIcons.award, AppTheme.sage800, AppTheme.sage100),
          _KpiTile('Completion Rate', '$completionRate%', AppIcons.shieldCheck, AppTheme.accent700, AppTheme.accent100),
          _KpiTile('Still Owed', pkr(tally.amountOwed), AppIcons.alert, AppTheme.danger, AppTheme.accent100),
        ];
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tiles.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 100,
          ),
          itemBuilder: (context, i) => tiles[i],
        );
      },
    );
  }
}

/// The two numbers the user cares about most for a salesman: what's still
/// owed to them, versus what's already been paid out — kept visually
/// distinct (danger vs. sage) since one is a pending liability.
class _PayoutCard extends StatelessWidget {
  const _PayoutCard({required this.salesmanName, required this.tally});

  final String salesmanName;
  final _SalesmanTally tally;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.tag, size: 16, color: AppTheme.accent700),
              const SizedBox(width: 8),
              Text('Payout to $salesmanName', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 480;
              final owed = _PayoutTile(
                label: 'Still owed (pending)',
                value: pkr(tally.amountOwed),
                icon: AppIcons.alert,
                color: AppTheme.danger,
                background: AppTheme.accent100,
              );
              final paid = _PayoutTile(
                label: 'Already paid',
                value: pkr(tally.amountPaid),
                icon: AppIcons.checkCircle,
                color: AppTheme.sage700,
                background: AppTheme.sage100,
              );
              final total = _PayoutTile(
                label: 'Total payout (all sales)',
                value: pkr(tally.amountOwed + tally.amountPaid),
                icon: AppIcons.users,
                color: AppTheme.subtle,
                background: AppTheme.neutral100,
              );
              if (stacked) {
                return Column(children: [owed, const SizedBox(height: 10), paid, const SizedBox(height: 10), total]);
              }
              return Row(
                children: [
                  Expanded(child: owed),
                  const SizedBox(width: 12),
                  Expanded(child: paid),
                  const SizedBox(width: 12),
                  Expanded(child: total),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PayoutTile extends StatelessWidget {
  const _PayoutTile({required this.label, required this.value, required this.icon, required this.color, required this.background});

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppTheme.radius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

/// Lead-stage funnel scoped to one salesman — same visual language as the
/// team-wide [_LeadStatusFunnelCard], built from [_SalesmanTally] instead
/// of [SalesStats] since this is a client-side-computed, single-person view.
class _SalesmanFunnelCard extends StatelessWidget {
  const _SalesmanFunnelCard({required this.tally});

  final _SalesmanTally tally;

  @override
  Widget build(BuildContext context) {
    final counts = {
      LeadStatus.newLead: tally.newCount,
      LeadStatus.inProgress: tally.inProgressCount,
      LeadStatus.completed: tally.completedCount,
      LeadStatus.cancelled: tally.cancelledCount,
    };
    final maxCount = counts.values.fold<int>(1, (m, c) => c > m ? c : m);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.barChart, size: 16, color: AppTheme.accent700),
              const SizedBox(width: 8),
              Text('Leads by stage', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 18),
          for (final status in LeadStatus.values)
            _CountBarRow(label: status.label, count: counts[status] ?? 0, maxCount: maxCount, style: leadStatusStyle(status)),
        ],
      ),
    );
  }
}

String _timeAgo(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

class _EmptySalesState extends StatelessWidget {
  const _EmptySalesState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
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
          ],
        ),
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.sale, this.onEdit, this.onDelete});

  final Sale sale;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final (leadColor, leadBg, leadIcon) = leadStatusStyle(sale.leadStatus);
    final (clientColor, clientBg) = clientPaymentStyle(sale.clientPaymentStatus);
    final (empColor, empBg) = employeePaymentStyle(sale.employeePaymentStatus);
    final profitColor = sale.profit < 0 ? AppTheme.danger : AppTheme.sage700;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: name, salesman, review link, lead-stage badge, actions.
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sale.businessName,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(AppIcons.users, size: 12, color: AppTheme.faint),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              sale.salesmanName ?? 'Unassigned',
                              style: const TextStyle(fontSize: 12.5, color: AppTheme.faint, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (sale.reviewLink != null && sale.reviewLink!.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Flexible(
                              child: InkWell(
                                onTap: () => launchUrl(Uri.parse(sale.reviewLink!)),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(AppIcons.externalLink, size: 12, color: AppTheme.faint),
                                    SizedBox(width: 4),
                                    Text(
                                      'Review link',
                                      style: TextStyle(fontSize: 12.5, color: AppTheme.faint, decoration: TextDecoration.underline),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _StatusPill(icon: leadIcon, label: sale.leadStatus.label, color: leadColor, background: leadBg),
                if (onEdit != null)
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(AppIcons.edit, size: 17, color: AppTheme.faint),
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                  ),
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(AppIcons.trash, size: 17, color: AppTheme.faint),
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.neutral200),
          // Financial ledger — two clearly-labeled currency columns.
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 480;
                final client = _LedgerColumn(
                  title: 'Client · USD',
                  rows: [
                    _LedgerRow('Billed', usd(sale.priceChargedToClient)),
                  ],
                  statusLabel: sale.clientPaymentStatus.label,
                  statusColor: clientColor,
                  statusBackground: clientBg,
                  footnote: sale.clientPaymentMethod,
                );
                final employee = _LedgerColumn(
                  title: 'Employee & Costs · PKR',
                  rows: [
                    _LedgerRow('Paid to employee', pkr(sale.employeePaymentAmount)),
                    _LedgerRow('Received from client', pkr(sale.clientAmountReceived)),
                    _LedgerRow('Removal cost', pkr(sale.removalCost)),
                  ],
                  statusLabel: sale.employeePaymentStatus.label,
                  statusColor: empColor,
                  statusBackground: empBg,
                );
                if (stacked) {
                  return Column(children: [client, const SizedBox(height: 16), employee]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: client),
                    const SizedBox(width: 24),
                    Expanded(child: employee),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1, color: AppTheme.neutral200),
          // Profit footer — the one number that matters most, always visible.
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            child: Row(
              children: [
                Icon(AppIcons.trendingUp, size: 16, color: profitColor),
                const SizedBox(width: 8),
                const Text('Profit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                const Spacer(),
                Text(
                  pkr(sale.profit),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: profitColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppTheme.faint)),
          ),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.ink)),
        ],
      ),
    );
  }
}

class _LedgerColumn extends StatelessWidget {
  const _LedgerColumn({
    required this.title,
    required this.rows,
    required this.statusLabel,
    required this.statusColor,
    required this.statusBackground,
    this.footnote,
  });

  final String title;
  final List<_LedgerRow> rows;
  final String statusLabel;
  final Color statusColor;
  final Color statusBackground;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.faint, letterSpacing: 0.3),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: statusBackground, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
              child: Text(statusLabel, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: statusColor)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...rows,
        if (footnote != null && footnote!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(footnote!, style: const TextStyle(fontSize: 11.5, color: AppTheme.faint)),
        ],
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label, required this.color, required this.background});

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
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
  late final _priceController =
      TextEditingController(text: widget.sale == null ? '' : widget.sale!.priceChargedToClient.toStringAsFixed(2));
  late final _paymentMethodController = TextEditingController(text: widget.sale?.clientPaymentMethod ?? '');
  late final _employeeAmountController =
      TextEditingController(text: widget.sale == null ? '' : widget.sale!.employeePaymentAmount.toStringAsFixed(2));
  late final _clientReceivedController =
      TextEditingController(text: widget.sale == null ? '' : widget.sale!.clientAmountReceived.toStringAsFixed(2));
  late final _removalCostController =
      TextEditingController(text: widget.sale == null ? '' : widget.sale!.removalCost.toStringAsFixed(2));

  String? _salesmanId;
  late LeadStatus _leadStatus = widget.sale?.leadStatus ?? LeadStatus.newLead;
  late ClientPaymentStatus _clientPaymentStatus = widget.sale?.clientPaymentStatus ?? ClientPaymentStatus.pending;
  late EmployeePaymentStatus _employeePaymentStatus = widget.sale?.employeePaymentStatus ?? EmployeePaymentStatus.pending;
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
    _paymentMethodController.dispose();
    _employeeAmountController.dispose();
    _clientReceivedController.dispose();
    _removalCostController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final businessName = _businessController.text.trim();
    if (businessName.isEmpty) {
      setState(() => _error = 'Business name is required');
      return;
    }
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    final employeeAmount = double.tryParse(_employeeAmountController.text.trim()) ?? 0;
    final clientReceived = double.tryParse(_clientReceivedController.text.trim()) ?? 0;
    final removalCost = double.tryParse(_removalCostController.text.trim()) ?? 0;
    final salesman = widget.salesmen.where((s) => s.id == _salesmanId).firstOrNull;
    final paymentMethod = _paymentMethodController.text.trim();

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
          leadStatus: _leadStatus,
          priceChargedToClient: price,
          clientPaymentStatus: _clientPaymentStatus,
          clientPaymentMethod: paymentMethod.isEmpty ? null : paymentMethod,
          employeePaymentAmount: employeeAmount,
          employeePaymentStatus: _employeePaymentStatus,
          clientAmountReceived: clientReceived,
          removalCost: removalCost,
        );
      } else {
        await repo.updateSale(
          widget.sale!.id,
          businessName: businessName,
          reviewLink: _linkController.text.trim().isEmpty ? null : _linkController.text.trim(),
          salesmanId: salesman?.id,
          salesmanName: salesman?.name,
          leadStatus: _leadStatus,
          priceChargedToClient: price,
          clientPaymentStatus: _clientPaymentStatus,
          clientPaymentMethod: paymentMethod.isEmpty ? null : paymentMethod,
          employeePaymentAmount: employeeAmount,
          employeePaymentStatus: _employeePaymentStatus,
          clientAmountReceived: clientReceived,
          removalCost: removalCost,
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
        width: 480,
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
                decoration: const InputDecoration(labelText: 'Employee (salesman)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
                  for (final s in widget.salesmen) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: _saving ? null : (v) => setState(() => _salesmanId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<LeadStatus>(
                initialValue: _leadStatus,
                decoration: const InputDecoration(labelText: 'Lead status'),
                items: [for (final s in LeadStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
                onChanged: _saving ? null : (v) => setState(() => _leadStatus = v ?? _leadStatus),
              ),
              const SizedBox(height: 20),
              _SectionLabel('Client (USD)'),
              const SizedBox(height: 10),
              TextField(
                controller: _priceController,
                decoration: const InputDecoration(labelText: 'Price charged to client', prefixText: '\$'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                enabled: !_saving,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<ClientPaymentStatus>(
                      initialValue: _clientPaymentStatus,
                      decoration: const InputDecoration(labelText: 'Client payment status'),
                      items: [for (final s in ClientPaymentStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
                      onChanged: _saving ? null : (v) => setState(() => _clientPaymentStatus = v ?? _clientPaymentStatus),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _paymentMethodController,
                      decoration: const InputDecoration(labelText: 'Payment method', hintText: 'UBL, PayPal…'),
                      enabled: !_saving,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionLabel('Employee & costs (PKR)'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _employeeAmountController,
                      decoration: const InputDecoration(labelText: 'Employee payment', prefixText: 'PKR '),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_saving,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<EmployeePaymentStatus>(
                      initialValue: _employeePaymentStatus,
                      decoration: const InputDecoration(labelText: 'Employee payment status'),
                      items: [for (final s in EmployeePaymentStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
                      onChanged: _saving ? null : (v) => setState(() => _employeePaymentStatus = v ?? _employeePaymentStatus),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _clientReceivedController,
                      decoration: const InputDecoration(labelText: 'Client amount received', prefixText: 'PKR '),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_saving,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _removalCostController,
                      decoration: const InputDecoration(labelText: 'Removal cost', prefixText: 'PKR '),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_saving,
                    ),
                  ),
                ],
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.subtle));
  }
}
