import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design_system/design_system.dart';
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

  /// Picks a stopped no-website scan back up (the covered cities are skipped).
  Future<void> _resumeStopped(String runId) async {
    try {
      await _repo.resumeNoWebsiteRun(runId);
      // Polling stopped when the scan finished; start it again for the resumed run.
      _timer?.cancel();
      _timer = Timer.periodic(_pollInterval, (_) => _poll());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
    await _poll();
  }

  Future<void> _confirmCancel() async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Stop scan?',
      message: 'The current city will finish, then the scan stops. Every state already completed stays saved — nothing already scanned is lost.',
      confirmLabel: 'Stop scan',
      cancelLabel: 'Keep running',
      destructive: true,
    );
    if (confirm) await _runControl(_repo.cancelStateScan);
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    final isDone = snap?.status == 'done';
    final isPaused = snap?.paused ?? false;
    final gutter = AppSpace.pageGutter(MediaQuery.sizeOf(context).width);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _loading
          ? const LoadingView(label: 'Loading scan status…')
          : (snap == null && _error != null)
              ? _ErrorState(message: _error!, onRetry: _poll)
              : snap == null || !snap.hasJob
                  ? const _NoJobState()
                  : Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 0),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: AppSpace.pageMaxWidth),
                              child: PageHeader(
                                title: snap.isNoWebsite ? 'No-website scan progress' : '1-star scan progress',
                                subtitle: snap.canResume
                                    ? 'Stopped — resume to carry on; the cities already covered are skipped.'
                                    : isDone
                                        ? 'This scan has finished.'
                                        : (isPaused ? 'Paused — resume to carry on.' : 'Live, state by state and city by city.'),
                                onBack: () => context.go('/scan'),
                                actions: [
                                  if (snap.canResume)
                                    AppButton.primary(label: 'Resume scan', icon: AppIcons.play, onPressed: () => _resumeStopped(snap.runId!)),
                                  if (!isDone)
                                    AppButton.outlined(
                                      label: isPaused ? 'Resume' : 'Pause',
                                      icon: isPaused ? AppIcons.play : AppIcons.pause,
                                      onPressed: () => _runControl(isPaused ? _repo.resumeStateScan : _repo.pauseStateScan),
                                    ),
                                  if (!isDone)
                                    AppButton.destructive(label: 'Stop', icon: AppIcons.stop, onPressed: _confirmCancel),
                                  AppButton.outlined(label: 'Refresh', icon: AppIcons.refresh, onPressed: _poll),
                                ],
                              ),
                            ),
                          ),
                        ),
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
    );
  }
}

class _NoJobState extends StatelessWidget {
  const _NoJobState();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: AppIcons.mapPinned,
      title: 'No scan running',
      message: 'Start a scan from the Scan page to see live state-by-state, city-by-city progress here.',
      action: AppButton.primary(label: 'New scan', icon: AppIcons.plus, onPressed: () => context.go('/scan')),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: AppIcons.alert,
      tone: AppTone.error,
      title: 'Could not load scan status',
      message: message,
      action: AppButton.outlined(label: 'Retry', icon: AppIcons.refresh, onPressed: onRetry),
    );
  }
}

class _ReconnectBanner extends StatelessWidget {
  const _ReconnectBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final gutter = AppSpace.pageGutter(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, AppSpace.md, gutter, 0),
      child: AppAlert(tone: AppTone.warning, icon: AppIcons.refresh, message: 'Reconnecting — showing last known progress. ($message)'),
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
          padding: EdgeInsets.fromLTRB(AppSpace.pageGutter(MediaQuery.sizeOf(context).width), AppSpace.xl, AppSpace.pageGutter(MediaQuery.sizeOf(context).width), AppSpace.xxxl),
          sliver: SliverList.list(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: AppSpace.pageMaxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (snapshot.stoppedForSignIn) ...[
                        const _StoppedForSignInBanner(),
                        const SizedBox(height: 16),
                      ],
                      if (snapshot.blocked != null) ...[
                        _GoogleCheckBanner(info: snapshot.blocked!),
                        const SizedBox(height: 16),
                      ],
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
                      if (snapshot.isNoWebsite)
                        _NoWebsiteResultsCard(category: cat)
                      else
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

/// Shown when the scan stopped itself because Google asked to sign in: the
/// saved session ended, so carrying on would have missed reviews.
/// Google's "unusual traffic" check has the scan paused. The scan waits and
/// looks again by itself; nothing is retried through the check.
class _GoogleCheckBanner extends StatelessWidget {
  const _GoogleCheckBanner({required this.info});

  final ScanBlockInfo info;

  String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final retry = info.retryAt;
    return AppAlert(
      tone: AppTone.warning,
      icon: AppIcons.clock,
      title: 'Paused by Google',
      message: 'Google is showing its "unusual traffic" check for this network (since ${_clock(info.since)}). '
          'The scan is waiting instead of pushing through it, and nothing is lost: the city it was on will be redone. '
          '${retry != null ? 'It looks again at ${_clock(retry)}' : 'It looks again soon'}'
          '${info.checks > 0 ? ' (checked ${info.checks}×)' : ''} and continues by itself once Google serves results again.',
    );
  }
}

class _StoppedForSignInBanner extends StatelessWidget {
  const _StoppedForSignInBanner();

