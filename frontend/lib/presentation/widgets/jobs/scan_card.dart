import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/job_json.dart';
import '../../../domain/entities/job_scan.dart';
import '../../utils/date_format.dart';
import 'jobs_ui.dart';

Color _statusColor(String status) => switch (status) {
      'completed' => AppTheme.success700,
      'running' || 'queued' => AppTheme.primary700,
      'failed' => AppTheme.error,
      _ => AppTheme.neutral700,
    };

String statusLabel(String status) => switch (status) {
      'queued' => 'Starting',
      'running' => 'Running',
      'paused' => 'Paused',
      'stopping' => 'Stopping',
      'completed' => 'Completed',
      'stopped' => 'Stopped',
      'failed' => 'Failed',
      'interrupted' => 'Interrupted — resumes automatically',
      _ => humanize(status),
    };

class ScanStatusPill extends StatelessWidget {
  const ScanStatusPill(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    final active = const {'running', 'queued', 'stopping'}.contains(status);
    return JobPill(
      statusLabel(status),
      icon: active ? AppIcons.refresh : (status == 'completed' ? AppIcons.checkCircle : (status == 'failed' ? AppIcons.alert : AppIcons.clock)),
      background: color.withValues(alpha: 0.12),
      foreground: color,
    );
  }
}

/// A scan's live numbers, controls and — when [expanded] — its sources and errors.
class ScanCard extends StatelessWidget {
  const ScanCard({
    super.key,
    required this.scan,
    this.busy = false,
    this.expanded = false,
    this.failures = const [],
    this.onPause,
    this.onResume,
    this.onStop,
    this.onTap,
  });

  final JobScan scan;
  final bool busy;
  final bool expanded;
  final List<JobScanFailure> failures;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onStop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = scan.totals;
    final c = scan.jobs;
    return JobsCard(
      onTap: onTap,
      border: scan.isActive ? AppTheme.primary300 : AppTheme.neutral200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(scan.searchName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium)),
              const SizedBox(width: 10),
              ScanStatusPill(scan.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (scan.startedAt != null) 'Started ${relativeTime(scan.startedAt)}',
              if (scan.trigger == 'scheduled') 'daily schedule',
              if (scan.trigger == 'resume') 'resumed',
              if (!scan.isActive) 'took ${durationLabel(scan.elapsed)}',
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: t.combinations == 0 ? null : (scan.percent / 100).clamp(0, 1), minHeight: 10, backgroundColor: AppTheme.primary100),
          ),
          const SizedBox(height: 8),
          Text(
            '${thousands(t.finished)} of ${thousands(t.combinations)} searches · ${scan.percent.toStringAsFixed(scan.percent == scan.percent.roundToDouble() ? 0 : 1)}%'
            '${t.failed > 0 ? ' · ${thousands(t.failed)} failed' : ''}${t.skipped > 0 ? ' · ${thousands(t.skipped)} skipped' : ''}'
            '${scan.enqueuing ? ' · queueing…' : ''}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSecondary),
          ),
          if (scan.current.isNotEmpty && scan.isActive) ...[
            const SizedBox(height: 12),
            for (final cur in scan.current.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(AppIcons.mapPin, size: 13, color: AppTheme.primary600),
                    const SizedBox(width: 6),
                    Expanded(child: Text('${cur.where} · ${cur.title ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary))),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 6, children: [
            JobPill('${thousands(c.found)} found', icon: AppIcons.search),
            JobPill.sage('${thousands(c.newJobs)} new', icon: AppIcons.sparkles),
            JobPill('${thousands(c.updated)} updated', icon: AppIcons.refresh),
            JobPill('${thousands(c.duplicate)} duplicates', icon: AppIcons.copy),
          ]),
          if (scan.canPause || scan.canResume || scan.canStop) ...[
            const SizedBox(height: 14),
            Row(children: [
              if (scan.canPause) FilledButton.tonalIcon(onPressed: busy ? null : onPause, icon: const Icon(AppIcons.pause, size: 15), label: const Text('Pause')),
              if (scan.canResume) FilledButton.icon(onPressed: busy ? null : onResume, icon: const Icon(AppIcons.play, size: 15), label: const Text('Resume')),
              const SizedBox(width: 10),
              if (scan.canStop)
                OutlinedButton.icon(
                  onPressed: busy ? null : onStop,
                  icon: const Icon(AppIcons.stop, size: 14),
                  label: const Text('Stop'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error),
                ),
              if (busy) const Padding(padding: EdgeInsets.only(left: 12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
            ]),
          ],
          if (expanded) ...[
            const Divider(height: 32),
            _SourceTable(scan.sources),
            if (scan.recentErrors.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Recent errors', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final e in scan.recentErrors.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      JobPill(sourceLabel(e.source), dense: true, background: AppTheme.primary100, foreground: AppTheme.primary800),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${humanize(e.kind)}: ${e.message}${e.combination == null ? '' : '  (${e.combination})'}', style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary))),
                    ],
                  ),
                ),
            ],
            if (failures.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Failed searches', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final f in failures.take(10))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• ${f.label}${f.message == null ? '' : ' — ${f.message}'}', style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SourceTable extends StatelessWidget {
  const _SourceTable(this.sources);

  final List<JobScanSource> sources;

  @override
  Widget build(BuildContext context) {
    final used = sources.where((s) => s.requests > 0 || s.errors > 0 || s.state != 'ready').toList();
    if (used.isEmpty) return Text('No source has answered yet.', style: Theme.of(context).textTheme.bodySmall);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sources', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        for (final s in used)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 108, child: Text(sourceLabel(s.id), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        s.healthy
                            ? JobPill.sage(s.stateLabel, dense: true)
                            : JobPill(s.stateLabel, dense: true, background: AppTheme.primary100, foreground: AppTheme.primary800, icon: AppIcons.alert),
                        if (s.requests > 0) JobPill('${thousands(s.requests)} requests', dense: true),
                        if (s.found > 0) JobPill('${thousands(s.found)} found', dense: true),
                        if (s.newJobs > 0) JobPill.sage('${thousands(s.newJobs)} new', dense: true),
                        if (s.errors > 0) JobPill('${thousands(s.errors)} errors', dense: true, background: AppTheme.primary100, foreground: AppTheme.primary800),
                      ]),
                      if (s.lastError != null && !s.healthy || s.errors > 0 && s.lastError != null)
                        Padding(padding: const EdgeInsets.only(top: 4), child: Text(s.lastError!, style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A one-line row for a finished scan in the history.
class ScanHistoryRow extends StatelessWidget {
  const ScanHistoryRow({super.key, required this.scan, required this.selected, required this.onTap});

  final JobScan scan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary100 : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(scan.searchName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  Text('${formatDate(scan.startedAt) ?? '—'} · ${durationLabel(scan.elapsed)}', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text('${thousands(scan.totals.completed)}/${thousands(scan.totals.combinations)} searches${scan.totals.failed > 0 ? ' · ${scan.totals.failed} failed' : ''}', style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
            ),
            Expanded(flex: 2, child: Text('${thousands(scan.jobs.newJobs)} new · ${thousands(scan.jobs.found)} found', style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary))),
            ScanStatusPill(scan.status),
          ],
        ),
      ),
    );
  }
}
