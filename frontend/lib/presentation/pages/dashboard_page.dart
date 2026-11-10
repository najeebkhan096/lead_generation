import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/excel_archive.dart';
import '../../domain/entities/job.dart';
import '../../domain/entities/job_filters.dart';
import '../../domain/entities/job_stats.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/lead_page.dart';
import '../../domain/entities/multi_search_snapshot.dart';
import '../../domain/entities/paged.dart';
import '../../domain/repositories/jobs_repository.dart';
import '../../domain/repositories/lead_repository.dart';
import '../design_system/design_system.dart';
import '../utils/date_format.dart';
import 'business_details_page.dart';

enum _LoadStatus { loading, success, failure }

/// Everything the dashboard shows. Only [overview] is required; every other
/// source is optional, so one slow or failing endpoint leaves its own card
/// empty instead of taking the whole page down.
class _DashboardData {
  const _DashboardData({
    required this.overview,
    this.websiteLeads,
    this.emailLeads,
    this.emailCategories = const [],
    this.jobStats,
    this.recentJobs = const [],
    this.archives = const [],
  });

  final DashboardOverview overview;
  final int? websiteLeads;
  final int? emailLeads;
  final List<LeadCategory> emailCategories;
  final JobStats? jobStats;
  final List<Job> recentJobs;

  /// Finished and partial scans, newest first.
  final List<ExcelArchive> archives;

  int get totalLeads => overview.reviewLeads + (websiteLeads ?? 0) + (emailLeads ?? 0);

  int get businessesScanned => archives.fold(0, (sum, a) => sum + a.totalBusinessesProcessed);
}

