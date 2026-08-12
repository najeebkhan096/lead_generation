import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/sales_user.dart';
import '../../domain/repositories/lead_repository.dart';
import 'sales_page.dart' show money, statusStyle;

const _allSalesmen = 'All salesmen';

/// Rollup statistics over every sale — revenue, profit, a funnel by status,
/// and a per-salesman leaderboard. Filterable to one salesman via the
/// dropdown in the app bar, which re-queries the backend rather than
/// filtering client-side (so it scales the same way the CRUD list does).
class SalesDashboardPage extends StatefulWidget {
  const SalesDashboardPage({super.key});

  @override
  State<SalesDashboardPage> createState() => _SalesDashboardPageState();
}

class _SalesDashboardPageState extends State<SalesDashboardPage> {
  SalesStats? _stats;
  List<SalesUser> _salesmen = [];
  bool _loading = true;
  String? _error;
  String _filterSalesmanId = _allSalesmen;

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _loadSalesmen();
    _load();
  }

  Future<void> _loadSalesmen() async {
    try {
      final salesmen = await _repo.listSalesmen();
      if (!mounted) return;
      setState(() => _salesmen = salesmen);
    } catch (_) {
      // Non-critical — the filter just won't offer names.
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stats = await _repo.getSalesStats(
        salesmanId: _filterSalesmanId == _allSalesmen ? null : _filterSalesmanId,
      );
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
    final filtered = _filterSalesmanId != _allSalesmen;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Dashboard'),
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
          const SizedBox(width: 8),
          IconButton(tooltip: 'Refresh', icon: const Icon(AppIcons.refresh), onPressed: _load),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.danger)))
                : stats == null || stats.totalSales == 0
                    ? const _EmptyState()
                    : CustomScrollView(
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
                                        _StatusFunnelCard(stats: stats),
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
                      ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
              'Statistics show up here once sales are logged on the Sales page.',
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
    final completedCount = stats.byStatus[SaleStatus.completed]?.count ?? 0;
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
          _KpiTile('Revenue', money(stats.totalRevenue), AppIcons.trendingUp, AppTheme.sage700, AppTheme.sage100),
          _KpiTile('Salesman Payout', money(stats.totalSalesmanPayout), AppIcons.users, AppTheme.subtle, AppTheme.neutral100),
          _KpiTile('Profit', money(stats.totalProfit), AppIcons.award, AppTheme.sage800, AppTheme.sage100),
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
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: AppTheme.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.faint), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Sales funnel by status — bar length encodes count, with revenue shown
/// as secondary text. Every status pairs its color with an icon + label
/// (never color alone), matching the rest of this app's muted palette,
/// which doesn't clear strict CVD-separation on its own.
class _StatusFunnelCard extends StatelessWidget {
  const _StatusFunnelCard({required this.stats});

  final SalesStats stats;

  @override
  Widget build(BuildContext context) {
    final maxCount = SaleStatus.values.fold<int>(
      1,
      (m, s) => (stats.byStatus[s]?.count ?? 0) > m ? stats.byStatus[s]!.count : m,
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
              Text('Sales by status', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 18),
          for (final status in SaleStatus.values) _StatusRow(status: status, breakdown: stats.byStatus[status], maxCount: maxCount),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.status, required this.breakdown, required this.maxCount});

  final SaleStatus status;
  final SaleStatusBreakdown? breakdown;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final (color, _, icon) = statusStyle(status);
    final count = breakdown?.count ?? 0;
    final revenue = breakdown?.revenue ?? 0;
    final fraction = maxCount > 0 ? count / maxCount : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 190,
            child: Row(
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    status.label,
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
            width: 150,
            child: Text(
              '$count · ${money(revenue)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({required this.salesmen});

  final List<SalesmanBreakdown> salesmen;

  @override
  Widget build(BuildContext context) {
    final maxRevenue = salesmen.fold<double>(1, (m, s) => s.revenue > m ? s.revenue : m);

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
            'Ranked by revenue generated. Bar length is revenue — a single hue, since this compares one measure across people, not identity.',
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
    final fraction = maxRevenue > 0 ? entry.revenue / maxRevenue : 0.0;
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
                '${entry.count} sale${entry.count == 1 ? '' : 's'} · $completionRate% completed',
                style: const TextStyle(fontSize: 11.5, color: AppTheme.faint),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 90,
                child: Text(
                  money(entry.revenue),
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
