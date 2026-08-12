import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/multi_search_snapshot.dart';
import '../../domain/repositories/lead_repository.dart';
import '../utils/duration_format.dart';
import '../utils/web_download.dart';
import 'excel_archive_page.dart';

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
  bool _exporting = false;
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
      // exportOnly jobs keep building/uploading the Excel archive for a
      // little while after status flips to 'done' — keep polling until
      // that finishes too, or the archive card would be stuck spinning.
      final archiveSettled = !snap.exportOnly || snap.archiveStatus == 'done' || snap.archiveStatus == 'failed';
      if (snap.status == 'done' && archiveSettled) {
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

  Future<void> _exportExcel() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await _repo.exportMultiExcel();
      downloadBytesFile(
        'scan-results.xlsx',
        bytes,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
          if (isDone && !(snap?.exportOnly ?? false) && (overall?.totalLeads ?? 0) > 0) ...[
            TextButton.icon(
              onPressed: _exporting ? null : _exportExcel,
              icon: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AppIcons.download, size: 18),
              label: Text(_exporting ? 'Exporting…' : 'Export to Excel'),
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
                        onToggleExpand: (key) => setState(() {
                          _expanded.contains(key) ? _expanded.remove(key) : _expanded.add(key);
                        }),
                        onCancelCategory: (p) => _runControl(
                          () => _repo.cancelMultiSearchCategory(p.category, country: p.country),
                        ),
                        onPauseCategory: (p) => _runControl(
                          () => _repo.pauseMultiSearchCategory(p.category, country: p.country),
                        ),
                        onResumeCategory: (p) => _runControl(
                          () => _repo.resumeMultiSearchCategory(p.category, country: p.country),
                        ),
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
  final ValueChanged<CategoryProgress> onCancelCategory;
  final ValueChanged<CategoryProgress> onPauseCategory;
  final ValueChanged<CategoryProgress> onResumeCategory;

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
                      if (snapshot.exportOnly) ...[
                        _ArchiveStatusCard(snapshot: snapshot),
                        const SizedBox(height: 24),
                      ],
                      if (snapshot.overall != null) ...[
                        _OverallCard(overall: snapshot.overall!, status: snapshot.status),
                        const SizedBox(height: 24),
                      ],
                      if (snapshot.categories.isNotEmpty) ...[
                        _LeadsBarChart(categories: snapshot.categories),
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

String _formatDuration(int ms) => formatDuration(Duration(milliseconds: ms));

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
              final multiCountry = overall.totalCountries > 1;
              final tiles = [
                _StatTile(multiCountry ? 'Scans' : 'Categories', '${overall.totalCategories}', AppIcons.tag),
                if (multiCountry) _StatTile('Countries', '${overall.totalCountries}', AppIcons.globe),
                _StatTile('Completed', '${overall.completed}', AppIcons.checkCircle),
                _StatTile('Running', '${overall.running}', AppIcons.zap),
                _StatTile('Queued', '${overall.queued}', AppIcons.clock),
                _StatTile('States done', '${overall.totalStatesDone}', AppIcons.mapPinned),
                _StatTile('Businesses scanned', '${overall.totalBusinessesProcessed}', AppIcons.search),
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

/// Shown in place of the normal "Export to Excel" flow for `exportOnly`
/// jobs — these never touch Firestore, so their only output is the
/// archive built automatically once every category finishes.
class _ArchiveStatusCard extends StatelessWidget {
  const _ArchiveStatusCard({required this.snapshot});

  final MultiSearchSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final status = snapshot.archiveStatus;
    final result = snapshot.archiveResult;

    if (status == 'done' && result != null) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: AppTheme.sage100, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: AppTheme.sage500, shape: BoxShape.circle),
              child: const Icon(AppIcons.checkCircle, color: AppTheme.surface, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Excel archive ready', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.sage800)),
                  const SizedBox(height: 2),
                  Text(
                    '${result.fileName} · ${result.totalLeads} leads',
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.sage700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse(result.downloadUrl)),
              icon: const Icon(AppIcons.download, size: 16),
              label: const Text('Download'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExcelArchivePage()),
              ),
              icon: const Icon(AppIcons.inbox, size: 16),
              label: const Text('View Archive'),
            ),
          ],
        ),
      );
    }

    if (status == 'failed') {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppTheme.accent100, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
        child: Row(
          children: [
            const Icon(AppIcons.alert, color: AppTheme.accent700, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Excel archive upload failed: ${snapshot.archiveError ?? 'unknown error'}',
                style: const TextStyle(color: AppTheme.accent700, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    // pending | building | null (job still running)
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.neutral100, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Row(
        children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
          const SizedBox(width: 14),
          Text(
            snapshot.status == 'done' ? 'Building Excel archive…' : 'Excel archive will be built once the scan finishes.',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.subtle),
          ),
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

/// Bar color for the leads-found chart — a reduced 3-tier status encoding
/// (running / completed / other) rather than all 8 [CategoryScanStatus]
/// values: this app's muted palette doesn't separate that many hues well
/// under colorblind simulation, so color here is always a secondary cue —
/// every bar also carries a status icon and text label (see
/// [_LeadsBarRow]), never relied on alone.
Color _barColorForStatus(CategoryScanStatus status) {
  if (status.isRunning) return AppTheme.accent500;
  if (status == CategoryScanStatus.completed) return AppTheme.sage600;
  return AppTheme.neutral400;
}

IconData _barStatusIcon(CategoryScanStatus status) {
  if (status.isRunning) return AppIcons.zap;
  if (status == CategoryScanStatus.completed) return AppIcons.checkCircle;
  if (status == CategoryScanStatus.failed) return AppIcons.alert;
  if (status == CategoryScanStatus.cancelled) return AppIcons.close;
  return AppIcons.clock; // queued
}

/// Live-updating horizontal bar chart: one bar per (category, country) scan,
/// length proportional to leads found so far, redrawn every poll (~1.5s) as
/// the snapshot streams in. Row order is stable (queue order) rather than
/// re-sorted by value each poll, so bars don't jump around while running.
class _LeadsBarChart extends StatelessWidget {
  const _LeadsBarChart({required this.categories});

  final List<CategoryProgress> categories;

  @override
  Widget build(BuildContext context) {
    final maxLeads = categories.fold<int>(
      1,
      (m, c) => c.leadsCollected > m ? c.leadsCollected : m,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(AppIcons.barChart, size: 16, color: AppTheme.accent700),
                  const SizedBox(width: 8),
                  Text('Leads found', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const _ChartLegendItem(icon: AppIcons.zap, color: AppTheme.accent500, label: 'Running'),
              const _ChartLegendItem(icon: AppIcons.checkCircle, color: AppTheme.sage600, label: 'Completed'),
              const _ChartLegendItem(icon: AppIcons.clock, color: AppTheme.neutral400, label: 'Queued / stopped'),
            ],
          ),
          const SizedBox(height: 18),
          for (final c in categories) _LeadsBarRow(progress: c, maxLeads: maxLeads),
        ],
      ),
    );
  }
}

class _ChartLegendItem extends StatelessWidget {
  const _ChartLegendItem({required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.faint, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _LeadsBarRow extends StatelessWidget {
  const _LeadsBarRow({required this.progress, required this.maxLeads});

  final CategoryProgress progress;
  final int maxLeads;

  @override
  Widget build(BuildContext context) {
    final color = _barColorForStatus(progress.status);
    final fraction = maxLeads > 0 ? (progress.leadsCollected / maxLeads).clamp(0.0, 1.0) : 0.0;

    return Tooltip(
      message: '${progress.label}\n'
          '${progress.leadsCollected} leads · ${progress.businessesProcessed} businesses scanned\n'
          '${progress.statesDone}/${progress.statesTotal} states',
      waitDuration: const Duration(milliseconds: 300),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 176,
              child: Row(
                children: [
                  Icon(_barStatusIcon(progress.status), size: 11, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      progress.label,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.ink),
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
                        decoration: BoxDecoration(
                          color: AppTheme.neutral100,
                          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOut,
                        height: 14,
                        width: constraints.maxWidth * fraction,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 36,
              child: Text(
                '${progress.leadsCollected}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppTheme.ink),
              ),
            ),
          ],
        ),
      ),
    );
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
  final ValueChanged<CategoryProgress> onCancelCategory;
  final ValueChanged<CategoryProgress> onPauseCategory;
  final ValueChanged<CategoryProgress> onResumeCategory;

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
          // `label` (not `category`) is unique per work item — the same
          // category can appear multiple times when searching all countries.
          for (final c in categories)
            _CategoryCard(
              progress: c,
              isExpanded: expanded.contains(c.label),
              onToggleExpand: () => onToggleExpand(c.label),
              onCancel: () => onCancelCategory(c),
              onPause: () => onPauseCategory(c),
              onResume: () => onResumeCategory(c),
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
                        Text(progress.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
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
