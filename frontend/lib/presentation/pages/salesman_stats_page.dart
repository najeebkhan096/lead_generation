import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_labels.dart';
import '../../domain/entities/salesman_stats.dart';
import '../../domain/repositories/lead_repository.dart';

/// The time range the page is showing: today, or everything since the start.
enum StatsRange { today, all }

/// How many days the daily charts cover when the range is All.
const _allDaysWindow = 30;

/// Every salesman's new-lead contacts. The range filter (Today by default, or
/// All) sets the numbers and the charts. Tap a salesman to see their contacted
/// leads and move them back to New.
class SalesmanStatsPage extends StatefulWidget {
  const SalesmanStatsPage({super.key});

  @override
  State<SalesmanStatsPage> createState() => _SalesmanStatsPageState();
}

class _SalesmanStatsPageState extends State<SalesmanStatsPage> {
  SalesmanStats? _stats;
  bool _loading = true;
  String? _error;
  StatsRange _range = StatsRange.today;

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
      final stats = await _repo.getSalesmanStats(days: _allDaysWindow);
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
    final today = _range == StatsRange.today;
    final salesmen = [...stats.salesmen]
      ..sort((a, b) => _valueOf(b, _range).compareTo(_valueOf(a, _range)));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: AppTheme.danger)),
          const SizedBox(height: 12),
        ],
        SegmentedButton<StatsRange>(
          segments: const [
            ButtonSegment(value: StatsRange.today, label: Text('Today'), icon: Icon(AppIcons.clock, size: 16)),
            ButtonSegment(value: StatsRange.all, label: Text('All'), icon: Icon(AppIcons.barChart, size: 16)),
          ],
          selected: {_range},
          onSelectionChanged: (s) => setState(() => _range = s.first),
        ),
        const SizedBox(height: 16),
        _TotalsGrid(stats: stats, range: _range),
        const SizedBox(height: 20),
        _SectionTitle(today ? 'Contacted today, by salesman' : 'Contacted in total, by salesman'),
        _Card(
          child: salesmen.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No salesmen yet.', style: TextStyle(color: AppTheme.faint))),
                )
              : _BarChart(
                  counts: [for (final s in salesmen) _valueOf(s, _range)],
                  labels: {for (var i = 0; i < salesmen.length; i++) i: _firstName(salesmen[i].name)},
                  labelSpan: 1,
                ),
        ),
        const SizedBox(height: 20),
        _SectionTitle(today ? 'Contacted today, by hour (all salesmen)' : 'Contacted per day, last $_allDaysWindow days (all salesmen)'),
        _Card(
          child: today
              ? _BarChart(
                  counts: stats.totals.hourlyToday,
                  labels: _hourLabels(),
                  labelSpan: 6,
                )
              : _BarChart(
                  counts: [for (final d in stats.totals.daily) d.count],
                  labels: _dayLabels(stats.days),
                  labelSpan: 5,
                ),
        ),
        const SizedBox(height: 20),
        _SectionTitle('Salesmen (${stats.salesmen.length})'),
        if (stats.salesmen.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No salesmen yet.', style: TextStyle(color: AppTheme.faint))),
          ),
        for (final s in salesmen)
          _SalesmanCard(
            stat: s,
            range: _range,
            onOpen: () => context.push('/salesman-stats/${s.id}?name=${Uri.encodeComponent(s.name)}'),
          ),
        const SizedBox(height: 8),
        Text(
          'Updated ${_updated(stats)} · business day ${dayLabel(stats.today)} (Asia/Dubai)',
          style: const TextStyle(fontSize: 12, color: AppTheme.faint),
        ),
      ],
    );
  }
}

/// The number that ranks and charts a salesman for the range.
int _valueOf(SalesmanStat s, StatsRange range) => range == StatsRange.today ? s.contactedToday : s.contactedTotal;

String _firstName(String name) {
  final first = name.trim().split(RegExp(r'\s+')).first;
  return first.length > 10 ? '${first.substring(0, 9)}…' : first;
}

Map<int, String> _hourLabels() => {
      for (final h in const [0, 6, 12, 18]) h: '${h.toString().padLeft(2, '0')}:00',
    };

Map<int, String> _dayLabels(List<String> days) {
  return {
    for (var i = 0; i < days.length; i += 5) i: dayLabel(days[i]),
  };
}

