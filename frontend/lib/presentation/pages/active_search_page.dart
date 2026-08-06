import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../bloc/search/search_bloc.dart';
import '../bloc/search/search_event.dart';
import '../bloc/search/search_state.dart';
import 'results_page.dart';

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
              const Spacer(),
              if (state.status == SearchStatus.loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
            ],
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Stat(label: 'LEADS FOUND', value: '${state.leads.length}'),
              _Stat(label: 'SCANNED', value: '${progress?.businessesScraped ?? 0}'),
              _Stat(
                label: 'USA PROGRESS',
                value: '${((progress?.statesFraction ?? 0) * 100).toStringAsFixed(0)}%',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, SearchState state) {
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
          Text('Matching leads will appear here live.',
              style: Theme.of(context).textTheme.bodyMedium),
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
                'LIVE FEED',
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

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppTheme.faint,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
      ],
    );
  }
}
