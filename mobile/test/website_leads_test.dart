// ignore_for_file: subtype_of_sealed_class
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/pages/website_leads_screen.dart';
import 'package:lead_mobile/theme/app_theme.dart';
import 'package:lead_mobile/widgets/verified_lead_card.dart';

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

/// An in-memory collection queried the way the page does: `where ==`,
/// `orderBy` (which leaves out docs lacking the field, like Firestore),
/// `limit` and `startAfterDocument`.
class _Query implements Query<Map<String, dynamic>> {
  _Query(this.rows, this.log, {this.filters = const {}, this.order, this.desc = false, this.max, this.after});

  final Map<String, Map<String, dynamic>> rows;
  final List<Map<String, Object?>> log;
  final Map<String, Object?> filters;
  final String? order;
  final bool desc;
  final int? max;
  final String? after;

  _Query _copy({Map<String, Object?>? filters, String? order, bool? desc, int? max, String? after}) => _Query(
        rows,
        log,
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
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) => _copy(order: field as String, desc: descending);

  @override
  Query<Map<String, dynamic>> limit(int limit) => _copy(max: limit);

  @override
  Query<Map<String, dynamic>> startAfterDocument(DocumentSnapshot documentSnapshot) => _copy(after: documentSnapshot.id);

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    log.add(filters);
    var found = rows.entries.where((e) => filters.entries.every((f) => e.value[f.key] == f.value)).toList();
    if (order != null) {
      found = found.where((e) => e.value[order] != null).toList();
      found.sort((a, b) {
        final c = (a.value[order] as Timestamp).compareTo(b.value[order] as Timestamp);
        return desc ? -c : c;
      });
    }
    if (after != null) found = found.sublist(found.indexWhere((e) => e.key == after) + 1);
    if (max != null && found.length > max!) found = found.sublist(0, max);
    return Stream.value(_Snap([for (final e in found) _Doc(e.key, e.value)]));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _site(String business, DateTime at,
        {bool whatsApp = true, String status = 'missing', String phone = '+97455500001', String category = 'Salon'}) =>
    {
      'business': business,
      'category': category,
      'location': 'Doha',
      'phone': phone,
      'waLink': 'https://wa.me/${phone.substring(1)}',
      'websiteStatus': status,
      'hasWhatsApp': whatsApp,
      'whatsAppCheckedAt': Timestamp.fromDate(at),
      'updatedAt': Timestamp.fromDate(at),
      'createdAt': Timestamp.fromDate(at),
    };

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  final now = DateTime.now();
  final rows = <String, Map<String, dynamic>>{};
  late List<Map<String, Object?>> log;
  late List<String> opened;

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: WebsiteLeadsScreen(
          collectionQuery: (c) {
            expect(c, 'websiteLeads');
            return _Query(rows, log);
          },
          actions: LeadActions(whatsapp: (url) async {
            opened.add('$url');
            return true;
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    log = [];
    opened = [];
    rows
      ..clear()
      ..['a'] = _site('Alpha Salon', DateTime(now.year, now.month, now.day, 9))
      ..['b'] = _site('Bravo Salon', DateTime(now.year, now.month, now.day - 1), phone: '+97455500002')
      // Not validated, or has a website after all: neither belongs here.
      ..['c'] = _site('Charlie Salon', DateTime(now.year, now.month, now.day - 2), whatsApp: false, phone: '+97455500003')
      ..['d'] = _site('Delta Salon', DateTime(now.year, now.month, now.day - 3), status: 'available', phone: '+97455500004');
  });

  testWidgets('lists only validated no-website leads, newest first, with no review block', (tester) async {
    await pumpScreen(tester);

    expect(find.text('WhatsApp · no website'), findsOneWidget);
    expect(find.text('Alpha Salon'), findsOneWidget);
    expect(find.text('Bravo Salon'), findsOneWidget);
    expect(find.text('Charlie Salon'), findsNothing);
    expect(find.text('Delta Salon'), findsNothing);
    expect(tester.getTopLeft(find.text('Alpha Salon')).dy, lessThan(tester.getTopLeft(find.text('Bravo Salon')).dy));
    expect(find.textContaining('1-star review'), findsNothing);
    expect(find.textContaining('On WhatsApp'), findsWidgets);
    // The query asked for exactly the validated, confirmed-missing ones.
    expect(log.first, {'hasWhatsApp': true, 'websiteStatus': 'missing'});
  });

  testWidgets('WhatsApp opens the lead\'s chat without marking anything contacted', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'WhatsApp').first);
    await tester.pumpAndSettle();
    expect(opened, ['https://wa.me/97455500001']);
  });

  testWidgets('says so when nothing is validated yet', (tester) async {
    rows.clear();
    await pumpScreen(tester);

    expect(find.text('No validated no-website leads yet'), findsOneWidget);
  });
}