String _updated(SalesmanStats stats) {
  final at = stats.generatedAt;
  return at == null ? '—' : dateTimeLabel(at);
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
  const _TotalsGrid({required this.stats, required this.range});

  final SalesmanStats stats;
  final StatsRange range;

  @override
  Widget build(BuildContext context) {
    final t = stats.totals;
    final tiles = range == StatsRange.today
        ? [
            ('Contacted today', '${t.contactedToday}'),
            ('Salesmen active today', '${stats.salesmen.where((s) => s.contactedToday > 0).length}'),
            ('New leads left', '${t.newLeft}'),
            ('1-star WhatsApp leads', '${t.reviewLeads}'),
          ]
        : [
            ('Contacted in total', '${t.contactedTotal}'),
            ('Contacted, last 7 days', '${t.contactedLast7}'),
            ('Salesmen who contacted', '${t.activeSalesmen}'),
            ('New leads left', '${t.newLeft}'),
            ('1-star WhatsApp leads', '${t.reviewLeads}'),
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
  const _SalesmanCard({required this.stat, required this.range, required this.onOpen});

  final SalesmanStat stat;
  final StatsRange range;

  /// Opens this salesman's contacted leads.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final name = stat.name.trim();
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    final today = range == StatsRange.today;

    final chips = today
        ? [
            _Chip('Today ${stat.contactedToday} of ${stat.dailyLeadLimit}', highlight: stat.limitLeftToday == 0),
            _Chip('${stat.limitLeftToday} left today'),
            _Chip('Last contact ${stat.lastContactAt == null ? '—' : dateTimeLabel(stat.lastContactAt!)}'),
          ]
        : [
            _Chip('Total ${stat.contactedTotal}'),
            _Chip('Last 7 days ${stat.contactedLast7}'),
            _Chip('Active days ${stat.activeDays}'),
            _Chip('Average ${stat.averagePerActiveDay.toStringAsFixed(1)} per active day'),
            _Chip('Days at limit ${stat.daysAtLimit}', highlight: stat.daysAtLimit > 0),
            _Chip('First contact ${stat.firstContactAt == null ? '—' : dateLabel(stat.firstContactAt!)}'),
            _Chip('Last contact ${stat.lastContactAt == null ? '—' : dateTimeLabel(stat.lastContactAt!)}'),
          ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
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
                            stat.approved ? 'Approved · tap to see contacted leads' : 'Not approved · tap to see contacted leads',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: stat.approved ? AppTheme.sage700 : AppTheme.accent700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(AppIcons.chevronRight, size: 18, color: AppTheme.faint),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: chips),
                const SizedBox(height: 16),
                Text(
                  today
                      ? 'Contacted by hour, today'
                      : 'Contacted per day, last $_allDaysWindow days · limit ${stat.dailyLeadLimit}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                today
                    ? _BarChart(counts: stat.hourlyToday, labels: _hourLabels(), labelSpan: 6)
                    : _BarChart(
                        counts: [for (final d in stat.daily) d.count],
                        labels: _dayLabels([for (final d in stat.daily) d.day]),
                        labelSpan: 5,
                        limit: stat.dailyLeadLimit,
                      ),
              ],
            ),
          ),
        ),
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

/// Bars for [counts]. [labels] puts text under the bars at the given indexes,
/// each centred over [labelSpan] bars. Bars at or over [limit] are terracotta,
/// and a line marks the limit when one is given.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.counts, this.labels = const {}, this.labelSpan = 1, this.limit});

  final List<int> counts;
  final Map<int, String> labels;
  final int labelSpan;
  final int? limit;

  static const _plot = 120.0;
  static const _labelRow = 22.0;
  static const _countRow = 16.0;

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) return const SizedBox(height: _plot + _labelRow);
    final cap = limit;
    final peak = [1, ...counts, ?cap].reduce((a, b) => math.max(a, b));
    double heightFor(int n) => n <= 0 ? 0 : (n / peak) * (_plot - _countRow);

    return LayoutBuilder(
      builder: (context, box) {
        final slot = box.maxWidth / counts.length;
        final labelWidth = math.min(80.0, slot * labelSpan);
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
              for (final entry in labels.entries)
                Positioned(
                  left: (entry.key * slot + slot / 2 - labelWidth / 2).clamp(0.0, box.maxWidth - labelWidth),
                  width: labelWidth,
                  bottom: 0,
                  height: _labelRow,
                  child: Text(
                    entry.value,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppTheme.faint),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
