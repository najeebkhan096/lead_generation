// ignore_for_file: subtype_of_sealed_class
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/services/paged_query.dart';
import 'package:lead_mobile/utils/seeded_shuffle.dart';

/// A document of a fake, in-memory "collection".
class _Doc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Doc(this.id, [this._data = const {}]);

  @override
  final String id;
  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Snap implements QuerySnapshot<Map<String, dynamic>> {
  _Snap(this.docs);

  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An ordered list of documents that listeners hear about when it changes.
class _Collection {
  _Collection(this.rows);

  List<_Doc> rows;
  final _listeners = <void Function()>[];

  /// How many `snapshots()` listeners are attached right now.
  int get listening => _listeners.length;

  /// Every listen, as "limit N".
  final log = <String>[];

  void changed() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void set(List<_Doc> next) {
    rows = next;
    changed();
  }
}

/// Just enough of a Query: `limit` and `snapshots`.
class _FakeQuery implements Query<Map<String, dynamic>> {
  _FakeQuery(this.collection, {this.max, this.fail = false});

  final _Collection collection;
  final int? max;
  final bool fail;

  @override
  Query<Map<String, dynamic>> limit(int limit) => _FakeQuery(collection, max: limit, fail: fail);

  QuerySnapshot<Map<String, dynamic>> _now() {
    var out = collection.rows;
    if (max != null && out.length > max!) out = out.sublist(0, max);
    return _Snap(out);
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    late StreamController<QuerySnapshot<Map<String, dynamic>>> controller;
    void emit() => controller.add(_now());
    controller = StreamController<QuerySnapshot<Map<String, dynamic>>>(
      onListen: () {
        collection.log.add('limit $max');
        if (fail) {
          controller.addError(StateError('permission-denied'));
          return;
        }
        collection._listeners.add(emit);
        emit();
      },
      onCancel: () => collection._listeners.remove(emit),
    );
    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<_Doc> _docs(int n, {String prefix = 'd', Map<String, dynamic> data = const {}}) =>
    [for (var i = 0; i < n; i++) _Doc('$prefix${i.toString().padLeft(4, '0')}', data)];

/// Lets stream events and the controller's reactions run.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  test('reports the list\'s true total from its counter, not just what has loaded', () async {
    final rows = _Collection(_docs(125));
    final c = PagedQueryController<String>(
      segments: [(category) => _FakeQuery(rows)],
      map: (doc) => doc.id,
      pageSize: 30,
      counter: (category) async => rows.rows.length,
    );

    await c.refresh();
    await settle();
    expect(c.items, hasLength(30), reason: 'only the first page is loaded');
    expect(c.hasMore, isTrue);
    expect(c.total, 125, reason: 'the header can say 125, not "30+"');
    c.dispose();
  });

  test('the total follows the list when it changes', () async {
    final rows = _Collection(_docs(40));
    var counted = 40;
    final c = PagedQueryController<String>(
      segments: [(category) => _FakeQuery(rows)],
      map: (doc) => doc.id,
      pageSize: 30,
      counter: (category) async => counted,
    );

    await c.refresh();
    await settle();
    expect(c.total, 40);

    counted = 39; // a lead was contacted: it leaves the list
    rows.set(_docs(40).sublist(1)); // the first one, inside the loaded window
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(c.total, 39);
    c.dispose();
  });

  test('a failing counter leaves the total unknown instead of breaking the list', () async {
    final rows = _Collection(_docs(10));
    final c = PagedQueryController<String>(
      segments: [(category) => _FakeQuery(rows)],
      map: (doc) => doc.id,
      counter: (category) async => throw StateError('count unavailable'),
    );

    await c.refresh();
    await settle();
    expect(c.items, hasLength(10));
    expect(c.total, isNull);
    expect(c.error, isNull);
    c.dispose();
  });

  test('listens to one page, grows by a page on loadMore, and stops at the end', () async {
    final rows = _Collection(_docs(70));
    final c = PagedQueryController<String>(
      segments: [(category) => _FakeQuery(rows)],
      map: (doc) => doc.id,
      pageSize: 30,
    );

    await c.refresh();
    expect(c.items, hasLength(30));
    expect(c.hasMore, isTrue);
    expect(rows.log, ['limit 30'], reason: 'one window of one page');

    await c.loadMore();
    expect(c.items, hasLength(60));
    expect(rows.log.last, 'limit 60');
    await c.loadMore();
    expect(c.items, hasLength(70));
    expect(c.hasMore, isFalse);
    expect(c.items.toSet(), hasLength(70), reason: 'no duplicates');

    final listens = rows.log.length;
    await c.loadMore();
    expect(rows.log.length, listens, reason: 'nothing left: no new listener');
    expect(rows.listening, 1, reason: 'one live listener, never one per page');
    c.dispose();
  });

  test('changes arrive on their own: a new document, an edit, a removal', () async {
    final rows = _Collection(_docs(5));
    final c = PagedQueryController<String>(
      segments: [(category) => _FakeQuery(rows)],
      map: (doc) => '${doc.id}:${doc.data()['v'] ?? 0}',
      pageSize: 30,
    );
    await c.refresh();
    var notified = 0;
    c.addListener(() => notified++);

    // A lead arrives from the web console.
    rows.set([_Doc('new', {'v': 1}), ...rows.rows]);
    await settle();
    expect(c.items.first, 'new:1');
    expect(c.items, hasLength(6));

    // One is edited.
    rows.set([for (final r in rows.rows) r.id == 'd0002' ? _Doc('d0002', {'v': 9}) : r]);
    await settle();
    expect(c.items, contains('d0002:9'));

    // One is deleted.
    rows.set(rows.rows.where((r) => r.id != 'd0000').toList());
    await settle();
    expect(c.items, hasLength(5));
    expect(c.items.any((i) => i.startsWith('d0000')), isFalse);
    expect(notified, greaterThanOrEqualTo(3));
    c.dispose();
  });

  test('a document that stops being included leaves the list, and one that starts appears', () async {
    final rows = _Collection([
      _Doc('a', {'status': 'lead'}),
      _Doc('b', {'status': 'lead'}),
      _Doc('c', {'status': 'contacted'}),
    ]);
    final c = PagedQueryController<String>(
      segments: [(category) => _FakeQuery(rows)],
      map: (doc) => doc.id,
      include: null,
      pageSize: 30,
    );
    final isNew = PagedQueryController<_Row>(
      segments: [(category) => _FakeQuery(rows)],
      map: (doc) => _Row(doc.id, doc.data()['status'] as String),
      include: (r) => r.status == 'lead',
      pageSize: 30,
    );
    await isNew.refresh();
    expect(isNew.items.map((r) => r.id), ['a', 'b']);

    // "a" is contacted — in the same collection, from anywhere.
    rows.set([_Doc('a', {'status': 'contacted'}), rows.rows[1], rows.rows[2]]);
    await settle();
    expect(isNew.items.map((r) => r.id), ['b']);

    // "c" moves back to New.
    rows.set([rows.rows[0], rows.rows[1], _Doc('c', {'status': 'lead'})]);
    await settle();
    expect(isNew.items.map((r) => r.id), ['b', 'c']);
    c.dispose();
    isNew.dispose();
  });

  test('a salesman’s listing wraps from their start point back to the beginning', () async {
    final all = _docs(50);
    final tail = _Collection(all.sublist(30)); // from the salesman's point to the end
    final head = _Collection(all.sublist(0, 30)); // then from the beginning
    final c = PagedQueryController<String>(
      segments: [(category) => _FakeQuery(tail), (category) => _FakeQuery(head)],
      map: (doc) => doc.id,
      pageSize: 15,
    );

    await c.refresh();
    expect(c.items.first, 'd0030', reason: 'starts at the salesman’s point, not the newest');
    while (c.hasMore) {
      await c.loadMore();
    }
    expect(c.items, hasLength(50));
    expect(c.items.toSet(), hasLength(50), reason: 'every lead exactly once');
    expect(c.items.sublist(20).first, 'd0000', reason: 'wrapped around to the start');
    c.dispose();
  });

  test('documents that are excluded client-side are read past, not shown', () async {
    // 100 documents; only every 10th is "new".
    final rows = _Collection([for (var i = 0; i < 100; i++) _Doc('d$i')]);
    final c = PagedQueryController<String>(
      segments: [(category) => _FakeQuery(rows)],
      map: (doc) => doc.id,
      include: (id) => int.parse(id.substring(1)) % 10 == 0,
      pageSize: 5,
    );

    await c.refresh();
    expect(c.items, isNotEmpty, reason: 'kept growing the window until something matched');
    expect(c.items.every((id) => int.parse(id.substring(1)) % 10 == 0), isTrue);
    expect(c.documentsRead, greaterThan(c.items.length));
    c.dispose();
  });

  test('growing to find included documents is bounded by maxEmptyPages', () async {
    // Nothing is ever included, in a collection far larger than the budget.
    final rows = _Collection(_docs(1000));
    final c = PagedQueryController<String>(
      segments: [(category) => _FakeQuery(rows)],
      map: (doc) => doc.id,
      include: (_) => false,
      pageSize: 10,
      maxEmptyPages: 3,
    );

    await c.refresh();
    await settle();
    expect(c.items, isEmpty);
    expect(c.documentsRead, lessThanOrEqualTo(10 * (3 + 1)), reason: 'did not read the whole collection');
    expect(c.hasMore, isTrue);
    expect(c.loading, isFalse);
    c.dispose();
  });

  test('refresh with a category restarts from page one and remembers the category', () async {
    final seen = <String?>[];
    final all = _Collection(_docs(40));
    final cafe = _Collection(_docs(10, prefix: 'c'));
    final c = PagedQueryController<String>(
      segments: [
        (category) {
          seen.add(category);
          return _FakeQuery(category == 'Cafe' ? cafe : all);
        },
      ],
      map: (doc) => doc.id,
      pageSize: 20,
    );

    await c.refresh();
    expect(c.items, hasLength(20));
    await c.refresh(category: 'Cafe');
    expect(c.items, hasLength(10));
    expect(c.items.every((id) => id.startsWith('c')), isTrue);
    expect(c.hasMore, isFalse);
    expect(c.category, 'Cafe');
    expect(all.listening, 0, reason: 'the old listener was cancelled');

    // Pull-to-refresh keeps the filter.
    await c.refresh(keepCategory: true);
    expect(c.category, 'Cafe');
    expect(seen.last, 'Cafe');
    expect(cafe.listening, 1);
    c.dispose();
  });

  test('a listener error surfaces and keeps what was loaded', () async {
    final good = _Collection(_docs(60));
    var queries = 0;
    final c = PagedQueryController<String>(
      segments: [
        (category) {
          queries += 1;
          return _FakeQuery(good);
        },
      ],
      map: (doc) => doc.id,
      pageSize: 30,
    );
    await c.refresh();
    expect(c.items, hasLength(30));

    // The server starts refusing the query.
    final failing = PagedQueryController<String>(
      segments: [(category) => _FakeQuery(good, fail: true)],
      map: (doc) => doc.id,
    );
    await failing.refresh();
    await settle();
    expect(failing.error, isNotNull);
    expect(failing.loading, isFalse);
    expect(failing.items, isEmpty);
    expect(queries, 1);
    c.dispose();
    failing.dispose();
  });

  test('dispose cancels every listener', () async {
    final rows = _Collection(_docs(100));
    final c = PagedQueryController<String>(
      segments: [(category) => _FakeQuery(rows)],
      map: (doc) => doc.id,
      pageSize: 30,
    );
    await c.refresh();
    await c.loadMore();
    expect(rows.listening, 1);

    c.dispose();
    expect(rows.listening, 0);
    rows.set(_docs(3)); // must not throw into a disposed controller
    await settle();
  });

  test('seededStartId is a stable 40-hex id that differs per salesman', () {
    final a = seededStartId('uid-alice');
    expect(a, matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(seededStartId('uid-alice'), a, reason: 'stable across calls');
    expect(seededStartId('uid-bob'), isNot(a));
  });
}

class _Row {
  const _Row(this.id, this.status);

  final String id;
  final String status;
}
