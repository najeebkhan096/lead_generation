import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/lead.dart';
import '../../domain/entities/lead_page.dart';
import '../../domain/repositories/lead_repository.dart';
import '../bloc/paged_leads/paged_leads_bloc.dart';
import '../bloc/paged_leads/paged_leads_event.dart';
import '../bloc/paged_leads/paged_leads_state.dart';
import '../design_system/design_system.dart';
import '../utils/web_download.dart';
import '../widgets/lead_table.dart';
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
    this.tableKind,
    this.rowAction = const LeadRowAction(icon: AppIcons.eye, tooltip: 'Open'),
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

  /// The table layout for this list (wide windows); `null` keeps cards only.
  final LeadTableKind? tableKind;

  /// The button at the end of a table row — the same action as tapping a card.
  final LeadRowAction rowAction;
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

  /// Table rows the user has ticked (by `dbId`, else `id`).
  Set<String> _selected = {};
  String? _sortBy;
  bool _sortAscending = true;
  bool _tableView = true;

  LeadListConfig get _c => widget.config;
  PagedLeadsBloc get _bloc => context.read<PagedLeadsBloc>();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _key(Lead lead) => lead.dbId ?? lead.id;

  Future<void> _confirmDelete(Lead lead) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete this lead?',
      message: '"${lead.business}" will be permanently removed. This can\'t be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirm && lead.dbId != null && mounted) _bloc.add(PagedLeadDeleted(lead.dbId!));
  }

  Future<void> _confirmDeleteSelected(List<Lead> leads) async {
    final ids = [for (final l in leads) if (l.dbId != null) l.dbId!];
    if (ids.isEmpty) return;
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete ${ids.length} lead${ids.length == 1 ? '' : 's'}?',
      message: 'The selected ${_c.noun}${ids.length == 1 ? '' : 'es'} will be permanently removed. This can\'t be undone.',
      confirmLabel: 'Delete ${ids.length}',
      destructive: true,
    );
    if (!confirm || !mounted) return;
    for (final id in ids) {
      _bloc.add(PagedLeadDeleted(id));
    }
    setState(() => _selected = {});
  }

  Future<void> _confirmDeleteCategory(String category, int? count) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete this category?',
      message: 'All ${count == null ? '' : '${groupedNumber(count)} '}${_c.noun}s in "$category" will be '
          'permanently removed. This can\'t be undone.',
      confirmLabel: 'Delete all',
      destructive: true,
    );
    if (confirm && mounted) _bloc.add(PagedLeadsCategoryDeleted(category));
  }

  /// Downloads [leads] (the ticked ones, else everything loaded) as CSV.
  void _exportCsv(List<Lead> leads) {
    if (leads.isEmpty) return;
    final slug = _c.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    downloadBytesFile('$slug-${DateTime.now().toIso8601String().substring(0, 10)}.csv', leadsToCsv(leads), 'text/csv');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported ${leads.length} ${_c.noun}${leads.length == 1 ? '' : 'es'} to CSV.')));
  }

  List<Lead> _selectedLeads(PagedLeadsState s) => [for (final l in s.leads) if (_selected.contains(_key(l))) l];

  String _subtitle(PagedLeadsState s) {
    final noun = _c.noun;
    if (s.status == PagedLeadsStatus.success && s.leads.isEmpty && !s.hasActiveFilter) {
      return _c.subtitleEmpty ?? 'Nothing here yet.';
    }
    if (s.total != null) {
      return '${groupedNumber(s.total!)} $noun${s.total == 1 ? '' : 'es'}'
          '${s.hasActiveFilter ? ' match' : ''}';
    }
    if (s.isSearching) {
      final n = s.leads.length;
      return s.loadingMore || s.hasMore
          ? 'Searching… $n found so far'
          : '$n $noun${n == 1 ? '' : 'es'} found';
    }
    final n = s.leads.length;
    return s.hasMore ? '${groupedNumber(n)}+ ${noun}es' : '${groupedNumber(n)} $noun${n == 1 ? '' : 'es'}';
  }

  Widget _header(BuildContext context, PagedLeadsState s) {
    final categories = s.categories;
    final selected = categories.any((c) => c.name == s.category) ? s.category : null;
    final selectedCount = categories.where((c) => c.name == selected).map((c) => c.count).firstOrNull;
    final actions = _c.headerActions?.call(context, s) ?? const <Widget>[];
    final picked = _selectedLeads(s);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: _c.title,
          subtitle: _subtitle(s),
          actions: [
            ...actions,
            if (_c.tableKind != null)
              Row(mainAxisSize: MainAxisSize.min, children: [
                AppIconButton(icon: AppIcons.table, tooltip: 'Table view', selected: _tableView, onPressed: () => setState(() => _tableView = true)),
                AppIconButton(icon: AppIcons.layoutGrid, tooltip: 'Card view', selected: !_tableView, onPressed: () => setState(() => _tableView = false)),
              ]),
            AppButton.outlined(
              label: picked.isEmpty ? 'Export CSV' : 'Export ${picked.length}',
              icon: AppIcons.download,
              onPressed: s.leads.isEmpty ? null : () => _exportCsv(picked.isEmpty ? s.leads : picked),
            ),
            AppButton.outlined(label: 'Refresh', icon: AppIcons.refresh, onPressed: () => _bloc.add(const PagedLeadsRefreshed())),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
        if (_c.validationCollection != null && s.leads.isNotEmpty) ...[
          // Validates what's loaded — a page at a time, not a whole
          // collection: scroll to load more leads, then validate them.
          LeadValidationBar(
            collection: _c.validationCollection!,
            leads: s.leads,
            onFinished: () => _bloc.add(const PagedLeadsRefreshed()),
          ),
          const SizedBox(height: AppSpace.lg),
        ],
        Wrap(
          spacing: AppSpace.md,
          runSpacing: AppSpace.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 340,
              child: AppSearchField(
                controller: _search,
                hint: _c.searchHint,
                onChanged: (v) => _bloc.add(PagedLeadsQueryChanged(v)),
              ),
            ),
            if (categories.isNotEmpty)
              AppDropdown<String?>(
                width: 300,
                value: selected,
                hint: 'All categories',
                leadingIcon: AppIcons.filter,
                options: [
                  const AppOption<String?>(null, 'All categories'),
                  for (final c in categories) AppOption<String?>(c.name, c.name, caption: groupedNumber(c.count)),
                ],
                onChanged: (v) => _bloc.add(PagedLeadsCategoryChanged(v)),
              ),
            if (selected != null)
              AppIconButton(
                icon: AppIcons.trash,
                tooltip: 'Delete this category',
                color: AppTheme.error,
                loading: s.deletingCategory == selected,
                onPressed: () => _confirmDeleteCategory(selected, selectedCount),
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
        if (picked.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          _SelectionBar(
            count: picked.length,
            hasPhones: picked.any((l) => (l.phone ?? '').isNotEmpty),
            hasEmails: picked.any((l) => leadEmails(l).isNotEmpty),
            onCopyPhones: () => copyText(
              context,
              picked.where((l) => (l.phone ?? '').isNotEmpty).map((l) => l.phone!).join('\n'),
              'Copied ${picked.where((l) => (l.phone ?? '').isNotEmpty).length} phone numbers',
            ),
            onCopyEmails: () {
              final emails = picked.expand(leadEmails).map((e) => e.address).toSet();
              copyText(context, emails.join('\n'), 'Copied ${emails.length} email addresses');
            },
            onExport: () => _exportCsv(picked),
            onDelete: () => _confirmDeleteSelected(picked),
            onClear: () => setState(() => _selected = {}),
          ),
        ],
      ],
    );
  }

  Widget? _placeholder(BuildContext context, PagedLeadsState s) {
    if (s.status == PagedLeadsStatus.failure && s.leads.isEmpty) {
      return AppCard(
        child: EmptyState(
          icon: AppIcons.alert,
          tone: AppTone.error,
          title: 'Could not load ${_c.title.toLowerCase()}',
          message: s.error ?? 'Something went wrong.',
          action: AppButton.outlined(label: 'Retry', icon: AppIcons.refresh, onPressed: () => _bloc.add(const PagedLeadsRefreshed())),
        ),
      );
    }
    if (s.leads.isEmpty) {
      final waiting = s.status == PagedLeadsStatus.loading ||
          s.status == PagedLeadsStatus.initial ||
          (s.isSearching && (s.loadingMore || s.hasMore));
      if (waiting) {
        return AppCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: Column(
            children: [
              const SkeletonRows(rows: 7),
              if (s.isSearching)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.lg),
                  child: Text('Searching ${_c.title.toLowerCase()}…', style: Theme.of(context).textTheme.bodyMedium),
                ),
            ],
          ),
        );
      }
      if (s.hasActiveFilter) {
        return const AppCard(
          child: EmptyState(icon: AppIcons.searchX, title: 'No matches', message: 'Try a different search, category or filter.'),
        );
      }
      return AppCard(child: EmptyState(icon: _c.emptyIcon, title: _c.emptyTitle, message: _c.emptyBody));
    }
    return null;
  }

  /// The loaded leads in the table's current sort order.
  List<Lead> _sorted(List<Lead> leads, List<AppColumn<Lead>> columns) {
    final by = _sortBy;
    if (by == null) return leads;
    final compare = leadComparator(by);
    if (compare == null) return leads;
    final copy = [...leads]..sort(compare);
    return _sortAscending ? copy : copy.reversed.toList();
  }

  Future<void> _open(Lead lead) async {
    final changed = await _c.onOpen(context, lead);
    if (changed == true && mounted) _bloc.add(const PagedLeadsRefreshed());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BlocConsumer<PagedLeadsBloc, PagedLeadsState>(
        listenWhen: (a, b) => a.deleteError != b.deleteError || a.categoryDeleteMessage != b.categoryDeleteMessage,
        listener: (context, s) {
          final message = s.deleteError ?? s.categoryDeleteMessage;
          if (message != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
          }
        },
        builder: (context, s) {
          final kind = _c.tableKind;
          List<AppColumn<Lead>>? columns;
          if (kind != null && _tableView) {
            columns = leadTableColumns(
              kind,
              action: _c.rowAction,
              deletingId: s.deletingLeadId,
              onOpen: _open,
              onDelete: (lead) => lead.dbId == null ? null : _confirmDelete,
            );
          }
          // Forget ticks for leads that are gone (deleted, or filtered out).
          final present = {for (final l in s.leads) _key(l)};
          if (_selected.any((k) => !present.contains(k))) _selected = _selected.intersection(present);

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
            tableMinWidth: columns == null ? 0 : minTableWidth(columns, selectable: true) + 2,
            tableBuilder: columns == null
                ? null
                : (context) {
                    final cols = columns!;
                    return SliverAppTable<Lead>(
                      columns: cols,
                      rows: _sorted(s.leads, cols),
                      rowKey: _key,
                      onRowTap: _open,
                      selected: _selected,
                      onSelectionChanged: (next) => setState(() => _selected = next),
                      sortBy: _sortBy,
                      sortAscending: _sortAscending,
                      onSort: (column, ascending) => setState(() {
                        _sortBy = column;
                        _sortAscending = ascending;
                      }),
                    );
                  },
            itemBuilder: (context, i) {
              final lead = s.leads[i];
              return _c.cardBuilder(
                context,
                lead,
                onTap: () => _open(lead),
                onDelete: lead.dbId == null ? null : () => _confirmDelete(lead),
                deleting: s.deletingLeadId != null && s.deletingLeadId == lead.dbId,
              );
            },
          );
        },
      ),
    );
  }
}

