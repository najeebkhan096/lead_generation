import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/lead_page.dart';
import '../../domain/repositories/lead_repository.dart';
import '../bloc/paged_leads/paged_leads_bloc.dart';
import '../bloc/paged_leads/paged_leads_event.dart';
import '../bloc/paged_leads/paged_leads_state.dart';
import '../widgets/lead_validation_bar.dart';
import '../widgets/paged_lead_list.dart';

typedef LeadCardBuilder = Widget Function(
  BuildContext context,
  Lead lead, {
  required VoidCallback onTap,
  required VoidCallback? onDelete,
  required bool deleting,
});

/// What makes one lead list different from another. Everything else — paging,
/// category filter, search, delete, validation — is [LeadListPage].
class LeadListConfig {
  const LeadListConfig({
    required this.collection,
    required this.title,
    required this.emptyTitle,
    required this.emptyBody,
    required this.emptyIcon,
    required this.searchHint,
    required this.cardBuilder,
    required this.onOpen,
    this.subtitleEmpty,
    this.noun = 'business',
    this.validationCollection,
    this.verifiedFilter = false,
    this.headerActions,
    this.cardExtent = 248,
  });

  final LeadCollection collection;
  final String title;
  final String emptyTitle;
  final String emptyBody;
  final IconData emptyIcon;
  final String searchHint;

  /// Shown under the title when the collection is empty.
  final String? subtitleEmpty;

  /// Singular noun for counts ("business" → "21,208 businesses").
  final String noun;
  final LeadCardBuilder cardBuilder;

  /// Tapping a card. Return `true` if the lead changed (reload the list).
  final Future<bool?> Function(BuildContext context, Lead lead) onOpen;

  /// `leads` — shows the WhatsApp validation bar for the loaded leads.
  /// `null` hides it.
  final String? validationCollection;

  /// "WhatsApp verified only" (review leads).
  final bool verifiedFilter;

  /// Extra actions in the header row.
  final List<Widget> Function(BuildContext context, PagedLeadsState state)? headerActions;
  final double cardExtent;
}

String _thousands(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// One lead list, paged and lazily rendered. See [LeadListConfig] for what
/// varies; the same page backs Review leads and WhatsApp leads.
class LeadListPage extends StatelessWidget {
  const LeadListPage({super.key, required this.config});

  final LeadListConfig config;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => PagedLeadsBloc(context.read<LeadRepository>(), config.collection)
        ..add(const PagedLeadsStarted()),
      child: _LeadListView(config: config),
    );
  }
}

class _LeadListView extends StatefulWidget {
  const _LeadListView({required this.config});

  final LeadListConfig config;

  @override
  State<_LeadListView> createState() => _LeadListViewState();
}

class _LeadListViewState extends State<_LeadListView> {
  final _search = TextEditingController();

  LeadListConfig get _c => widget.config;
  PagedLeadsBloc get _bloc => context.read<PagedLeadsBloc>();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(Lead lead) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this lead?'),
        content: Text('"${lead.business}" will be permanently removed. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm == true && lead.dbId != null && mounted) _bloc.add(PagedLeadDeleted(lead.dbId!));
  }

  Future<void> _confirmDeleteCategory(String category, int? count) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this category?'),
        content: Text(
          'All ${count == null ? '' : '${_thousands(count)} '}${_c.noun}s in "$category" will be '
          'permanently removed. This can\'t be undone.',
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
    if (confirm == true && mounted) _bloc.add(PagedLeadsCategoryDeleted(category));
  }

  String _subtitle(PagedLeadsState s) {
    final noun = _c.noun;
    if (s.status == PagedLeadsStatus.success && s.leads.isEmpty && !s.hasActiveFilter) {
      return _c.subtitleEmpty ?? 'Nothing here yet.';
    }
    if (s.total != null) {
      return '${_thousands(s.total!)} $noun${s.total == 1 ? '' : 'es'}'
          '${s.hasActiveFilter ? ' match' : ''}';
    }
    if (s.isSearching) {
      final n = s.leads.length;
      return s.loadingMore || s.hasMore
          ? 'Searching… $n found so far'
          : '$n $noun${n == 1 ? '' : 'es'} found';
    }
    final n = s.leads.length;
    return s.hasMore ? '${_thousands(n)}+ ${noun}es' : '${_thousands(n)} $noun${n == 1 ? '' : 'es'}';
  }

