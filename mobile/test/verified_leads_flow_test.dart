// ignore_for_file: subtype_of_sealed_class
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/pages/verified_leads_screen.dart';
import 'package:lead_mobile/services/verified_lead_repository.dart';
import 'package:lead_mobile/theme/app_theme.dart';
import 'package:lead_mobile/widgets/verified_lead_card.dart';

/// An in-memory Firestore: collections of maps, queried the way the pages do
/// (`where ==`, `orderBy` — which leaves out docs lacking the field, like
/// Firestore — `limit`, `startAfterDocument`).
class _Store {
  final Map<String, Map<String, Map<String, dynamic>>> data = {};
  final writes = <String>[];
  final _listeners = <void Function()>[];

  Map<String, Map<String, dynamic>> col(String c) => data.putIfAbsent(c, () => {});

  /// Tells every live query the data changed, as Firestore does for a write.
  void changed() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}

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

class _Query implements Query<Map<String, dynamic>> {
  _Query(this.store, this.collection, {this.filters = const {}, this.order, this.desc = false, this.max, this.after});

  final _Store store;
  final String collection;
  final Map<String, Object?> filters;
  final String? order;
  final bool desc;
  final int? max;
  final String? after;

  _Query _copy({Map<String, Object?>? filters, String? order, bool? desc, int? max, String? after}) => _Query(
        store,
        collection,
        filters: filters ?? this.filters,
        order: order ?? this.order,
        desc: desc ?? this.desc,
        max: max ?? this.max,
        after: after ?? this.after,
      );

  @override
  Query<Map<String, dynamic>> where(Object field, {Object? isEqualTo, Object? isNotEqualTo, Object? isLessThan, Object? isLessThanOrEqualTo, Object? isGreaterThan, Object? isGreaterThanOrEqualTo, Object? arrayContains, Iterable<Object?>? arrayContainsAny, Iterable<Object?>? whereIn, Iterable<Object?>? whereNotIn, bool? isNull}) =>
      _copy(filters: {...filters, field as String: isEqualTo});

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) =>
      _copy(order: field as String, desc: descending);

  @override
  Query<Map<String, dynamic>> limit(int limit) => _copy(max: limit);

  @override
  Query<Map<String, dynamic>> startAfterDocument(DocumentSnapshot documentSnapshot) => _copy(after: documentSnapshot.id);

  QuerySnapshot<Map<String, dynamic>> _compute() {
    var rows = store.col(collection).entries.toList();
    rows = rows.where((e) => filters.entries.every((f) => e.value[f.key] == f.value)).toList();
    if (order != null) {
      rows = rows.where((e) => e.value[order] != null).toList();
      rows.sort((a, b) {
        final c = (a.value[order] as Timestamp).compareTo(b.value[order] as Timestamp);
        return desc ? -c : c;
      });
    }
    if (after != null) rows = rows.sublist(rows.indexWhere((e) => e.key == after) + 1);
    if (max != null && rows.length > max!) rows = rows.sublist(0, max);
    return _Snap([for (final e in rows) _Doc(e.key, e.value)]);
  }

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

/// Writes what the real repository writes, into the in-memory store.
class _FakeRepo extends VerifiedLeadRepository {
  _FakeRepo(this.store);

  final _Store store;
  bool failNext = false;

  @override
  Future<void> setContacted(String collection, String leadId, {required bool contacted}) async {
    if (failNext) {
      failNext = false;
      throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    }
    store.writes.add('$collection/$leadId contacted=$contacted');
    final doc = store.col(collection)[leadId]!;
    if (contacted) {
      doc['status'] = 'contacted';
      doc['contactedAt'] = Timestamp.now();
    } else {
      doc['status'] = 'lead';
      doc.remove('contactedAt');
    }
    store.changed();
  }
}

