import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/lead_page.dart';
import '../../../domain/repositories/lead_repository.dart';
import 'paged_leads_event.dart';
import 'paged_leads_state.dart';

/// Pages through one lead collection — the single list engine behind
/// Review leads, No-website leads, WhatsApp leads and Email leads.
///
/// Nothing here ever holds a whole collection: it loads [pageSize] leads at
/// a time (the next page when the list is scrolled near its end), and the
/// category filter and text search are applied by the server.
///
/// A search on a large collection can't be answered from an index, so the
/// backend scans it in slices and may return a page with few matches plus a
/// cursor. The bloc keeps asking until a page is full or the collection is
/// exhausted, emitting after each slice so matches appear as they're found.
class PagedLeadsBloc extends Bloc<PagedLeadsEvent, PagedLeadsState> {
  PagedLeadsBloc(this._repository, this.collection, {this.pageSize = 50, this.searchDebounce = const Duration(milliseconds: 400)})
      : super(const PagedLeadsState()) {
    on<PagedLeadsStarted>(_onStarted);
    on<PagedLeadsCategoriesLoaded>((event, emit) => emit(state.copyWith(categories: event.categories)));
    on<PagedLeadsRefreshed>((event, emit) => _reload(emit));
    on<PagedLeadsLoadMore>(_onLoadMore);
    on<PagedLeadsQueryChanged>(_onQueryChanged);
    on<PagedLeadsQueryCommitted>((event, emit) => _reload(emit, clearList: true));
    on<PagedLeadsCategoryChanged>(_onCategoryChanged);
    on<PagedLeadsFilterChanged>(_onFilterChanged);
    on<PagedLeadDeleted>(_onDeleted);
    on<PagedLeadsCategoryDeleted>(_onCategoryDeleted);
  }

  final LeadRepository _repository;
  final LeadCollection collection;
  final int pageSize;
  final Duration searchDebounce;

  Timer? _debounce;

