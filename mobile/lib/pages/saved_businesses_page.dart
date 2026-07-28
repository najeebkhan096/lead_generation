import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/lead_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/saved_business_card.dart';
import 'business_details_page.dart';

/// Lists every business saved to Firestore, with search and pull-to-refresh.
class SavedBusinessesPage extends StatefulWidget {
  const SavedBusinessesPage({super.key});

  @override
  State<SavedBusinessesPage> createState() => _SavedBusinessesPageState();
}

class _SavedBusinessesPageState extends State<SavedBusinessesPage> {
  final _repo = LeadRepository();
  final _searchController = TextEditingController();

  late Future<List<Lead>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchAllLeads();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final next = _repo.fetchAllLeads();
    setState(() => _future = next);
    await next;
  }

  List<Lead> _filter(List<Lead> leads) {
    if (_query.isEmpty) return leads;
    return leads.where((lead) {
      return (lead.business.toLowerCase().contains(_query)) ||
          (lead.phone?.toLowerCase().contains(_query) ?? false) ||
          (lead.website?.toLowerCase().contains(_query) ?? false) ||
          (lead.email?.toLowerCase().contains(_query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Businesses')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, phone, website, or email',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: _searchController.clear,
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.line),
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<Lead>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _ScrollableState(
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasError) {
                    return _ScrollableState(
                      child: _ErrorState(
                        message: snapshot.error.toString(),
                        onRetry: _refresh,
                      ),
                    );
                  }

                  final leads = snapshot.data ?? const <Lead>[];
                  final filtered = _filter(leads);

                  if (leads.isEmpty) {
                    return const _ScrollableState(child: _EmptyState());
                  }

                  if (filtered.isEmpty) {
                    return const _ScrollableState(child: _NoResultsState());
                  }

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
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
                          MaterialPageRoute(
                            builder: (_) => BusinessDetailsPage(lead: lead),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
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
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: child,
              ),
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
          'Run a search in LeadFinder web and tap Save to Firebase.',
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
  final Future<void> Function() onRetry;

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
