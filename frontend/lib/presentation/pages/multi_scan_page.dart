import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/multi_search_snapshot.dart';
import '../../domain/repositories/lead_repository.dart';

const _pollInterval = Duration(milliseconds: 1500);

/// Live dashboard for a concurrent multi-category scan: overall progress,
/// one expandable card per category, a real-time activity feed, and
/// pause/resume/cancel controls at both the job and category level.
class MultiScanPage extends StatefulWidget {
  const MultiScanPage({super.key});

  @override
  State<MultiScanPage> createState() => _MultiScanPageState();
}

class _MultiScanPageState extends State<MultiScanPage> {
  Timer? _timer;
  MultiSearchSnapshot? _snapshot;
  String? _error;
  bool _loading = true;
  final Set<String> _expanded = {};

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final snap = await _repo.getMultiSearchStatus();
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _error = null;
        _loading = false;
      });
      if (snap.status == 'done') {
        _timer?.cancel();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _runControl(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
    await _poll();
  }

  Future<void> _confirmCancelAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel entire job?'),
        content: const Text(
          'Running categories will stop after their current state. Queued categories will be skipped. Progress so far is kept.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep running')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel job', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _runControl(_repo.cancelMultiSearchJob);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    final overall = snap?.overall;
    final isDone = snap?.status == 'done';
    final isPaused = overall?.paused ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Multi-Category Scan'),
        actions: [
          if (snap != null && !isDone) ...[
            IconButton(
              tooltip: isPaused ? 'Resume job' : 'Pause job',
              icon: Icon(isPaused ? AppIcons.checkCircle : Icons.pause_circle_outline),
              onPressed: () => _runControl(
                isPaused ? _repo.resumeMultiSearchJob : _repo.pauseMultiSearchJob,
              ),
            ),
            IconButton(
              tooltip: 'Cancel job',
              icon: const Icon(AppIcons.close),
              onPressed: _confirmCancelAll,
            ),
          ],
          IconButton(tooltip: 'Refresh', icon: const Icon(AppIcons.refresh), onPressed: _poll),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _poll)
                : snap == null || !snap.hasJob
                    ? const _NoJobState()
                    : _DashboardBody(
                        snapshot: snap,
                        expanded: _expanded,
                        onToggleExpand: (category) => setState(() {
                          _expanded.contains(category) ? _expanded.remove(category) : _expanded.add(category);
                        }),
                        onCancelCategory: (c) => _runControl(() => _repo.cancelMultiSearchCategory(c)),
                        onPauseCategory: (c) => _runControl(() => _repo.pauseMultiSearchCategory(c)),
                        onResumeCategory: (c) => _runControl(() => _repo.resumeMultiSearchCategory(c)),
                      ),
      ),
    );
  }
}

class _NoJobState extends StatelessWidget {
  const _NoJobState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(color: AppTheme.accent100, shape: BoxShape.circle),
              child: const Icon(AppIcons.search, size: 36, color: AppTheme.accent700),
            ),
            const SizedBox(height: 20),
            Text('No scan running', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Start a multi-category search from the New Search form to see live progress here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

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
              child: const Icon(AppIcons.alert, size: 30, color: AppTheme.accent700),
            ),
            const SizedBox(height: 18),
            Text('Could not load scan status', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.danger)),
            const SizedBox(height: 18),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(AppIcons.refresh, size: 18), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.snapshot,
    required this.expanded,
    required this.onToggleExpand,
    required this.onCancelCategory,
    required this.onPauseCategory,
    required this.onResumeCategory,
  });

  final MultiSearchSnapshot snapshot;
  final Set<String> expanded;
  final ValueChanged<String> onToggleExpand;
  final ValueChanged<String> onCancelCategory;
  final ValueChanged<String> onPauseCategory;
  final ValueChanged<String> onResumeCategory;

  @override
  Widget build(BuildContext context) {
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
                      if (snapshot.finalStats != null) _FinalStatsCard(stats: snapshot.finalStats!),
                      if (snapshot.overall != null) ...[
                        _OverallCard(overall: snapshot.overall!, status: snapshot.status),
                        const SizedBox(height: 24),
                      ],
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stacked = constraints.maxWidth < 820;
                          final categoryList = _CategoryList(
                            categories: snapshot.categories,
                            expanded: expanded,
                            onToggleExpand: onToggleExpand,
                            onCancelCategory: onCancelCategory,
                            onPauseCategory: onPauseCategory,
                            onResumeCategory: onResumeCategory,
                          );
                          final activity = _ActivityFeed(entries: snapshot.activity);
                          if (stacked) {
                            return Column(
                              children: [categoryList, const SizedBox(height: 20), activity],
                            );
                          }
                          // Not IntrinsicHeight: the activity feed contains
                          // a ListView, which (like the category bars'
                          // LayoutBuilder) can't answer intrinsic-dimension
                          // queries. Top-aligned already, so nothing relied
                          // on the stretch behavior anyway.
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: categoryList),
                              const SizedBox(width: 20),
                              Expanded(flex: 2, child: activity),
                            ],
                          );
                        },
                      ),
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

