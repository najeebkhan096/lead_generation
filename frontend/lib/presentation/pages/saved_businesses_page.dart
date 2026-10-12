import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead.dart';
import '../../domain/repositories/lead_repository.dart';
import '../bloc/saved_businesses/saved_businesses_bloc.dart';
import '../bloc/saved_businesses/saved_businesses_event.dart';
import '../bloc/saved_businesses/saved_businesses_state.dart';
import '../widgets/lead_validation_bar.dart';
import '../widgets/saved_business_card.dart';
import 'business_details_page.dart' show LeadDetailsArgs;

const _allCategories = 'All categories';

/// Every business saved to Firestore — searchable, filterable by
/// category and by real WhatsApp verification, laid out as a responsive
/// card grid.
///
/// [lockToVerified] powers the dedicated "WhatsApp Business" tab: same
/// data and bloc, just permanently filtered to [Lead.hasWhatsApp] with the
/// toggle and bulk-validate action hidden, since everything shown here is
/// already checked.
class SavedBusinessesPage extends StatelessWidget {
  const SavedBusinessesPage({super.key, this.lockToVerified = false});

  final bool lockToVerified;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          SavedBusinessesBloc(context.read<LeadRepository>())..add(const SavedBusinessesRequested()),
      child: _SavedBusinessesView(lockToVerified: lockToVerified),
    );
  }
}

class _SavedBusinessesView extends StatefulWidget {
  const _SavedBusinessesView({required this.lockToVerified});

  final bool lockToVerified;

  @override
  State<_SavedBusinessesView> createState() => _SavedBusinessesViewState();
}

class _SavedBusinessesViewState extends State<_SavedBusinessesView> {
  final _searchController = TextEditingController();
  String _category = _allCategories;
  late bool _verifiedOnly;

  @override
  void initState() {
    super.initState();
    _verifiedOnly = widget.lockToVerified;
  }

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
      context.read<SavedBusinessesBloc>().add(SavedBusinessDeleted(lead.dbId!));
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
      context.read<SavedBusinessesBloc>().add(SavedCategoryDeleted(category));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<SavedBusinessesBloc, SavedBusinessesState>(
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
                context.read<SavedBusinessesBloc>().add(const SavedBusinessesRequested());
                await context.read<SavedBusinessesBloc>().stream.firstWhere(
                      (s) => s.status != SavedBusinessesStatus.loading,
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

  Widget _buildBody(BuildContext context, SavedBusinessesState state) {
    if (state.status == SavedBusinessesStatus.loading && state.businesses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 100),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.status == SavedBusinessesStatus.failure) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(total: 0, locked: widget.lockToVerified),
          const SizedBox(height: 24),
          _ErrorState(
            message: state.error ?? 'Something went wrong.',
            onRetry: () => context.read<SavedBusinessesBloc>().add(const SavedBusinessesRequested()),
          ),
        ],
      );
    }

    if (state.businesses.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(total: 0, locked: widget.lockToVerified),
          const SizedBox(height: 24),
          _EmptyState(locked: widget.lockToVerified),
        ],
      );
    }

    final categories = _categoriesFrom(state.businesses);
    final effectiveCategory = categories.contains(_category) ? _category : _allCategories;
    final searched = state.filteredBusinesses;
    final categoryFiltered = effectiveCategory == _allCategories
        ? searched
        : searched.where((b) => b.category == effectiveCategory).toList();
    final filtered =
        _verifiedOnly ? categoryFiltered.where((b) => b.hasWhatsApp).toList() : categoryFiltered;
    final verifiedCount = state.businesses.where((b) => b.hasWhatsApp).length;
    // Deleting a category removes every lead in it regardless of the search
    // box or "verified only" toggle, so the confirm dialog must count from
    // the full unfiltered list, not `categoryFiltered` (which is narrowed
    // by the current search text).
    final categoryTotalCount = state.businesses.where((b) => b.category == effectiveCategory).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          total: widget.lockToVerified ? verifiedCount : state.businesses.length,
          locked: widget.lockToVerified,
        ),
        const SizedBox(height: 24),
        // Both validations — WhatsApp and email — for the list as filtered.
        if (!widget.lockToVerified) ...[
          LeadValidationBar(
            collection: 'leads',
            leads: categoryFiltered,
            onFinished: () => context.read<SavedBusinessesBloc>().add(const SavedBusinessesRequested()),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _searchController,
                onChanged: (value) =>
                    context.read<SavedBusinessesBloc>().add(SavedBusinessesSearchChanged(value)),
                decoration: InputDecoration(
                  hintText: 'Search by name, phone, website, or email',
                  prefixIcon: const Icon(AppIcons.search, size: 19),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(AppIcons.close, size: 18),
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
        if (!widget.lockToVerified) ...[
          const SizedBox(height: 12),
          _VerifiedFilterChip(
            value: _verifiedOnly,
            verifiedCount: verifiedCount,
            onChanged: (v) => setState(() => _verifiedOnly = v),
          ),
        ],
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          _NoResultsState(locked: widget.lockToVerified)
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
                      final changed = await context.push<bool>(
                        '/leads/details',
                        extra: LeadDetailsArgs(lead: lead),
                      );
                      if (changed == true && context.mounted) {
                        context.read<SavedBusinessesBloc>().add(const SavedBusinessesRequested());
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

class _VerifiedFilterChip extends StatelessWidget {
  const _VerifiedFilterChip({
    required this.value,
    required this.verifiedCount,
    required this.onChanged,
  });

  final bool value;
  final int verifiedCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value ? AppTheme.sage500 : AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.checkCircle, size: 16, color: value ? AppTheme.surface : AppTheme.sage600),
              const SizedBox(width: 8),
              Text(
                'WhatsApp verified only',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: value ? AppTheme.surface : AppTheme.ink,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: value ? Colors.white.withValues(alpha: 0.2) : AppTheme.sage100,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
                child: Text(
                  '$verifiedCount',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                    color: value ? AppTheme.surface : AppTheme.sage700,
                  ),
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
  const _Header({required this.total, required this.locked});

  final int total;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(locked ? 'WhatsApp Business' : 'Review leads', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 6),
              Text(
                locked
                    ? (total == 0
                        ? 'Businesses with a confirmed WhatsApp number will show up here.'
                        : '$total business${total == 1 ? '' : 'es'} with a validated WhatsApp number.')
                    : (total == 0
                        ? 'Businesses with a recent 1-star review land here.'
                        : '$total business${total == 1 ? '' : 'es'} with a recent 1-star review.'),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => context.read<SavedBusinessesBloc>().add(const SavedBusinessesRequested()),
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
  const _EmptyState({required this.locked});

  final bool locked;

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
            child: Icon(locked ? AppIcons.badgeCheck : AppIcons.inbox, size: 36, color: AppTheme.accent700),
          ),
          const SizedBox(height: 20),
          Text(locked ? 'No validated WhatsApp businesses yet' : 'No businesses saved yet',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            locked
                ? 'Save businesses from a search, then validate their numbers from the Leads tab.'
                : 'Run a search and tap "Save to Firebase" to see businesses here.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState({required this.locked});

  final bool locked;

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
            locked
                ? 'No WhatsApp-verified businesses match this search or category.'
                : 'Try a different name, phone number, category, or WhatsApp filter.',
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
