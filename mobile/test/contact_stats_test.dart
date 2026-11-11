import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/models/client_record.dart';
import 'package:lead_mobile/models/sale.dart';
import 'package:lead_mobile/models/sales_user.dart';
import 'package:lead_mobile/pages/admin_salesman_detail_page.dart';
import 'package:lead_mobile/services/admin_data.dart';
import 'package:lead_mobile/services/admin_repository.dart';
import 'package:lead_mobile/services/contact_stats_repository.dart';
import 'package:lead_mobile/theme/app_theme.dart';

import 'support/memory_firestore.dart';

// A fixed "now": 13:00 on 2026-11-11 in Qatar (UTC+3).
final _now = DateTime.utc(2026, 11, 11, 10);
Timestamp _at(DateTime utc) => Timestamp.fromDate(utc);
DateTime _hoursAgo(int h) => _now.subtract(Duration(hours: h));
DateTime _daysAgo(int d, {int hour = 10}) => DateTime.utc(2026, 11, 11 - d, hour);

Map<String, dynamic> _review(String business, String by, DateTime when, {String status = 'contacted', String sourceType = 'review'}) => {
      'business': business, 'category': 'Cafe USA', 'location': 'TX', 'sourceType': sourceType,
      'status': status, 'contactedBy': by, 'contactedAt': _at(when),
    };

Map<String, dynamic> _site(String business, String by, DateTime when) => {
      'business': business, 'category': 'Salon USA', 'location': 'FL', 'websiteStatus': 'missing',
      'hasWhatsApp': true, 'status': 'contacted', 'contactedBy': by, 'contactedAt': _at(when),
    };

MemoryStore _store() {
  final s = MemoryStore();
  s.col('whatsappLeads')
    ..['r1'] = _review('Review Today', 'ali', _hoursAgo(2)) // today
    ..['r2'] = _review('Review Yesterday', 'ali', _daysAgo(1)) // in the last 7
    ..['r3'] = _review('Review Old', 'ali', _daysAgo(20)) // total only
    ..['r4'] = _review('Not Ali', 'bo', _hoursAgo(1))
    ..['r5'] = _review('Side Type', 'ali', _hoursAgo(3), sourceType: 'website') // not a 1-star lead
    ..['r6'] = _review('Deal', 'ali', _daysAgo(3), status: 'dealDone');
  s.col('websiteLeads')
    ..['w1'] = _site('Site Today', 'ali', _hoursAgo(1))
    ..['w2'] = _site('Site Week', 'ali', _daysAgo(5))
    ..['w3'] = _site('Site Old', 'ali', _daysAgo(40))
    ..['w4'] = _site('Not Ali Site', 'bo', _hoursAgo(1))
    // New: never contacted.
    ..['w5'] = {'business': 'Fresh', 'websiteStatus': 'missing', 'hasWhatsApp': true};
  return s;
}

class _FakeAdminRepository extends AdminRepository {
  @override
  Future<List<SalesUser>> listUsers() async => const [
        SalesUser(id: 'ali', name: 'Ali Khan', email: 'ali@x.com', approved: true, dailyLeadLimit: 3),
        SalesUser(id: 'boss', name: 'The Boss', email: 'boss@x.com', approved: true, role: 'admin'),
      ];

  @override
  Future<List<Sale>> listSales() async => const [];