/// The bar that appears while table rows are ticked.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.hasPhones,
    required this.hasEmails,
    required this.onCopyPhones,
    required this.onCopyEmails,
    required this.onExport,
    required this.onDelete,
    required this.onClear,
  });

  final int count;
  final bool hasPhones;
  final bool hasEmails;
  final VoidCallback onCopyPhones;
  final VoidCallback onCopyEmails;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: AppTheme.primary100,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.primary200),
      ),
      child: Wrap(
        spacing: AppSpace.sm,
        runSpacing: AppSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$count selected', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppTheme.primary800)),
          const SizedBox(width: AppSpace.sm),
          if (hasPhones) AppButton.outlined(label: 'Copy phones', icon: AppIcons.phone, size: AppButtonSize.sm, onPressed: onCopyPhones),
          if (hasEmails) AppButton.outlined(label: 'Copy emails', icon: AppIcons.mail, size: AppButtonSize.sm, onPressed: onCopyEmails),
          AppButton.outlined(label: 'Export CSV', icon: AppIcons.download, size: AppButtonSize.sm, onPressed: onExport),
          AppButton.destructive(label: 'Delete', icon: AppIcons.trash, size: AppButtonSize.sm, onPressed: onDelete),
          AppButton.text(label: 'Clear', size: AppButtonSize.sm, onPressed: onClear),
        ],
      ),
    );
  }
}
