import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../models/search_batch.dart';
import '../services/lead_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/saved_business_card.dart';
import 'business_details_page.dart';

typedef _SavedBusinessesData = ({List<Lead> leads, List<SavedSearch> searches});

/// Lists every business saved to Firestore, with search and pull-to-refresh.
class SavedBusinessesPage extends StatefulWidget {
  const SavedBusinessesPage({super.key});

  @override
  State<SavedBusinessesPage> createState() => _SavedBusinessesPageState();
}

const _allCategories = 'All';

class _SavedBusinessesPageState extends State<SavedBusinessesPage> {
  final _repo = LeadRepository();
  final _searchController = TextEditingController();

  late Future<_SavedBusinessesData> _future;
  String _query = '';
  String _selectedCategory = _allCategories;
  String? _selectedSearchId;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_SavedBusinessesData> _load() async {
    final leadsFuture = _repo.fetchAllLeads();
    final searchesFuture = _repo.fetchSearches();
    return (leads: await leadsFuture, searches: await searchesFuture);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
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

  List<Lead> _filter(List<Lead> leads, String category, String? searchId) {
    var result = category == _allCategories
        ? leads
        : leads.where((lead) => lead.category == category).toList();
    if (searchId != null) {
      result = result.where((lead) => lead.searchId == searchId).toList();
    }
    if (_query.isEmpty) return result;
    return result.where((lead) {
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
              child: FutureBuilder<_SavedBusinessesData>(
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

                  final leads = snapshot.data?.leads ?? const <Lead>[];
                  final searches = snapshot.data?.searches ?? const <SavedSearch>[];

                  if (leads.isEmpty) {
                    return const _ScrollableState(child: _EmptyState());
                  }

                  final categories = _categoriesFrom(leads);
                  final effectiveCategory = categories.contains(_selectedCategory)
                      ? _selectedCategory
                      : _allCategories;
                  final searchIds = searches.map((s) => s.id).toSet();
                  final effectiveSearchId =
                      searchIds.contains(_selectedSearchId) ? _selectedSearchId : null;
                  final filtered = _filter(leads, effectiveCategory, effectiveSearchId);

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Column(
                          children: [
                            _CategoryDropdown(
                              categories: categories,
                              value: effectiveCategory,
                              onChanged: (value) => setState(() => _selectedCategory = value),
                            ),
                            if (searches.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _SearchBatchDropdown(
                                searches: searches,
                                value: effectiveSearchId,
                                onChanged: (value) => setState(() => _selectedSearchId = value),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Expanded(
                        child: filtered.isEmpty
                            ? const _ScrollableState(child: _NoResultsState())
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
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
                              ),
                      ),
                    ],
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
      initialValue: value,
      icon: const Icon(Icons.expand_more_rounded),
      decoration: InputDecoration(
        labelText: 'Category',
        prefixIcon: const Icon(Icons.filter_list_rounded),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.line),
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

/// Filters the list down to businesses saved by one specific search run
/// (e.g. "Dentist · All US states · 47 found"), or all of them.
class _SearchBatchDropdown extends StatelessWidget {
  const _SearchBatchDropdown({
    required this.searches,
    required this.value,
    required this.onChanged,
  });

  final List<SavedSearch> searches;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: value,
      icon: const Icon(Icons.expand_more_rounded),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Search',
        prefixIcon: const Icon(Icons.travel_explore_rounded),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.line),
        ),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('All searches')),
        for (final search in searches)
          DropdownMenuItem(
            value: search.id,
            child: Text(search.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
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
