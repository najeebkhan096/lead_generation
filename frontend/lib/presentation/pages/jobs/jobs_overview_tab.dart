import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/job_application.dart';
import '../../../domain/entities/job_filters.dart';
import '../../../domain/entities/job_json.dart';
import '../../../domain/entities/job_source_info.dart';
import '../../../domain/entities/job_stats.dart';
import '../../bloc/jobs/jobs_overview_cubit.dart';
import '../../bloc/jobs/scan/jobs_scan_bloc.dart';
import '../../bloc/jobs/scan/jobs_scan_event.dart';
import '../../bloc/jobs/scan/jobs_scan_state.dart';
import '../../widgets/jobs/jobs_ui.dart';
import '../../widgets/jobs/scan_card.dart';
import 'jobs_hub_page.dart';

/// **A. Jobs overview** — totals, the last scan and how scans have been going.
class JobsOverviewTab extends StatelessWidget {
  const JobsOverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = JobsNavigation.of(context);
    return BlocBuilder<JobsOverviewCubit, JobsOverviewState>(
      builder: (context, state) {
        final stats = state.stats;
        if (state.loading && stats == null) return const Center(child: CircularProgressIndicator());
        return RefreshIndicator(
          onRefresh: () => context.read<JobsOverviewCubit>().load(refresh: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              if (state.error != null) ...[JobsErrorBanner(state.error!, onRetry: () => context.read<JobsOverviewCubit>().load(refresh: true)), const SizedBox(height: 16)],
              if (stats != null) ...[
                if (stats.total == 0)
                  JobsCard(
                    child: JobsEmpty(
                      icon: AppIcons.briefcase,
                      title: 'No jobs yet',
                      body: 'Create a search — pick countries, states or cities and the job titles you want — then start a scan. Everything it finds shows up here.',
                      action: FilledButton.icon(onPressed: () => nav.goTo(JobsTab.search), icon: const Icon(AppIcons.plus, size: 16), label: const Text('Create a search')),
                    ),
                  )
                else
                  _StatGrid(stats: stats, nav: nav),
                const SizedBox(height: 20),
                _ActiveScans(),
                _LastScan(stats: stats, onOpen: () => nav.goTo(JobsTab.scans)),
                const SizedBox(height: 20),
                _ScanHealth(stats: stats),
                const SizedBox(height: 20),
                _Pipeline(stats: stats, onOpen: () => nav.goTo(JobsTab.tracker)),
                const SizedBox(height: 20),
                _Alerts(alerts: state.alerts),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats, required this.nav});

  final JobStats stats;
  final JobsNavigation nav;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      JobStatTile(icon: AppIcons.briefcase, label: 'Jobs discovered', value: thousands(stats.total), hint: '${thousands(stats.discoveredLast24h)} in the last 24 h', onTap: () => nav.explore(const JobFilters(view: JobView.all))),
      JobStatTile(icon: AppIcons.sparkles, label: 'New jobs', value: thousands(stats.unseen), hint: 'not triaged yet', onTap: () => nav.explore(const JobFilters(view: JobView.newJobs))),
      JobStatTile(icon: AppIcons.circleCheck, label: 'Active jobs', value: thousands(stats.active), tint: AppTheme.success100, iconColor: AppTheme.success700, onTap: () => nav.explore(const JobFilters(view: JobView.active))),
      JobStatTile(icon: AppIcons.clock, label: 'Expired jobs', value: thousands(stats.expired), tint: AppTheme.neutral100, iconColor: AppTheme.neutral700, onTap: () => nav.explore(const JobFilters(view: JobView.expired))),
      JobStatTile(icon: AppIcons.building, label: 'Companies', value: thousands(stats.companies), tint: AppTheme.success100, iconColor: AppTheme.success700),
      JobStatTile(icon: AppIcons.bookmark, label: 'Applications tracked', value: thousands(stats.applications), onTap: () => nav.goTo(JobsTab.tracker)),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 900 ? 6 : (c.maxWidth >= 560 ? 3 : 2);
      return GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        // A fixed tile height (not an aspect ratio): the text inside has a fixed size,
        // so the tile must not shrink with the window.
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 160),
        children: tiles,
      );
    });
  }
}

class _ActiveScans extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JobsScanBloc, JobsScanState>(
      builder: (context, state) {
        if (state.active.isEmpty) return const SizedBox.shrink();
        final nav = JobsNavigation.of(context);
        return Column(children: [
          for (final scan in state.active)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ScanCard(
                scan: scan,
                busy: state.busy.contains(scan.id),
                onTap: () {
                  context.read<JobsScanBloc>().add(JobsScanSelected(scan.id));
                  nav.goTo(JobsTab.scans);
                },
                onPause: () => context.read<JobsScanBloc>().add(JobsScanPause(scan.id)),
                onResume: () => context.read<JobsScanBloc>().add(JobsScanResume(scan.id)),
                onStop: () => context.read<JobsScanBloc>().add(JobsScanStop(scan.id)),
              ),
            ),
        ]);
      },
    );
  }
}

