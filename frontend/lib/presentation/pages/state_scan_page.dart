import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/state_city_scan_snapshot.dart';
import '../../domain/repositories/lead_repository.dart';
import '../utils/duration_format.dart';

const _pollInterval = Duration(milliseconds: 1500);
// Very large states (curated lists can run into the hundreds of cities)
// would otherwise render hundreds of chips at once, redrawn every poll —
// capped so the UI stays responsive regardless of state size; the real
// counts (used everywhere else) are never affected by this cap.
const _maxCityChipsShown = 60;

/// Live dashboard for the state-by-state, city-by-city scan — the sole
/// scan engine now that the app is US-only. Shows, for whichever category
/// is currently running: every US state in order, which one is active
/// right now, and — the detail this page exists for — exactly which
/// cities within that state are covered vs. still pending.
class StateScanPage extends StatefulWidget {
  const StateScanPage({super.key});

  @override
  State<StateScanPage> createState() => _StateScanPageState();
}

class _StateScanPageState extends State<StateScanPage> {
  Timer? _timer;
  StateCityScanSnapshot? _snapshot;
  String? _error;
  bool _loading = true;
  String? _selectedCategory;
  final Set<String> _expandedStates = {};

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
      final snap = await _repo.getStateScanStatus();
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _error = null;
        _loading = false;
        _selectedCategory ??= snap.currentCategory ?? (snap.categories.isNotEmpty ? snap.categories.first.category : null);
      });
      if (snap.status == 'done') _timer?.cancel();
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

  Future<void> _confirmCancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel scan?'),
        content: const Text(
          'The current city will finish, then the scan stops. Every state already completed stays saved — nothing already scanned is lost.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep running')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel scan', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm == true) await _runControl(_repo.cancelStateScan);
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    final isDone = snap?.status == 'done';
    final isPaused = snap?.paused ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Progress'),
        actions: [
          if (snap != null && !isDone) ...[
            IconButton(
              tooltip: isPaused ? 'Resume scan' : 'Pause scan',
              icon: Icon(isPaused ? AppIcons.checkCircle : Icons.pause_circle_outline),
              onPressed: () => _runControl(isPaused ? _repo.resumeStateScan : _repo.pauseStateScan),
            ),
            IconButton(tooltip: 'Cancel scan', icon: const Icon(AppIcons.close), onPressed: _confirmCancel),
          ],
          IconButton(tooltip: 'Refresh', icon: const Icon(AppIcons.refresh), onPressed: _poll),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (snap == null && _error != null)
                ? _ErrorState(message: _error!, onRetry: _poll)
                : snap == null || !snap.hasJob
                    ? const _NoJobState()
                    : Column(
                        children: [
                          if (_error != null) _ReconnectBanner(message: _error!),
                          Expanded(
                            child: _DashboardBody(
                              snapshot: snap,
                              selectedCategory: _selectedCategory ?? snap.categories.first.category,
                              onSelectCategory: (c) => setState(() => _selectedCategory = c),
                              expandedStates: _expandedStates,
                              onToggleState: (state) => setState(() {
                                _expandedStates.contains(state) ? _expandedStates.remove(state) : _expandedStates.add(state);
                              }),
                            ),
                          ),
                        ],
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
              child: const Icon(AppIcons.mapPinned, size: 36, color: AppTheme.accent700),
            ),
            const SizedBox(height: 20),
            Text('No scan running', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Start a scan from the Excel Scan page to see live state-by-state, city-by-city progress here.',
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

class _ReconnectBanner extends StatelessWidget {
  const _ReconnectBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: AppTheme.accent100,
      child: Row(
        children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent700)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Reconnecting — showing last known progress. ($message)',
              style: const TextStyle(fontSize: 12, color: AppTheme.accent700, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(int ms) => formatDuration(Duration(milliseconds: ms));

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.snapshot,
    required this.selectedCategory,
    required this.onSelectCategory,
    required this.expandedStates,
    required this.onToggleState,
  });

  final StateCityScanSnapshot snapshot;
  final String selectedCategory;
  final ValueChanged<String> onSelectCategory;
  final Set<String> expandedStates;
  final ValueChanged<String> onToggleState;

  @override
  Widget build(BuildContext context) {
    final cat = snapshot.categories.firstWhere(
      (c) => c.category == selectedCategory,
      orElse: () => snapshot.categories.first,
    );
    final elapsedMs = (snapshot.finishedAt ?? DateTime.now()).difference(snapshot.startedAt ?? DateTime.now()).inMilliseconds;

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
                      _OverallCard(snapshot: snapshot, elapsedMs: elapsedMs),
                      if (snapshot.categories.length > 1) ...[
                        const SizedBox(height: 20),
                        _CategorySelector(
                          categories: snapshot.categories,
                          selected: selectedCategory,
                          onSelect: onSelectCategory,
                        ),
                      ],
                      const SizedBox(height: 24),
                      _CategoryArchiveCard(category: cat),
                      const SizedBox(height: 24),
                      _StateListCard(
                        category: cat,
                        expandedStates: expandedStates,
                        onToggleState: onToggleState,
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

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.snapshot, required this.elapsedMs});

  final StateCityScanSnapshot snapshot;
  final int elapsedMs;

  @override
  Widget build(BuildContext context) {
    // Rolled up across every category, not just the one currently selected
    // in the tab strip — this card is the "whole job" summary.
    final statesTotal = snapshot.categories.fold<int>(0, (s, c) => s + c.statesTotal);
    final statesDone = snapshot.categories.fold<int>(0, (s, c) => s + c.statesDone);
    final citiesTotal = snapshot.categories.fold<int>(0, (s, c) => s + c.citiesTotal);
    final citiesDone = snapshot.categories.fold<int>(0, (s, c) => s + c.citiesDone);
    final leads = snapshot.categories.fold<int>(0, (s, c) => s + c.leadsCollected);
    final businesses = snapshot.categories.fold<int>(0, (s, c) => s + c.businessesProcessed);
    final percent = citiesTotal > 0 ? (citiesDone / citiesTotal * 100).round() : 0;
    final categoriesDone = snapshot.categories.where((c) => c.status == 'done').length;

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
              if (snapshot.status == 'running' && !snapshot.paused)
                _Chip(
                  label: snapshot.currentCategory != null ? 'Scanning "${snapshot.currentCategory}"' : 'Running',
                  color: AppTheme.sage700,
                  background: AppTheme.sage100,
                )
              else if (snapshot.paused)
                const _Chip(label: 'Paused', color: AppTheme.accent700, background: AppTheme.accent100)
              else
                const _Chip(label: 'Done', color: AppTheme.sage700, background: AppTheme.sage100),
              const Spacer(),
              Text('$percent%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.accent700)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            child: LinearProgressIndicator(value: citiesTotal > 0 ? citiesDone / citiesTotal : 0, minHeight: 10),
          ),
          const SizedBox(height: 6),
          Text('Elapsed ${_formatDuration(elapsedMs)}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 6
                  : constraints.maxWidth >= 620
                      ? 3
                      : 2;
              final tiles = [
                _StatTile('Categories', '$categoriesDone/${snapshot.categories.length}', AppIcons.tag),
                _StatTile('States done', '$statesDone/$statesTotal', AppIcons.mapPinned),
                _StatTile('Cities done', '$citiesDone/$citiesTotal', AppIcons.mapPin),
                _StatTile('Businesses scanned', '$businesses', AppIcons.search),
                _StatTile('Leads found', '$leads', AppIcons.trendingUp),
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
        ],
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({required this.categories, required this.selected, required this.onSelect});

  final List<CategoryStateProgress> categories;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = categories[i];
          final isSelected = cat.category == selected;
          final (icon, color) = switch (cat.status) {
            'done' => (AppIcons.checkCircle, AppTheme.sage700),
            'running' => (AppIcons.zap, AppTheme.accent700),
            _ => (AppIcons.clock, AppTheme.faint),
          };
          return ChoiceChip(
            label: Text('${cat.category} · ${cat.statesDone}/${cat.statesTotal}'),
            avatar: Icon(icon, size: 14, color: isSelected ? AppTheme.surface : color),
            selected: isSelected,
            onSelected: (_) => onSelect(cat.category),
            selectedColor: AppTheme.accent500,
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isSelected ? AppTheme.surface : AppTheme.ink,
            ),
            backgroundColor: AppTheme.neutral100,
            side: BorderSide.none,
          );
        },
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
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppTheme.ink)),
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
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// One category's own archive — a workbook checkpointed after every state
/// finishes, downloadable well before the whole category (let alone the
/// whole job) is done.
class _CategoryArchiveCard extends StatelessWidget {
  const _CategoryArchiveCard({required this.category});