String _formatDuration(int ms) {
  if (ms <= 0) return '0s';
  final totalSeconds = (ms / 1000).round();
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  if (h > 0) return '${h}h ${m}m ${s}s';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

String? _formatEta(int? ms) {
  if (ms == null) return null;
  return '~${_formatDuration(ms)} left';
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.overall, required this.status});

  final OverallProgress overall;
  final String status;

  @override
  Widget build(BuildContext context) {
    final eta = _formatEta(overall.etaMs);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Overall progress', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 10),
              if (status == 'running' && !overall.paused)
                _Chip(label: '${overall.activeWorkers} active', color: AppTheme.sage, background: AppTheme.sage100)
              else if (overall.paused)
                const _Chip(label: 'Paused', color: AppTheme.accent700, background: AppTheme.accent100)
              else
                const _Chip(label: 'Done', color: AppTheme.sage700, background: AppTheme.sage100),
              const Spacer(),
              Text('${overall.percent}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.accent700)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            child: LinearProgressIndicator(value: overall.percent / 100, minHeight: 10),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('Elapsed ${_formatDuration(overall.elapsedMs)}', style: Theme.of(context).textTheme.bodySmall),
              if (eta != null) ...[
                const Text(' · ', style: TextStyle(color: AppTheme.faint)),
                Text(eta, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 6
                  : constraints.maxWidth >= 620
                      ? 3
                      : 2;
              final tiles = [
                _StatTile('Categories', '${overall.totalCategories}', AppIcons.tag),
                _StatTile('Completed', '${overall.completed}', AppIcons.checkCircle),
                _StatTile('Running', '${overall.running}', AppIcons.zap),
                _StatTile('Queued', '${overall.queued}', AppIcons.clock),
                _StatTile('States done', '${overall.totalStatesDone}', AppIcons.mapPinned),
                _StatTile('Leads found', '${overall.totalLeads}', AppIcons.trendingUp),
              ];
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tiles.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 92,
                ),
                itemBuilder: (context, i) => tiles[i],
              );
            },
          ),
          if (overall.failed > 0 || overall.cancelled > 0) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (overall.failed > 0)
                  _Chip(label: '${overall.failed} failed', color: AppTheme.accent700, background: AppTheme.accent100),
                if (overall.cancelled > 0)
                  _Chip(label: '${overall.cancelled} cancelled', color: AppTheme.subtle, background: AppTheme.neutral100),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.neutral100, borderRadius: BorderRadius.circular(AppTheme.radius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppTheme.subtle),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.ink)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.faint), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, required this.background});

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11.5)),
    );
  }
}

