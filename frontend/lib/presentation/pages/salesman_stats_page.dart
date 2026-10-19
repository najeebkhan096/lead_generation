import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/salesman_stats.dart';
import '../../domain/repositories/lead_repository.dart';

const _ranges = [7, 14, 30];

/// Every salesman's new-lead contacts: today against their daily limit, the
/// totals, and a bar chart per day over the chosen range.
class SalesmanStatsPage extends StatefulWidget {
  const SalesmanStatsPage({super.key});

  @override
  State<SalesmanStatsPage> createState() => _SalesmanStatsPageState();
}

class _SalesmanStatsPageState extends State<SalesmanStatsPage> {
  SalesmanStats? _stats;
  bool _loading = true;
  String? _error;
  int _days = 14;

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats = await _repo.getSalesmanStats(days: _days);
      if (!mounted) return;
      setState(() {
        _stats = stats;
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

  void _setDays(int days) {
    setState(() => _days = days);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salesman stats'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(AppIcons.refresh, size: 18),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: _body(),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final stats = _stats;
    if (stats == null) {
      if (_error != null) return _ErrorView(message: _error!, onRetry: _load);
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: AppTheme.danger)),
          const SizedBox(height: 12),
        ],
        SegmentedButton<int>(
          segments: [for (final d in _ranges) ButtonSegment(value: d, label: Text('$d days'))],
          selected: {_days},
          onSelectionChanged: _loading ? null : (s) => _setDays(s.first),
        ),
        const SizedBox(height: 16),
        _TotalsGrid(totals: stats.totals),
        const SizedBox(height: 20),
        const _SectionTitle('Contacts per day · all salesmen'),
        _Card(child: _BarChart(days: stats.days, counts: [for (final d in stats.totals.daily) d.count])),
        const SizedBox(height: 20),
        _SectionTitle('Salesmen (${stats.salesmen.length})'),
        if (stats.salesmen.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No salesmen yet.', style: TextStyle(color: AppTheme.faint))),
          ),
        for (final s in stats.salesmen) _SalesmanCard(stat: s, days: stats.days),
        const SizedBox(height: 8),
        Text(
          'Updated ${_when(stats.generatedAt)} · business day ${stats.today} (Asia/Dubai)',
          style: const TextStyle(fontSize: 12, color: AppTheme.faint),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: const TextStyle(color: AppTheme.danger), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(AppIcons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsGrid extends StatelessWidget {
  const _TotalsGrid({required this.totals});

  final SalesmanStatsTotals totals;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      ('Contacted today', '${totals.contactedToday}'),
      ('Contacted, last 7 days', '${totals.contactedLast7}'),
      ('Contacted in total', '${totals.contactedTotal}'),
      ('Active salesmen', '${totals.activeSalesmen}'),
      ('New leads left', '${totals.newLeft}'),
      ('1-star WhatsApp leads', '${totals.reviewLeads}'),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [for (final (label, value) in tiles) _Tile(label: label, value: value)],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.faint, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _SalesmanCard extends StatelessWidget {
  const _SalesmanCard({required this.stat, required this.days});

  final SalesmanStat stat;
  final List<String> days;

  @override
  Widget build(BuildContext context) {
    final name = stat.name.trim();
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.sage100,
                child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.sage700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stat.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    if (stat.email != null)
                      Text(stat.email!, style: const TextStyle(fontSize: 12, color: AppTheme.faint), overflow: TextOverflow.ellipsis),
                    Text(
                      stat.approved ? 'Approved' : 'Not approved',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: stat.approved ? AppTheme.sage700 : AppTheme.accent700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip('Today ${stat.contactedToday} of ${stat.dailyLeadLimit}', highlight: stat.limitLeftToday == 0),
              _Chip('${stat.limitLeftToday} left today'),
              _Chip('Last 7 days ${stat.contactedLast7}'),
              _Chip('Total ${stat.contactedTotal}'),
              _Chip('Active days ${stat.activeDays}'),
              _Chip('Average ${stat.averagePerActiveDay.toStringAsFixed(1)} per active day'),
              _Chip('Days at limit ${stat.daysAtLimit}', highlight: stat.daysAtLimit > 0),
              _Chip('First contact ${_when(stat.firstContactAt)}'),
              _Chip('Last contact ${_when(stat.lastContactAt)}'),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Contacts per day · limit ${stat.dailyLeadLimit}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _BarChart(
            days: days,
            counts: [for (final d in stat.daily) d.count],
            limit: stat.dailyLeadLimit,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? AppTheme.accent100 : AppTheme.sage100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: highlight ? AppTheme.accent700 : AppTheme.sage700,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: child,
    );
  }
}

/// One bar per day: the number of new leads contacted. Bars on or over the
/// [limit] are terracotta, and a line marks the limit when one is given.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.days, required this.counts, this.limit});

  final List<String> days;
  final List<int> counts;
  final int? limit;

  static const _plot = 120.0;
  static const _labelRow = 22.0;
  static const _countRow = 16.0;

  @override
  Widget build(BuildContext context) {
    final cap = limit;
    final peak = [1, ...counts, ?cap].reduce((a, b) => math.max(a, b));
    double heightFor(int n) => n <= 0 ? 0 : (n / peak) * (_plot - _countRow);

    return SizedBox(
      height: _plot + _labelRow,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: _labelRow,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < counts.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SizedBox(
                            height: _countRow,
                            child: counts[i] > 0
                                ? Text(
                                    '${counts[i]}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.faint),
                                  )
                                : null,
                          ),
                          Container(
                            height: heightFor(counts[i]),
                            decoration: BoxDecoration(
                              color: cap != null && counts[i] >= cap ? AppTheme.accent700 : AppTheme.sage500,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (cap != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: _labelRow + heightFor(cap),
              child: Container(height: 1.5, color: AppTheme.accent700.withValues(alpha: 0.6)),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _labelRow,
            child: Row(
              children: [
                for (var i = 0; i < days.length; i++)
                  Expanded(
                    child: Text(
                      days[i].length >= 10 ? days[i].substring(8) : '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10, color: AppTheme.faint),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _when(DateTime? d) {
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${two(d.hour)}:${two(d.minute)}';
}
