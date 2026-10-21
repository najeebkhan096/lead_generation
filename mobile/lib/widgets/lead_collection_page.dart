import 'dart:async';

import 'package:flutter/material.dart';

import '../services/paged_query.dart';
import '../theme/app_theme.dart';
import '../utils/date_groups.dart';
import 'page_header.dart';
import 'search_field.dart';

const allCategories = 'All';

/// How many matches a search should aim for before it stops reading ahead.
const _searchTarget = 20;

/// How many documents a search may read in total. Firestore can't do
/// substring search, so searching means reading pages and filtering them on
/// the phone; this keeps a search over a huge collection from downloading
/// all of it. Category narrows it server-side, so searching within a
/// category reaches further into the data.
const _searchReadCap = 1500;

/// How many documents opening the category list may read to find every
/// category that has leads. The lists this is used on are hundreds of
/// documents; the cap stops a huge collection from being read whole.
const _categoryReadCap = 1500;

/// One list filter value (e.g. "New" / "Contacted"); `value == null` is
/// "all".
typedef LeadFilter = ({String label, String? value});

/// A paged, lazily-loaded list of leads — the one list screen behind every
/// Firestore-backed lead list in the app (Discover, WhatsApp).
///
/// It reads a page at a time through a [PagedQueryController], asks for the
/// next page when the scroll position nears the end, and applies the
/// category filter on the server. Pull-to-refresh reloads from page one.
class LeadCollectionPage<T> extends StatefulWidget {
  const LeadCollectionPage({
    super.key,
    required this.title,
    required this.noun,
    required this.headerIcon,
    required this.searchHint,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyBody,
    required this.emptySubtitle,
    required this.controllerFor,
    required this.itemBuilder,
    required this.searchText,
    required this.categoryOf,
    this.filters = const [],
    this.dateOf,
    this.groupWhen,
    this.banner,
    this.showCounts = true,
  });

  final String title;

  /// Shown under the header, above the search: e.g. today's contact count.
  final Widget? banner;

  /// Singular noun for counts ("business").
  final String noun;

  /// Whether the header shows how many leads there are. Off on the salesman
  /// app, where the size of the pool is not theirs to see.
  final bool showCounts;
  final IconData headerIcon;
  final String searchHint;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyBody;
  final String emptySubtitle;

  /// Builds the controller for the given filter value (`null` = none).
  /// Called again — and the old one disposed — when the filter changes.
  final PagedQueryController<T> Function(String? filter) controllerFor;
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Lower-cased text the search box matches against.
  final String Function(T item) searchText;
  final String Function(T item) categoryOf;

  final List<LeadFilter> filters;

  /// The date a lead is grouped under ("Today", "Yesterday", ...). Items must
  /// be loaded newest-first by that same date, so null disables grouping.
  final DateTime? Function(T item)? dateOf;

  /// Whether the list for this filter value is in [dateOf] order and so can be
  /// grouped (null = always). A list read in some other order must not be.
  final bool Function(String? filter)? groupWhen;

  @override
  State<LeadCollectionPage<T>> createState() => _LeadCollectionPageState<T>();
}

class _LeadCollectionPageState<T> extends State<LeadCollectionPage<T>> {
  final _scroll = ScrollController();
  final _searchController = TextEditingController();
  late PagedQueryController<T> _controller;
  String? _filter;
  String _query = '';
  bool _searchTopUpScheduled = false;

  /// Per signal filter: the categories that have at least one lead in the
  /// list — what the category dropdown offers. Read from the loaded leads of
  /// the list when no category is selected (a selected category narrows the
  /// list to itself, so it can't be re-derived then).
  final Map<String?, Set<String>> _nonEmpty = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _attach(widget.controllerFor(_filter));
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _attach(PagedQueryController<T> controller) {
    _controller = controller..addListener(_onChanged);
  }

  void _onChanged() {
    _syncCategories();
    if (mounted) setState(() {});
  }

