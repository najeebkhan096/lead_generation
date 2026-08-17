import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/website_lead_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/page_header.dart';
import '../widgets/saved_business_card.dart';
import '../widgets/search_field.dart';
import 'business_details_page.dart';
import 'saved_businesses_page.dart' show StateBadge;

/// Lists every business a scan found with no website — the same
/// discover/browse flow as the "Direct" saved-businesses tab, just backed
/// by the `websiteLeads` collection instead of `leads`.
class WebsiteLeadsPage extends StatefulWidget {
  const WebsiteLeadsPage({super.key});

  @override
  State<WebsiteLeadsPage> createState() => _WebsiteLeadsPageState();
}

const _allCategories = 'All';

class _WebsiteLeadsPageState extends State<WebsiteLeadsPage> {
  final _repo = WebsiteLeadRepository();
  String _selectedCategory = _allCategories;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  late final Stream<List<Lead>> _leadsStream;

  @override
  void initState() {
    super.initState();
    _leadsStream = _repo.getLeadsStream();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
    final t = context.tokens;
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<Lead>>(
          stream: _leadsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _ScrollableState(
                child: _ErrorState(
                  message: snapshot.error.toString(),
                  onRetry: () async => setState(() {}),
                ),
              );
            }

            final allLeads = snapshot.data ?? const <Lead>[];

            final categories = _categoriesFrom(allLeads);
            final effectiveCategory = categories.contains(_selectedCategory)
                ? _selectedCategory
                : _allCategories;

            var filtered = effectiveCategory == _allCategories
                ? allLeads
                : allLeads.where((lead) => lead.category == effectiveCategory).toList();

            if (_searchQuery.isNotEmpty) {
              final query = _searchQuery.toLowerCase();
              filtered = filtered.where((lead) {
                final name = lead.business.toLowerCase();
                final location = lead.location.toLowerCase();
                final phone = (lead.phone ?? '').toLowerCase();
                return name.contains(query) ||
                    location.contains(query) ||
                    phone.contains(query);
              }).toList();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: 'Website leads',
                  subtitle: filtered.isEmpty && _searchQuery.isEmpty
                      ? 'Businesses found with no website will land here'
                      : '${filtered.length} ${filtered.length == 1 ? 'business' : 'businesses'} found',
                  trailing: HeaderBadge(
                    icon: AppIcons.globe,
                    background: t.accentTint,
                    foreground: t.accentDeep,
                  ),
                ),
                if (allLeads.isEmpty)
                  const Expanded(child: _ScrollableState(child: _EmptyState()))
                else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        SearchField(
                          controller: _searchController,
                          value: _searchQuery,
                          hintText: 'Search website leads...',
                          onChanged: (value) => setState(() => _searchQuery = value),
                        ),
                        const SizedBox(height: 12),
                        _CategoryDropdown(
                          categories: categories,
                          selected: effectiveCategory,
                          countFor: (category) => category == _allCategories
                              ? allLeads.length
                              : allLeads
                                  .where((l) => l.category == category)
                                  .length,
                          onSelected: (value) =>
                              setState(() => _selectedCategory = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: filtered.isEmpty
                        ? const _ScrollableState(child: _NoResultsState())
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final lead = filtered[index];
                              return SavedBusinessCard(
                                lead: lead,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => BusinessDetailsPage(
                                      lead: lead,
                                      updateStatus: _repo.updateStatus,
                                      updateWhatsAppStatus: _repo.updateWhatsAppStatus,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Pill dropdown field that opens a searchable category picker sheet.
class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({
    required this.categories,
    required this.selected,
    required this.countFor,
    required this.onSelected,
  });

  final List<String> categories;
  final String selected;
  final int Function(String category) countFor;
  final ValueChanged<String> onSelected;

  Future<void> _openPicker(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CategoryPickerSheet(
        categories: categories,
        selected: selected,
        countFor: countFor,
      ),
    );
    if (choice != null) onSelected(choice);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isFiltered = selected != _allCategories;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: InkWell(
        onTap: () => _openPicker(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Icon(AppIcons.filter, size: 19, color: t.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isFiltered ? selected : 'All categories',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isFiltered ? t.accentTextStrong : t.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isFiltered) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.accentTint,
                    borderRadius: const BorderRadius.all(
                        Radius.circular(AppTheme.radiusPill)),
                  ),
                  child: Text(
                    '${countFor(selected)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: t.accentTextStrong,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Icon(AppIcons.chevronDown, size: 18, color: t.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded bottom sheet with a search bar and the category list.
class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.categories,
    required this.selected,
    required this.countFor,
  });

  final List<String> categories;
  final String selected;
  final int Function(String category) countFor;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final query = _query.trim().toLowerCase();
    final results = query.isEmpty
        ? widget.categories
        : widget.categories
            .where((c) =>
                c == _allCategories || c.toLowerCase().contains(query))
            .toList();

    return Padding(
      // Keep the sheet above the keyboard while typing.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Filter by category',
                          style: Theme.of(context).textTheme.headlineSmall),
                    ),
                    Text(
                      '${widget.categories.length - 1} categories',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  autofocus: false,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Search categories…',
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 20, right: 12),
                      child: Icon(AppIcons.search, size: 19, color: t.faint),
                    ),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 0, minHeight: 0),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No category matches “${_query.trim()}”',
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final category = results[index];
                          final isAll = category == _allCategories;
                          final isSelected = category == widget.selected;
                          return ListTile(
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? t.accentTint
                                    : t.neutralTint,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isAll ? AppIcons.sparkles : AppIcons.tag,
                                size: 18,
                                color: isSelected
                                    ? t.accentTextStrong
                                    : t.subtle,
                              ),
                            ),
                            title: Text(
                              isAll ? 'All categories' : category,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: isSelected
                                    ? t.accentTextStrong
                                    : t.ink,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${widget.countFor(category)}',
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 10),
                                  Icon(AppIcons.check,
                                      size: 20, color: t.accentDeep),
                                ],
                              ],
                            ),
                            onTap: () => Navigator.pop(context, category),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
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
        const StateBadge(icon: AppIcons.globe),
        const SizedBox(height: 20),
        Text(
          'No website leads yet',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Every business a scan finds with no website lands here automatically.',
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
        const StateBadge(icon: AppIcons.searchX),
        const SizedBox(height: 20),
        Text(
          'No matches',
          style: Theme.of(context).textTheme.headlineSmall,
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
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StateBadge(
          icon: AppIcons.alert,
          background: t.accentTint,
          foreground: t.accentText,
        ),
        const SizedBox(height: 20),
        Text(
          'Could not load businesses',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: t.danger),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(AppIcons.refresh, size: 18),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}
