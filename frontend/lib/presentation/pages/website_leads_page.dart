import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead.dart';
import '../../domain/repositories/lead_repository.dart';
import '../bloc/website_leads/website_leads_bloc.dart';
import '../bloc/website_leads/website_leads_event.dart';
import '../bloc/website_leads/website_leads_state.dart';
import '../widgets/saved_business_card.dart';

const _allCategories = 'All categories';

/// Every business discovered during a scan that has no website — the same
/// discover → save → browse flow as the review-based Leads page, just
/// filtered on the opposite signal (no website instead of a bad review).
/// Saved automatically the instant a scan finds one; there's no separate
/// "save" step here.
class WebsiteLeadsPage extends StatelessWidget {
  const WebsiteLeadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          WebsiteLeadsBloc(context.read<LeadRepository>())..add(const WebsiteLeadsRequested()),
      child: const _WebsiteLeadsView(),
    );
  }
}

class _WebsiteLeadsView extends StatefulWidget {
  const _WebsiteLeadsView();

  @override
  State<_WebsiteLeadsView> createState() => _WebsiteLeadsViewState();
}

class _WebsiteLeadsViewState extends State<_WebsiteLeadsView> {
  final _searchController = TextEditingController();
  String _category = _allCategories;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> _categoriesFrom(List<Lead> businesses) {
    final present = <String>{};
    for (final b in businesses) {
      final c = b.category.trim();
      if (c.isNotEmpty) present.add(c);
    }
    final sorted = present.toList()..sort();
    return [_allCategories, ...sorted];
  }

  Future<void> _confirmDelete(BuildContext context, Lead lead) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this business?'),
        content: Text(
          '"${lead.business}" will be permanently removed from Firebase. This can\'t be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm == true && lead.dbId != null && context.mounted) {
      context.read<WebsiteLeadsBloc>().add(WebsiteLeadDeleted(lead.dbId!));
    }
  }

  Future<void> _confirmDeleteCategory(BuildContext context, String category, int count) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this category?'),
        content: Text(
          'All $count business${count == 1 ? '' : 'es'} in "$category" will be permanently '
          'removed from Firebase. This can\'t be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      context.read<WebsiteLeadsBloc>().add(WebsiteLeadsCategoryDeleted(category));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<WebsiteLeadsBloc, WebsiteLeadsState>(
          listenWhen: (previous, current) =>
              previous.deleteError != current.deleteError ||
              previous.categoryDeleteMessage != current.categoryDeleteMessage,
          listener: (context, state) {
            if (state.deleteError != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.deleteError!)),
              );
            }
            if (state.categoryDeleteMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.categoryDeleteMessage!)),
              );
            }
          },
          builder: (context, state) {
            return RefreshIndicator(
              onRefresh: () async {
                context.read<WebsiteLeadsBloc>().add(const WebsiteLeadsRequested());
                await context.read<WebsiteLeadsBloc>().stream.firstWhere(
                      (s) => s.status != WebsiteLeadsStatus.loading,
                    );
              },
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1080),
                          child: _buildBody(context, state),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WebsiteLeadsState state) {
    if (state.status == WebsiteLeadsStatus.loading && state.businesses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 100),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.status == WebsiteLeadsStatus.failure) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Header(total: 0),
          const SizedBox(height: 24),
          _ErrorState(
            message: state.error ?? 'Something went wrong.',
            onRetry: () => context.read<WebsiteLeadsBloc>().add(const WebsiteLeadsRequested()),
          ),
        ],
      );
    }

    if (state.businesses.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(total: 0),
          SizedBox(height: 24),
          _EmptyState(),
        ],
      );
    }

    final categories = _categoriesFrom(state.businesses);
    final effectiveCategory = categories.contains(_category) ? _category : _allCategories;
    final searched = state.filteredBusinesses;
    final filtered = effectiveCategory == _allCategories
        ? searched
        : searched.where((b) => b.category == effectiveCategory).toList();
    // Deleting a category removes every lead in it regardless of the search
    // box, so the confirm dialog must count from the full unfiltered list.
    final categoryTotalCount = state.businesses.where((b) => b.category == effectiveCategory).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(total: state.businesses.length),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _searchController,
                onChanged: (value) =>
                    context.read<WebsiteLeadsBloc>().add(WebsiteLeadsSearchChanged(value)),
                decoration: InputDecoration(
                  hintText: 'Search by name, phone, or address',
                  prefixIcon: const Icon(AppIcons.search, size: 19),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(AppIcons.close, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            context
                                .read<WebsiteLeadsBloc>()
                                .add(const WebsiteLeadsSearchChanged(''));
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                initialValue: effectiveCategory,
                icon: const Icon(AppIcons.chevronDown, size: 18, color: AppTheme.accent),
                decoration: const InputDecoration(prefixIcon: Icon(AppIcons.filter, size: 19)),
                items: [
                  for (final c in categories) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
            ),
            if (effectiveCategory != _allCategories) ...[
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                width: 48,
                child: state.deletingCategory == effectiveCategory
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : OutlinedButton(
                        onPressed: () =>
                            _confirmDeleteCategory(context, effectiveCategory, categoryTotalCount),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: AppTheme.danger,
                          side: const BorderSide(color: AppTheme.danger),
                        ),
                        child: const Icon(AppIcons.trash, size: 18),
                      ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          const _NoResultsState()
        else ...[
          Text(
            '${filtered.length} business${filtered.length == 1 ? '' : 'es'}',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 340,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  mainAxisExtent: 248,
                ),
                itemBuilder: (context, index) {
                  final lead = filtered[index];
                  return SavedBusinessCard(
                    lead: lead,
                    onTap: () async {
                      final changed = await context.push<bool>('/leads/details', extra: lead);
                      if (changed == true && context.mounted) {
                        context.read<WebsiteLeadsBloc>().add(const WebsiteLeadsRequested());
                      }
                    },
                    onDelete: lead.dbId == null ? null : () => _confirmDelete(context, lead),
                    deleting: state.deletingLeadId != null && state.deletingLeadId == lead.dbId,
                  );
                },
              );
            },
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Website Leads', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 6),
              Text(
                total == 0
                    ? 'Businesses found during a scan with no website will land here.'
                    : '$total business${total == 1 ? '' : 'es'} with no website found.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => context.read<WebsiteLeadsBloc>().add(const WebsiteLeadsRequested()),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
            child: const Icon(AppIcons.globe, size: 36, color: AppTheme.accent700),
          ),
          const SizedBox(height: 20),
          Text('No website leads yet', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Run a scan — every business it finds with no website is saved here automatically.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 32),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: AppTheme.neutral100, shape: BoxShape.circle),
            child: const Icon(AppIcons.searchX, size: 30, color: AppTheme.subtle),
          ),
          const SizedBox(height: 18),
          Text('No matches', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Try a different name, phone number, or category.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

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
          Text('Could not load businesses', style: Theme.of(context).textTheme.headlineSmall),
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