/// Landing screen: the whole pipeline at a glance — lead totals by kind, how
/// scans have performed, what came in lately, jobs and email availability —
/// plus the one-tap way to start scanning for more.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  _LoadStatus _status = _LoadStatus.loading;
  _DashboardData? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Runs [call]; any failure becomes `null` (the section just shows "—").
  Future<T?> _optional<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (_) {
      return null;
    }
  }

  JobsRepository? _jobsRepository() {
    try {
      return context.read<JobsRepository>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    if (_data == null) setState(() => _status = _LoadStatus.loading);
    final leads = context.read<LeadRepository>();
    final jobs = _jobsRepository();
    try {
      // Server-computed numbers (a few hundred bytes) — the dashboard never
      // downloads every lead just to count them.
      final overviewFuture = leads.getDashboardOverview();
      // It may fail while the other requests are still pending; the `await`
      // below still throws it.
      overviewFuture.ignore();
      final others = await Future.wait<Object?>([
        _optional(() => leads.getLeadsPage(LeadCollection.websiteLeads, limit: 1)),
        _optional(() => leads.getLeadsPage(LeadCollection.emailLeads, limit: 1)),
        _optional(() => leads.getLeadCategories(LeadCollection.emailLeads)),
        _optional(() => leads.listExcelArchives()),
        if (jobs != null) _optional(() => jobs.stats()) else Future<Object?>.value(),
        if (jobs != null) _optional(() => jobs.jobs(const JobFilters(view: JobView.all), limit: 5)) else Future<Object?>.value(),
      ]);
      final overview = await overviewFuture;
      if (!mounted) return;

      final archives = [...((others[3] as List<ExcelArchive>?) ?? const <ExcelArchive>[])]
        ..sort((a, b) => (b.scannedAt ?? b.createdAt ?? DateTime(0)).compareTo(a.scannedAt ?? a.createdAt ?? DateTime(0)));
      setState(() {
        _data = _DashboardData(
          overview: overview,
          websiteLeads: (others[0] as LeadPage?)?.total,
          emailLeads: (others[1] as LeadPage?)?.total,
          emailCategories: (others[2] as List<LeadCategory>?) ?? const [],
          archives: archives,
          jobStats: others[4] as JobStats?,
          recentJobs: (others[5] as Paged<Job>?)?.items ?? const [],
        );
        _status = _LoadStatus.success;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _status = _LoadStatus.failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = _status == _LoadStatus.loading;
    final data = _data;
    return AppPage(
      title: 'Dashboard',
      subtitle: 'Your lead pipeline at a glance.',
      onRefresh: _load,
      actions: [
        AppButton.outlined(label: 'Refresh', icon: AppIcons.refresh, onPressed: loading ? null : _load),
        AppButton.primary(label: 'New scan', icon: AppIcons.plus, onPressed: () => context.go('/scan')),
      ],
      children: [
        const _ScanBanner(),
        if (loading)
          const _DashboardSkeleton()
        else if (_status == _LoadStatus.failure && data == null)
          _DashboardError(message: _error ?? 'Something went wrong.', onRetry: _load)
        else if (data != null) ...[
          if (data.overview.isEmpty && (data.websiteLeads ?? 0) == 0 && (data.emailLeads ?? 0) == 0)
            const _EmptyDashboard()
          else
            _DashboardBody(data: data),
        ],
        if (!loading) _DangerZone(onCleared: _load),
      ],
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data});

  final _DashboardData data;

  @override
  Widget build(BuildContext context) {
    final o = data.overview;
    String count(int? n) => n == null ? '—' : groupedNumber(n);
    final jobs = data.jobStats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(
          minTileWidth: 190,
          children: [
            StatCard(
              label: 'Total leads',
              value: groupedNumber(data.totalLeads),
              icon: AppIcons.layers,
              hint: 'Across all lead lists',
              onTap: () => context.go('/leads'),
            ),
            StatCard(
              label: '1-star review leads',
              value: groupedNumber(o.reviewLeads),
              icon: AppIcons.thumbsDown,
              tone: AppTone.error,
              delta: o.addedThisWeek > 0 ? '+${groupedNumber(o.addedThisWeek)} this week' : null,
              hint: o.whatsAppReady > 0 ? '${groupedNumber(o.whatsAppReady)} with WhatsApp' : 'Recent 1-star reviews',
              onTap: () => context.go('/leads'),
            ),
            StatCard(
              label: 'No-website leads',
              value: count(data.websiteLeads),
              icon: AppIcons.globe,
              tone: AppTone.info,
              hint: 'Listed without a website',
              onTap: () => context.go('/website-leads'),
            ),
            StatCard(
              label: 'Jobs found',
              value: count(jobs?.total),
              icon: AppIcons.briefcase,
              tone: AppTone.warning,
              hint: jobs == null ? null : '${groupedNumber(jobs.discoveredLast24h)} in the last 24h',
              onTap: () => context.go('/jobs'),
            ),
            StatCard(
              label: 'Emails available',
              value: count(data.emailLeads),
              icon: AppIcons.mail,
              tone: AppTone.success,
              hint: 'Published on their site',
              onTap: () => context.go('/email-leads'),
            ),
            StatCard(
              label: 'Businesses scanned',
              value: data.archives.isEmpty ? '—' : groupedNumber(data.businessesScanned),
              icon: AppIcons.store,
              tone: AppTone.neutral,
              hint: data.archives.isEmpty ? null : 'Across ${data.archives.length} scan${data.archives.length == 1 ? '' : 's'}',
              onTap: () => context.go('/archive'),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
        _Split(left: _ScanPerformanceCard(archives: data.archives), right: _DistributionCard(data: data)),
        const SizedBox(height: AppSpace.xl),
        _Split(left: _RecentScansCard(archives: data.archives), right: _TopCategoriesCard(categories: o.topCategories)),
        const SizedBox(height: AppSpace.xl),
        ResponsiveGrid(
          minTileWidth: 340,
          spacing: AppSpace.xl,
          children: [
            _RecentLeadsCard(leads: o.recent),
            _RecentJobsCard(jobs: data.recentJobs, available: data.jobStats != null),
            _EmailAvailabilityCard(total: data.emailLeads, categories: data.emailCategories),
          ],
        ),
      ],
    );
  }
}

/// Two cards side by side on a wide window (3 : 2), stacked on a narrow one.
class _Split extends StatelessWidget {
  const _Split({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 900) {
          return Column(children: [left, const SizedBox(height: AppSpace.xl), right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: left),
            const SizedBox(width: AppSpace.xl),
            Expanded(flex: 2, child: right),
          ],
        );
      },
    );
  }
}

// ── Cards ────────────────────────────────────────────────────────────────

String _shortDate(DateTime? d) {
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final l = d.toLocal();
  return '${m[l.month - 1]} ${l.day}';
}

class _ScanPerformanceCard extends StatelessWidget {
  const _ScanPerformanceCard({required this.archives});

  final List<ExcelArchive> archives;

  @override
  Widget build(BuildContext context) {
    // The eight most recent scans, oldest first.
    final recent = archives.take(8).toList().reversed.toList();
    final leads = archives.fold<int>(0, (s, a) => s + a.totalLeads);
    final businesses = archives.fold<int>(0, (s, a) => s + a.totalBusinessesProcessed);
    final yieldPct = businesses == 0 ? null : leads * 100 / businesses;

    return SectionCard(
      title: 'Scan performance',
      subtitle: recent.isEmpty ? null : 'Leads found by each of the last ${recent.length} scan${recent.length == 1 ? '' : 's'}',
      trailing: yieldPct == null ? null : AppBadge('${yieldPct.toStringAsFixed(1)}% of businesses became leads', tone: AppTone.primary, dense: true),
      child: recent.isEmpty || leads == 0
          ? const EmptyState(icon: AppIcons.barChart, title: 'No scans yet', message: 'Run a scan and its results will chart here.', compact: true)
          : AppBarChart(
              bars: [
                for (final a in recent)
                  ChartBar(
                    label: _shortDate(a.scannedAt ?? a.createdAt),
                    value: a.totalLeads.toDouble(),
                    tooltip: '${a.categories.take(2).join(', ')}${a.categories.length > 2 ? '…' : ''}\n'
                        '${groupedNumber(a.totalLeads)} leads from ${groupedNumber(a.totalBusinessesProcessed)} businesses',
                  ),
              ],
            ),
    );
  }
}

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({required this.data});

  final _DashboardData data;

  @override
  Widget build(BuildContext context) {
    final segments = [
      ShareSegment(label: '1-star reviews', value: data.overview.reviewLeads, tone: AppTone.primary),
      if (data.websiteLeads != null) ShareSegment(label: 'No website', value: data.websiteLeads!, tone: AppTone.info),
      if (data.emailLeads != null) ShareSegment(label: 'Email leads', value: data.emailLeads!, tone: AppTone.success),
    ];
    return SectionCard(
      title: 'Lead distribution',
      subtitle: 'How your ${groupedNumber(data.totalLeads)} leads divide',
      child: ShareBar(segments: segments),
    );
  }
}

class _RecentScansCard extends StatelessWidget {
  const _RecentScansCard({required this.archives});

  final List<ExcelArchive> archives;

  @override
  Widget build(BuildContext context) {
    final shown = archives.take(5).toList();
    return SectionCard(
      title: 'Recent scanning activity',
      trailing: AppButton.text(label: 'All scans', size: AppButtonSize.sm, trailingIcon: AppIcons.chevronRight, onPressed: () => context.go('/archive')),
      padding: EdgeInsets.zero,
      child: shown.isEmpty
          ? const EmptyState(icon: AppIcons.inbox, title: 'No scans yet', message: 'Finished and in-progress scans show up here.', compact: true)
          : Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppTheme.divider),
                  _ScanRow(archive: shown[i]),
                ],
              ],
            ),
    );
  }
}

