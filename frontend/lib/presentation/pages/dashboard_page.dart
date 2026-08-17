import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/multi_search_snapshot.dart';
import '../../domain/repositories/lead_repository.dart';
import '../utils/date_format.dart';

enum _LoadStatus { loading, success, failure }

/// Landing screen: an at-a-glance read on the whole saved-lead database —
/// totals, category mix, and what just came in — plus the one-tap way to
/// start scanning for more.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  _LoadStatus _status = _LoadStatus.loading;
  List<Lead> _leads = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _status = _LoadStatus.loading);
    try {
      final leads = await context.read<LeadRepository>().getSavedBusinesses();
      if (!mounted) return;
      setState(() {
        _leads = leads;
        _status = _LoadStatus.success;
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
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
                sliver: SliverList.list(
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Header(onRefresh: _load),
                            const SizedBox(height: 8),
                            const _MultiScanBanner(),
                            const SizedBox(height: 24),
                            if (_status == _LoadStatus.loading)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 80),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            else if (_status == _LoadStatus.failure)
                              _DashboardError(message: _error!, onRetry: _load)
                            else
                              _DashboardBody(leads: _leads),
                            if (_status != _LoadStatus.loading) ...[
                              const SizedBox(height: 32),
                              _DangerZoneCard(onCleared: _load),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dashboard', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 6),
              Text(
                'Your saved-lead database at a glance.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: onRefresh,
          icon: const Icon(AppIcons.refresh),
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.surface,
            padding: const EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }
}

/// Surfaces a multi-category scan that's running or just finished in the
/// background — otherwise there's no way back to [MultiScanPage] once
/// you've navigated away from it except starting a brand new search
/// (which the backend rejects while one is already running).
class _MultiScanBanner extends StatefulWidget {
  const _MultiScanBanner();

  @override
  State<_MultiScanBanner> createState() => _MultiScanBannerState();
}

class _MultiScanBannerState extends State<_MultiScanBanner> {
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
    final text = running
        ? 'Multi-category scan in progress — ${overall?.completed ?? 0}/${overall?.totalCategories ?? 0} categories done, ${overall?.totalLeads ?? 0} leads so far.'
        : 'Multi-category scan finished — ${snap.finalStats?.totalLeads ?? overall?.totalLeads ?? 0} leads collected.';

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: running ? AppTheme.accent100 : AppTheme.sage100,
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: running ? AppTheme.accent200 : AppTheme.sage200,
                shape: BoxShape.circle,
              ),
              child: Icon(
                running ? AppIcons.zap : AppIcons.checkCircle,
                size: 18,
                color: running ? AppTheme.accent700 : AppTheme.sage700,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: running ? AppTheme.accent800 : AppTheme.sage800,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () => context.push('/multi-scan'),
              child: Text(running ? 'View progress' : 'View results'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.leads});

  final List<Lead> leads;

  @override
  Widget build(BuildContext context) {
    if (leads.isEmpty) {
      return const _EmptyDashboard();
    }

    final stats = _Stats.from(leads);
    final categories = _categoryBreakdown(leads);
    final recent = _recentLeads(leads);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatGrid(stats: stats),
        const SizedBox(height: 32),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 760;
            final breakdown = _CategoryBreakdownCard(categories: categories);
            final recentCard = _RecentLeadsCard(leads: recent);
            if (stacked) {
              return Column(
                children: [breakdown, const SizedBox(height: 20), recentCard],
              );
            }
            // Not IntrinsicHeight: both cards contain their own
            // LayoutBuilder (the category bars), which explicitly can't
            // answer intrinsic-dimension queries. Top-aligned instead —
            // the cards' natural heights read fine independently.
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: breakdown),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: recentCard),
              ],
            );
          },
        ),
      ],
    );
  }

  static List<MapEntry<String, int>> _categoryBreakdown(List<Lead> leads) {
    final counts = <String, int>{};
    for (final lead in leads) {
      final category = lead.category.trim();
      if (category.isEmpty) continue;
      counts[category] = (counts[category] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(6).toList();
  }

  static List<Lead> _recentLeads(List<Lead> leads) {
    final withDates = leads.where((l) => l.savedAt != null).toList()
      ..sort((a, b) => b.savedAt!.compareTo(a.savedAt!));
    return withDates.take(5).toList();
  }
}

/// Precomputed dashboard metrics, kept in one place so the numbers shown
/// in the stat grid are guaranteed consistent with each other.
const _clearConfirmPhrase = 'DELETE ALL DATA';

/// A single irreversible action, visually set apart so it can't be tapped
/// by accident: wipes every lead and search record in Firestore. Gated
/// behind typing the exact confirm phrase, not just an OK/Cancel dialog,
/// since a stray double-tap on a plain confirm button is exactly the kind
/// of accident this needs to survive.
class _DangerZoneCard extends StatefulWidget {
  const _DangerZoneCard({required this.onCleared});

  final VoidCallback onCleared;

  @override
  State<_DangerZoneCard> createState() => _DangerZoneCardState();
}

class _DangerZoneCardState extends State<_DangerZoneCard> {
  bool _busy = false;

  Future<void> _confirmAndClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ClearAllDataDialog(),
    );
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
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.accent200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: AppTheme.accent100, shape: BoxShape.circle),
            child: const Icon(AppIcons.alert, size: 19, color: AppTheme.accent700),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Danger zone', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Permanently deletes every lead and search record from the database. '
                  'User accounts are not affected. This cannot be undone.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          OutlinedButton(
            onPressed: _busy ? null : _confirmAndClear,
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
            child: _busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Text('Clear all data'),
          ),
        ],
      ),
    );
  }
}