  final CategoryStateProgress category;

  @override
  Widget build(BuildContext context) {
    final archive = category.archive;
    final result = archive.result;
    final isPartial = archive.status == 'partial';
    final isSettled = archive.status == 'done' || archive.status == 'partial';

    if (isSettled && result != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isPartial ? AppTheme.accent100 : AppTheme.sage100,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: isPartial ? AppTheme.accent500 : AppTheme.sage500, shape: BoxShape.circle),
              child: Icon(isPartial ? AppIcons.clock : AppIcons.checkCircle, color: AppTheme.surface, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPartial ? '"${category.category}" — progress saved so far' : '"${category.category}" — archive ready',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: isPartial ? AppTheme.accent800 : AppTheme.sage800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${result.fileName} · ${result.totalLeads} leads · updates after every state',
                    style: TextStyle(fontSize: 12.5, color: isPartial ? AppTheme.accent700 : AppTheme.sage700),
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
              onPressed: () => context.push('/excel-archive'),
              icon: const Icon(AppIcons.inbox, size: 16),
              label: const Text('View Archive'),
            ),
          ],
        ),
      );
    }

    if (archive.status == 'failed') {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppTheme.accent100, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
        child: Row(
          children: [
            const Icon(AppIcons.alert, color: AppTheme.accent700, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '"${category.category}" archive upload failed: ${archive.error ?? 'unknown error'}',
                style: const TextStyle(color: AppTheme.accent700, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppTheme.neutral100, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Row(
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2)),
          const SizedBox(width: 14),
          Text(
            'Saved progress for "${category.category}" will appear here once the first state finishes.',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.subtle),
          ),
        ],
      ),
    );
  }
}

