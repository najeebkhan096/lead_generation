import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/job.dart';
import '../../../domain/entities/job_application.dart';
import '../../../domain/entities/job_json.dart';
import '../../../domain/entities/job_source_info.dart';
import '../../../domain/repositories/jobs_repository.dart';
import '../../bloc/jobs/job_details_cubit.dart';
import '../../utils/date_format.dart';
import '../../widgets/jobs/jobs_ui.dart';

/// **E. Job details** — the full posting, its requirements, where it was found,
/// and the actions on it. Opens at `/jobs/:id`, so a link to a job works cold.
class JobDetailsPage extends StatelessWidget {
  const JobDetailsPage({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => JobDetailsCubit(context.read<JobsRepository>(), jobId)..load(),
      child: const _View(),
    );
  }
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JobDetailsCubit, JobDetailsState>(
      builder: (context, state) {
        // Going back tells the list whether this job was changed, so it can reload.
        return PopScope<bool>(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) context.canPop() ? context.pop(state.changed) : context.go('/jobs?tab=explorer');
          },
          child: JobsMessageListener<JobDetailsCubit, JobDetailsState>(
            read: (s) => s.message,
            isError: (s) => s.messageIsError,
            clear: (c) => c.clearMessage(),
            child: Scaffold(
              appBar: AppBar(
                leading: IconButton(icon: const Icon(AppIcons.arrowLeft), tooltip: 'Back to jobs', onPressed: () => context.canPop() ? context.pop(state.changed) : context.go('/jobs?tab=explorer')),
                title: const Text('Job details'),
              ),
              body: SafeArea(
                child: state.loading
                    ? const Center(child: CircularProgressIndicator())
                    : state.job == null
                        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: JobsErrorBanner(state.error ?? 'Job not found.', onRetry: () => context.read<JobDetailsCubit>().load())))
                        : _Body(job: state.job!, state: state),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.job, required this.state});

  final Job job;
  final JobDetailsState state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
          children: [
            _Header(job: job, state: state),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, c) {
              final main = _Main(job: job);
              final side = _Side(job: job, state: state);
              if (c.maxWidth < 860) return Column(children: [main, const SizedBox(height: 16), side]);
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 17, child: main), const SizedBox(width: 16), Expanded(flex: 10, child: side)]);
            }),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.job, required this.state});

  final Job job;
  final JobDetailsState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobDetailsCubit>();
    final stage = ApplicationStage.parse(job.applicationStage);
    return JobsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(job.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 16, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [Icon(AppIcons.building, size: 15, color: AppTheme.textMuted), const SizedBox(width: 6), Text(job.companyName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))]),
            if (job.companyWebsite != null) InkWell(onTap: () => openExternal(context, job.companyWebsite), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(AppIcons.globe, size: 14, color: AppTheme.primary600), const SizedBox(width: 6), Text(shortHost(job.companyWebsite!), style: TextStyle(color: AppTheme.primary700, fontWeight: FontWeight.w700))])),
            Row(mainAxisSize: MainAxisSize.min, children: [Icon(AppIcons.mapPin, size: 15, color: AppTheme.textMuted), const SizedBox(width: 6), Text(job.placeLabel)]),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (job.isExpired) JobPill(humanize(job.status), icon: AppIcons.clock) else const JobPill.sage('Active', icon: AppIcons.circleCheck),
            if (stage != null) JobPill.accent(stage.label, icon: AppIcons.bookmark),
            if (job.salaryLabel != null) JobPill.sage(job.salaryLabel!, icon: AppIcons.banknote),
            if (job.workArrangement != null) JobPill(humanize(job.workArrangement), icon: AppIcons.laptop),
            if (job.employmentType != null) JobPill(humanize(job.employmentType), icon: AppIcons.clock),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            if (job.applyUrl != null)
              FilledButton.icon(onPressed: () => openExternal(context, job.applyUrl), icon: const Icon(AppIcons.send, size: 16), label: const Text('Apply on the employer\'s site')),
            if (job.sourceUrl != null)
              OutlinedButton.icon(onPressed: () => openExternal(context, job.sourceUrl), icon: const Icon(AppIcons.externalLink, size: 16), label: const Text('Open original posting')),
            if (stage == null || stage == ApplicationStage.saved)
              OutlinedButton.icon(onPressed: state.busy || stage != null ? null : () => cubit.setStage(ApplicationStage.saved), icon: const Icon(AppIcons.bookmark, size: 16), label: Text(stage == null ? 'Save' : 'Saved')),
            PopupMenuButton<ApplicationStage>(
              tooltip: 'Move in the tracker',
              enabled: !state.busy,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radius)),
              onSelected: cubit.setStage,
              itemBuilder: (_) => [for (final s in ApplicationStage.values) CheckedPopupMenuItem(value: s, checked: s == stage, child: Text(s.label))],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(border: Border.all(color: AppTheme.neutral300, width: 1.5), borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(AppIcons.chevronDown, size: 14), SizedBox(width: 8), Text('Application status', style: TextStyle(fontWeight: FontWeight.w700))]),
              ),
            ),
            if (stage != null) TextButton(onPressed: state.busy ? null : cubit.removeFromTracker, child: const Text('Remove from tracker')),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 4, children: [
            TextButton.icon(onPressed: state.busy ? null : cubit.verify, icon: state.busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.refresh, size: 15), label: const Text('Check it is still open')),
            if (!job.isExpired) TextButton(onPressed: state.busy ? null : cubit.markExpired, child: const Text('Mark as expired')) else TextButton(onPressed: state.busy ? null : cubit.markActive, child: const Text('Mark as active again')),
          ]),
        ],
      ),
    );
  }
}