/// Status -> (dot color, label). Kept to the app's warm palette rather
/// than literal traffic-light colors: sage reads as "healthy/positive",
/// terracotta as "needs attention", neutral as "not started yet".
(Color, Color, String) _statusStyle(CategoryScanStatus status) {
  switch (status) {
    case CategoryScanStatus.queued:
      return (AppTheme.neutral400, AppTheme.neutral100, 'Queued');
    case CategoryScanStatus.starting:
      return (AppTheme.sage500, AppTheme.sage100, 'Starting');
    case CategoryScanStatus.searching:
      return (AppTheme.sage500, AppTheme.sage100, 'Searching');
    case CategoryScanStatus.scraping:
      return (AppTheme.sage500, AppTheme.sage100, 'Scraping');
    case CategoryScanStatus.saving:
      return (AppTheme.sage600, AppTheme.sage100, 'Saving');
    case CategoryScanStatus.completed:
      return (AppTheme.sage700, AppTheme.sage100, 'Completed');
    case CategoryScanStatus.failed:
      return (AppTheme.accent700, AppTheme.accent100, 'Failed');
    case CategoryScanStatus.cancelled:
      return (AppTheme.neutral600, AppTheme.neutral100, 'Cancelled');
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.categories,
    required this.expanded,
    required this.onToggleExpand,
    required this.onCancelCategory,
    required this.onPauseCategory,
    required this.onResumeCategory,
  });

  final List<CategoryProgress> categories;
  final Set<String> expanded;
  final ValueChanged<String> onToggleExpand;
  final ValueChanged<String> onCancelCategory;
  final ValueChanged<String> onPauseCategory;
  final ValueChanged<String> onResumeCategory;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Categories', style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 12),
          for (final c in categories)
            _CategoryCard(
              progress: c,
              isExpanded: expanded.contains(c.category),
              onToggleExpand: () => onToggleExpand(c.category),
              onCancel: () => onCancelCategory(c.category),
              onPause: () => onPauseCategory(c.category),
              onResume: () => onResumeCategory(c.category),
            ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.progress,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onCancel,
    required this.onPause,
    required this.onResume,
  });

  final CategoryProgress progress;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onCancel;
  final VoidCallback onPause;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final (dotColor, bgColor, label) = _statusStyle(progress.status);
    final canControl = progress.status.isRunning;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: bgColor.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(AppTheme.radius + 4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleExpand,
            borderRadius: BorderRadius.circular(AppTheme.radius + 4),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(progress.category, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(
                          '$label${progress.currentState != null && progress.status.isRunning ? ' · ${progress.currentState}' : ''} · ${progress.statesDone}/${progress.statesTotal} states · ${progress.leadsCollected} leads',
                          style: const TextStyle(fontSize: 11.5, color: AppTheme.faint),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text('${progress.progressPercent}%', style: TextStyle(fontWeight: FontWeight.w800, color: dotColor, fontSize: 13)),
                  const SizedBox(width: 8),
                  Icon(isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppTheme.faint),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              child: LinearProgressIndicator(
                value: progress.progressPercent / 100,
                minHeight: 6,
                backgroundColor: AppTheme.surface,
                color: dotColor,
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 18,
                    runSpacing: 8,
                    children: [
                      _DetailStat('Worker', progress.workerId == null ? '—' : '#${progress.workerId}'),
                      _DetailStat('Businesses scanned', '${progress.businessesProcessed}'),
                      _DetailStat('States remaining', '${progress.statesRemaining}'),
                      _DetailStat('Elapsed', _formatDuration(progress.elapsedMs)),
                      if (progress.status.isRunning && progress.etaMs != null)
                        _DetailStat('ETA', _formatDuration(progress.etaMs!)),
                    ],
                  ),
                  if (progress.error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppTheme.accent100, borderRadius: BorderRadius.circular(AppTheme.radius)),
                      child: Text(progress.error!, style: const TextStyle(color: AppTheme.accent700, fontSize: 12)),
                    ),
                  ],
                  if (progress.warnings.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ...progress.warnings.reversed.take(3).map(
                          (w) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(AppIcons.alert, size: 13, color: AppTheme.accent600),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(w.message, style: const TextStyle(fontSize: 11.5, color: AppTheme.subtle)),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                  if (canControl) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: progress.paused ? onResume : onPause,
                          icon: Icon(progress.paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 16),
                          label: Text(progress.paused ? 'Resume' : 'Pause'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            minimumSize: Size.zero,
                            textStyle: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: onCancel,
                          icon: const Icon(AppIcons.close, size: 16),
                          label: const Text('Cancel'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                            side: const BorderSide(color: AppTheme.accent300),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            minimumSize: Size.zero,
                            textStyle: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  const _DetailStat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5, color: AppTheme.faint, fontWeight: FontWeight.w600)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.ink)),
      ],
    );
  }
}

class _ActivityFeed extends StatelessWidget {
  const _ActivityFeed({required this.entries});

  final List<ActivityLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      constraints: const BoxConstraints(maxHeight: 640),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.zap, size: 16, color: AppTheme.accent700),
              const SizedBox(width: 8),
              Text('Live activity', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: entries.isEmpty
                ? const Center(child: Text('Nothing yet.', style: TextStyle(color: AppTheme.faint)))
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, i) => _ActivityRow(entry: entries[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final ActivityLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      'error' => AppTheme.accent700,
      'warn' => AppTheme.accent600,
      _ => AppTheme.subtle,
    };
    final time = entry.timestamp.toLocal();
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final ss = time.second.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$hh:$mm:$ss', style: const TextStyle(fontSize: 10.5, color: AppTheme.faint, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(width: 8),
          Expanded(child: Text(entry.message, style: TextStyle(fontSize: 12, color: color))),
        ],
      ),
    );
  }
}

class _FinalStatsCard extends StatelessWidget {
  const _FinalStatsCard({required this.stats});

  final MultiSearchFinalStats stats;

  @override
  Widget build(BuildContext context) {
    final sorted = stats.leadsPerCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.sage100,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: AppTheme.sage500, shape: BoxShape.circle),
                child: const Icon(AppIcons.checkCircle, color: AppTheme.surface, size: 20),
              ),
              const SizedBox(width: 12),
              Text('Scan complete', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppTheme.sage800)),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              _DetailStat('Total time', _formatDuration(stats.totalExecutionMs)),
              _DetailStat('Total leads', '${stats.totalLeads}'),
              _DetailStat('States processed', '${stats.statesProcessed}'),
              _DetailStat('Succeeded', '${stats.successCount}'),
              _DetailStat('Failed', '${stats.failureCount}'),
              _DetailStat('Cancelled', '${stats.cancelledCount}'),
              if (stats.avgMsPerState != null) _DetailStat('Avg / state', _formatDuration(stats.avgMsPerState!.round())),
              if (stats.avgMsPerCategory != null) _DetailStat('Avg / category', _formatDuration(stats.avgMsPerCategory!.round())),
            ],
          ),
          if (sorted.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('Leads per category', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppTheme.sage800)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in sorted)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                    child: Text(
                      '${e.key} · ${e.value}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.ink),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