class _ClearAllDataDialog extends StatefulWidget {
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
    return AlertDialog(
      title: const Text('Clear all data?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently deletes every saved lead and search record. '
            'There is no undo. Type the phrase below to confirm.',
          ),
          const SizedBox(height: 16),
          Text(
            _clearConfirmPhrase,
            style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Type here'),
            onChanged: (v) => setState(() => _match = v.trim() == _clearConfirmPhrase),
            onSubmitted: (_) => _match ? Navigator.pop(context, true) : null,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _match ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          child: const Text('Delete everything'),
        ),
      ],
    );
  }
}

class _Stats {
  const _Stats({
    required this.total,
    required this.whatsAppReady,
    required this.categories,
    required this.markets,
    required this.avgRating,
    required this.addedThisWeek,
  });

  final int total;
  final int whatsAppReady;
  final int categories;
  final int markets;
  final double? avgRating;
  final int addedThisWeek;

  factory _Stats.from(List<Lead> leads) {
    final ratings = leads.where((l) => l.rating != null).map((l) => l.rating!);
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    return _Stats(
      total: leads.length,
      whatsAppReady: leads
          .where((l) => l.hasWhatsApp || (l.waLink?.isNotEmpty ?? false))
          .length,
      categories: leads.map((l) => l.category.trim()).where((c) => c.isNotEmpty).toSet().length,
      markets: leads.map((l) => l.location.trim()).where((l) => l.isNotEmpty).toSet().length,
      avgRating: ratings.isEmpty
          ? null
          : ratings.reduce((a, b) => a + b) / ratings.length,
      addedThisWeek: leads.where((l) => l.savedAt != null && l.savedAt!.isAfter(weekAgo)).length,
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

  final _Stats stats;

  @override
  Widget build(BuildContext context) {
    final waPercent = stats.total == 0
        ? 0
        : (stats.whatsAppReady / stats.total * 100).round();

    final cards = [
      _StatCard(
        icon: AppIcons.store,
        label: 'Total leads',
        value: '${stats.total}',
        tint: AppTheme.accent100,
        iconColor: AppTheme.accent700,
      ),
      _StatCard(
        icon: AppIcons.chat,
        label: 'WhatsApp-ready',
        value: '$waPercent%',
        sublabel: '${stats.whatsAppReady} businesses',
        tint: AppTheme.sage100,
        iconColor: AppTheme.sage700,
      ),
      _StatCard(
        icon: AppIcons.tag,
        label: 'Categories',
        value: '${stats.categories}',
        tint: AppTheme.accent100,
        iconColor: AppTheme.accent700,
      ),
      _StatCard(
        icon: AppIcons.mapPinned,
        label: 'Markets covered',
        value: '${stats.markets}',
        tint: AppTheme.sage100,
        iconColor: AppTheme.sage700,
      ),
      _StatCard(
        icon: AppIcons.star,
        label: 'Avg. rating',
        value: stats.avgRating == null ? '—' : stats.avgRating!.toStringAsFixed(1),
        tint: AppTheme.accent100,
        iconColor: AppTheme.accent700,
      ),
      _StatCard(
        icon: AppIcons.trendingUp,
        label: 'Added this week',
        value: '${stats.addedThisWeek}',
        tint: AppTheme.sage100,
        iconColor: AppTheme.sage700,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 6
            : constraints.maxWidth >= 700
                ? 3
                : constraints.maxWidth >= 460
                    ? 2
                    : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            mainAxisExtent: 128,
          ),
          itemBuilder: (context, index) => cards[index],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
    required this.iconColor,
    this.sublabel,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? sublabel;
  final Color tint;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sublabel ?? label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.faint,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _CategoryBreakdownCard extends StatelessWidget {
  const _CategoryBreakdownCard({required this.categories});

  final List<MapEntry<String, int>> categories;

  @override
  Widget build(BuildContext context) {
    final maxCount = categories.isEmpty
        ? 1
        : categories.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.barChart, size: 18, color: AppTheme.accent700),
              const SizedBox(width: 10),
              Text('Top categories', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 20),
          if (categories.isEmpty)
            Text('No categories yet.', style: Theme.of(context).textTheme.bodyMedium)
          else
            for (final entry in categories)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _CategoryBar(
                  label: entry.key,
                  count: entry.value,
                  fraction: entry.value / maxCount,
                ),
              ),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.label,
    required this.count,
    required this.fraction,
  });

  final String label;
  final int count;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                color: AppTheme.accent700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          child: Stack(
            children: [
              Container(height: 8, color: AppTheme.neutral100),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fraction.clamp(0.04, 1.0)),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => FractionallySizedBox(
                  widthFactor: value,
                  alignment: Alignment.centerLeft,
                  child: child,
                ),
                child: Container(
                  height: 8,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.accent400, AppTheme.accent600],
                    ),
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

class _RecentLeadsCard extends StatelessWidget {
  const _RecentLeadsCard({required this.leads});

  final List<Lead> leads;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.clock, size: 18, color: AppTheme.sage700),
              const SizedBox(width: 10),
              Text('Recently added', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 16),
          if (leads.isEmpty)
            Text('Nothing recent.', style: Theme.of(context).textTheme.bodyMedium)
          else
            for (final lead in leads) _RecentLeadRow(lead: lead),
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
    final letter = lead.business.trim().isEmpty ? '?' : lead.business.trim()[0].toUpperCase();
    final warm = lead.business.hashCode.isEven;
    final date = formatDate(lead.savedAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: warm ? AppTheme.accent100 : AppTheme.sage100,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              letter,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: warm ? AppTheme.accent700 : AppTheme.sage700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lead.business,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  lead.category,
                  style: const TextStyle(fontSize: 12, color: AppTheme.faint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (date != null)
            Text(date, style: const TextStyle(fontSize: 11, color: AppTheme.faint)),
        ],
      ),
    );
  }
}

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 32),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(color: AppTheme.accent100, shape: BoxShape.circle),
            child: const Icon(AppIcons.store, size: 36, color: AppTheme.accent700),
          ),
          const SizedBox(height: 20),
          Text('No leads saved yet', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Run your first Excel scan to see your dashboard fill in.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.push('/excel-scan'),
            icon: const Icon(AppIcons.download, size: 19),
            label: const Text('Start Excel scan'),
          ),
        ],
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: AppTheme.accent100, shape: BoxShape.circle),
            child: const Icon(AppIcons.alert, size: 30, color: AppTheme.accent700),
          ),
          const SizedBox(height: 18),
          Text('Could not load your dashboard', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.danger),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(AppIcons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
