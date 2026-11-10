import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../design_system/design_system.dart';
import '../../../domain/entities/job_filters.dart';
import '../../../domain/repositories/jobs_repository.dart';
import '../../bloc/jobs/explorer/jobs_explorer_bloc.dart';
import '../../bloc/jobs/explorer/jobs_explorer_event.dart';
import '../../bloc/jobs/job_sources_cubit.dart';
import '../../bloc/jobs/job_tracker_cubit.dart';
import '../../bloc/jobs/jobs_overview_cubit.dart';
import '../../bloc/jobs/jobs_search_cubit.dart';
import '../../bloc/jobs/scan/jobs_scan_bloc.dart';
import '../../bloc/jobs/scan/jobs_scan_event.dart';
import '../../bloc/jobs/scan/jobs_scan_state.dart';
import 'jobs_explorer_tab.dart';
import 'jobs_overview_tab.dart';
import 'jobs_scans_tab.dart';
import 'jobs_search_tab.dart';
import 'jobs_sources_tab.dart';
import 'jobs_tracker_tab.dart';

enum JobsTab {
  overview('overview', 'Overview', AppIcons.dashboard),
  search('search', 'Search', AppIcons.search),
  scans('scans', 'Scans', AppIcons.history),
  explorer('explorer', 'Jobs', AppIcons.briefcase),
  tracker('tracker', 'Tracker', AppIcons.bookmark),
  sources('sources', 'Sources', AppIcons.layers);

  const JobsTab(this.wire, this.label, this.icon);
  final String wire;
  final String label;
  final IconData icon;

  static JobsTab parse(String? v) => values.firstWhere((t) => t.wire == v, orElse: () => JobsTab.overview);
}

/// Lets a tab send the person to another tab (optionally with explorer filters).
class JobsNavigation extends InheritedWidget {
  const JobsNavigation({super.key, required this.goTo, required this.explore, required super.child});

  final void Function(JobsTab tab) goTo;
  final void Function(JobFilters filters) explore;

  static JobsNavigation of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<JobsNavigation>()!;

  @override
  bool updateShouldNotify(JobsNavigation old) => false;
}

/// **Jobs Finder** — search for jobs by place and title, run scans in the
/// background, browse what was found, and track applications.
///
/// Six tabs share one set of blocs; a tab loads when it is first opened and then
/// stays mounted, so filters and scroll positions survive switching.
class JobsHubPage extends StatelessWidget {
  const JobsHubPage({super.key, this.tab});

  final String? tab;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<JobsRepository>();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => JobsScanBloc(repo)..add(const JobsScanStarted())),
        BlocProvider(create: (_) => JobsOverviewCubit(repo)),
        BlocProvider(create: (_) => JobsSearchCubit(repo)),
        BlocProvider(create: (_) => JobsExplorerBloc(repo)),
        BlocProvider(create: (_) => JobTrackerCubit(repo)),
        BlocProvider(create: (_) => JobSourcesCubit(repo)),
      ],
      child: _Hub(initial: JobsTab.parse(tab)),
    );
  }
}

class _Hub extends StatefulWidget {
  const _Hub({required this.initial});

  final JobsTab initial;

  @override
  State<_Hub> createState() => _HubState();
}

class _HubState extends State<_Hub> {
  late JobsTab _tab = widget.initial;
  final Set<JobsTab> _visited = {};

  @override
  void initState() {
    super.initState();
    _open(_tab);
  }

  /// Marks a tab as opened and loads its data the first time.
  void _open(JobsTab tab) {
    if (!_visited.add(tab)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (tab) {
        case JobsTab.overview:
          context.read<JobsOverviewCubit>().load();
        case JobsTab.search:
          context.read<JobsSearchCubit>().load();
        case JobsTab.explorer:
          context.read<JobsExplorerBloc>().add(const JobsExplorerStarted());
        case JobsTab.tracker:
          context.read<JobTrackerCubit>().load();
        case JobsTab.sources:
          context.read<JobSourcesCubit>().load();
        case JobsTab.scans:
          break; // the scan bloc loads with the hub
      }
    });
  }

  void _goTo(JobsTab tab) {
    _open(tab);
    setState(() => _tab = tab);
  }

  @override
  void didUpdateWidget(_Hub old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial) _goTo(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    return JobsNavigation(
      goTo: _goTo,
      explore: (filters) {
        _open(JobsTab.explorer);
        context.read<JobsExplorerBloc>().add(JobsExplorerFiltersChanged(filters));
        setState(() => _tab = JobsTab.explorer);
      },
      child: BlocListener<JobsScanBloc, JobsScanState>(
        // A scan finishing changes what every other tab shows.
        listenWhen: (a, b) => a.finishedTick != b.finishedTick,
        listener: (context, _) {
          if (_visited.contains(JobsTab.overview)) context.read<JobsOverviewCubit>().scanFinished();
          if (_visited.contains(JobsTab.explorer)) context.read<JobsExplorerBloc>().add(const JobsExplorerRefreshed());
          if (_visited.contains(JobsTab.search)) context.read<JobsSearchCubit>().reloadSaved();
          if (_visited.contains(JobsTab.sources)) context.read<JobSourcesCubit>().load();
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final gutter = AppSpace.pageGutter(constraints.maxWidth);
              // The tabs pad their own content by 20; top up to the page gutter.
              final extra = gutter > 20 ? gutter - 20 : 0.0;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: AppSpace.pageMaxWidth),
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const PageHeader(
                              title: 'Jobs Finder',
                              subtitle: 'Find openings by country, state and city; scans run in the background.',
                            ),
                            const SizedBox(height: AppSpace.lg),
                            _TabPills(current: _tab, onSelect: _goTo),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: extra),
                          child: IndexedStack(
                            index: _tab.index,
                            children: [
                              for (final t in JobsTab.values) _visited.contains(t) ? _page(t) : const SizedBox.shrink(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _page(JobsTab tab) => switch (tab) {
        JobsTab.overview => const JobsOverviewTab(),
        JobsTab.search => const JobsSearchTab(),
        JobsTab.scans => const JobsScansTab(),
        JobsTab.explorer => const JobsExplorerTab(),
        JobsTab.tracker => const JobsTrackerTab(),
        JobsTab.sources => const JobsSourcesTab(),
      };
}

/// The section's tabs: an underline bar, the active one marked in the brand color.
class _TabPills extends StatelessWidget {
  const _TabPills({required this.current, required this.onSelect});

  final JobsTab current;
  final ValueChanged<JobsTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final scanning = context.select<JobsScanBloc, bool>((b) => b.state.anyActive);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final t in JobsTab.values)
              InkWell(
                onTap: () => onSelect(t),
                borderRadius: BorderRadius.circular(AppTheme.radius),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: t == current ? AppTheme.primary : Colors.transparent, width: 2)),
                  ),
                  child: Row(
                    children: [
                      Icon(t.icon, size: 16, color: t == current ? AppTheme.primary700 : AppTheme.textMuted),
                      const SizedBox(width: 8),
                      Text(
                        t.label,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: t == current ? AppTheme.primary700 : AppTheme.textSecondary),
                      ),
                      if (t == JobsTab.scans && scanning) ...[
                        const SizedBox(width: 8),
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle)),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
