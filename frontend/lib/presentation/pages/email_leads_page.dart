import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead.dart';
import '../../domain/repositories/lead_repository.dart';
import '../bloc/email_leads/email_leads_bloc.dart';
import '../bloc/email_leads/email_leads_event.dart';
import '../bloc/email_leads/email_leads_state.dart';
import '../widgets/email_lead_card.dart';

const _allCategories = 'All categories';

/// Every business the email validator found and verified a contact email
/// for — the same browse flow as Leads and Website Leads, filtered on a
/// third signal. Populated from an Excel Archive's "Validate emails"
/// action (see `email_validator_page.dart`), exactly as WhatsApp numbers
/// are verified from the same place.
class EmailLeadsPage extends StatelessWidget {
  const EmailLeadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          EmailLeadsBloc(context.read<LeadRepository>())..add(const EmailLeadsRequested()),
      child: const _EmailLeadsView(),
    );
  }
}

class _EmailLeadsView extends StatefulWidget {
  const _EmailLeadsView();

  @override
  State<_EmailLeadsView> createState() => _EmailLeadsViewState();
}

class _EmailLeadsViewState extends State<_EmailLeadsView> {
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
        title: const Text('Delete this email lead?'),
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
      context.read<EmailLeadsBloc>().add(EmailLeadDeleted(lead.dbId!));
    }
  }

  Future<void> _confirmDeleteCategory(BuildContext context, String category, int count) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this category?'),
        content: Text(
          'All $count email lead${count == 1 ? '' : 's'} in "$category" will be permanently '
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
      context.read<EmailLeadsBloc>().add(EmailLeadsCategoryDeleted(category));
    }
  }

  void _reload(BuildContext context) =>
      context.read<EmailLeadsBloc>().add(const EmailLeadsRequested());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<EmailLeadsBloc, EmailLeadsState>(
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
                _reload(context);
                await context.read<EmailLeadsBloc>().stream.firstWhere(
                      (s) => s.status != EmailLeadsStatus.loading,
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

  Widget _buildBody(BuildContext context, EmailLeadsState state) {
    if (state.status == EmailLeadsStatus.loading && state.businesses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 100),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.status == EmailLeadsStatus.failure) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(total: 0, onRefresh: () => _reload(context)),
          const SizedBox(height: 24),
          _ErrorState(
            message: state.error ?? 'Something went wrong.',
            onRetry: () => _reload(context),
          ),
        ],
      );
    }

    final header = _Header(total: state.businesses.length, onRefresh: () => _reload(context));

    if (state.businesses.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 24),
          const _EmptyState(),
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
    final allEmails = <String>{
      for (final b in filtered)
        if (b.email != null && b.email!.isNotEmpty) b.email!,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _searchController,
                onChanged: (value) =>
                    context.read<EmailLeadsBloc>().add(EmailLeadsSearchChanged(value)),
                decoration: InputDecoration(
                  hintText: 'Search by name, email, or website',
                  prefixIcon: const Icon(AppIcons.search, size: 19),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(AppIcons.close, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            context.read<EmailLeadsBloc>().add(const EmailLeadsSearchChanged(''));
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
                // Without this the field sizes to its widest item and
                // overflows the row on narrow (mobile-width) windows.
                isExpanded: true,
                icon: const Icon(AppIcons.chevronDown, size: 18, color: AppTheme.accent),
                decoration: const InputDecoration(prefixIcon: Icon(AppIcons.filter, size: 19)),
                items: [
                  for (final c in categories)
                    DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  '${filtered.length} business${filtered.length == 1 ? '' : 'es'}',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                ),
              ),
              if (allEmails.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => copyToClipboard(
                    context,
                    allEmails.join('\n'),
                    'Copied ${allEmails.length} email${allEmails.length == 1 ? '' : 's'}',
                  ),
                  icon: const Icon(AppIcons.copy, size: 16),
                  label: Text('Copy ${allEmails.length} email${allEmails.length == 1 ? '' : 's'}'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 340,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              mainAxisExtent: 262,
            ),
            itemBuilder: (context, index) {
              final lead = filtered[index];
              return EmailLeadCard(
                lead: lead,
                onTap: () async {
                  final changed = await context.push<bool>('/email-leads/details', extra: lead);
                  if (changed == true && context.mounted) _reload(context);
                },
                onDelete: lead.dbId == null ? null : () => _confirmDelete(context, lead),
                deleting: state.deletingLeadId != null && state.deletingLeadId == lead.dbId,
              );
            },
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.total, required this.onRefresh});

  final int total;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Email Leads', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 6),
              Text(
                total == 0
                    ? 'Businesses with a verified contact email will land here.'
                    : '$total business${total == 1 ? '' : 'es'} with a verified contact email.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: onRefresh,
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
            child: const Icon(AppIcons.mail, size: 36, color: AppTheme.accent700),
          ),
          const SizedBox(height: 20),
          Text('No email leads yet', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Open an Excel Archive and tap "Validate emails" — each business\'s website is '
            'checked for a contact address, and the verified ones are saved here.',
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
            'Try a different name, email, or category.',
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
          Text('Could not load email leads', style: Theme.of(context).textTheme.headlineSmall),
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