class _ScanRow extends StatelessWidget {
  const _ScanRow({required this.archive});

  final ExcelArchive archive;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final complete = archive.status == 'complete';
    final title = archive.categories.isEmpty ? archive.fileName : archive.categories.take(2).join(', ') + (archive.categories.length > 2 ? ' +${archive.categories.length - 2}' : '');
    return InkWell(
      onTap: () => context.go('/archive'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
        child: Row(
          children: [
            IconTile(complete ? AppIcons.checkCircle : AppIcons.clock, tone: complete ? AppTone.success : AppTone.warning, size: 34),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    '${formatDate(archive.scannedAt ?? archive.createdAt) ?? 'Date unknown'} · ${groupedNumber(archive.totalBusinessesProcessed)} businesses',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${groupedNumber(archive.totalLeads)} leads', style: AppText.cell.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                AppBadge(complete ? 'Complete' : 'Partial', tone: complete ? AppTone.success : AppTone.warning, dense: true, dot: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopCategoriesCard extends StatelessWidget {
  const _TopCategoriesCard({required this.categories});

  final List<LeadCategory> categories;

  @override
  Widget build(BuildContext context) {
    final max = categories.fold<int>(1, (m, c) => c.count > m ? c.count : m);
    return SectionCard(
      title: 'Top categories',
      subtitle: '1-star review leads by category',
      child: categories.isEmpty
          ? const EmptyState(icon: AppIcons.tag, title: 'No categories yet', compact: true)
          : Column(
              children: [
                for (final c in categories) ...[
                  RankedBar(label: c.name, count: c.count, fraction: c.count / max),
                  if (c != categories.last) const SizedBox(height: AppSpace.md + 2),
                ],
              ],
            ),
    );
  }
}

class _RecentLeadsCard extends StatelessWidget {
  const _RecentLeadsCard({required this.leads});

  final List<Lead> leads;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Recent leads',
      trailing: AppButton.text(label: 'View all', size: AppButtonSize.sm, onPressed: () => context.go('/leads')),
      padding: EdgeInsets.zero,
      child: leads.isEmpty
          ? const EmptyState(icon: AppIcons.leads, title: 'Nothing recent', compact: true)
          : Column(
              children: [
                for (var i = 0; i < leads.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppTheme.divider),
                  _RecentLeadRow(lead: leads[i]),
                ],
              ],
            ),
    );
  }
}

class _RecentLeadRow extends StatelessWidget {
  const _RecentLeadRow({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final letter = lead.business.trim().isEmpty ? '?' : lead.business.trim()[0].toUpperCase();
    return InkWell(
      onTap: () => context.push('/leads/details', extra: LeadDetailsArgs(lead: lead)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppTheme.primary100, borderRadius: BorderRadius.circular(AppTheme.radius)),
              child: Text(letter, style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary700, fontSize: 14)),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lead.business, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    [if (lead.category.isNotEmpty) lead.category, if (lead.location.isNotEmpty) lead.location].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            if (lead.rating != null) ...[
              const SizedBox(width: AppSpace.sm),
              Icon(AppIcons.star, size: 13, color: AppTheme.warning),
              const SizedBox(width: 3),
              Text('${lead.rating}', style: AppText.cell.copyWith(fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecentJobsCard extends StatelessWidget {
  const _RecentJobsCard({required this.jobs, required this.available});

  final List<Job> jobs;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SectionCard(
      title: 'Recent jobs',
      trailing: AppButton.text(label: 'Jobs Finder', size: AppButtonSize.sm, onPressed: () => context.go('/jobs')),
      padding: EdgeInsets.zero,
      child: jobs.isEmpty
          ? EmptyState(
              icon: AppIcons.briefcase,
              title: available ? 'No jobs yet' : 'Jobs unavailable',
              message: available ? 'Set up a search in Jobs Finder to start collecting openings.' : 'The jobs service did not respond.',
              compact: true,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < jobs.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppTheme.divider),
                  InkWell(
                    onTap: () => context.push('/jobs/${jobs[i].id}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(jobs[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                          const SizedBox(height: 2),
                          Text(
                            [jobs[i].companyName, if (jobs[i].locationText != null) jobs[i].locationText!].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _EmailAvailabilityCard extends StatelessWidget {
  const _EmailAvailabilityCard({required this.total, required this.categories});

  final int? total;
  final List<LeadCategory> categories;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final top = categories.take(4).toList();
    final max = top.fold<int>(1, (m, c) => c.count > m ? c.count : m);
    return SectionCard(
      title: 'Email availability',
      trailing: AppButton.text(label: 'View', size: AppButtonSize.sm, onPressed: () => context.go('/email-leads')),
      child: total == null
          ? const EmptyState(icon: AppIcons.mail, title: 'Email leads unavailable', compact: true)
          : total == 0
              ? const EmptyState(icon: AppIcons.mail, title: 'No emails found yet', message: 'Businesses whose website publishes an email land here.', compact: true)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(groupedNumber(total!), style: AppText.stat),
                    const SizedBox(height: 4),
                    Text('businesses with a published email', style: text.bodySmall),
                    if (top.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.lg),
                      Text('BY CATEGORY', style: AppText.columnHeader),
                      const SizedBox(height: AppSpace.md),
                      for (final c in top) ...[
                        RankedBar(label: c.name, count: c.count, fraction: c.count / max, tone: AppTone.success),
                        if (c != top.last) const SizedBox(height: AppSpace.md),
                      ],
                    ],
                  ],
                ),
    );
  }
}

// ── States ───────────────────────────────────────────────────────────────

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      child: Column(
        children: [
          ResponsiveGrid(minTileWidth: 190, children: [for (var i = 0; i < 6; i++) const SkeletonCard()]),
          const SizedBox(height: AppSpace.xl),
          const _Split(left: SkeletonCard(height: 280), right: SkeletonCard(height: 280)),
        ],
      ),
    );
  }
}

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: EmptyState(
        icon: AppIcons.store,
        title: 'No leads saved yet',
        message: 'Run your first scan to see your dashboard fill in.',
        action: AppButton.primary(label: 'Start a scan', icon: AppIcons.search, onPressed: () => context.go('/scan')),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: EmptyState(
        icon: AppIcons.alert,
        tone: AppTone.error,
        title: 'Could not load your dashboard',
        message: message,
        action: AppButton.outlined(label: 'Retry', icon: AppIcons.refresh, onPressed: onRetry),
      ),
    );
  }
}

/// Surfaces a multi-category scan that's running or just finished in the
/// background — otherwise there's no way back to [MultiScanPage] once
/// you've navigated away from it except starting a brand new search
/// (which the backend rejects while one is already running).
class _ScanBanner extends StatefulWidget {
  const _ScanBanner();

  @override
  State<_ScanBanner> createState() => _ScanBannerState();
}

class _ScanBannerState extends State<_ScanBanner> {
  MultiSearchSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final snap = await context.read<LeadRepository>().getMultiSearchStatus();
      if (!mounted) return;
      setState(() => _snapshot = snap);
    } catch (_) {
      // Silently ignore — this is a soft "resume" hint, not core content.
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    if (snap == null || !snap.hasJob) return const SizedBox.shrink();

    final running = snap.status == 'running';
    final overall = snap.overall;
    final message = running
        ? 'Multi-category scan in progress — ${overall?.completed ?? 0}/${overall?.totalCategories ?? 0} categories done, ${overall?.totalLeads ?? 0} leads so far.'
        : 'Multi-category scan finished — ${snap.finalStats?.totalLeads ?? overall?.totalLeads ?? 0} leads collected.';

    return AppAlert(
      tone: running ? AppTone.primary : AppTone.success,
      icon: running ? AppIcons.zap : AppIcons.checkCircle,
      message: message,
      actions: [
        AppButton.outlined(
          label: running ? 'View progress' : 'View results',
          size: AppButtonSize.sm,
          onPressed: () => context.push('/multi-scan'),
        ),
      ],
    );
  }
}

// ── Danger zone ──────────────────────────────────────────────────────────

const _clearConfirmPhrase = 'DELETE ALL DATA';

/// A single irreversible action, visually set apart so it can't be tapped
/// by accident: wipes every lead and search record in Firestore. Gated
/// behind typing the exact confirm phrase, not just an OK/Cancel dialog,
/// since a stray double-tap on a plain confirm button is exactly the kind
/// of accident this needs to survive.
class _DangerZone extends StatefulWidget {
  const _DangerZone({required this.onCleared});

