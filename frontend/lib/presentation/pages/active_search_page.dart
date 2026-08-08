import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/search_countries.dart';
import '../../core/theme/app_theme.dart';
import '../bloc/search/search_bloc.dart';
import '../bloc/search/search_event.dart';
import '../bloc/search/search_state.dart';
import '../utils/duration_format.dart';
import 'results_page.dart';

const _dateRangeLabels = <String, String>{
  '7': 'Last 7 days',
  '30': 'Last 30 days',
  '90': 'Last 90 days',
  '365': 'Last 365 days',
};

class ActiveSearchPage extends StatelessWidget {
  const ActiveSearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SearchBloc, SearchState>(
      listener: (context, state) {
        if (state.status == SearchStatus.success && state.categories.length <= 1) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ResultsPage()),
          );
        } else if (state.status == SearchStatus.success && state.categories.length > 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All categories completed! Results saved to Firebase.'),
              backgroundColor: AppTheme.sage600,
            ),
          );
        }
      },
      builder: (context, state) {
        final isSequential = state.categories.length > 1;

        return Scaffold(
          appBar: AppBar(
            title: Text(isSequential ? 'Sequential Scan' : 'Nationwide Scan'),
            leading: IconButton(
              icon: const Icon(AppIcons.close),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Cancel search?'),
                    content: const Text('Stopping now will lose unsaved progress.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep Searching')),
                      TextButton(
                        onPressed: () {
                          context.read<SearchBloc>().add(const SearchCleared());
                          Navigator.pop(ctx);
                          Navigator.pop(context);
                        },
                        child: const Text('Stop', style: TextStyle(color: AppTheme.danger)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          body: Column(
            children: [
              _buildHeader(context, state),
              Expanded(
                child: state.leads.isEmpty
                    ? _buildEmptyState(context, state)
                    : _buildLiveFeed(context, state),
              ),
              if (state.status == SearchStatus.success)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to dashboard'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, SearchState state) {
    final progress = state.progress;
    final isSequential = state.categories.length > 1;
    final currentIdx = state.categories.indexOf(state.category) + 1;
    final scanned = progress?.businessesScraped ?? 0;
    final foundCount = state.leads.length;
    final yieldPercent = scanned > 0 ? (foundCount / scanned * 100) : 0.0;
    final elapsed = state.startedAt == null ? null : DateTime.now().difference(state.startedAt!);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.neutral200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.accent100,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
                child: Text(
                  isSequential
                      ? '${state.category.toUpperCase()} [$currentIdx/${state.categories.length}]'
                      : state.category.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.accent800,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ConfigChip(
                icon: AppIcons.globe,
                label: SearchCountries.byCode(state.country).name,
              ),
              const SizedBox(width: 8),
              _ConfigChip(
                icon: AppIcons.calendar,
                label: _dateRangeLabels[state.dateRange] ?? '${state.dateRange}d',
              ),
              const Spacer(),
              if (state.status == SearchStatus.loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
            ],
          ),
          if (progress != null && progress.currentState.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(AppIcons.mapPin, size: 15, color: AppTheme.subtle),
                const SizedBox(width: 6),
                Text(
                  progress.currentState,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppTheme.ink),
                ),
                if (progress.statesTotal > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '· region ${progress.statesDone + 1} of ${progress.statesTotal}',
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.faint),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            (progress?.message.isEmpty ?? true)
                ? 'Preparing search sequence…'
                : progress!.message,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 17, height: 1.3),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            child: LinearProgressIndicator(
              value: progress?.statesFraction ?? 0,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720
                  ? 6
                  : constraints.maxWidth >= 460
                      ? 3
                      : 2;
              final tiles = [
                _StatTile(icon: AppIcons.checkCircle, label: 'LEADS FOUND', value: '$foundCount'),
                _StatTile(icon: AppIcons.search, label: 'SCANNED', value: '$scanned'),
                _StatTile(
                  icon: AppIcons.percent,
                  label: 'YIELD',
                  value: scanned > 0 ? '${yieldPercent.toStringAsFixed(1)}%' : '—',
                ),
                _StatTile(
                  icon: AppIcons.mapPinned,
                  label: 'REGIONS',
                  value: '${progress?.statesDone ?? 0}/${progress?.statesTotal ?? 0}',
                ),
                _StatTile(
                  icon: AppIcons.clock,
                  label: 'ELAPSED',
                  value: elapsed == null ? '—' : formatDuration(elapsed),
                ),
                _StatTile(
                  icon: AppIcons.trendingUp,
                  label: '${SearchCountries.byCode(state.country).shortName.toUpperCase()} PROGRESS',
                  value: '${((progress?.statesFraction ?? 0) * 100).toStringAsFixed(0)}%',
                ),
              ];
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tiles.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: 74,
                ),
                itemBuilder: (context, i) => tiles[i],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, SearchState state) {
    final scanned = state.progress?.businessesScraped ?? 0;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(color: AppTheme.accent100, shape: BoxShape.circle),
            child: const Icon(AppIcons.search, size: 36, color: AppTheme.accent700),
          ),
          const SizedBox(height: 20),
          Text('Scanning business listings…',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            scanned > 0
                ? '$scanned scanned so far, 0 with a qualifying recent 1★ review — that\'s expected, most businesses won\'t match.'
                : 'Only businesses with a recent 1★ review show up here — see SCANNED above for the full count.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildLiveFeed(BuildContext context, SearchState state) {
    final leads = state.leads.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Row(
            children: [
              const Icon(AppIcons.zap, color: AppTheme.accent700, size: 18),
              const SizedBox(width: 8),
              Text(
                'LIVE FEED · ${leads.length}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: AppTheme.accent700,
                    ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: leads.length,
                itemBuilder: (context, index) {
                  final lead = leads[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radius + 4),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            color: AppTheme.sage100,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(AppIcons.checkCircle,
                              color: AppTheme.sage700, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lead.business,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${lead.location} · ${lead.category}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (lead.rating != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(AppIcons.star, color: AppTheme.accent, size: 13),
                                    const SizedBox(width: 4),
                                    Text('${lead.rating}',
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(AppIcons.externalLink, size: 18),
                          onPressed: () {
                            if (lead.mapsUrl != null) {
                              launchUrl(Uri.parse(lead.mapsUrl!));
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small pill recapping one piece of the search config (country, date
/// range) next to the category chip, so the full setup stays visible
/// without leaving this page.
class _ConfigChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ConfigChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.neutral100,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.subtle),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppTheme.subtle),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.neutral100, borderRadius: BorderRadius.circular(AppTheme.radius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppTheme.subtle),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.faint,
                    letterSpacing: 0.6,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.ink),
          ),
        ],
      ),
    );
  }
}