Map<String, dynamic> _verified(String business, DateTime verified,
        {String phone = '+15125550001', DateTime? contacted, String sourceType = 'review'}) =>
    {
      'business': business,
      'category': 'Cafe USA',
      'location': 'Texas',
      'phone': phone,
      'sourceType': sourceType,
      'updatedAt': Timestamp.fromDate(verified),
      'createdAt': Timestamp.fromDate(verified),
      'whatsAppCheckedAt': Timestamp.fromDate(verified),
      if (contacted != null) ...{'status': 'contacted', 'contactedAt': Timestamp.fromDate(contacted)},
    };

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  late _Store store;
  late _FakeRepo repo;
  late List<String> opened;

  final today = DateTime.now();
  DateTime at(int daysAgo, [int hour = 10]) => DateTime(today.year, today.month, today.day - daysAgo, hour);

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: VerifiedLeadsScreen(
          repository: repo,
          collectionQuery: (c) => _Query(store, c),
          actions: LeadActions(
            whatsapp: (url) async {
              opened.add('whatsapp $url');
              return !(url ?? '').contains('fail');
            },
            phone: (n) async {
              opened.add('call $n');
              return true;
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The New / Contacted switch.
  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ChoiceChip, label).hitTestable().first);
    await tester.pumpAndSettle();
  }

  setUp(() {
    store = _Store();
    repo = _FakeRepo(store);
    opened = [];
    store.col('whatsappLeads')
      ..['a'] = _verified('Alpha Cafe', at(0, 9))
      ..['b'] = _verified('Bravo Cafe', at(1), phone: '+15125550002')
      ..['c'] = _verified('Charlie Cafe', at(2), phone: '+15125550003', contacted: at(0, 8))
      ..['d'] = _verified('Delta Cafe', at(3), phone: '+15125550004', contacted: at(0, 11));
  });

  testWidgets('New and Contacted each show only their own, most recently contacted first', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Alpha Cafe'), findsOneWidget);
    expect(find.text('Bravo Cafe'), findsOneWidget);
    expect(find.text('Charlie Cafe'), findsNothing);
    expect(find.text('WhatsApp · 1-star reviews'), findsOneWidget);

    await openTab(tester, 'Contacted');
    expect(find.text('Alpha Cafe'), findsNothing);
    expect(find.text('Charlie Cafe'), findsOneWidget);
    expect(find.text('Delta Cafe'), findsOneWidget);
    // Delta was contacted at 11:00, Charlie at 08:00 — newest contact first.
    expect(tester.getTopLeft(find.text('Delta Cafe')).dy, lessThan(tester.getTopLeft(find.text('Charlie Cafe')).dy));
    expect(find.textContaining('Contacted ·'), findsWidgets);
  });

  testWidgets('contacting a new lead moves it to Contacted and offers Undo', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'WhatsApp').first);
    await tester.pumpAndSettle();

    expect(opened.single, startsWith('whatsapp '));
    expect(store.writes, ['whatsappLeads/a contacted=true']);
    expect(store.col('whatsappLeads')['a']!['status'], 'contacted');
    // Gone from New, no reload flash; the other lead is still there.
    expect(find.text('Alpha Cafe'), findsNothing);
    expect(find.text('Bravo Cafe'), findsOneWidget);
    expect(find.text('Moved to Contacted'), findsOneWidget);

    await openTab(tester, 'Contacted');
    expect(find.text('Alpha Cafe'), findsOneWidget);
  });

  testWidgets('a call also counts as contacting', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Call').first);
    await tester.pumpAndSettle();

    expect(opened.single, startsWith('call '));
    expect(store.writes, hasLength(1));
    expect(find.text('Alpha Cafe'), findsNothing);
  });

  testWidgets('nothing changes when the WhatsApp app could not be opened', (tester) async {
    store.col('whatsappLeads')['a']!['phone'] = 'fail';
    store.col('whatsappLeads')['a']!['waLink'] = 'https://wa.me/fail';
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'WhatsApp').first);
    await tester.pumpAndSettle();

    expect(store.writes, isEmpty);
    expect(find.text('Alpha Cafe'), findsOneWidget);
    expect(find.text('Could not open WhatsApp'), findsOneWidget);
  });

  testWidgets('a rejected write leaves the lead in New and says so', (tester) async {
    repo.failNext = true;
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'WhatsApp').first);
    await tester.pumpAndSettle();

    expect(find.text('Alpha Cafe'), findsOneWidget);
    expect(find.textContaining('Could not update the lead'), findsOneWidget);
  });

  testWidgets('Undo brings the lead back to New', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'WhatsApp').first);
    await tester.pumpAndSettle();
    expect(find.text('Alpha Cafe'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(store.col('whatsappLeads')['a']!['status'], 'lead');
    expect(store.col('whatsappLeads')['a']!.containsKey('contactedAt'), isFalse);
    expect(find.text('Alpha Cafe'), findsOneWidget);
    await openTab(tester, 'Contacted');
    expect(find.text('Alpha Cafe'), findsNothing);
  });

  testWidgets('Move to New puts a contacted lead back in the New list', (tester) async {
    await pumpScreen(tester);
    await openTab(tester, 'Contacted');

    await tester.tap(find.widgetWithText(TextButton, 'Move to New').first);
    await tester.pumpAndSettle();

    expect(find.text('Delta Cafe'), findsNothing);
    expect(store.writes, ['whatsappLeads/d contacted=false']);

    await openTab(tester, 'New');
    expect(find.text('Delta Cafe'), findsOneWidget);
  });

  testWidgets('a lead that is already contacted does not change status again', (tester) async {
    await pumpScreen(tester);
    await openTab(tester, 'Contacted');

    await tester.tap(find.widgetWithText(FilledButton, 'WhatsApp').first);
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(store.writes, isEmpty);
    expect(find.text('Delta Cafe'), findsOneWidget);
  });

  group('category dropdown offers only categories that have leads', () {
    Future<void> openCategories(WidgetTester tester) async {
      await tester.tap(find.text('All categories').hitTestable().first);
      await tester.pumpAndSettle();
    }

    setUp(() {
      store.col('whatsappLeads')['b']!['category'] = 'Plumber USA'; // New
      store.col('whatsappLeads')['d']!['category'] = 'Gym USA'; // Contacted
    });

    testWidgets('New: the categories of the new leads, not those of contacted ones', (tester) async {
      await pumpScreen(tester);
      await openCategories(tester);

      expect(find.text('Cafe USA'), findsOneWidget);
      expect(find.text('Plumber USA'), findsOneWidget);
      expect(find.text('Gym USA'), findsNothing); // only has a contacted lead
      expect(find.text('2 categories'), findsOneWidget);
    });

    testWidgets('Contacted: the categories of the contacted leads', (tester) async {
      await pumpScreen(tester);
      await openTab(tester, 'Contacted');
      await openCategories(tester);

      expect(find.text('Cafe USA'), findsOneWidget);
      expect(find.text('Gym USA'), findsOneWidget);
      expect(find.text('Plumber USA'), findsNothing);
    });

    testWidgets('picking one narrows the list and the others stay on offer', (tester) async {
      await pumpScreen(tester);
      await openCategories(tester);
      await tester.tap(find.text('Plumber USA'));
      await tester.pumpAndSettle();

      expect(find.text('Bravo Cafe'), findsOneWidget);
      expect(find.text('Alpha Cafe'), findsNothing);

      // The chip now carries the selected category's name.
      await tester.tap(find.text('Plumber USA').hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.text('Cafe USA'), findsOneWidget);
      expect(find.text('Plumber USA'), findsWidgets); // the chip and the entry
    });

    testWidgets('a category disappears once its last lead has moved to Contacted', (tester) async {
      await pumpScreen(tester);
      // Bravo (Plumber) is the second New lead.
      await tester.tap(find.widgetWithText(FilledButton, 'WhatsApp').at(1));
      await tester.pumpAndSettle();
      expect(find.text('Bravo Cafe'), findsNothing);

      await openCategories(tester);
      expect(find.text('Cafe USA'), findsOneWidget);
      expect(find.text('Plumber USA'), findsNothing);
    });

    testWidgets('a category that only appears on a later page is found when the list opens', (tester) async {
      // 35 newer Cafe leads push a single Zoo lead well past the first page.
      for (var i = 0; i < 35; i++) {
        store.col('whatsappLeads')['cafe$i'] = _verified('Cafe $i', at(0, 8), phone: '+1512555${1000 + i}');
      }
      store.col('whatsappLeads')['zoo'] = _verified('Zoo Lead', at(5), phone: '+15125559999')..['category'] = 'Zoo USA';

      await pumpScreen(tester);
      expect(find.text('Zoo Lead'), findsNothing); // not on the first page

      await openCategories(tester);
      expect(find.text('Zoo USA'), findsOneWidget);
    });
  });

  group('lists listen to the data', () {
    testWidgets('a lead contacted from another phone moves between the tabs on its own', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Bravo Cafe'), findsOneWidget);

      // Another salesman marks it contacted: a write elsewhere, no action here.
      store.col('whatsappLeads')['b']!
        ..['status'] = 'contacted'
        ..['contactedAt'] = Timestamp.now();
      store.changed();
      await tester.pumpAndSettle();

      expect(find.text('Bravo Cafe'), findsNothing);
      await openTab(tester, 'Contacted');
      expect(find.text('Bravo Cafe'), findsOneWidget);
    });

    testWidgets('a lead validated in the web console appears without refreshing', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Echo Cafe'), findsNothing);

      store.col('whatsappLeads')['e'] = _verified('Echo Cafe', at(0, 23), phone: '+15125550005');
      store.changed();
      await tester.pumpAndSettle();

      expect(find.text('Echo Cafe'), findsOneWidget);
      // Newest first: above the others.
      expect(tester.getTopLeft(find.text('Echo Cafe')).dy, lessThan(tester.getTopLeft(find.text('Alpha Cafe')).dy));
    });

    testWidgets('a lead removed in the console disappears', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Alpha Cafe'), findsOneWidget);

      store.col('whatsappLeads').remove('a');
      store.changed();
      await tester.pumpAndSettle();

      expect(find.text('Alpha Cafe'), findsNothing);
      expect(find.text('Bravo Cafe'), findsOneWidget);
    });

    testWidgets('the category list follows a new lead in a new category', (tester) async {
      await pumpScreen(tester);

      store.col('whatsappLeads')['f'] = _verified('Foxtrot Gym', at(0, 22), phone: '+15125550006')..['category'] = 'Gym USA';
      store.changed();
      await tester.pumpAndSettle();

      await tester.tap(find.text('All categories').hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.text('Gym USA'), findsOneWidget);
    });
  });

  testWidgets('a no-website lead validated on WhatsApp stays out of the list', (tester) async {
    store.col('whatsappLeads')['w1'] = _verified('Whiskey Web', at(0, 7), phone: '+15125559001', sourceType: 'website');
    await pumpScreen(tester);

    expect(find.text('Alpha Cafe'), findsOneWidget);
    expect(find.text('Whiskey Web'), findsNothing);
  });
}