  Widget _header(BuildContext context, PagedLeadsState s) {
    final categories = s.categories;
    final selected = categories.any((c) => c.name == s.category) ? s.category : null;
    final selectedCount = categories.where((c) => c.name == selected).map((c) => c.count).firstOrNull;
    final actions = _c.headerActions?.call(context, s) ?? const <Widget>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_c.title, style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: 6),
                  Text(_subtitle(s), style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
            ...actions,
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => _bloc.add(const PagedLeadsRefreshed()),
              icon: const Icon(AppIcons.refresh),
              style: IconButton.styleFrom(backgroundColor: AppTheme.surface, padding: const EdgeInsets.all(12)),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_c.validationCollection != null && s.leads.isNotEmpty) ...[
          // Validates what's loaded — a page at a time, not a whole
          // collection: scroll to load more leads, then validate them.
          LeadValidationBar(
            collection: _c.validationCollection!,
            leads: s.leads,
            onFinished: () => _bloc.add(const PagedLeadsRefreshed()),
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 340,
              child: TextField(
                controller: _search,
                onChanged: (v) => _bloc.add(PagedLeadsQueryChanged(v)),
                decoration: InputDecoration(
                  hintText: _c.searchHint,
                  prefixIcon: const Icon(AppIcons.search, size: 19),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(AppIcons.close, size: 18),
                          onPressed: () {
                            _search.clear();
                            _bloc.add(const PagedLeadsQueryChanged(''));
                            setState(() {});
                          },
                        ),
                ),
              ),
            ),
            if (categories.isNotEmpty)
              SizedBox(
                width: 300,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('category-$selected'),
                  initialValue: selected,
                  isExpanded: true,
                  icon: const Icon(AppIcons.chevronDown, size: 18, color: AppTheme.accent),
                  decoration: const InputDecoration(prefixIcon: Icon(AppIcons.filter, size: 19)),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All categories')),
                    for (final c in categories)
                      DropdownMenuItem<String?>(
                        value: c.name,
                        child: Text('${c.name} (${_thousands(c.count)})', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => _bloc.add(PagedLeadsCategoryChanged(v)),
                ),
              ),
            if (selected != null)
              SizedBox(
                height: 48,
                width: 48,
                child: s.deletingCategory == selected
                    ? const Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2))
                    : OutlinedButton(
                        onPressed: () => _confirmDeleteCategory(selected, selectedCount),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: AppTheme.danger,
                          side: const BorderSide(color: AppTheme.danger),
                        ),
                        child: const Icon(AppIcons.trash, size: 18),
                      ),
              ),
            if (_c.verifiedFilter)
              FilterChip(
                avatar: const Icon(AppIcons.checkCircle, size: 16),
                label: const Text('WhatsApp verified only'),
                selected: s.verifiedOnly,
                onSelected: (v) => _bloc.add(PagedLeadsFilterChanged(verifiedOnly: v)),
              ),
          ],
        ),
      ],
    );
  }

  Widget? _placeholder(BuildContext context, PagedLeadsState s) {
    if (s.status == PagedLeadsStatus.failure && s.leads.isEmpty) {
      return _Message(
        icon: AppIcons.alert,
        title: 'Could not load ${_c.title.toLowerCase()}',
        body: s.error ?? 'Something went wrong.',
        bodyColor: AppTheme.danger,
        action: OutlinedButton.icon(
          onPressed: () => _bloc.add(const PagedLeadsRefreshed()),
          icon: const Icon(AppIcons.refresh, size: 18),
          label: const Text('Retry'),
        ),
      );
    }
    if (s.leads.isEmpty) {
      final waiting = s.status == PagedLeadsStatus.loading ||
          s.status == PagedLeadsStatus.initial ||
          (s.isSearching && (s.loadingMore || s.hasMore));
      if (waiting) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 80),
          child: Column(
            children: [
              const Center(child: CircularProgressIndicator()),
              if (s.isSearching) ...[
                const SizedBox(height: 16),
                Text('Searching ${_c.title.toLowerCase()}…', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        );
      }
      if (s.hasActiveFilter) {
        return const _Message(
          icon: AppIcons.searchX,
          title: 'No matches',
          body: 'Try a different search, category or filter.',
        );
      }
      return _Message(icon: _c.emptyIcon, title: _c.emptyTitle, body: _c.emptyBody);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<PagedLeadsBloc, PagedLeadsState>(
          listenWhen: (a, b) =>
              a.deleteError != b.deleteError || a.categoryDeleteMessage != b.categoryDeleteMessage,
          listener: (context, s) {
            final message = s.deleteError ?? s.categoryDeleteMessage;
            if (message != null) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
            }
          },
          builder: (context, s) {
            return PagedLeadList(
              header: _header(context, s),
              placeholder: _placeholder(context, s),
              itemCount: s.leads.length,
              hasMore: s.hasMore,
              loadingMore: s.loadingMore,
              mainAxisExtent: _c.cardExtent,
              onLoadMore: () => _bloc.add(const PagedLeadsLoadMore()),
              onRefresh: () async {
                _bloc.add(const PagedLeadsRefreshed());
                await _bloc.stream.firstWhere((x) => x.status != PagedLeadsStatus.loading);
              },
              itemBuilder: (context, i) {
                final lead = s.leads[i];
                return _c.cardBuilder(
                  context,
                  lead,
                  onTap: () async {
                    final changed = await _c.onOpen(context, lead);
                    if (changed == true && context.mounted) _bloc.add(const PagedLeadsRefreshed());
                  },
                  onDelete: lead.dbId == null ? null : () => _confirmDelete(lead),
                  deleting: s.deletingLeadId != null && s.deletingLeadId == lead.dbId,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.bodyColor,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final Color? bodyColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 32),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: AppTheme.accent100, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: AppTheme.accent700),
          ),
          const SizedBox(height: 18),
          Text(title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: bodyColor),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}
