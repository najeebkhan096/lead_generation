import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/job_json.dart';
import '../../../domain/entities/job_source_info.dart';
import '../../bloc/jobs/job_sources_cubit.dart';
import '../../widgets/jobs/jobs_ui.dart';

/// Job sources — what each needs, how it is doing today, and its limits.
/// API keys are set in the backend's environment, never here.
class JobsSourcesTab extends StatelessWidget {
  const JobsSourcesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return JobsMessageListener<JobSourcesCubit, JobSourcesState>(
      read: (s) => s.message,
      isError: (s) => s.messageIsError,
      clear: (c) => c.clearMessage(),
      child: BlocBuilder<JobSourcesCubit, JobSourcesState>(
        builder: (context, state) {
          if (state.loading) return const Center(child: CircularProgressIndicator());
          return RefreshIndicator(
            onRefresh: () => context.read<JobSourcesCubit>().load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                if (state.error != null) ...[JobsErrorBanner(state.error!, onRetry: () => context.read<JobSourcesCubit>().load()), const SizedBox(height: 16)],
                Text('Sources are tried in this order of trust: official APIs, public feeds, public applicant-tracking boards, then employers\' own career pages. A source that fails never stops a scan.', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                for (final s in state.sources) Padding(padding: const EdgeInsets.only(bottom: 14), child: _SourceCard(source: s, busy: state.busy.contains(s.id))),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source, required this.busy});

  final JobSourceInfo source;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobSourcesCubit>();
    final s = source;
    final failing = s.consecutiveFailures > 0;
    return JobsCard(
      border: !s.configured ? AppTheme.primary300 : AppTheme.neutral200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(s.name, style: Theme.of(context).textTheme.titleMedium)),
            if (busy) const Padding(padding: EdgeInsets.only(right: 10), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
            Switch(value: s.enabled, activeThumbColor: AppTheme.primary500, onChanged: busy ? null : (v) => cubit.setEnabled(s.id, v)),
          ]),
          Wrap(spacing: 8, runSpacing: 6, children: [
            JobPill(switch (s.type) { 'api' => 'Official API', 'ats' => 'Public job boards', 'feed' => 'Public feed', 'career' => 'Career pages', _ => humanize(s.type) }, dense: true),
            s.configured ? const JobPill.sage('Ready', icon: AppIcons.circleCheck, dense: true) : const JobPill.accent('Needs setup', icon: AppIcons.triangleAlert, dense: true),
            if (!s.enabled) const JobPill('Disabled', dense: true),
            if (failing) JobPill('${s.consecutiveFailures} failed run${s.consecutiveFailures == 1 ? '' : 's'} in a row', dense: true, background: AppTheme.primary100, foreground: AppTheme.primary800),
          ]),
          const SizedBox(height: 10),
          Text(s.description, style: Theme.of(context).textTheme.bodySmall),
          if (!s.configured && s.configurationHint != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.primary100, borderRadius: BorderRadius.circular(AppTheme.radius)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(s.requiresKey ? AppIcons.key : AppIcons.link, size: 16, color: AppTheme.primary700),
                const SizedBox(width: 10),
                Expanded(child: Text(s.configurationHint!, style: TextStyle(fontSize: 13, color: AppTheme.primary800, fontWeight: FontWeight.w600))),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 18, runSpacing: 6, children: [
            _Fact('Today', '${thousands(s.requestsToday)}${s.dailyLimit == null ? '' : ' / ${thousands(s.dailyLimit!)}'} requests'),
            _Fact('Pace', '${s.limits.perMinute}/min, ${s.limits.maxConcurrent} at once'),
            _Fact('Last success', relativeTime(s.lastSuccessAt)),
          ]),
          if (s.lastError != null && failing)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Last error: ${s.lastError}', style: TextStyle(fontSize: 12.5, color: AppTheme.primary700, fontWeight: FontWeight.w600))),
          if (s.usesBoards) ...[
            const SizedBox(height: 14),
            _BoardsEditor(source: s),
          ],
          if (s.usesCareerPages) ...[
            const SizedBox(height: 14),
            _CareerPagesEditor(source: s),
          ],
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _editLimits(context, cubit), icon: const Icon(AppIcons.settings, size: 15), label: const Text('Request limits'))),
        ],
      ),
    );
  }

  Future<void> _editLimits(BuildContext context, JobSourcesCubit cubit) async {
    final minute = TextEditingController(text: '${source.limits.perMinute}');
    final day = TextEditingController(text: '${source.limits.perDay}');
    final conc = TextEditingController(text: '${source.limits.maxConcurrent}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${source.name} — request limits'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Keeps scans inside the provider\'s quota. When the daily limit is used up, the source rests until tomorrow and the scan carries on without it.', style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 14),
          TextField(controller: minute, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Requests per minute')),
          const SizedBox(height: 12),
          TextField(controller: day, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Requests per day')),
          const SizedBox(height: 12),
          TextField(controller: conc, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Requests at once (1–8)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      cubit.setLimits(
        source.id,
        JobSourceLimits(perMinute: int.tryParse(minute.text) ?? source.limits.perMinute, perDay: int.tryParse(day.text) ?? source.limits.perDay, maxConcurrent: int.tryParse(conc.text) ?? source.limits.maxConcurrent),
      );
    }
    for (final c in [minute, day, conc]) {
      c.dispose();
    }
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ', style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
        Text(value, style: TextStyle(fontSize: 12.5, color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
      ]);
}

/// Company board tokens for Greenhouse / Lever / Ashby / Workable.
class _BoardsEditor extends StatelessWidget {
  const _BoardsEditor({required this.source});

  final JobSourceInfo source;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobSourcesCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JobsChipInput(
          label: 'Company boards',
          hint: switch (source.id) {
            'greenhouse' => 'e.g. airbnb (boards.greenhouse.io/airbnb)',
            'lever' => 'e.g. palantir (jobs.lever.co/palantir)',
            'ashby' => 'e.g. ramp (jobs.ashbyhq.com/ramp)',
            _ => 'e.g. company-name (apply.workable.com/company-name)',
          },
          values: source.boards,
          maxItems: 200,
          onAdd: (b) => cubit.setBoards(source.id, [...source.boards, b]),
          onRemove: (b) => cubit.setBoards(source.id, source.boards.where((x) => x != b).toList()),
        ),
      ],
    );
  }
}