  /// Keeps [_nonEmpty] true to the loaded leads: replaced from the list while
  /// unfiltered, and a selected category that has run out of leads (the last
  /// one moved elsewhere) is dropped.
  void _syncCategories() {
    final c = _controller;
    if (c.loading) return;
    final known = _nonEmpty.putIfAbsent(_filter, () => <String>{});
    if (c.category == null) {
      known
        ..clear()
        ..addAll([
          for (final item in c.items)
            if (widget.categoryOf(item).trim().isNotEmpty) widget.categoryOf(item).trim(),
        ]);
    } else if (c.items.isEmpty && !c.hasMore && c.error == null) {
      known.remove(c.category);
    }
  }

  /// Opening the category list: read the rest of the list (up to a cap) so
  /// every category that has leads is offered, not just those on the pages
  /// scrolled so far.
  Future<void> _loadAllForCategories() async {
    final c = _controller;
    if (c.category != null) return;
    while (mounted && identical(c, _controller) && c.hasMore && c.error == null && c.documentsRead < _categoryReadCap) {
      if (c.loading || c.loadingMore) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      } else {
        await c.loadMore();
      }
    }
  }

  bool get _categoriesPartial =>
      _controller.category == null && _controller.hasMore && _controller.error == null;

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.maxScrollExtent - p.pixels < 600) _controller.loadMore();
  }

  Future<void> _setFilter(String? value) async {
    if (value == _filter) return;
    final previous = _controller..removeListener(_onChanged);
    setState(() => _filter = value);
    _attach(widget.controllerFor(value));
    unawaited(Future<void>.microtask(previous.dispose));
    // A different signal is a different list, with its own categories, so
    // it starts on "All categories".
    await _controller.refresh();
  }

  bool get _grouped => widget.dateOf != null && (widget.groupWhen?.call(_filter) ?? true);

  List<T> _visible() {
    final items = _controller.items;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return items;
    final words = q.split(RegExp(r'\s+'));
    return items.where((item) {
      final text = widget.searchText(item);
      return words.every(text.contains);
    }).toList();
  }

  /// A search keeps reading further pages until it has enough matches (or
  /// hits the read cap), so a rare term still turns up without the user
  /// having to scroll an apparently-empty list.
  void _topUpSearch(int matches) {
    if (_query.trim().isEmpty ||
        _searchTopUpScheduled ||
        !_controller.hasMore ||
        _controller.loading ||
        _controller.loadingMore ||
        matches >= _searchTarget ||
        _controller.documentsRead >= _searchReadCap) {
      return;
    }
    _searchTopUpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchTopUpScheduled = false;
      if (mounted) _controller.loadMore();
    });
  }

  /// The dropdown's entries: "All" plus every category with leads in this
  /// list (never the categories of other scans, which would open an empty list).
  List<String> _categories() {
    final names = {
      ...?_nonEmpty[_filter],
      if (_controller.category != null) _controller.category!,
    };
    return [allCategories, ...(names.toList()..sort())];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = _controller;
    final visible = _visible();
    _topUpSearch(visible.length);

    final searching = _query.trim().isNotEmpty;
    final capped = searching && c.hasMore && c.documentsRead >= _searchReadCap;
    final selected = c.category ?? allCategories;

    /// Leads found today. They sort first, so they are always among what's
    /// loaded; a trailing '+' would only matter if today alone overflowed a page.
    int newToday() {
      final dateOf = widget.dateOf;
      if (!_grouped || dateOf == null) return 0;
      return visible.where((l) {
        final d = dateOf(l);
        return d != null && daysAgo(d) <= 0;
      }).length;
    }

    String subtitle() {
      if (!widget.showCounts) return widget.emptySubtitle;
      if (c.loading && c.items.isEmpty) return 'Loading…';
      if (c.items.isEmpty && !searching && c.category == null) return widget.emptySubtitle;
      // The true total when the list can count itself; otherwise only what
      // has loaded so far, marked with '+' while more remains.
      final counted = !searching && c.total != null;
      final n = counted ? (c.total! > visible.length ? c.total! : visible.length) : visible.length;
      final more = !counted && c.hasMore && !searching ? '+' : '';
      final noun = n == 1 ? widget.noun : '${widget.noun}es';
      if (searching && c.hasMore && !capped) return 'Searching… $n found so far';
      final base = '$n$more $noun${capped ? ' found in the newest ${c.documentsRead}' : ''}';
      final today = newToday();
      return today > 0 ? '$base · $today new today' : base;
    }

    Widget body;
    if (c.loading && c.items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (c.error != null && c.items.isEmpty) {
      body = _ScrollableState(
        child: _Message(
          icon: AppIcons.alert,
          title: 'Could not load ${widget.title.toLowerCase()}',
          body: c.error.toString(),
          bodyColor: t.danger,
          action: OutlinedButton.icon(
            onPressed: () => c.refresh(keepCategory: true),
            icon: const Icon(AppIcons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ),
      );
    } else if (c.items.isEmpty && !searching && c.category == null && !c.hasMore) {
      body = _ScrollableState(
        child: _Message(icon: widget.emptyIcon, title: widget.emptyTitle, body: widget.emptyBody),
      );
    } else if (visible.isEmpty) {
      final waiting = searching && (c.hasMore || c.loadingMore) && !capped;
      body = waiting
          ? const Center(child: CircularProgressIndicator())
          : _ScrollableState(
              child: _Message(
                icon: AppIcons.searchX,
                title: 'No matches',
                body: capped
                    ? 'Nothing in the newest ${c.documentsRead} — pick a category to search further.'
                    : 'Try a different category or search.',
              ),
            );
    } else {
      final dateOf = widget.dateOf;
      final rows = _grouped && dateOf != null
          ? groupByDay<T>(visible, dateOf)
          : [for (final item in visible) DateGroupRow<T>.item(item)];
      body = RefreshIndicator(
        onRefresh: () => c.refresh(keepCategory: true),
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          itemCount: rows.length + 1,
          itemBuilder: (context, i) {
            if (i < rows.length) {
              final row = rows[i];
              if (row.header != null) return _DateHeader(label: row.header!, first: i == 0);
              return widget.itemBuilder(context, row.item as T);
            }
            // Footer: the paging state, so the end of the list is never a mystery.
            if (c.loadingMore) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))),
              );
            }
            if (c.error != null) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: TextButton.icon(
                    onPressed: c.loadMore,
                    icon: const Icon(AppIcons.refresh, size: 16),
                    label: const Text('Couldn’t load more — tap to retry'),
                  ),
                ),
              );
            }
            if (c.hasMore) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Center(child: TextButton(onPressed: c.loadMore, child: const Text('Load more'))),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: Text('That’s all of them', style: Theme.of(context).textTheme.bodySmall)),
            );
          },
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(title: widget.title, subtitle: subtitle()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  if (widget.banner != null) ...[
                    widget.banner!,
                    const SizedBox(height: 12),
                  ],
                  SearchField(
                    controller: _searchController,
                    value: _query,
                    hintText: widget.searchHint,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 10),
                  // Category and signal filters share one scrolling row, so
                  // the list starts higher on the screen.
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        CategoryDropdown(
                          compact: true,
                          categories: _categories(),
                          liveCategories: _categories,
                          refreshOn: _controller,
                          loadingMore: () => _categoriesPartial,
                          onOpen: _loadAllForCategories,
                          selected: selected,
                          onSelected: (value) => c.refresh(category: value == allCategories ? null : value),
                        ),
                        if (widget.filters.length > 1) ...[
                          const SizedBox(width: 8),
                          for (final f in widget.filters)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(f.label),
                                selected: _filter == f.value,
                                showCheckmark: false,
                                onSelected: (_) => _setFilter(f.value),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Day heading above a run of leads found that day: a small-caps label and
/// a hairline that runs to the edge.
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label, required this.first});

  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(top: first ? 2 : 12, bottom: 10),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: t.faint),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: t.border, height: 1)),
        ],
      ),
    );
  }
}