/// The centerpiece of this page: every US state for the selected category,
/// in order, with the currently active one expanded to show exactly which
/// cities are covered vs. still pending — tap any state to expand/collapse
/// it, including already-finished ones (to review what it covered).
class _StateListCard extends StatelessWidget {
  const _StateListCard({required this.category, required this.expandedStates, required this.onToggleState});

  final CategoryStateProgress category;
  final Set<String> expandedStates;
  final ValueChanged<String> onToggleState;

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
            child: Row(
              children: [
                const Icon(AppIcons.mapPinned, size: 16, color: AppTheme.accent700),
                const SizedBox(width: 8),
                Text('States — "${category.category}"', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${category.statesDone}/${category.statesTotal} done',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.faint),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final state in category.states)
            _StateRow(
              state: state,
              expanded: expandedStates.contains(state.state) || state.status == 'running',
              onToggle: () => onToggleState(state.state),
            ),
        ],
      ),
    );
  }
}

(Color, Color, IconData, String) _stateStyle(String status) {
  switch (status) {
    case 'running':
      return (AppTheme.accent700, AppTheme.accent100, AppIcons.zap, 'Scanning');
    case 'done':
      return (AppTheme.sage700, AppTheme.sage100, AppIcons.checkCircle, 'Done');
    default:
      return (AppTheme.faint, AppTheme.neutral100, AppIcons.clock, 'Waiting');
  }
}