class _CareerPagesEditor extends StatelessWidget {
  const _CareerPagesEditor({required this.source});

  final JobSourceInfo source;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobSourcesCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text('Career pages', style: Theme.of(context).textTheme.titleSmall)),
          OutlinedButton.icon(onPressed: () => _add(context, cubit), icon: const Icon(AppIcons.plus, size: 15), label: const Text('Add page')),
        ]),
        const SizedBox(height: 6),
        Text('Only pages that publish schema.org JobPosting data, and only where robots.txt allows. Pages behind a CAPTCHA or login are skipped, never worked around.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        if (source.careerPages.isEmpty) Text('None yet.', style: Theme.of(context).textTheme.bodySmall),
        for (final p in source.careerPages)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(p.company ?? p.url, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(p.url, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(tooltip: 'Remove', icon: const Icon(AppIcons.trash, size: 16), onPressed: () => cubit.setCareerPages(source.id, source.careerPages.where((x) => x.url != p.url).toList())),
          ),
      ],
    );
  }

  Future<void> _add(BuildContext context, JobSourcesCubit cubit) async {
    final company = TextEditingController();
    final url = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a career page'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: company, decoration: const InputDecoration(labelText: 'Company')),
            const SizedBox(height: 12),
            TextField(controller: url, autofocus: true, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Careers page URL', hintText: 'https://example.com/careers')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    final page = JobCareerPage(url: url.text.trim(), company: company.text.trim().isEmpty ? null : company.text.trim());
    company.dispose();
    url.dispose();
    if (ok == true && page.url.isNotEmpty) cubit.setCareerPages(source.id, [...source.careerPages, page]);
  }
}
