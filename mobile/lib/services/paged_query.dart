import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

typedef QueryDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// Builds the Firestore query for one stretch of a listing. A listing is a
/// list of these, read in order — most have just one (newest first); the
/// per-salesman order has two (from the salesman's start point to the end of
/// the collection, then from the beginning back to the start point).
typedef SegmentQuery = Query<Map<String, dynamic>> Function(String? category);

/// Pages through a Firestore query a page at a time.
///
/// Replaces the old pattern of streaming a whole collection live: the
/// website-leads collection alone has tens of thousands of documents, and
/// every phone was downloading and re-diffing all of them. This reads
/// [pageSize] documents per request (`limit` + `startAfterDocument`) and
/// only fetches the next page when the list is scrolled near its end.
///
/// Pull-to-refresh ([refresh]) is how new data arrives — pages are one-shot
/// reads, not subscriptions.
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
  /// read — the controller keeps fetching until it has something to show.
  final bool Function(T item)? include;
  final int pageSize;

  /// Stops chasing a page full of excluded documents after this many reads
  /// in a row, so a long run of non-matching documents can't loop forever.
  final int maxEmptyPages;

  final List<T> _items = [];
  String? _category;
  int _segment = 0;
  QueryDoc? _last;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;
  int _generation = 0;

  /// Documents read so far (included or not).
  int _read = 0;

  List<T> get items => List.unmodifiable(_items);
  String? get category => _category;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  Object? get error => _error;
  int get documentsRead => _read;
  bool get hasLoaded => !_loading && _error == null;

  /// Loads page one, optionally for a category (`null` = all).
  Future<void> refresh({String? category, bool keepCategory = false}) async {
    if (!keepCategory) _category = category;
    final generation = ++_generation;
    _items.clear();
    _segment = 0;
    _last = null;
    _hasMore = true;
    _read = 0;
    _error = null;
    _loading = true;
    _loadingMore = false;
    notifyListeners();
    await _fill(generation);
  }

  /// Loads the next page, if there is one and none is already in flight.
  Future<void> loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final generation = _generation;
    _loadingMore = true;
    _error = null;
    notifyListeners();
    await _fill(generation);
  }

  Future<void> _fill(int generation) async {
    var emptyPages = 0;
    try {
      while (_hasMore && generation == _generation) {
        final added = await _readPage();
        if (generation != _generation) return;
        if (added > 0) break;
        // The page was all excluded documents — read on, within reason.
        emptyPages += 1;
        if (emptyPages >= maxEmptyPages) break;
      }
    } catch (e) {
      if (generation != _generation) return;
      _error = e;
    }
    if (generation != _generation) return;
    _loading = false;
    _loadingMore = false;
    notifyListeners();
  }

  /// Reads one page; returns how many items it added.
  Future<int> _readPage() async {
    var query = segments[_segment](_category);
    if (_last != null) query = query.startAfterDocument(_last!);
    final snap = await query.limit(pageSize).get();
    _read += snap.docs.length;

    var added = 0;
    for (final doc in snap.docs) {
      final item = map(doc);
      if (include == null || include!(item)) {
        _items.add(item);
        added += 1;
      }
    }

    if (snap.docs.length < pageSize) {
      // This stretch is exhausted: move on to the next, or finish.
      if (_segment + 1 < segments.length) {
        _segment += 1;
        _last = null;
      } else {
        _hasMore = false;
      }
    } else {
      _last = snap.docs.last;
    }
    return added;
  }
}
