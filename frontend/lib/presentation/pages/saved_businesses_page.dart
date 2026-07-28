import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/repositories/lead_repository.dart';
import '../bloc/saved_businesses/saved_businesses_bloc.dart';
import '../bloc/saved_businesses/saved_businesses_event.dart';
import '../bloc/saved_businesses/saved_businesses_state.dart';
import '../widgets/saved_business_card.dart';
import 'business_details_page.dart';

/// Lists every business saved to Firestore, with search and pull-to-refresh.
class SavedBusinessesPage extends StatelessWidget {
  const SavedBusinessesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          SavedBusinessesBloc(context.read<LeadRepository>())..add(const SavedBusinessesRequested()),
      child: const _SavedBusinessesView(),
    );
  }
}

class _SavedBusinessesView extends StatefulWidget {
  const _SavedBusinessesView();

  @override
  State<_SavedBusinessesView> createState() => _SavedBusinessesViewState();
}

class _SavedBusinessesViewState extends State<_SavedBusinessesView> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Businesses'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                context.read<SavedBusinessesBloc>().add(const SavedBusinessesRequested()),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF0F4F8), Color(0xFFE8F5F3)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => context
                        .read<SavedBusinessesBloc>()
                        .add(SavedBusinessesSearchChanged(value)),
                    decoration: InputDecoration(
                      hintText: 'Search by name, phone, website, or email',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                context
                                    .read<SavedBusinessesBloc>()
                                    .add(const SavedBusinessesSearchChanged(''));
                              },
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: BlocBuilder<SavedBusinessesBloc, SavedBusinessesState>(
                    builder: (context, state) {
                      return RefreshIndicator(
                        onRefresh: () async {
                          context
                              .read<SavedBusinessesBloc>()
                              .add(const SavedBusinessesRequested());
                          await context.read<SavedBusinessesBloc>().stream.firstWhere(
                                (s) => s.status != SavedBusinessesStatus.loading,
                              );
                        },
                        child: _buildBody(context, state),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, SavedBusinessesState state) {
    if (state.status == SavedBusinessesStatus.loading && state.businesses.isEmpty) {
      return const _ScrollableState(child: Center(child: CircularProgressIndicator()));
    }

    if (state.status == SavedBusinessesStatus.failure) {
      return _ScrollableState(
        child: _ErrorState(
          message: state.error ?? 'Something went wrong.',
          onRetry: () =>
              context.read<SavedBusinessesBloc>().add(const SavedBusinessesRequested()),
        ),
      );
    }

    if (state.businesses.isEmpty) {
      return const _ScrollableState(child: _EmptyState());
    }

    final filtered = state.filteredBusinesses;
    if (filtered.isEmpty) {
      return const _ScrollableState(child: _NoResultsState());
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      itemCount: filtered.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${filtered.length} business${filtered.length == 1 ? '' : 'es'}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.ink,
                  ),
            ),
          );
        }
        final lead = filtered[index - 1];
        return SavedBusinessCard(
          lead: lead,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => BusinessDetailsPage(lead: lead)),
          ),
        );
      },
    );
  }
}

/// Makes non-list states (loading/empty/error) reachable by pull-to-refresh.
class _ScrollableState extends StatelessWidget {
  const _ScrollableState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(padding: const EdgeInsets.all(28), child: child),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.inbox_outlined, size: 48, color: AppTheme.slate),
        const SizedBox(height: 12),
        Text(
          'No businesses saved yet',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Run a search and tap "Save to Firebase" to see businesses here.',
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.search_off_rounded, size: 48, color: AppTheme.slate),
        const SizedBox(height: 12),
        Text(
          'No matches',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Try a different name, phone number, website, or email.',
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 48, color: Color(0xFFB91C1C)),
        const SizedBox(height: 12),
        Text(
          'Could not load businesses',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFB91C1C)),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}