  @override
  Widget build(BuildContext context) {
    return const AppAlert(
      tone: AppTone.error,
      title: 'The scan stopped',
      message: 'Google asked to sign in, so the saved session has expired. '
          'Nothing was missed silently. The city it was on was left out of the results. '
          'Sign in again on the Scan page, then open the Archive and Resume this scan.',
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
    final needsRecheck = snapshot.needsRecheck;
    final percent = citiesTotal > 0 ? (citiesDone / citiesTotal * 100).round() : 0;
    final categoriesDone = snapshot.categories.where((c) => c.status == 'done').length;

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.xl - 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Overall progress', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: AppSpace.md),
              if (snapshot.status == 'running' && !snapshot.paused)
                AppBadge(snapshot.currentCategory != null ? 'Scanning "${snapshot.currentCategory}"' : 'Running', tone: AppTone.primary, dot: true)
              else if (snapshot.paused)
                const AppBadge('Paused', tone: AppTone.warning, dot: true)
              else
                const AppBadge('Done', tone: AppTone.success, icon: AppIcons.check),
              const Spacer(),
              Text('$percent%', style: AppText.stat.copyWith(fontSize: 22)),
            ],
          ),
          const SizedBox(height: AppSpace.md + 2),
          AppProgressBar(value: citiesTotal > 0 ? citiesDone / citiesTotal : 0, height: 8, tone: snapshot.paused ? AppTone.warning : (snapshot.status == 'done' ? AppTone.success : AppTone.primary)),
          const SizedBox(height: 8),
          Text('Elapsed ${_formatDuration(elapsedMs)}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            [
              if (snapshot.coverage != null && snapshot.coverage != 'custom') 'Coverage: ${snapshot.coverage}',
              if (snapshot.pacePerMinute != null)
                'pace ${snapshot.pacePerMinute!.round()}/min (tunes itself, ceiling ${snapshot.paceMax?.round() ?? '?'})',
              if (snapshot.skippedWithoutOpening > 0)
                '${snapshot.skippedWithoutOpening} listings not opened (repeats, or provably no 1-star)',
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpace.xl - 4),
          ResponsiveGrid(
            minTileWidth: 150,
            spacing: AppSpace.md,
            children: [
              _StatTile('Categories', '$categoriesDone/${snapshot.categories.length}', AppIcons.tag),
              _StatTile('States done', '$statesDone/$statesTotal', AppIcons.mapPinned),
              _StatTile('Cities done', '$citiesDone/$citiesTotal', AppIcons.mapPin),
              _StatTile('Businesses scanned', '$businesses', AppIcons.search),
              _StatTile(snapshot.isNoWebsite ? 'No-website leads found' : 'Review leads found', '$leads', AppIcons.trendingUp),
              _StatTile(snapshot.isNoWebsite ? 'Listings not opened' : 'Not fully read', '$needsRecheck', AppIcons.alert),
            ],
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
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (context, i) {
          final cat = categories[i];
          final isSelected = cat.category == selected;
          final (icon, tone) = switch (cat.status) {
            'done' => (AppIcons.checkCircle, AppTone.success),
            'running' => (AppIcons.zap, AppTone.primary),
            _ => (AppIcons.clock, AppTone.neutral),
          };
          return InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            onTap: () => onSelect(cat.category),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md + 2),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary100 : AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radius),
                border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: isSelected ? AppTheme.primary700 : tone.onSurface),
                  const SizedBox(width: 8),
                  Text(
                    '${cat.category} · ${cat.statesDone}/${cat.statesTotal}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSelected ? AppTheme.primary800 : AppTheme.textPrimary),
                  ),
                ],
              ),
            ),
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
      height: 84,
      padding: const EdgeInsets.all(AppSpace.md + 2),
      decoration: BoxDecoration(
        color: AppTheme.isDark ? AppTheme.neutral100 : AppTheme.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppTheme.textMuted),
          const Spacer(),
          Text(value, style: AppText.stat.copyWith(fontSize: 18)),
          Text(label, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// A no-website scan has no workbook: its leads go straight to the No Website Leads list.
class _NoWebsiteResultsCard extends StatelessWidget {
  const _NoWebsiteResultsCard({required this.category});

  final CategoryStateProgress category;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg + 4),
      decoration: BoxDecoration(
        color: AppTone.info.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTone.info.border),
      ),
      child: Wrap(
        spacing: AppSpace.lg,
        runSpacing: AppSpace.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IconTile(AppIcons.globe, tone: AppTone.info),
              const SizedBox(width: AppSpace.md + 2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('"${category.category}" — ${category.leadsCollected} no-website lead${category.leadsCollected == 1 ? '' : 's'} so far',
                        style: text.titleMedium?.copyWith(color: AppTone.info.onSurface)),
                    const SizedBox(height: 2),
                    Text(
                      'Saved to No Website Leads as each city finishes. A business is saved only when its Maps listing is confirmed to have no website.',
                      style: TextStyle(fontSize: 12.5, color: AppTone.info.onSurface),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppButton.primary(label: 'View leads', icon: AppIcons.globe, onPressed: () => context.go('/website-leads')),
        ],
      ),
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
      final tone = isPartial ? AppTone.warning : AppTone.success;
      return Container(
        padding: const EdgeInsets.all(AppSpace.lg + 4),
        decoration: BoxDecoration(
          color: tone.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: tone.border),
        ),
        child: Wrap(
          spacing: AppSpace.lg,
          runSpacing: AppSpace.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTile(isPartial ? AppIcons.clock : AppIcons.checkCircle, tone: tone),
                const SizedBox(width: AppSpace.md + 2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPartial ? '"${category.category}" — progress saved so far' : '"${category.category}" — archive ready',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: tone.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${result.fileName} · ${result.totalLeads} leads · updates after every state',
                        style: TextStyle(fontSize: 12.5, color: tone.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppButton.outlined(label: 'Download', icon: AppIcons.download, onPressed: () => launchUrl(Uri.parse(result.downloadUrl))),
                const SizedBox(width: AppSpace.sm),
                AppButton.primary(label: 'View archive', icon: AppIcons.inbox, onPressed: () => context.go('/archive')),
              ],
            ),
          ],
        ),
      );
    }

    if (archive.status == 'failed') {
      return AppAlert(
        tone: AppTone.error,
        message: '"${category.category}" archive upload failed: ${archive.error ?? 'unknown error'}',
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Row(
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2)),
          const SizedBox(width: AppSpace.md + 2),
          Expanded(
            child: Text(
              'Saved progress for "${category.category}" will appear here once the first state finishes.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
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
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(AppIcons.mapPinned, size: 16, color: AppTheme.primary700),
                const SizedBox(width: 8),
                Text('States — "${category.category}"', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${category.statesDone}/${category.statesTotal} done',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted),
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
      return (AppTheme.primary700, AppTheme.primary100, AppIcons.zap, 'Scanning');
    case 'done':
      return (AppTheme.success700, AppTheme.success100, AppIcons.checkCircle, 'Done');
    default:
      return (AppTheme.textMuted, AppTheme.neutral100, AppIcons.clock, 'Waiting');
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
                              : '$label · ${state.citiesDone}/${state.citiesTotal} cities · ${state.leadsCollected} leads${state.incompleteBusinesses + state.skippedListings > 0 ? ' · ${state.incompleteBusinesses + state.skippedListings} not fully read' : ''}',
                          style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text('$percent%', style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 13)),
                  const SizedBox(width: 8),
                  Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppTheme.textMuted, size: 20),
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
                    color: AppTheme.success700,
                    background: AppTheme.success100,
                  );
                  final pending = _CityColumn(
                    title: 'Pending',
                    cities: state.pending,
                    icon: AppIcons.clock,
                    color: AppTheme.textSecondary,
                    background: AppTheme.neutral100,
                  );
                  final children = <Widget>[covered, pending];
                  if (state.failed.isNotEmpty) {
                    children.add(_CityColumn(
                      title: 'Failed',
                      cities: state.failed,
                      icon: AppIcons.alert,
                      color: AppTheme.error,
                      background: AppTheme.primary100,
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
      decoration: BoxDecoration(color: AppTheme.primary100, borderRadius: BorderRadius.circular(AppTheme.radius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.zap, size: 13, color: AppTheme.primary700),
              const SizedBox(width: 6),
              Text('Scanning now (${cities.length})', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.primary700)),
            ],
          ),
          const SizedBox(height: 8),
          for (final c in cities)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(strokeWidth: 1.8, color: AppTheme.primary700),
                  ),
                  const SizedBox(width: 8),
                  Text(c.city, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                  if (c.message.isNotEmpty) ...[
                    Text(' — ', style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                    Expanded(
                      child: Text(
                        c.message,
                        style: TextStyle(fontSize: 11.5, color: AppTheme.primary700),
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
            Text('None', style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted))
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
                        child: Text('+$overflow more', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
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

