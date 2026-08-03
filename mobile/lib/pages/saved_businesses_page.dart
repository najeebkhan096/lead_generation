import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../models/search_batch.dart';
import '../services/auth_service.dart';
import '../services/lead_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/saved_business_card.dart';
import 'business_details_page.dart';

typedef _SavedBusinessesData = ({List<Lead> leads, List<SavedSearch> searches});

/// Lists every business saved to Firestore, filterable by category and by
/// search batch, with pull-to-refresh.
class SavedBusinessesPage extends StatefulWidget {
  const SavedBusinessesPage({super.key});

  @override
  State<SavedBusinessesPage> createState() => _SavedBusinessesPageState();
}

const _allCategories = 'All';

class _SavedBusinessesPageState extends State<SavedBusinessesPage> {
  final _repo = LeadRepository();

  late Future<List<Lead>> _future;
  String _selectedCategory = _allCategories;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchAllLeads();
  }

  Future<void> _refresh() async {
    setState(() => _future = _repo.fetchAllLeads());
    await _future;
  }

  /// Categories actually present among the saved businesses — not the
  /// full static category list, since a dropdown option with nothing to
  /// show would be a dead end.
  List<String> _categoriesFrom(List<Lead> leads) {
    final present = <String>{};
    for (final lead in leads) {
      final category = lead.category.trim();
      if (category.isNotEmpty) present.add(category);
    }
    final sorted = present.toList()..sort();
    return [_allCategories, ...sorted];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover Leads'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
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

            if (leads.isEmpty) {
              return const _ScrollableState(child: _EmptyState());
            }

            final categories = _categoriesFrom(leads);
            final effectiveCategory = categories.contains(_selectedCategory)
                ? _selectedCategory
                : _allCategories;
            final filtered = effectiveCategory == _allCategories
                ? leads
                : leads.where((lead) => lead.category == effectiveCategory).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: _CategoryDropdown(
                    categories: categories,
                    value: effectiveCategory,
                    onChanged: (value) => setState(() => _selectedCategory = value),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const _ScrollableState(child: _NoResultsState())
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                          itemCount: filtered.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16, top: 4),
                                child: Row(
                                  children: [
                                    Text(
                                      '${filtered.length} Potential Leads',
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    const Spacer(),
                                    Icon(Icons.auto_graph_rounded, size: 16, color: AppTheme.accent.withOpacity(0.5)),
                                  ],
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
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Category filter built only from categories present in the saved
/// businesses — never the full static category list.
class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({
    required this.categories,
    required this.value,
    required this.onChanged,
  });

  final List<String> categories;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      icon: const Icon(Icons.expand_more_rounded, color: AppTheme.accent),
      decoration: InputDecoration(
        labelText: 'Filter by Category',
        labelStyle: const TextStyle(color: AppTheme.slate, fontWeight: FontWeight.w500),
        prefixIcon: const Icon(Icons.filter_list_rounded, color: AppTheme.accent),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppTheme.accent.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppTheme.accent.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
        ),
      ),
      items: [
        for (final category in categories)
          DropdownMenuItem(value: category, child: Text(category)),
      ],
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
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
          'Try a different category or search.',
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