/// Pill dropdown that opens a searchable category sheet. [countFor] is
/// optional — with server-side paging the per-category totals aren't known
/// on the phone, so the list shows names only.
class CategoryDropdown extends StatelessWidget {
  const CategoryDropdown({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
    this.countFor,
    this.compact = false,
    this.liveCategories,
    this.refreshOn,
    this.loadingMore,
    this.onOpen,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;
  final int Function(String category)? countFor;

  /// A chip-sized button for a filter row, instead of a full-width field.
  final bool compact;

  /// While the picker is open: the current entries, re-read whenever
  /// [refreshOn] notifies (the list is still loading more leads).
  final List<String> Function()? liveCategories;
  final Listenable? refreshOn;

  /// Whether more leads are still being read (the entries may still grow).
  final bool Function()? loadingMore;

  /// Called as the picker opens.
  final VoidCallback? onOpen;

  Future<void> _openPicker(BuildContext context) async {
    onOpen?.call();
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ListenableBuilder(
        listenable: refreshOn ?? Listenable.merge(const []),
        builder: (_, _) => _CategoryPickerSheet(
          categories: liveCategories?.call() ?? categories,
          selected: selected,
          countFor: countFor,
          loading: loadingMore?.call() ?? false,
        ),
      ),
    );
    if (choice != null) onSelected(choice);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isFiltered = selected != allCategories;
    if (compact) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: isFiltered ? t.accentTint : t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            side: BorderSide(color: isFiltered ? t.accent : t.border),
          ),
          child: InkWell(
            onTap: () => _openPicker(context),
            borderRadius: BorderRadius.circular(AppTheme.radius),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220, minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AppIcons.filter, size: 16, color: isFiltered ? t.accentText : t.subtle),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isFiltered ? selected : 'All categories',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isFiltered ? t.accentTextStrong : t.subtle,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(AppIcons.chevronDown, size: 16, color: isFiltered ? t.accentText : t.subtle),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Material(
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: BorderSide(color: isFiltered ? t.accent : t.border),
      ),
      child: InkWell(
        onTap: () => _openPicker(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(AppIcons.filter, size: 19, color: t.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isFiltered ? selected : 'All categories',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: isFiltered ? t.accentTextStrong : t.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isFiltered && countFor != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.accentTint,
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                  ),
                  child: Text(
                    '${countFor!(selected)}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.accentTextStrong),
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

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.categories,
    required this.selected,
    this.countFor,
    this.loading = false,
  });

  /// More leads are still being read, so more categories may appear.
  final bool loading;
  final List<String> categories;
  final String selected;
  final int Function(String category)? countFor;

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
        : widget.categories.where((c) => c == allCategories || c.toLowerCase().contains(query)).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(child: Text('Filter by category', style: Theme.of(context).textTheme.headlineSmall)),
                    Text('${widget.categories.length - 1} categories', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (widget.loading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                  child: Row(
                    children: [
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Text('Checking every lead…', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Search categories…',
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 20, right: 12),
                      child: Icon(AppIcons.search, size: 19, color: t.faint),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
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
                          final isAll = category == allCategories;
                          final isSelected = category == widget.selected ||
                              (isAll && widget.selected == allCategories);
                          return ListTile(
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: isSelected ? t.accentTint : t.neutralTint,
                                borderRadius: BorderRadius.circular(AppTheme.radius),
                              ),
                              child: Icon(
                                isAll ? AppIcons.sparkles : AppIcons.tag,
                                size: 18,
                                color: isSelected ? t.accentTextStrong : t.subtle,
                              ),
                            ),
                            title: Text(
                              isAll ? 'All categories' : category,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                color: isSelected ? t.accentTextStrong : t.ink,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.countFor != null)
                                  Text('${widget.countFor!(category)}', style: Theme.of(context).textTheme.bodySmall),
                                if (isSelected) ...[
                                  const SizedBox(width: 10),
                                  Icon(AppIcons.check, size: 20, color: t.accentDeep),
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

/// Makes non-list states (empty/error) reachable by pull-to-refresh.
class _ScrollableState extends StatelessWidget {
  const _ScrollableState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: Padding(padding: const EdgeInsets.all(28), child: child)),
        ),
      ),
    );
  }
}

/// Icon inside a soft tinted circle — shared look for all empty states.
class StateBadge extends StatelessWidget {
  const StateBadge({super.key, required this.icon, this.background, this.foreground});

  final IconData icon;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: background ?? t.accentTint,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard + 4),
      ),
      child: Icon(icon, size: 32, color: foreground ?? t.accentText),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body, this.action, this.bodyColor});

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final Color? bodyColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StateBadge(icon: icon),
        const SizedBox(height: 20),
        Text(title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          body,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: bodyColor),
          textAlign: TextAlign.center,
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    );
  }
}
