// ignore_for_file: subtype_of_sealed_class
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// An in-memory Firestore, queried the way the app's pages and repositories do:
/// `where` (equality, `arrayContains`, `>=` / `>` / `<=` / `<`), `orderBy`
/// (which, like Firestore, leaves out documents lacking the field), `limit`,
/// `startAfterDocument`, `count()`, `get()` and live `snapshots()`.
class MemoryStore {
  final Map<String, Map<String, Map<String, dynamic>>> data = {};
  final _listeners = <void Function()>[];

  Map<String, Map<String, dynamic>> col(String name) => data.putIfAbsent(name, () => {});

  /// A query over [collection] — what the pages take as `collectionQuery`.
  Query<Map<String, dynamic>> query(String collection) => MemoryQuery(this, collection);

  /// Tells every live query the data changed, as Firestore does for a write.
  void changed() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}

class MemoryDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  MemoryDoc(this.id, this._data);

  @override
  final String id;
  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemorySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  MemorySnapshot(this.docs);

  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  int get size => docs.length;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountSnapshot implements AggregateQuerySnapshot {
  _CountSnapshot(this.count);

  @override
  final int? count;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Count implements AggregateQuery {
  _Count(this._n);

  final int _n;

  @override
  Future<AggregateQuerySnapshot> get({AggregateSource source = AggregateSource.server}) async => _CountSnapshot(_n);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

typedef MemoryFilter = ({String field, String op, Object? value});

int _compare(Object? a, Object? b) {
  if (a is Timestamp && b is Timestamp) return a.compareTo(b);
  if (a is Comparable && b is Comparable) return a.compareTo(b);
  return 0;
}

class MemoryQuery implements Query<Map<String, dynamic>> {
  MemoryQuery(this.store, this.collection, {this.filters = const [], this.order, this.desc = false, this.max, this.after});

  final MemoryStore store;
  final String collection;
  final List<MemoryFilter> filters;
  final String? order;
  final bool desc;
  final int? max;
  final String? after;

  MemoryQuery _copy({List<MemoryFilter>? filters, String? order, bool? desc, int? max, String? after}) => MemoryQuery(
        store,
        collection,
        filters: filters ?? this.filters,
        order: order ?? this.order,
        desc: desc ?? this.desc,
        max: max ?? this.max,
        after: after ?? this.after,
      );

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    final name = field as String;
    final added = <MemoryFilter>[
      if (isEqualTo != null) (field: name, op: '==', value: isEqualTo),
      if (arrayContains != null) (field: name, op: 'array-contains', value: arrayContains),
      if (isGreaterThanOrEqualTo != null) (field: name, op: '>=', value: isGreaterThanOrEqualTo),
      if (isGreaterThan != null) (field: name, op: '>', value: isGreaterThan),
      if (isLessThanOrEqualTo != null) (field: name, op: '<=', value: isLessThanOrEqualTo),
      if (isLessThan != null) (field: name, op: '<', value: isLessThan),
    ];
    return _copy(filters: [...filters, ...added]);
  }

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) => _copy(order: field as String, desc: descending);

  @override
  Query<Map<String, dynamic>> limit(int limit) => _copy(max: limit);

  @override
  Query<Map<String, dynamic>> startAfterDocument(DocumentSnapshot documentSnapshot) => _copy(after: documentSnapshot.id);

  bool _matches(Map<String, dynamic> row, MemoryFilter f) {
    final value = row[f.field];
    return switch (f.op) {
      '==' => value == f.value,
      'array-contains' => value is List && value.contains(f.value),
      '>=' => value != null && _compare(value, f.value) >= 0,
      '>' => value != null && _compare(value, f.value) > 0,
      '<=' => value != null && _compare(value, f.value) <= 0,
      '<' => value != null && _compare(value, f.value) < 0,
      _ => false,
    };
  }

  List<MapEntry<String, Map<String, dynamic>>> _rows({bool paged = true}) {
    var rows = store.col(collection).entries.where((e) => filters.every((f) => _matches(e.value, f))).toList();
    final key = order;
    if (key != null) {
      rows = rows.where((e) => e.value[key] != null).toList();
      rows.sort((a, b) {
        final c = _compare(a.value[key], b.value[key]);
        return desc ? -c : c;
      });
    }
    if (paged) {
      if (after != null) rows = rows.sublist(rows.indexWhere((e) => e.key == after) + 1);
      if (max != null && rows.length > max!) rows = rows.sublist(0, max);
    }
    return rows;
  }

  MemorySnapshot _compute() => MemorySnapshot([for (final e in _rows()) MemoryDoc(e.key, e.value)]);

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async => _compute();

  @override
  AggregateQuery count() => _Count(_rows(paged: false).length);

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    late StreamController<QuerySnapshot<Map<String, dynamic>>> controller;
    void emit() => controller.add(_compute());
    controller = StreamController<QuerySnapshot<Map<String, dynamic>>>(
      onListen: () {
        store._listeners.add(emit);
        emit();
      },
      onCancel: () => store._listeners.remove(emit),
    );
    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
