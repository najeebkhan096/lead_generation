import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/domain/entities/excel_archive.dart';
import 'package:lead_generation_app/domain/entities/lead.dart';
import 'package:lead_generation_app/domain/entities/lead_page.dart';
import 'package:lead_generation_app/domain/repositories/lead_repository.dart';
import 'package:lead_generation_app/presentation/bloc/paged_leads/paged_leads_bloc.dart';
import 'package:lead_generation_app/presentation/bloc/paged_leads/paged_leads_event.dart';
import 'package:lead_generation_app/presentation/bloc/paged_leads/paged_leads_state.dart';
import 'package:lead_generation_app/presentation/pages/excel_archive_page.dart';

/// Only the paged-list methods are implemented; anything else the code under
/// test shouldn't touch fails loudly via [noSuchMethod].
class _FakeRepository implements LeadRepository {
  _FakeRepository({this.leads = const [], this.listFails = false});

  List<Lead> leads;
  final bool listFails;
  final deleted = <String>[];

  // Paged listing.
  final pageCalls = <Map<String, Object?>>[];
  List<LeadCategory> categories = [];

  /// Simulates the server's scan budget: while searching, look at no more
  /// than this many documents per request (a short page with a cursor).
  int? searchSliceSize;

  /// Delay a response by query, to exercise out-of-order responses.
  final Map<String, Duration> delayByQuery = {};

  @override
  Future<LeadPage> getLeadsPage(
    LeadCollection collection, {
    String? cursor,
    String? category,
    String? query,
    int limit = 50,
    bool verifiedOnly = false,
  }) async {
    pageCalls.add({
      'collection': collection,
      'cursor': cursor,
      'category': category,
      'query': query,
      'limit': limit,
      'verifiedOnly': verifiedOnly,
    });
    final delay = delayByQuery[query ?? ''];
    if (delay != null) await Future<void>.delayed(delay);
    if (listFails) throw Exception('Failed to load leads');

    final all = switch (collection) {
      LeadCollection.whatsappLeads => leads,
      LeadCollection.reviewLeads => leads,
    };
    final q = (query ?? '').trim().toLowerCase();
    bool matches(Lead l) {
      if (category != null && l.category != category) return false;
      if (verifiedOnly && !l.hasWhatsApp) return false;
      if (q.isEmpty) return true;
      return l.business.toLowerCase().contains(q);
    }

    var i = int.tryParse(cursor ?? '') ?? 0;
    final slice = q.isNotEmpty ? searchSliceSize : null;
    final out = <Lead>[];
    var scanned = 0;
    while (i < all.length && out.length < limit && (slice == null || scanned < slice)) {
      if (matches(all[i])) out.add(all[i]);
      i++;
      scanned++;
    }
    return LeadPage(
      leads: out,
      nextCursor: i < all.length ? '$i' : null,
      total: cursor == null && q.isEmpty ? all.where(matches).length : null,
    );
  }

  @override
  Future<List<LeadCategory>> getLeadCategories(LeadCollection collection) async => categories;

  @override
  Future<void> deleteLeadIn(LeadCollection collection, String leadId) async => deleted.add(leadId);

  @override
  Future<int> deleteLeadsInCategory(LeadCollection collection, String category) async {
    final n = leads.where((l) => l.category == category).length;
    leads = leads.where((l) => l.category != category).toList();
    return n;
  }