class _LastScan extends StatelessWidget {
  const _LastScan({required this.stats, required this.onOpen});

  final JobStats stats;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final last = stats.lastScan;
    return JobsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobsSectionTitle('Last scan', icon: AppIcons.history, trailing: TextButton(onPressed: onOpen, child: const Text('All scans'))),
          const SizedBox(height: 14),
          if (last == null)
            Text('No scan has run yet.', style: Theme.of(context).textTheme.bodyMedium)
          else ...[
            Row(children: [
              Expanded(child: Text(last.searchName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              ScanStatusPill(last.status),
            ]),
            const SizedBox(height: 4),
            Text(last.finishedAt != null ? 'Finished ${relativeTime(last.finishedAt)} · took ${durationLabel(last.elapsed)}' : 'Started ${relativeTime(last.startedAt)}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 6, children: [
              JobPill('${thousands(last.totals.completed)}/${thousands(last.totals.combinations)} searches', icon: AppIcons.search),
              if (last.totals.failed > 0) JobPill('${thousands(last.totals.failed)} failed', icon: AppIcons.alert, background: AppTheme.primary100, foreground: AppTheme.primary800),
              JobPill.sage('${thousands(last.jobs.newJobs)} new jobs', icon: AppIcons.sparkles),
              JobPill('${thousands(last.jobs.updated)} updated'),
              JobPill('${thousands(last.jobs.duplicate)} duplicates'),
            ]),
          ],
        ],
      ),
    );
  }
}

class _ScanHealth extends StatelessWidget {
  const _ScanHealth({required this.stats});

  final JobStats stats;

  @override
  Widget build(BuildContext context) {
    final total = stats.scansFinished;
    return JobsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobsSectionTitle('Scan success', subtitle: total == 0 ? 'Nothing to measure yet.' : 'Over the last $total finished scans', icon: AppIcons.trendingUp, trailing: stats.successRate == null ? null : Text('${stats.successRate}%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.success700))),
          if (total > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 12,
                child: Row(children: [
                  if (stats.scansCompleted > 0) Expanded(flex: stats.scansCompleted, child: Container(color: AppTheme.success500)),
                  if (stats.scansStopped > 0) Expanded(flex: stats.scansStopped, child: Container(color: AppTheme.neutral300)),
                  if (stats.scansFailed > 0) Expanded(flex: stats.scansFailed, child: Container(color: AppTheme.primary600)),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 16, runSpacing: 4, children: [
              _Legend(AppTheme.success500, '${stats.scansCompleted} completed'),
              _Legend(AppTheme.neutral300, '${stats.scansStopped} stopped'),
              _Legend(AppTheme.primary600, '${stats.scansFailed} failed'),
            ]),
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
      ]);
}

class _Pipeline extends StatelessWidget {
  const _Pipeline({required this.stats, required this.onOpen});

  final JobStats stats;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return JobsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobsSectionTitle('Applications', icon: AppIcons.bookmark, trailing: TextButton(onPressed: onOpen, child: const Text('Open tracker'))),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in ApplicationStage.values) JobPill('${s.label} · ${stats.applicationsByStage[s] ?? 0}', background: (stats.applicationsByStage[s] ?? 0) > 0 ? AppTheme.primary100 : AppTheme.neutral100, foreground: (stats.applicationsByStage[s] ?? 0) > 0 ? AppTheme.primary800 : AppTheme.neutral600),
          ]),
        ],
      ),
    );
  }
}

class _Alerts extends StatelessWidget {
  const _Alerts({required this.alerts});

  final List<JobAlert> alerts;

  @override
  Widget build(BuildContext context) {
    return JobsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobsSectionTitle('Saved alerts', subtitle: 'Checked against each scan\'s new jobs. Create one from the Jobs tab with "Save as alert".', icon: AppIcons.bell),
          const SizedBox(height: 12),
          if (alerts.isEmpty) Text('No alerts yet.', style: Theme.of(context).textTheme.bodyMedium),
          for (final a in alerts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${a.summary}${a.lastMatchAt == null ? '' : ' · last matched ${relativeTime(a.lastMatchAt)} (${a.lastMatchCount})'}'),
              trailing: IconButton(tooltip: 'Delete alert', icon: const Icon(AppIcons.trash, size: 18), onPressed: () => context.read<JobsOverviewCubit>().deleteAlert(a.id)),
            ),
        ],
      ),
    );
  }
}