  @override
  Future<List<ClientRecord>> listClients() async => const [];
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  group('ContactStatsRepository', () {
    test('counts today, the last 7 days and the total, per kind and together', () async {
      final repo = ContactStatsRepository(collectionQuery: _store().query, clock: () => _now);
      final stats = await repo.load('ali');

      // 1-star: today 1 · last 7 = today + yesterday + the deal 3 days ago · total 4.
      expect((stats.review.today, stats.review.last7, stats.review.total), (1, 3, 4));
      // No website: today 1 · last 7 = + the one 5 days ago · total 3.
      expect((stats.website.today, stats.website.last7, stats.website.total), (1, 2, 3));
      // The daily limit counts both kinds, so the headline numbers do too.
      expect((stats.today, stats.last7, stats.total), (2, 5, 7));
    });

    test('only this salesman\'s leads, and only 1-star leads of the review kind', () async {
      final stats = await ContactStatsRepository(collectionQuery: _store().query, clock: () => _now).load('bo');
      expect((stats.review.total, stats.website.total), (1, 1));
      final nobody = await ContactStatsRepository(collectionQuery: _store().query, clock: () => _now).load('nobody');
      expect(nobody.total, 0);
      expect(nobody.recent, isEmpty);
    });

    test('the day turns over at midnight in Qatar, not UTC', () async {
      final store = MemoryStore();
      // 20:30 UTC on the 10th is 23:30 Qatar on the 10th; 21:30 UTC is 00:30 Qatar on the 11th.
      store.col('websiteLeads')
        ..['late10'] = _site('Late on the 10th', 'ali', DateTime.utc(2026, 11, 10, 20, 30))
        ..['early11'] = _site('Early on the 11th', 'ali', DateTime.utc(2026, 11, 10, 21, 30));
      final stats = await ContactStatsRepository(collectionQuery: store.query, clock: () => _now).load('ali');
      expect(stats.website.today, 1, reason: 'only the one after Qatar midnight is today');
      expect(stats.website.total, 2);
    });

    test('recent contacts of both kinds, newest first, and capped', () async {
      final stats = await ContactStatsRepository(collectionQuery: _store().query, clock: () => _now).load('ali');
      expect(stats.recent.take(3).map((i) => i.business), ['Site Today', 'Review Today', 'Review Yesterday']);
      expect(stats.recent.first.business, 'Site Today');
      expect(stats.recent.first.kind, ContactKind.website);
      final times = stats.recent.map((i) => i.contactedAt!).toList();
      expect([...times]..sort((a, b) => b.compareTo(a)), times, reason: 'newest first across both kinds');
      expect(stats.recent.where((i) => i.status == 'dealDone'), hasLength(1));

      final many = MemoryStore();
      for (var i = 0; i < 40; i++) {
        many.col('websiteLeads')['w$i'] = _site('Site $i', 'ali', _hoursAgo(i + 1));
        many.col('whatsappLeads')['r$i'] = _review('Review $i', 'ali', _hoursAgo(i + 1));
      }
      final capped = await ContactStatsRepository(collectionQuery: many.query, clock: () => _now).load('ali');
      expect(capped.recent, hasLength(ContactStatsRepository.recentShown));
      expect(capped.total, 80, reason: 'counted by aggregation, not by the capped list');
    });
  });

  group('the salesman page in the admin console', () {
    Future<void> pump(WidgetTester tester, String userId, ContactStatsRepository repo) async {
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final data = AdminData(repository: _FakeAdminRepository());
      await data.load();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: AdminScope(data: data, child: AdminSalesmanDetailPage(userId: userId, contacts: repo)),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('shows today against the limit, the 7-day and total counts, split by kind', (tester) async {
      await pump(tester, 'ali', ContactStatsRepository(collectionQuery: _store().query, clock: () => _now));

      expect(find.text('Contacts'), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget); // today, both kinds, against the limit of 3
      expect(find.text('1-star 1 · No website 1'), findsOneWidget);
      expect(find.text('5'), findsOneWidget); // last 7 days
      expect(find.text('1-star 3 · No website 2'), findsOneWidget);
      expect(find.text('7'), findsOneWidget); // total
      expect(find.text('1-star 4 · No website 3'), findsOneWidget);
    });

    testWidgets('lists the latest contacts with their kind', (tester) async {
      await pump(tester, 'ali', ContactStatsRepository(collectionQuery: _store().query, clock: () => _now));
      expect(find.text('Recent contacts'), findsOneWidget);
      expect(find.text('Site Today'), findsOneWidget);
      expect(find.text('Review Today'), findsOneWidget);
      expect(find.text('No website'), findsWidgets);
      expect(find.text('1-star · deal'), findsOneWidget); // the closed deal
      expect(find.text('Not Ali'), findsNothing);
    });

    testWidgets('an admin account has no contacts section', (tester) async {
      await pump(tester, 'boss', ContactStatsRepository(collectionQuery: _store().query, clock: () => _now));
      expect(find.text('Contacts'), findsNothing);
    });

    testWidgets('a failed read says so, and Retry loads it', (tester) async {
      var fail = true;
      final repo = _FlakyStats(() => fail);
      await pump(tester, 'ali', repo);
      expect(find.textContaining('Could not load the contacts'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Could not load the contacts'), findsNothing);
      expect(find.text('0 of 3'), findsOneWidget);
    });
  });
}

class _FlakyStats extends ContactStatsRepository {
  _FlakyStats(this.shouldFail) : super(collectionQuery: MemoryStore().query, clock: () => _now);

  final bool Function() shouldFail;

  @override
  Future<ContactStats> load(String uid) async {
    if (shouldFail()) throw Exception('offline');
    return super.load(uid);
  }
}