class _StateRow extends StatelessWidget {
  const _StateRow({required this.state, required this.expanded, required this.onToggle});

  final StateCityProgress state;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final (color, bg, icon, label) = _stateStyle(state.status);
    final percent = state.citiesTotal > 0 ? (state.citiesDone / state.citiesTotal * 100).round() : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: bg.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(AppTheme.radius + 2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(AppTheme.radius + 2),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(state.state, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        const SizedBox(height: 2),
                        Text(
                          state.inProgress.isNotEmpty
                              ? '$label · ${state.citiesDone}/${state.citiesTotal} cities · ${state.inProgress.length} active now · ${state.leadsCollected} leads'
                              : '$label · ${state.citiesDone}/${state.citiesTotal} cities · ${state.leadsCollected} leads',
                          style: const TextStyle(fontSize: 11.5, color: AppTheme.faint),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text('$percent%', style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 13)),
                  const SizedBox(width: 8),
                  Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppTheme.faint, size: 20),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              child: LinearProgressIndicator(value: state.citiesTotal > 0 ? state.citiesDone / state.citiesTotal : 0, minHeight: 6, backgroundColor: AppTheme.surface, color: color),
            ),
          ),
          if (expanded && state.inProgress.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _ScanningNowCard(cities: state.inProgress),
            ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 560;
                  final covered = _CityColumn(
                    title: 'Covered',
                    cities: state.covered,
                    icon: AppIcons.checkCircle,
                    color: AppTheme.sage700,
                    background: AppTheme.sage100,
                  );
                  final pending = _CityColumn(
                    title: 'Pending',
                    cities: state.pending,
                    icon: AppIcons.clock,
                    color: AppTheme.subtle,
                    background: AppTheme.neutral100,
                  );
                  final children = <Widget>[covered, pending];
                  if (state.failed.isNotEmpty) {
                    children.add(_CityColumn(
                      title: 'Failed',
                      cities: state.failed,
                      icon: AppIcons.alert,
                      color: AppTheme.danger,
                      background: AppTheme.accent100,
                    ));
                  }
                  if (stacked) {
                    return Column(
                      children: [
                        for (var i = 0; i < children.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          children[i],
                        ],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < children.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(child: children[i]),
                      ],
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The real answer to "what's going on" — every city a worker has claimed
/// right now, with its most recent live status straight from the scraper
/// (e.g. "opening listing 4/20"). Without this, claimed-but-unfinished
/// cities are invisible, which is exactly what made a working scan look
/// frozen.
class _ScanningNowCard extends StatelessWidget {
  const _ScanningNowCard({required this.cities});

  final List<CityInProgress> cities;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.accent100, borderRadius: BorderRadius.circular(AppTheme.radius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.zap, size: 13, color: AppTheme.accent700),
              const SizedBox(width: 6),
              Text('Scanning now (${cities.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.accent700)),
            ],
          ),
          const SizedBox(height: 8),
          for (final c in cities)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(strokeWidth: 1.8, color: AppTheme.accent700),
                  ),
                  const SizedBox(width: 8),
                  Text(c.city, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                  if (c.message.isNotEmpty) ...[
                    const Text(' — ', style: TextStyle(fontSize: 11.5, color: AppTheme.faint)),
                    Expanded(
                      child: Text(
                        c.message,
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.accent700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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

class _CityColumn extends StatelessWidget {
  const _CityColumn({
    required this.title,
    required this.cities,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String title;
  final List<String> cities;
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final shown = cities.take(_maxCityChipsShown).toList();
    final overflow = cities.length - shown.length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 6),
              Text('$title (${cities.length})', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          if (cities.isEmpty)
            const Text('None', style: TextStyle(fontSize: 11.5, color: AppTheme.faint))
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final city in shown)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                        child: Text(city, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                      ),
                    if (overflow > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: AppTheme.neutral200, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                        child: Text('+$overflow more', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.faint)),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

