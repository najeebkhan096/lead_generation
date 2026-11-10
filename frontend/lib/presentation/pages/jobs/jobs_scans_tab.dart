import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/job_search.dart';
import '../../bloc/jobs/jobs_search_cubit.dart';
import '../../bloc/jobs/scan/jobs_scan_bloc.dart';
import '../../bloc/jobs/scan/jobs_scan_event.dart';
import '../../bloc/jobs/scan/jobs_scan_state.dart';
import '../../widgets/jobs/jobs_ui.dart';
import '../../widgets/jobs/scan_card.dart';
import 'jobs_hub_page.dart';

/// **C. Scan management** — start, pause, resume and stop scans; live progress;
/// what is being searched right now; per-source errors; scan history.
class JobsScansTab extends StatefulWidget {
  const JobsScansTab({super.key});

  @override
  State<JobsScansTab> createState() => _JobsScansTabState();
}

class _JobsScansTabState extends State<JobsScansTab> {
  @override
  void initState() {
    super.initState();
    // The "run a saved search" picker needs the saved searches, even if the Search tab was never opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<JobsSearchCubit>().reloadSaved();
    });
  }

  @override
  Widget build(BuildContext context) {
    return JobsMessageListener<JobsScanBloc, JobsScanState>(
      read: (s) => s.message,
      isError: (s) => s.messageIsError,
      clear: (b) => b.add(const JobsScanMessageCleared()),
      child: BlocBuilder<JobsScanBloc, JobsScanState>(
        builder: (context, state) {
          if (state.loading && state.history.items.isEmpty && state.active.isEmpty) return const Center(child: CircularProgressIndicator());
          final bloc = context.read<JobsScanBloc>();
          final detail = state.selected;
          return RefreshIndicator(
            onRefresh: () async => bloc.add(const JobsScanRefreshed(force: true)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                const _RunPicker(),
                const SizedBox(height: 16),
                if (state.active.isEmpty)
                  JobsCard(child: Row(children: [
                    Icon(AppIcons.circleCheck, color: AppTheme.success600),
                    const SizedBox(width: 12),
                    Expanded(child: Text('No scan is running. Pick a saved search above to start one.', style: Theme.of(context).textTheme.bodyMedium)),
                  ])),
                if (state.active.isEmpty) const SizedBox(height: 16),
                for (final scan in state.active)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ScanCard(
                      scan: scan,
                      expanded: true,
                      failures: scan.id == state.selectedId ? state.failures : const [],
                      busy: state.busy.contains(scan.id),
                      onPause: () => bloc.add(JobsScanPause(scan.id)),
                      onResume: () => bloc.add(JobsScanResume(scan.id)),
                      onStop: () => _confirmStop(context, scan.id),
                      onTap: () => bloc.add(JobsScanSelected(scan.id)),
                    ),
                  ),
                if (detail != null && !detail.isActive) ...[
                  Row(children: [
                    Expanded(child: Text('Scan details', style: Theme.of(context).textTheme.titleMedium)),
                    TextButton(onPressed: () => bloc.add(const JobsScanSelected(null)), child: const Text('Close')),
                  ]),
                  const SizedBox(height: 8),
                  ScanCard(scan: detail, expanded: true, failures: state.failures),
                  const SizedBox(height: 16),
                ],
                _History(state: state),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmStop(BuildContext context, String runId) async {
    final bloc = context.read<JobsScanBloc>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop this scan?'),
        content: const Text('Searches already finished keep their jobs. The rest are left undone; start the search again to continue from scratch.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep running')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Stop scan', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (ok == true) bloc.add(JobsScanStop(runId));
  }
}

class _RunPicker extends StatefulWidget {
  const _RunPicker();

  @override
  State<_RunPicker> createState() => _RunPickerState();
}

class _RunPickerState extends State<_RunPicker> {
  String? _id;

  @override
  Widget build(BuildContext context) {
    final nav = JobsNavigation.of(context);
    return BlocBuilder<JobsSearchCubit, JobsSearchState>(
      builder: (context, search) {
        final saved = search.saved;
        final selected = saved.where((s) => s.id == _id).firstOrNull ?? saved.firstOrNull;
        return JobsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const JobsSectionTitle('Start a scan', subtitle: 'Scans run on the server; you can close this page.', icon: AppIcons.play),
              const SizedBox(height: 14),
              if (saved.isEmpty)
                Row(children: [
                  Expanded(child: Text('Create and save a search first.', style: Theme.of(context).textTheme.bodyMedium)),
                  FilledButton(onPressed: () => nav.goTo(JobsTab.search), child: const Text('Create a search')),
                ])
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 360,
                      child: DropdownButtonFormField<String>(
                        initialValue: selected?.id,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Saved search'),
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        items: [for (final s in saved) DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))],
                        onChanged: (v) => setState(() => _id = v),
                      ),
                    ),
                    BlocBuilder<JobsScanBloc, JobsScanState>(
                      builder: (context, scan) => FilledButton.icon(
                        onPressed: selected?.id == null || scan.starting ? null : () => context.read<JobsScanBloc>().add(JobsScanBegin(selected!.id!)),
                        icon: scan.starting ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary)) : const Icon(AppIcons.play, size: 16),
                        label: const Text('Start scan'),
                      ),
                    ),
                    if (selected != null) TextButton(onPressed: () { context.read<JobsSearchCubit>().edit(selected); nav.goTo(JobsTab.search); }, child: const Text('Edit search')),
                  ],
                ),
              if (selected != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_describe(selected), style: Theme.of(context).textTheme.bodySmall)),
            ],
          ),
        );
      },
    );
  }

  String _describe(JobSearch s) => '${s.countries.map((c) => c.name).join(', ')} · ${s.titles.length} title${s.titles.length == 1 ? '' : 's'}${s.schedule.enabled ? ' · daily at ${s.schedule.timeOfDay} (${s.schedule.timezone})' : ''}';
}

class _History extends StatelessWidget {
  const _History({required this.state});

  final JobsScanState state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<JobsScanBloc>();
    final finished = state.history.items.where((s) => !s.isActive).toList();
    return JobsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const JobsSectionTitle('Scan history', icon: AppIcons.history),
          const SizedBox(height: 10),
          if (finished.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('Finished scans are listed here.', style: Theme.of(context).textTheme.bodyMedium)),
          for (final s in finished) ScanHistoryRow(scan: s, selected: s.id == state.selectedId, onTap: () => bloc.add(JobsScanSelected(s.id))),
          if (state.history.hasMore)
            Center(
              child: TextButton(
                onPressed: state.loadingMoreHistory ? null : () => bloc.add(const JobsScanMoreHistory()),
                child: state.loadingMoreHistory ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Show older scans'),
              ),
            ),
        ],
      ),
    );
  }
}