String shortHost(String url) {
  final uri = Uri.tryParse(url.contains('://') ? url : 'https://$url');
  return (uri?.host.isNotEmpty ?? false) ? uri!.host.replaceFirst(RegExp(r'^www\.'), '') : url;
}

class _Main extends StatelessWidget {
  const _Main({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final description = job.description;
    return Column(
      children: [
        JobsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const JobsSectionTitle('Description', icon: AppIcons.fileText),
              const SizedBox(height: 14),
              if (description == null)
                Text('The source did not provide a description. Open the original posting for the full text.', style: Theme.of(context).textTheme.bodyMedium)
              else
                SelectableText(description, style: TextStyle(fontSize: 14.5, height: 1.6, color: AppTheme.textPrimary)),
              if (description != null && job.sources.any((s) => s.source == 'adzuna' || s.source == 'jooble') && job.sources.length == 1)
                Padding(padding: const EdgeInsets.only(top: 12), child: Text('This source only shares a short excerpt. The original posting has the full text.', style: Theme.of(context).textTheme.bodySmall)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        JobsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const JobsSectionTitle('Requirements', icon: AppIcons.award),
              const SizedBox(height: 14),
              _Row('Experience', job.experienceText ?? job.experienceLabel),
              _Row('Education', job.educationText),
              if (job.requiredSkills.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Skills mentioned as required', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final s in job.requiredSkills) JobPill.accent(s)]),
              ],
              if (job.preferredSkills.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Nice to have', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final s in job.preferredSkills) JobPill.sage(s)]),
              ],
              if (job.requiredSkills.isEmpty && job.preferredSkills.isEmpty && job.experienceText == null && job.educationText == null)
                Text('The posting does not state specific requirements in a form we could read.', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        if (job.responsibilities != null && job.responsibilities!.isNotEmpty) ...[
          const SizedBox(height: 16),
          JobsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const JobsSectionTitle('Responsibilities', icon: AppIcons.check),
                const SizedBox(height: 12),
                for (final r in job.responsibilities!)
                  Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: EdgeInsets.only(top: 7, right: 10), child: Icon(Icons.circle, size: 5, color: AppTheme.primary500)), Expanded(child: SelectableText(r, style: const TextStyle(height: 1.5)))])),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 116, child: Text(label, style: TextStyle(fontSize: 13, color: AppTheme.textMuted, fontWeight: FontWeight.w700))),
          Expanded(child: Text(value ?? 'Not stated', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: value == null ? AppTheme.neutral400 : AppTheme.textPrimary))),
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.job, required this.state});

  final Job job;
  final JobDetailsState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        JobsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const JobsSectionTitle('At a glance', icon: AppIcons.target),
              const SizedBox(height: 14),
              _Row('Salary', job.salaryLabel),
              _Row('Type', job.employmentType == null ? null : humanize(job.employmentType)),
              _Row('Arrangement', job.workArrangement == null ? null : humanize(job.workArrangement)),
              _Row('Level', job.experienceLevel == null ? null : humanize(job.experienceLevel)),
              _Row('Posted', formatDate(job.postedAt)),
              _Row('Apply by', formatDate(job.deadlineAt)),
              _Row('Found', formatDate(job.discoveredAt)),
              _Row('Last checked', relativeTime(job.lastVerifiedAt)),
              if (job.recruiter != null) ...[
                _Row('Recruiter', [job.recruiter!['name'], job.recruiter!['email'], job.recruiter!['phone']].whereType<String>().join(' · ')),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SourcesCard(job: job),
        const SizedBox(height: 16),
        _NotesCard(job: job, busy: state.busy),
        const SizedBox(height: 16),
        _MatchCard(state: state),
      ],
    );
  }
}

