import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/job.dart';
import '../../../domain/entities/job_json.dart';
import '../../bloc/jobs/explorer/jobs_explorer_event.dart';
import '../../utils/date_format.dart';
import 'jobs_ui.dart';

/// One discovered job in the explorer: the facts a person scans for (who, where,
/// pay, experience, skills, when, from where) and the actions on it.
class JobCard extends StatelessWidget {
  const JobCard({
    super.key,
    required this.job,
    required this.selected,
    required this.busy,
    required this.onToggleSelect,
    required this.onOpen,
    required this.onTriage,
  });

  final Job job;
  final bool selected;
  final bool busy;
  final VoidCallback onToggleSelect;
  final VoidCallback onOpen;
  final ValueChanged<JobTriage> onTriage;

  static const _maxSkills = 6;

  @override
  Widget build(BuildContext context) {
    final skills = job.requiredSkills;
    final posted = job.postedAt;
    return JobsCard(
      padding: const EdgeInsets.fromLTRB(8, 14, 16, 14),
      border: selected ? AppTheme.primary400 : AppTheme.neutral200,
      color: job.isExpired ? AppTheme.neutral100 : AppTheme.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(value: selected, onChanged: (_) => onToggleSelect(), visualDensity: VisualDensity.compact, activeColor: AppTheme.primary500),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: onOpen,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          job.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: job.isExpired ? AppTheme.neutral600 : AppTheme.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Wrap(spacing: 6, children: [
                        if (job.isExpired) JobPill(humanize(job.status), icon: AppIcons.clock, dense: true),
                        if (job.userState != 'new') JobPill.sage(humanize(job.applicationStage ?? job.userState), icon: AppIcons.bookmark, dense: true),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 14,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Meta(AppIcons.building, job.companyName, strong: true),
                    _Meta(AppIcons.mapPin, job.placeLabel),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (job.salaryLabel != null) JobPill.sage(job.salaryLabel!, icon: AppIcons.banknote),
                    if (job.workArrangement != null) JobPill(humanize(job.workArrangement), icon: AppIcons.laptop),
                    if (job.employmentType != null) JobPill(humanize(job.employmentType), icon: AppIcons.clock),
                    if (job.experienceLabel != null) JobPill(job.experienceLabel!, icon: AppIcons.award),
                    if (posted != null) JobPill('Posted ${formatDate(posted)}', icon: AppIcons.calendar),
                  ],
                ),
                if (skills.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final s in skills.take(_maxSkills)) JobPill.accent(s, dense: true),
                    if (skills.length > _maxSkills) JobPill('+${skills.length - _maxSkills}', dense: true),
                  ]),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'via ${job.sourceNames.map(sourceLabel).join(', ')}${job.discoveredAt == null ? '' : ' · found ${relativeTime(job.discoveredAt)}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (busy) const Padding(padding: EdgeInsets.only(right: 8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: onOpen,
                      icon: const Icon(AppIcons.eye, size: 15),
                      label: const Text('Details'),
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.primary100, foregroundColor: AppTheme.primary800, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), minimumSize: const Size(0, 38)),
                    ),
                    if (job.sourceUrl != null)
                      OutlinedButton.icon(
                        onPressed: () => openExternal(context, job.sourceUrl),
                        icon: const Icon(AppIcons.externalLink, size: 15),
                        label: const Text('Original'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14)),
                      ),
                    if (job.applyUrl != null)
                      OutlinedButton.icon(
                        onPressed: () => openExternal(context, job.applyUrl),
                        icon: const Icon(AppIcons.send, size: 15),
                        label: const Text('Apply'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14)),
                      ),
                    if (job.userState == 'new' && !job.isExpired)
                      TextButton.icon(onPressed: busy ? null : () => onTriage(JobTriage.save), icon: const Icon(AppIcons.bookmark, size: 15), label: const Text('Save')),
                    PopupMenuButton<JobTriage>(
                      tooltip: 'More actions',
                      enabled: !busy,
                      icon: Icon(AppIcons.more, size: 18, color: AppTheme.textSecondary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radius)),
                      onSelected: onTriage,
                      itemBuilder: (_) => [
                        if (job.userState != 'saved') const PopupMenuItem(value: JobTriage.save, child: Text('Save')),
                        if (job.userState != 'applied') const PopupMenuItem(value: JobTriage.applied, child: Text('Mark as applied')),
                        if (job.userState != 'rejected') const PopupMenuItem(value: JobTriage.rejected, child: Text('Mark as rejected')),
                        if (job.userState != 'new') const PopupMenuItem(value: JobTriage.reset, child: Text('Remove from tracker')),
                        const PopupMenuDivider(),
                        if (!job.isExpired) const PopupMenuItem(value: JobTriage.expired, child: Text('Mark as expired')) else const PopupMenuItem(value: JobTriage.reactivate, child: Text('Mark as active again')),
                        PopupMenuItem(value: JobTriage.delete, child: Text('Delete…', style: TextStyle(color: AppTheme.error))),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text, {this.strong = false});

  final IconData icon;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textMuted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, color: strong ? AppTheme.textPrimary : AppTheme.textSecondary, fontWeight: strong ? FontWeight.w700 : FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