  @override
  Future<List<ExcelArchive>> listExcelArchives() async => const [_archive];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _archive = ExcelArchive(
  id: 'arch1',
  fileName: 'scan.xlsx',
  downloadUrl: 'https://example.test/scan.xlsx',
  categories: ['Cafe'],
  totalLeads: 3,
);

Lead _lead(String dbId, String name, {String category = 'Cafe'}) => Lead(
      id: dbId,
      dbId: dbId,
      business: name,
      category: category,
      location: 'Austin',
      website: 'https://$dbId.example',
      badReview: const BadReview(stars: 1, text: '', date: 'Unknown'),
    );

void main() {
  group('PagedLeadsBloc', () {
    List<Lead> many(int n, {String category = 'Cafe'}) =>
        [for (var i = 0; i < n; i++) _lead('id$i', 'Business $i', category: i.isEven ? category : 'Bakery')];

    PagedLeadsBloc bloc(_FakeRepository repo, {int pageSize = 50}) => PagedLeadsBloc(
          repo,
          LeadCollection.reviewLeads,
          pageSize: pageSize,
          searchDebounce: const Duration(milliseconds: 10),
        );

    test('loads one page at a time and stops at the last page', () async {
      final repo = _FakeRepository(leads: many(120));
      final b = bloc(repo)..add(const PagedLeadsStarted());
      var s = await b.stream.firstWhere((s) => s.status == PagedLeadsStatus.success);

      expect(s.leads, hasLength(50));
      expect(s.total, 120);
      expect(s.hasMore, isTrue);
      expect(repo.pageCalls.single['cursor'], isNull);
      expect(repo.pageCalls.single['limit'], 50);

      b.add(const PagedLeadsLoadMore());
      s = await b.stream.firstWhere((s) => s.leads.length == 100 && !s.loadingMore);
      expect(s.hasMore, isTrue);

      b.add(const PagedLeadsLoadMore());
      s = await b.stream.firstWhere((s) => s.leads.length == 120 && !s.loadingMore);
      expect(s.hasMore, isFalse);
      expect(s.leads.map((l) => l.dbId).toSet(), hasLength(120), reason: 'no duplicates across pages');

      final calls = repo.pageCalls.length;
      b.add(const PagedLeadsLoadMore());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(repo.pageCalls.length, calls, reason: 'nothing left to ask for');
      await b.close();
    });

    test('a burst of keystrokes becomes one search, applied from page one', () async {
      final repo = _FakeRepository(leads: many(200));
      final b = bloc(repo)..add(const PagedLeadsStarted());
      await b.stream.firstWhere((s) => s.status == PagedLeadsStatus.success);
      final before = repo.pageCalls.length;

      for (final q in ['b', 'bu', 'busi', 'business 19']) {
        b.add(PagedLeadsQueryChanged(q));
      }
      // Wait for the *answer*, not just the state that records the query.
      final s = await b.stream.firstWhere(
        (s) =>
            s.query == 'business 19' &&
            s.status == PagedLeadsStatus.success &&
            s.leads.isNotEmpty &&
            s.leads.every((l) => l.business.contains('Business 19')),
      );

      final searches = repo.pageCalls.skip(before).where((c) => c['query'] != null && c['query'] != '').toList();
      expect(searches, hasLength(1), reason: 'debounced into a single request');
      expect(searches.single['query'], 'business 19');
      expect(searches.single['cursor'], isNull);
      expect(s.leads, isNotEmpty);
      await b.close();
    });

    test('a search the server answers in slices keeps going until a page is full', () async {
      // 300 leads; only the last ones match. The fake scans 40 per request,
      // so the first responses are empty with a cursor.
      final rows = [
        for (var i = 0; i < 300; i++) _lead('id$i', i >= 280 ? 'Zebra $i' : 'Other $i'),
      ];
      final repo = _FakeRepository(leads: rows)..searchSliceSize = 40;
      final b = bloc(repo, pageSize: 10)..add(const PagedLeadsStarted());
      await b.stream.firstWhere((s) => s.status == PagedLeadsStatus.success);
      final before = repo.pageCalls.length;

      b.add(const PagedLeadsQueryChanged('zebra'));
      var s = await b.stream.firstWhere(
        (s) =>
            s.query == 'zebra' &&
            s.leads.length == 10 &&
            s.leads.every((l) => l.business.startsWith('Zebra')) &&
            !s.loadingMore,
      );

      // The first page of matches (10) only exists after several empty
      // slices were skipped over.
      expect(s.leads.every((l) => l.business.startsWith('Zebra')), isTrue);
      expect(repo.pageCalls.length - before, greaterThan(3), reason: 'several slices were requested');
      expect(s.hasMore, isTrue);

      b.add(const PagedLeadsLoadMore());
      s = await b.stream.firstWhere((s) => s.leads.length == 20 && !s.loadingMore);
      expect(s.hasMore, isFalse);
      await b.close();
    });

    test('changing the category or a filter restarts from the first page', () async {
      final repo = _FakeRepository(leads: many(120))
        ..categories = const [LeadCategory(name: 'Cafe', count: 60), LeadCategory(name: 'Bakery', count: 60)];
      final b = bloc(repo)..add(const PagedLeadsStarted());
      var s = await b.stream.firstWhere((s) => s.status == PagedLeadsStatus.success && s.categories.isNotEmpty);
      expect(s.categories.map((c) => c.name), ['Cafe', 'Bakery']);

      b.add(const PagedLeadsLoadMore());
      await b.stream.firstWhere((s) => s.leads.length == 100 && !s.loadingMore);

      b.add(const PagedLeadsCategoryChanged('Bakery'));
      // The filter and the reload arrive together: never old rows under a new filter.
      s = await b.stream.firstWhere((s) => s.category == 'Bakery');
      expect(s.status, PagedLeadsStatus.loading);
      expect(s.leads, isEmpty);
      s = await b.stream.firstWhere((s) => s.category == 'Bakery' && s.status == PagedLeadsStatus.success);
      expect(s.total, 60);
      expect(s.leads.every((l) => l.category == 'Bakery'), isTrue);
      expect(repo.pageCalls.last['cursor'], isNull);
      expect(repo.pageCalls.last['category'], 'Bakery');

      b.add(const PagedLeadsCategoryChanged(null));
      s = await b.stream.firstWhere(
        (s) => s.category == null && s.status == PagedLeadsStatus.success && s.total == 120,
      );
      expect(s.leads, hasLength(50));
      await b.close();
    });

    test('a slow answer to an old search never overwrites the newer one', () async {
      final repo = _FakeRepository(leads: [_lead('a', 'Alpha'), _lead('b', 'Beta'), _lead('c', 'Gamma')])
        ..delayByQuery['alpha'] = const Duration(milliseconds: 150);
      final b = bloc(repo)..add(const PagedLeadsStarted());
      await b.stream.firstWhere((s) => s.status == PagedLeadsStatus.success);

      b.add(const PagedLeadsQueryChanged('alpha')); // slow
      await Future<void>.delayed(const Duration(milliseconds: 30));
      b.add(const PagedLeadsQueryChanged('beta')); // fast, issued later
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(b.state.query, 'beta');
      expect(b.state.leads.map((l) => l.business), ['Beta']);
      await b.close();
    });

    test('delete removes the lead and the total follows', () async {
      final repo = _FakeRepository(leads: many(3));
      final b = bloc(repo)..add(const PagedLeadsStarted());
      await b.stream.firstWhere((s) => s.status == PagedLeadsStatus.success);

      b.add(const PagedLeadDeleted('id1'));
      final s = await b.stream.firstWhere((s) => s.leads.length == 2);
      expect(repo.deleted, ['id1']);
      expect(s.total, 2);
      await b.close();
    });

    test('a failing first page surfaces the error; a failing later page keeps the list', () async {
      final failing = bloc(_FakeRepository(listFails: true))..add(const PagedLeadsStarted());
      final f = await failing.stream.firstWhere((s) => s.status == PagedLeadsStatus.failure);
      expect(f.error, 'Failed to load leads');
      await failing.close();

      final repo = _FakeRepository(leads: many(120));
      final b = bloc(repo)..add(const PagedLeadsStarted());
      await b.stream.firstWhere((s) => s.status == PagedLeadsStatus.success);
      repo.leads = const []; // the next request will return nothing useful
      b.add(const PagedLeadsLoadMore());
      await b.stream.firstWhere((s) => !s.loadingMore && s.leads.length >= 50);
      expect(b.state.leads, hasLength(50), reason: 'already-loaded leads are kept');
      await b.close();
    });
  });

  test('LeadPage.fromJson reads the cursor and total; the last page has no cursor', () {
    final page = LeadPage.fromJson({
      'leads': [
        {'dbId': 'a', 'business': 'A'}
      ],
      'nextCursor': 'abc',
      'total': 21208,
    });
    expect(page.leads.single.dbId, 'a');
    expect(page.hasMore, isTrue);
    expect(page.total, 21208);
    expect(LeadPage.fromJson({'leads': []}).hasMore, isFalse);
  });

  test('DashboardOverview.fromJson reads server-computed stats', () {
    final o = DashboardOverview.fromJson({
      'review': {
        'total': 886,
        'whatsAppReady': 40,
        'categories': 9,
        'markets': 31,
        'avgRating': 2.4,
        'addedThisWeek': 12,
        'topCategories': [
          {'name': 'Auto Body Shop USA', 'count': 300}
        ],
      },
      'counts': {'reviewLeads': 886, 'whatsappLeads': 55, 'emailLeads': 5},
      'recent': [
        {'dbId': 'x', 'business': 'X'}
      ],
    });
    expect(o.total, 886);
    expect(o.topCategories.single.count, 300);
    expect(o.recent.single.business, 'X');
    expect(o.isEmpty, isFalse);
  });

  group('ExcelArchivePage', () {
    // The archive row carries the WhatsApp validate button next to
    // view/download/delete (and Resume on partial scans) — it has to
    // reflow on a phone-width window instead of overflowing.
    for (final width in [380.0, 560.0, 820.0]) {
      testWidgets('offers Validate WhatsApp and fits at ${width.toInt()}px', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          RepositoryProvider<LeadRepository>.value(
            value: _FakeRepository(),
            child: const MaterialApp(home: ExcelArchivePage()),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Validate WhatsApp'), findsOneWidget);
      });
    }
  });

}
