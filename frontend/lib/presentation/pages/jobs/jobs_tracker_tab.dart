import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/job_application.dart';
import '../../bloc/jobs/job_tracker_cubit.dart';
import '../../utils/date_format.dart';
import '../../widgets/jobs/jobs_ui.dart';
import 'jobs_hub_page.dart';

/// **F. Application tracker** — Saved → Applied → Assessment → Interview →
/// Offered, or Rejected / Withdrawn. Move an application between stages and keep notes.
class JobsTrackerTab extends StatelessWidget {
  const JobsTrackerTab({super.key});

  @override
  Widget build(BuildContext context) {
    return JobsMessageListener<JobTrackerCubit, JobTrackerState>(
      read: (s) => s.message,
      isError: (s) => s.messageIsError,
      clear: (c) => c.clearMessage(),
      child: BlocBuilder<JobTrackerCubit, JobTrackerState>(
        builder: (context, state) {
          if (state.loading) return const Center(child: CircularProgressIndicator());
          if (state.error != null && state.columns.isEmpty) {
            return Padding(padding: const EdgeInsets.all(20), child: JobsErrorBanner(state.error!, onRetry: () => context.read<JobTrackerCubit>().load()));
          }
          if (state.total == 0) {
            return JobsEmpty(
              icon: AppIcons.bookmark,
              title: 'Nothing tracked yet',
              body: 'Save a job, or mark one as applied, from the Jobs tab and it appears here.',
              action: FilledButton(onPressed: () => JobsNavigation.of(context).goTo(JobsTab.explorer), child: const Text('Browse jobs')),
            );
          }
          return RefreshIndicator(
            onRefresh: () => context.read<JobTrackerCubit>().load(),
            child: LayoutBuilder(builder: (context, c) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: SizedBox(
                  height: c.maxHeight - 32,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final stage in ApplicationStage.values) Padding(padding: const EdgeInsets.only(right: 14), child: _Column(stage: stage, state: state)),
                    ],
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.stage, required this.state});

  final ApplicationStage stage;
  final JobTrackerState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobTrackerCubit>();
    final column = state.columns[stage];
    final items = column?.items ?? const <JobApplication>[];
    final count = state.counts[stage] ?? items.length;
    final negative = stage == ApplicationStage.rejected || stage == ApplicationStage.withdrawn;
    return Container(
      width: 300,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: negative ? AppTheme.neutral100 : AppTheme.success100.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
            child: Row(children: [
              Expanded(child: Text(stage.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              JobPill('$count', dense: true, background: AppTheme.surface),
            ]),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text('Empty', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600)))
                : ListView.separated(
                    itemCount: items.length + (column?.hasMore == true ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      if (i == items.length) {
                        return Center(
                          child: TextButton(
                            onPressed: state.loadingMore.contains(stage) ? null : () => cubit.loadMore(stage),
                            child: state.loadingMore.contains(stage) ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Show more'),
                          ),
                        );
                      }
                      return _ApplicationCard(app: items[i]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.app});

  final JobApplication app;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobTrackerCubit>();
    return JobsCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => context.push<bool>('/jobs/${Uri.encodeComponent(app.jobId)}').then((changed) => changed == true ? cubit.load() : null),
            child: Text(app.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, height: 1.25)),
          ),
          const SizedBox(height: 4),
          Text([app.companyName, app.locationText].whereType<String>().where((s) => s.isNotEmpty).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
          if (app.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(app.notes, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppTheme.neutral700, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 8),
          Text('Updated ${formatDate(app.updatedAt) ?? '—'}', style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
          const SizedBox(height: 8),
          Row(children: [
            PopupMenuButton<ApplicationStage>(
              tooltip: 'Move to…',
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radius)),
              onSelected: (s) => cubit.move(app, s),
              itemBuilder: (_) => [
                for (final s in ApplicationStage.values)
                  if (s != app.stage) PopupMenuItem(value: s, child: Text('Move to ${s.label}')),
              ],
              child: const JobPill.accent('Move', icon: AppIcons.chevronDown),
            ),
            const Spacer(),
            IconButton(tooltip: 'Notes', visualDensity: VisualDensity.compact, icon: const Icon(AppIcons.edit, size: 16), onPressed: () => _editNotes(context, cubit)),
            if (app.applyUrl != null || app.sourceUrl != null) IconButton(tooltip: 'Open the posting', visualDensity: VisualDensity.compact, icon: const Icon(AppIcons.externalLink, size: 16), onPressed: () => openExternal(context, app.applyUrl ?? app.sourceUrl)),
            IconButton(tooltip: 'Remove from tracker', visualDensity: VisualDensity.compact, icon: const Icon(AppIcons.trash, size: 16), onPressed: () => cubit.remove(app)),
          ]),
        ],
      ),
    );
  }

  Future<void> _editNotes(BuildContext context, JobTrackerCubit cubit) async {
    final c = TextEditingController(text: app.notes);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Notes — ${app.title}', maxLines: 2, overflow: TextOverflow.ellipsis),
        content: SizedBox(width: 460, child: TextField(controller: c, autofocus: true, maxLines: 8, maxLength: 4000, decoration: const InputDecoration(hintText: 'Contacts, interview dates, what was said…'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save notes')),
        ],
      ),
    );
    c.dispose();
    if (result != null) cubit.saveNotes(app, result);
  }
}
