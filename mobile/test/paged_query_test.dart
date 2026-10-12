// ignore_for_file: subtype_of_sealed_class
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

/// Just enough of a Query: `limit`, `startAfterDocument`, `get`.
class _FakeQuery implements Query<Map<String, dynamic>> {
  _FakeQuery(this.rows, this.log, {this.max, this.after});

  final List<_Doc> rows;
  final List<String> log;
  final int? max;
  final String? after;

  @override
  Query<Map<String, dynamic>> limit(int limit) => _FakeQuery(rows, log, max: limit, after: after);

  @override
  Query<Map<String, dynamic>> startAfterDocument(DocumentSnapshot documentSnapshot) =>
      _FakeQuery(rows, log, max: max, after: documentSnapshot.id);

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    var out = rows;
    if (after != null) {
      final i = out.indexWhere((d) => d.id == after);
      out = out.sublist(i + 1);
    }
    if (max != null && out.length > max!) out = out.sublist(0, max);
    log.add('read ${out.length} after ${after ?? 'start'}');
    return _Snap(out);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<_Doc> _docs(int n, {String prefix = 'd', Map<String, dynamic> data = const {}}) =>
    [for (var i = 0; i < n; i++) _Doc('$prefix${i.toString().padLeft(4, '0')}', data)];

void main() {
  test('reads one page, then the next on loadMore, and stops at the end', () async {
    final log = <String>[];
    final rows = _docs(70);
    final c = PagedQueryController<String>(
      segments: [(category) => _FakeQuery(rows, log)],
      map: (doc) => doc.id,
      pageSize: 30,
    );

    await c.refresh();
    expect(c.items, hasLength(30));
    expect(c.hasMore, isTrue);
    expect(log, ['read 30 after start'], reason: 'exactly one page was read');

    await c.loadMore();
    expect(c.items, hasLength(60));
    await c.loadMore();
    expect(c.items, hasLength(70));
    expect(c.hasMore, isFalse);
    expect(c.items.toSet(), hasLength(70), reason: 'no duplicates');

    final reads = log.length;
    await c.loadMore();
    expect(log.length, reads, reason: 'nothing left: no request');
  });

  test('a salesman’s listing wraps from their start point back to the beginning', () async {
    final log = <String>[];
    final rows = _docs(50);
    // Segment 1 = from index 30 to the end; segment 2 = from the beginning.
    final c = PagedQueryController<String>(
      segments: [
        (category) => _FakeQuery(rows.sublist(30), log),
        (category) => _FakeQuery(rows.sublist(0, 30), log),
      ],
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
  });

  test('documents that are excluded client-side are read past, not shown', () async {
    final log = <String>[];
    // 100 documents; only every 10th is "new".
    final rows = [
      for (var i = 0; i < 100; i++) _Doc('d$i', {'new': i % 10 == 0}),
    ];
    final c = PagedQueryController<String>(
      segments: [(category) => _FakeQuery(rows, log)],
      map: (doc) => doc.id,
      include: (id) => int.parse(id.substring(1)) % 10 == 0,
      pageSize: 5,
    );

    await c.refresh();
    expect(c.items, isNotEmpty, reason: 'kept reading until something matched');
    expect(c.items.every((id) => int.parse(id.substring(1)) % 10 == 0), isTrue);
    expect(c.documentsRead, greaterThan(c.items.length));
  });

  test('refresh with a category restarts from page one and remembers the category', () async {
    final log = <String>[];
    final seen = <String?>[];
    final c = PagedQueryController<String>(
      segments: [
        (category) {
          seen.add(category);
          return _FakeQuery(category == 'Cafe' ? _docs(10, prefix: 'c') : _docs(40), log);
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

    // Pull-to-refresh keeps the filter.
    await c.refresh(keepCategory: true);
    expect(c.category, 'Cafe');
    expect(seen.last, 'Cafe');
  });

  test('a failed page surfaces the error and keeps what was loaded', () async {
    var calls = 0;
    final log = <String>[];
    final c = PagedQueryController<String>(
      segments: [
        (category) {
          calls += 1;
          if (calls == 2) throw StateError('network down');
          return _FakeQuery(_docs(60), log);
        },
      ],
      map: (doc) => doc.id,
      pageSize: 30,
    );

    await c.refresh();
    expect(c.items, hasLength(30));
    await c.loadMore();
    expect(c.error, isNotNull);
    expect(c.items, hasLength(30), reason: 'already-loaded items are kept');
    expect(c.loadingMore, isFalse);
  });

  test('seededStartId is a stable 40-hex id that differs per salesman', () {
    final a = seededStartId('uid-alice');
    expect(a, matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(seededStartId('uid-alice'), a, reason: 'stable across calls');
    expect(seededStartId('uid-bob'), isNot(a));
  });
}