  final VoidCallback onCleared;

  @override
  State<_DangerZone> createState() => _DangerZoneState();
}

class _DangerZoneState extends State<_DangerZone> {
  bool _busy = false;

  Future<void> _confirmAndClear() async {
    final confirmed = await showAppDialog<bool>(context, builder: (ctx) => const _ClearAllDataDialog());
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final message = await context.read<LeadRepository>().clearAllData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      widget.onCleared();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      borderColor: AppTheme.error200,
      child: LayoutBuilder(
        builder: (context, c) {
          final button = AppButton.destructive(label: 'Clear all data', icon: AppIcons.trash, loading: _busy, onPressed: _confirmAndClear);
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Danger zone', style: text.titleMedium?.copyWith(color: AppTheme.error700)),
              const SizedBox(height: 4),
              Text(
                'Permanently deletes every lead and search record from the database. '
                'User accounts are not affected. This cannot be undone.',
                style: text.bodySmall,
              ),
            ],
          );
          if (c.maxWidth < 560) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [copy, const SizedBox(height: AppSpace.md), button]);
          }
          return Row(
            children: [
              const IconTile(AppIcons.alert, tone: AppTone.error),
              const SizedBox(width: AppSpace.md + 2),
              Expanded(child: copy),
              const SizedBox(width: AppSpace.lg),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _ClearAllDataDialog extends StatefulWidget {
  const _ClearAllDataDialog();

  @override
  State<_ClearAllDataDialog> createState() => _ClearAllDataDialogState();
}

class _ClearAllDataDialogState extends State<_ClearAllDataDialog> {
  final _controller = TextEditingController();
  bool _match = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Clear all data?',
      message: 'This permanently deletes every saved lead and search record. There is no undo. Type the phrase below to confirm.',
      icon: AppIcons.trash,
      tone: AppTone.error,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_clearConfirmPhrase, style: AppText.cell.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const SizedBox(height: AppSpace.sm + 2),
          AppTextField(
            controller: _controller,
            autofocus: true,
            hint: 'Type here',
            onChanged: (v) => setState(() => _match = v.trim() == _clearConfirmPhrase),
            onSubmitted: (_) => _match ? Navigator.pop(context, true) : null,
          ),
        ],
      ),
      actions: [
        AppButton.outlined(label: 'Cancel', onPressed: () => Navigator.pop(context, false)),
        AppButton.destructive(label: 'Delete everything', onPressed: _match ? () => Navigator.pop(context, true) : null),
      ],
    );
  }
}