class _SourcesCard extends StatelessWidget {
  const _SourcesCard({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    return JobsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobsSectionTitle('Found on', subtitle: job.sources.length > 1 ? 'Seen on ${job.sources.length} sources and merged into one job' : null, icon: AppIcons.layers),
          const SizedBox(height: 10),
          for (final s in job.sources)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(sourceLabel(s.source), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('first seen ${formatDate(s.firstSeenAt) ?? '—'} · last seen ${relativeTime(s.lastSeenAt)}${s.missedChecks > 0 ? ' · missed in ${s.missedChecks} check${s.missedChecks == 1 ? '' : 's'}' : ''}'),
              trailing: (s.sourceUrl ?? s.applyUrl) == null ? null : IconButton(tooltip: 'Open on ${sourceLabel(s.source)}', icon: const Icon(AppIcons.externalLink, size: 16), onPressed: () => openExternal(context, s.sourceUrl ?? s.applyUrl)),
            ),
          if (job.sources.isEmpty) Text('—', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _NotesCard extends StatefulWidget {
  const _NotesCard({required this.job, required this.busy});

  final Job job;
  final bool busy;

  @override
  State<_NotesCard> createState() => _NotesCardState();
}

class _NotesCardState extends State<_NotesCard> {
  late final _c = TextEditingController(text: widget.job.notes ?? '');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return JobsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const JobsSectionTitle('My notes', icon: AppIcons.edit),
          const SizedBox(height: 12),
          TextField(controller: _c, maxLines: 5, maxLength: 2000, decoration: const InputDecoration(hintText: 'Anything worth remembering about this job')),
          Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: widget.busy ? null : () => context.read<JobDetailsCubit>().saveNotes(_c.text), child: const Text('Save notes'))),
        ],
      ),
    );
  }
}

/// Compares a CV with the job's requirements. Runs only when asked, and locally
/// on the backend: no AI service is called and nothing is stored.
class _MatchCard extends StatefulWidget {
  const _MatchCard({required this.state});

  final JobDetailsState state;

  @override
  State<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<_MatchCard> {
  final _cv = TextEditingController();

  @override
  void dispose() {
    _cv.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.state.match;
    return JobsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const JobsSectionTitle('Compare with my CV', subtitle: 'Paste your CV as text. Skills and experience are compared here, on the server; nothing is sent to an AI service or saved.', icon: AppIcons.sparkles),
          const SizedBox(height: 12),
          TextField(controller: _cv, maxLines: 6, decoration: const InputDecoration(hintText: 'Paste your CV text…')),
          const SizedBox(height: 10),
          Row(children: [
            FilledButton.icon(
              onPressed: widget.state.matching ? null : () => context.read<JobDetailsCubit>().compareWithCv(_cv.text),
              icon: widget.state.matching ? SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary)) : const Icon(AppIcons.target, size: 16),
              label: const Text('Compare'),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: () async { final d = await Clipboard.getData('text/plain'); if (d?.text != null) _cv.text = d!.text!; }, child: const Text('Paste')),
          ]),
          if (match != null) ...[const Divider(height: 28), _MatchResult(match: match)],
        ],
      ),
    );
  }
}

class _MatchResult extends StatelessWidget {
  const _MatchResult({required this.match});

  final JobMatch match;

  @override
  Widget build(BuildContext context) {
    final color = match.score >= 70 ? AppTheme.success600 : (match.score >= 40 ? AppTheme.primary500 : AppTheme.neutral500);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('${match.score}%', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: color, height: 1)),
          const SizedBox(width: 14),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: match.score / 100, minHeight: 10, color: color, backgroundColor: AppTheme.neutral100))),
        ]),
        const SizedBox(height: 14),
        if (match.matchingSkills.isNotEmpty) ...[
          Text('Matching skills', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final s in match.matchingSkills) JobPill.sage(s, dense: true)]),
          const SizedBox(height: 12),
        ],
        if (match.missingSkills.isNotEmpty) ...[
          Text('Missing skills', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final s in match.missingSkills) JobPill.accent(s, dense: true)]),
          const SizedBox(height: 12),
        ],
        Text(
          switch (match.experienceCompatible) {
            true => 'Experience: ${match.candidateYears} years vs ${match.requiredYears}+ asked — enough.',
            false => 'Experience: ${match.candidateYears} years vs ${match.requiredYears}+ asked — short of it.',
            null => 'Experience: not enough information to compare.',
          },
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSecondary),
        ),
        if (match.relevantRequirements.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Requirements your CV speaks to', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final r in match.relevantRequirements) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $r', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary))),
        ],
        if (match.suggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Suggested CV improvements', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final r in match.suggestions) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $r', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary))),
        ],
      ],
    );
  }
}
