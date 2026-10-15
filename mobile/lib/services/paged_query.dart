import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

typedef QueryDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// Builds the Firestore query for one stretch of a listing. A listing is a
/// list of these, read in order — most have just one (newest first); the
/// per-salesman order has two (from the salesman's start point to the end of
/// the collection, then from the beginning back to the start point).
typedef SegmentQuery = Query<Map<String, dynamic>> Function(String? category);

/// A live, lazily-growing view of a Firestore query.
///
/// It listens (`snapshots()`) to the first [pageSize] documents, so changes —
/// a lead moved to Contacted here or on another phone, a new lead from the
/// web console — show up on their own, and asks for [pageSize] more only when
/// the list is scrolled near its end. It never listens to a whole large
/// collection: the listener's `limit` grows one page at a time.
///
/// Why one growing `limit` rather than a listener per page: a document that
/// moves (re-sorted by an update) can slip between two pages' boundaries, and
/// a single ordered window has no gaps. Growing re-reads the window, which is
/// cheap for lists of hundreds, and the SDK serves most of it from cache.
///
/// Pull-to-refresh ([refresh]) rebuilds the listeners from page one.
class PagedQueryController<T> extends ChangeNotifier {
  PagedQueryController({
    required this.segments,
    required this.map,
    this.include,
    this.pageSize = 30,
    this.maxEmptyPages = 6,
  }) : assert(segments.isNotEmpty);

  final List<SegmentQuery> segments;
  final T Function(QueryDoc doc) map;

  /// Client-side inclusion test, for conditions Firestore can't express
  /// (e.g. "status is unset or 'lead'"). Excluded documents still count as
  /// read — the window keeps growing until it has something to show.
  final bool Function(T item)? include;
  final int pageSize;

  /// Stops growing the window to find included documents after this many
  /// pages in a row, so a long run of non-matching documents can't make one
  /// fill read forever.
  final int maxEmptyPages;

  final List<_Segment> _active = [];
  String? _category;
  bool _loading = false;
  bool _loadingMore = false;
  bool _filling = false;
  Object? _error;
  int _generation = 0;
  bool _disposed = false;

  /// Included items the list is trying to hold (it keeps itself filled to
  /// this as documents come and go).
  int _wanted = 0;

  /// The most documents a single fill may hold before it stops growing.
  int _readCeiling = 0;

  /// How many times a live change (not the user) may still grow the window to
  /// refill the list — bounded, so a list full of excluded documents can't
  /// make every update read further.
  int _liveRefillsLeft = 0;
  Completer<void>? _fill;

  List<T> _items = const [];

  List<T> get items => _items;
  String? get category => _category;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  Object? get error => _error;
  bool get hasLoaded => !_loading && _error == null;

  /// Documents currently held (included or not).
  int get documentsRead => _active.fold(0, (n, s) => n + s.docs.length);

  /// Whether there are more documents beyond the window.
  bool get hasMore {
    if (_active.isEmpty) return true;
    final last = _active.last;
    if (!last.received) return true;
    return !last.exhausted || _active.length < segments.length;
  }

  /// Rebuilds the listeners from page one, optionally for a category
  /// (`null` = all).
  Future<void> refresh({String? category, bool keepCategory = false}) {
    if (!keepCategory) _category = category;
    _generation += 1;
    _cancelAll();
    _error = null;
    _loading = true;
    _loadingMore = false;
    _wanted = pageSize;
    _items = const [];
    _active.add(_Segment(segments[0](_category)));
    _startFill();
    _subscribe(_active.first, pageSize);
    _notify();
    return _fill!.future;
  }

  /// Asks for the next page. Completes when it has arrived (or there is
  /// nothing more).
  Future<void> loadMore() {
    if (_loading || _loadingMore || !hasMore) return Future.value();
    _loadingMore = true;
    _error = null;
    _wanted = _items.length + pageSize;
    _startFill();
    _notify();
    _reconcile(_generation);
    return _fill!.future;
  }

  /// [byUser] fills (refresh, loadMore) get a fresh live-refill budget.
  void _startFill({bool byUser = true}) {
    _filling = true;
    if (byUser) _liveRefillsLeft = maxEmptyPages;
    _readCeiling = documentsRead + pageSize * (maxEmptyPages + 1);
    _fill = Completer<void>();
  }

  void _endFill() {
    _filling = false;
    _loading = false;
    _loadingMore = false;
    final fill = _fill;
    if (fill != null && !fill.isCompleted) fill.complete();
  }

  void _subscribe(_Segment segment, int limit) {
    final generation = _generation;
    segment.sub?.cancel();
    segment.limit = limit;
    segment.sub = segment.query.limit(limit).snapshots().listen(
      (snap) {
        if (generation != _generation || segment.limit != limit) return; // superseded
        segment.docs = snap.docs;
        segment.received = true;
        _reconcile(generation);
      },
      onError: (Object e) {
        if (generation != _generation) return;
        _error = e;
        _endFill();
        _notify();
      },
    );
  }

  /// Recomputes the visible items from the latest snapshots and, if the list
  /// holds fewer than it wants and there is more to read, grows the window.
  void _reconcile(int generation) {
    if (generation != _generation) return;

    final seen = <String>{};
    final items = <T>[];
    for (final segment in _active) {
      for (final doc in segment.docs) {
        if (!seen.add(doc.id)) continue; // a document can sit in two segments mid-move
        final item = map(doc);
        if (include == null || include!(item)) items.add(item);
      }
    }
    _items = items;

    final last = _active.last;
    if (!last.received) {
      _notify();
      return;
    }

    if (items.length < _wanted) {
      // A change on its own (not a user fill) may refill the list a few
      // times; past that, scrolling asks for more.
      final mayGrow = _filling || _liveRefillsLeft > 0;
      if (!last.exhausted && mayGrow) {
        if (!_filling) {
          _liveRefillsLeft -= 1;
          _startFill(byUser: false);
        }
        if (documentsRead + pageSize <= _readCeiling) {
          _subscribe(last, last.limit + pageSize);
          _notify();
          return;
        }
      } else if (last.exhausted && _active.length < segments.length) {
        if (!_filling) _startFill(byUser: false);
        final next = _Segment(segments[_active.length](_category));
        _active.add(next);
        _subscribe(next, pageSize);
        _notify();
        return;
      }
    }

    _endFill();
    _notify();
  }

  void _cancelAll() {
    for (final segment in _active) {
      segment.sub?.cancel();
    }
    _active.clear();
    final fill = _fill;
    if (fill != null && !fill.isCompleted) fill.complete();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _cancelAll();
    super.dispose();
  }
}

class _Segment {
  _Segment(this.query);

  final Query<Map<String, dynamic>> query;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;
  List<QueryDoc> docs = const [];
  int limit = 0;
  bool received = false;

  /// The listener returned fewer documents than it asked for: this stretch
  /// has no more.
  bool get exhausted => received && docs.length < limit;
}
