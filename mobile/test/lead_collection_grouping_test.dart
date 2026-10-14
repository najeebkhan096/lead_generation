// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/services/paged_query.dart';
import 'package:lead_mobile/theme/app_theme.dart';
import 'package:lead_mobile/widgets/lead_collection_page.dart';

class _Doc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Doc(this.id, this._data);

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

class _FakeQuery implements Query<Map<String, dynamic>> {
  _FakeQuery(this.rows, {this.max, this.after});

  final List<_Doc> rows;
  final int? max;
  final String? after;

  @override
  Query<Map<String, dynamic>> limit(int limit) => _FakeQuery(rows, max: limit, after: after);

  @override
  Query<Map<String, dynamic>> startAfterDocument(DocumentSnapshot documentSnapshot) =>
      _FakeQuery(rows, max: max, after: documentSnapshot.id);

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    var out = rows;
    if (after != null) out = out.sublist(out.indexWhere((d) => d.id == after) + 1);
    if (max != null && out.length > max!) out = out.sublist(0, max);
    return _Snap(out);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

typedef _Lead = ({String name, DateTime found});

Widget _page(List<_Doc> rows) => MaterialApp(
      theme: AppTheme.light(),
      home: LeadCollectionPage<_Lead>(
        title: 'Discover leads',
        noun: 'business',
        headerIcon: Icons.search,
        searchHint: 'Search',
        emptyIcon: Icons.inbox,
        emptyTitle: 'Empty',
        emptyBody: 'Nothing',
        emptySubtitle: 'Nothing yet',
        filters: const [
          (label: 'Newest', value: null),
          (label: 'My queue', value: 'queue'),
        ],
        dateOf: (l) => l.found,
        groupWhen: (filter) => filter != 'queue',
        controllerFor: (_) => PagedQueryController<_Lead>(
          segments: [(category) => _FakeQuery(rows)],
          map: (doc) => (name: doc.id, found: doc.data()['found'] as DateTime),
        ),
        itemBuilder: (context, l) => SizedBox(height: 56, child: Text(l.name)),
        searchText: (l) => l.name.toLowerCase(),
        categoryOf: (_) => '',
        loadCategories: () async => const [],
      ),
    );

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 9);
  final yesterday = DateTime(now.year, now.month, now.day - 1, 20);
  final older = DateTime(now.year, now.month, now.day - 30, 10);
  final rows = [
    _Doc('Cafe A', {'found': today}),
    _Doc('Cafe B', {'found': today}),
    _Doc('Gym C', {'found': yesterday}),
    _Doc('Spa D', {'found': older}),
  ];

  testWidgets('groups newest-first leads under Today / Yesterday / a date, and counts today', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_page(rows));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.textContaining('4 businesses'), findsOneWidget);
    expect(find.textContaining('2 new today'), findsOneWidget);

    // Headers sit above their leads, in order.
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('Today'), lessThan(y('Cafe A')));
    expect(y('Cafe B'), lessThan(y('Yesterday')));
    expect(y('Yesterday'), lessThan(y('Gym C')));
    expect(y('Gym C'), lessThan(y('Spa D')));
  });

  testWidgets('a list in another order (My queue) is not grouped', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_page(rows));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);

    await tester.tap(find.text('My queue'));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsNothing);
    expect(find.text('Yesterday'), findsNothing);
    expect(find.text('Cafe A'), findsOneWidget);
    expect(find.textContaining('new today'), findsNothing);
  });
}
