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
              backgroundColor: AppTheme.accent,
            ),
          );
        }
      },
      builder: (context, state) {
        final progress = state.progress;
        final leads = state.leads;
        final isSequential = state.categories.length > 1;

        return Scaffold(
          appBar: AppBar(
            title: Text(isSequential ? 'Sequential Scan' : 'Nationwide Scan'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                // Confirm cancel
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Cancel Search?'),
                    content: const Text('Stopping now will lose unsaved progress.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep Searching')),
                      TextButton(
                        onPressed: () {
                          context.read<SearchBloc>().add(const SearchCleared());
                          Navigator.pop(ctx);
                          Navigator.pop(context);
                        },
                        child: const Text('Stop', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF0F4F8), Color(0xFFE8F5F3)],
              ),
            ),
            child: Column(
              children: [
                _buildHeader(context, state),
                Expanded(
                  child: leads.isEmpty
                      ? _buildEmptyState(context, state)
                      : _buildLiveFeed(context, state),
                ),
                if (state.status == SearchStatus.success)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to Dashboard'),
                    ),
                  ),
              ],
            ),
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
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isSequential 
                      ? '${state.category.toUpperCase()} [$currentIdx/${state.categories.length}]'
                      : state.category.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const Spacer(),
              if (state.status == SearchStatus.loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            (progress?.message == null || progress!.message.isEmpty) 
                ? 'Preparing search sequence...' 
                : progress.message,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 17, height: 1.3),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),
          LinearProgressIndicator(
            value: progress?.statesFraction ?? 0,
            backgroundColor: Colors.black12,
            color: AppTheme.accent,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Stat(label: 'LEADS FOUND', value: '${state.leads.length}'),
              _Stat(label: 'SCANNED', value: '${progress?.businessesScraped ?? 0}'),
              _Stat(
                label: 'USA PROGRESS', 
                value: '${((progress?.statesFraction ?? 0) * 100).toStringAsFixed(0)}%'
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
          Icon(Icons.search_rounded, size: 64, color: AppTheme.slate.withOpacity(0.2)),
          const SizedBox(height: 16),
          const Text('Scanning business listings...', style: TextStyle(color: AppTheme.slate)),
          const SizedBox(height: 8),
          const Text('Matching leads will appear here live.', style: TextStyle(color: Colors.black38, fontSize: 12)),
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
              const Icon(Icons.bolt, color: AppTheme.warn, size: 18),
              const SizedBox(width: 8),
              Text(
                'LIVE FEED',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: leads.length,
            itemBuilder: (context, index) {
              final lead = leads[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.black.withOpacity(0.05)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                  ),
                  title: Text(
                    lead.business,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text('${lead.location} · ${lead.category}'),
                      if (lead.rating != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star, color: AppTheme.warn, size: 14),
                            const SizedBox(width: 4),
                            Text('${lead.rating}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () {
                      if (lead.mapsUrl != null) {
                        launchUrl(Uri.parse(lead.mapsUrl!));
                      }
                    },
                  ),
                ),
              );
            },
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
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: AppTheme.slate.withOpacity(0.5),
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.ink,
          ),
        ),
      ],
    );
  }
}