  /// Bumped whenever the filters change or the list reloads, so a response
  /// to a request the user has since superseded is dropped, not applied.
  int _generation = 0;

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }

  Future<LeadPage> _fetch(String? cursor) {
    return _repository.getLeadsPage(
      collection,
      cursor: cursor,
      category: state.category,
      query: state.query,
      limit: pageSize,
      verifiedOnly: state.verifiedOnly,
      emailOnly: state.emailOnly,
      sourceType: state.sourceType,
    );
  }

  String _message(Object e) => e.toString().replaceFirst('Exception: ', '');

  /// Fetches the category list in the background and hands it to the bloc as
  /// an event. A nicety for the filter — it never blocks or fails the list.
  void _loadCategories() {
    unawaited(_repository.getLeadCategories(collection).then(
      (c) {
        if (!isClosed) add(PagedLeadsCategoriesLoaded(c));
      },
      onError: (_) {},
    ));
  }

  Future<void> _onStarted(PagedLeadsStarted event, Emitter<PagedLeadsState> emit) async {
    _loadCategories();
    await _reload(emit);
  }

  /// Loads page one for the current filters. [seed] is the state to start
  /// from (a filter change passes its new filters here), so the change and
  /// the loading state land in one emit — the list never shows old results
  /// under a new filter.
  Future<void> _reload(
    Emitter<PagedLeadsState> emit, {
    bool clearList = false,
    PagedLeadsState? seed,
  }) async {
    final generation = ++_generation;
    emit((seed ?? state).copyWith(
      status: PagedLeadsStatus.loading,
      leads: clearList ? const [] : null,
      clearCursor: clearList,
      clearTotal: clearList,
      loadingMore: false,
      clearError: true,
    ));
    try {
      final page = await _fetch(null);
      if (generation != _generation) return;
      emit(state.copyWith(
        status: PagedLeadsStatus.success,
        leads: page.leads,
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        total: page.total,
        clearTotal: page.total == null,
      ));
      await _fillSearch(emit, generation, target: pageSize);
    } catch (e) {
      if (generation != _generation) return;
      emit(state.copyWith(status: PagedLeadsStatus.failure, error: _message(e)));
    }
  }

  /// A scanning search may return a short page with a cursor; keep asking
  /// until [target] leads are loaded or the collection runs out.
  Future<void> _fillSearch(Emitter<PagedLeadsState> emit, int generation, {required int target}) async {
    if (!state.isSearching) return;
    while (generation == _generation && state.hasMore && state.leads.length < target) {
      emit(state.copyWith(loadingMore: true));
      try {
        final page = await _fetch(state.nextCursor);
        if (generation != _generation) return;
        emit(state.copyWith(
          leads: [...state.leads, ...page.leads],
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
        ));
      } catch (e) {
        if (generation != _generation) return;
        emit(state.copyWith(loadingMore: false, error: _message(e)));
        return;
      }
    }
    if (generation == _generation) emit(state.copyWith(loadingMore: false));
  }

  Future<void> _onLoadMore(PagedLeadsLoadMore event, Emitter<PagedLeadsState> emit) async {
    if (state.loadingMore || !state.hasMore || state.status == PagedLeadsStatus.loading) return;
    final generation = _generation;
    emit(state.copyWith(loadingMore: true, clearError: true));
    try {
      final page = await _fetch(state.nextCursor);
      if (generation != _generation) return;
      emit(state.copyWith(
        leads: [...state.leads, ...page.leads],
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        loadingMore: false,
      ));
      await _fillSearch(emit, generation, target: state.leads.length + (page.leads.isEmpty ? pageSize : 0));
    } catch (e) {
      if (generation != _generation) return;
      emit(state.copyWith(loadingMore: false, error: _message(e)));
    }
  }

  void _onQueryChanged(PagedLeadsQueryChanged event, Emitter<PagedLeadsState> emit) {
    emit(state.copyWith(query: event.query));
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, () {
      if (!isClosed) add(const PagedLeadsQueryCommitted());
    });
  }

  Future<void> _onCategoryChanged(PagedLeadsCategoryChanged event, Emitter<PagedLeadsState> emit) async {
    await _reload(
      emit,
      clearList: true,
      seed: state.copyWith(category: event.category, clearCategory: event.category == null),
    );
  }

  Future<void> _onFilterChanged(PagedLeadsFilterChanged event, Emitter<PagedLeadsState> emit) async {
    await _reload(
      emit,
      clearList: true,
      seed: state.copyWith(
        verifiedOnly: event.verifiedOnly,
        emailOnly: event.emailOnly,
        sourceType: event.sourceType,
        clearSourceType: event.clearSourceType,
      ),
    );
  }

  Future<void> _onDeleted(PagedLeadDeleted event, Emitter<PagedLeadsState> emit) async {
    emit(state.copyWith(deletingLeadId: event.leadId, clearDeleteError: true));
    try {
      await _repository.deleteLeadIn(collection, event.leadId);
      final total = state.total;
      emit(state.copyWith(
        leads: state.leads.where((l) => l.dbId != event.leadId).toList(),
        total: total == null ? null : (total - 1).clamp(0, total),
        clearDeletingLeadId: true,
      ));
    } catch (e) {
      emit(state.copyWith(clearDeletingLeadId: true, deleteError: _message(e)));
    }
  }

  Future<void> _onCategoryDeleted(PagedLeadsCategoryDeleted event, Emitter<PagedLeadsState> emit) async {
    emit(state.copyWith(deletingCategory: event.category, clearCategoryDeleteMessage: true));
    try {
      final deleted = await _repository.deleteLeadsInCategory(collection, event.category);
      emit(state.copyWith(
        clearDeletingCategory: true,
        clearCategory: state.category == event.category,
        categoryDeleteMessage: 'Deleted $deleted lead${deleted == 1 ? '' : 's'} in "${event.category}".',
      ));
      _loadCategories();
      await _reload(emit, clearList: true);
    } catch (e) {
      emit(state.copyWith(clearDeletingCategory: true, categoryDeleteMessage: _message(e)));
    }
  }
}
