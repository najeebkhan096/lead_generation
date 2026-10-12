import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/domain/entities/email_validation_snapshot.dart';
import 'package:lead_generation_app/domain/entities/excel_archive.dart';
import 'package:lead_generation_app/domain/entities/lead.dart';
import 'package:lead_generation_app/domain/entities/validation_start.dart';
import 'package:lead_generation_app/domain/entities/whatsapp_web_status.dart';
import 'package:lead_generation_app/domain/repositories/lead_repository.dart';
import 'package:lead_generation_app/domain/entities/lead_page.dart';
import 'package:lead_generation_app/presentation/bloc/paged_leads/paged_leads_bloc.dart';
import 'package:lead_generation_app/presentation/bloc/paged_leads/paged_leads_event.dart';
import 'package:lead_generation_app/presentation/bloc/paged_leads/paged_leads_state.dart';
import 'package:lead_generation_app/presentation/pages/email_lead_details_page.dart';
import 'package:lead_generation_app/presentation/pages/email_leads_page.dart';
import 'package:lead_generation_app/presentation/pages/email_validator_page.dart';
import 'package:lead_generation_app/presentation/pages/excel_archive_page.dart';
import 'package:lead_generation_app/presentation/pages/website_leads_page.dart';
import 'package:lead_generation_app/presentation/widgets/saved_business_card.dart';
import 'package:lead_generation_app/presentation/widgets/lead_validation_bar.dart';
import 'package:lead_generation_app/presentation/widgets/email_lead_card.dart';

/// Only the email-related methods are implemented; anything else the code
/// under test shouldn't touch fails loudly via [noSuchMethod].
class _FakeRepository implements LeadRepository {
  _FakeRepository({
    this.leads = const [],
    this.archiveLeads = const [],
    this.snapshot,
    this.listFails = false,
  });

  List<Lead> leads;
  final bool listFails;
  final deleted = <String>[];

  // Website-lead validator flow.
  List<Lead> websiteLeads = [];
  List<String>? validatedWebsiteLeadIds;
  String? validatedCollection;
  List<String>? whatsAppValidatedIds;
  WhatsAppWebStatus whatsAppStatus = const WhatsAppWebStatus(
    status: WhatsAppWebConnectionStatus.ready,
    safety: WhatsAppSafetyStatus(dailyCap: 100, remainingToday: 100),
  );
  WhatsAppValidationSnapshot whatsAppSnapshot =
      const WhatsAppValidationSnapshot(active: false, status: 'idle');
  List<Lead> whatsAppLeads = [];

  // Archive validator flow.
  final List<Lead> archiveLeads;
  EmailValidationSnapshot? snapshot;
  List<Map<String, dynamic>>? validated;
  List<Map<String, dynamic>>? uploadedSheets;
  String? uploadedSourceArchiveId;

  // Paged listing.
  List<Lead> reviewLeads = [];
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
    bool emailOnly = false,
    String? sourceType,
  }) async {
    pageCalls.add({
      'collection': collection,
      'cursor': cursor,
      'category': category,
      'query': query,
      'limit': limit,
      'verifiedOnly': verifiedOnly,
      'emailOnly': emailOnly,
      'sourceType': sourceType,
    });
    final delay = delayByQuery[query ?? ''];
    if (delay != null) await Future<void>.delayed(delay);
    if (listFails) throw Exception('Failed to load leads');

    final all = switch (collection) {
      LeadCollection.emailLeads => leads,
      LeadCollection.websiteLeads => websiteLeads,
      LeadCollection.whatsappLeads => whatsAppLeads,
      LeadCollection.reviewLeads => reviewLeads,
    };
    final q = (query ?? '').trim().toLowerCase();
    bool matches(Lead l) {
      if (category != null && l.category != category) return false;
      if (emailOnly && (l.email == null || l.email!.isEmpty)) return false;
      if (verifiedOnly && !l.hasWhatsApp) return false;
      if (sourceType != null && l.sourceType != sourceType) return false;
      if (q.isEmpty) return true;
      return l.business.toLowerCase().contains(q) || (l.email ?? '').toLowerCase().contains(q);
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
  Future<void> deleteEmailLead(String leadId) async => deleted.add(leadId);

  @override
  Future<ValidationStart> validateSavedLeadEmails(String collection, List<String> ids, {bool recheck = false}) async {
    validatedCollection = collection;
    validatedWebsiteLeadIds = ids;
    return const ValidationStart(total: 1);
  }

  @override
  Future<ValidationStart> validateSavedLeadWhatsApp(String collection, List<String> ids, {bool recheck = false}) async {
    validatedCollection = collection;
    whatsAppValidatedIds = ids;
    return const ValidationStart(total: 1);
  }

  @override
  Future<WhatsAppWebStatus> getWhatsAppWebStatus() async => whatsAppStatus;

  @override
  Future<WhatsAppValidationSnapshot> getWhatsAppValidationStatus() async => whatsAppSnapshot;

  @override
  Future<void> cancelWhatsAppValidation() async {}

  @override
  Future<void> deleteWhatsAppLead(String leadId) async => deleted.add(leadId);

  @override
  Future<List<Lead>> getExcelArchiveLeads(String id) async => archiveLeads;

  @override
  Future<List<ExcelArchive>> listExcelArchives() async => [_archive];

  @override
  Future<ValidationStart> validateEmailLeads(List<Map<String, dynamic>> leads, {bool recheck = false}) async {
    validated = leads;
    return const ValidationStart(total: 1);
  }

  @override
  Future<ValidationStart> validateExternalLeads(List<Map<String, dynamic>> leads, {bool recheck = false}) async {
    validated = leads;
    return const ValidationStart(total: 1);
  }

  @override
  Future<EmailValidationSnapshot> getEmailValidationStatus() async =>
      snapshot ?? const EmailValidationSnapshot(active: false, status: 'idle');

  @override
  Future<void> cancelEmailValidation() async {}

  @override
  Future<ExcelArchive> uploadEmailVerifiedArchive({
    required List<Map<String, dynamic>> sheets,
    String? sourceArchiveId,
    String? sourceFileName,
    List<String>? countries,
  }) async {
    uploadedSheets = sheets;
    uploadedSourceArchiveId = sourceArchiveId;
    return ExcelArchive(
      id: 'up1',
      fileName: 'email-verified.xlsx',
      downloadUrl: 'https://example.test/x.xlsx',
      totalLeads: sheets.fold<int>(0, (n, s) => n + (s['leads'] as List).length),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Lead _lead(String dbId, String name, {String category = 'Cafe', String? email}) => Lead(
      id: dbId,
      dbId: dbId,
      business: name,
      category: category,
      location: 'Austin',
      website: 'https://$dbId.example',
      email: email ?? 'info@$dbId.example',
      emails: [email ?? 'info@$dbId.example'],
      emailSource: 'contact_page',
      badReview: const BadReview(stars: 1, text: '', date: 'Unknown'),
    );

/// An archive lead as `getExcelArchiveLeads` returns it — never saved, so
/// no dbId and no email yet.
Lead _archiveLead(String id, String name, {String? website, String location = 'Austin, TX'}) => Lead(
      id: id,
      business: name,
      category: 'Cafe',
      location: location,
      website: website,
      phone: '+1 512 555 0100',
      badReview: const BadReview(stars: 1, text: '', date: 'Unknown'),
    );

const _archive = ExcelArchive(
  id: 'arch1',
  fileName: 'scan.xlsx',
  downloadUrl: 'https://example.test/scan.xlsx',
  categories: ['Cafe'],
  totalLeads: 3,
);

void main() {
  test('Lead.fromJson reads email-lead fields and defaults them for other lead types', () {
    final emailLead = Lead.fromJson({
      'dbId': 'abc',
      'business': 'ABC Cafe',
      'email': 'info@abc.example',
      'emails': ['info@abc.example', 'sales@abc.example'],
      'emailSource': 'contact_page',
    });
    expect(emailLead.emails, ['info@abc.example', 'sales@abc.example']);
    expect(emailLead.emailSource, 'contact_page');

    final reviewLead = Lead.fromJson({'dbId': 'x', 'business': 'X'});
    expect(reviewLead.emails, isEmpty);
    expect(reviewLead.emailSource, isNull);
  });

  test('Lead.copyWith can attach a verified email without losing the rest', () {
    final verified = _archiveLead('a', 'A', website: 'https://a.example')
        .copyWith(email: 'info@a.example', emails: ['info@a.example'], emailSource: 'mailto');
    expect(verified.email, 'info@a.example');
    expect(verified.emailSource, 'mailto');
    expect(verified.website, 'https://a.example');
    expect(verified.phone, '+1 512 555 0100');
  });

  test('EmailValidationSnapshot.fromJson reads counters and per-business results', () {
    final snap = EmailValidationSnapshot.fromJson({
      'active': false,
      'status': 'done',
      'total': 3,
      'checked': 3,
      'validCount': 1,
      'invalidCount': 1,
      'noEmailCount': 1,
      'results': {
        'a': {'valid': true, 'email': 'info@a.example', 'emails': ['info@a.example'], 'source': 'mailto'},
        'b': {'valid': false, 'email': 'x@b.example', 'result': 'invalid', 'reason': 'no_mx'},
      },
    });
    expect(snap.hasJob, isTrue);
    expect(snap.results['a']!.valid, isTrue);
    expect(snap.results['a']!.source, 'mailto');
    expect(snap.results['b']!.reason, 'no_mx');
    expect(const EmailValidationSnapshot(active: false, status: 'idle').hasJob, isFalse);
  });

  group('PagedLeadsBloc', () {
    List<Lead> many(int n, {String category = 'Cafe'}) =>
        [for (var i = 0; i < n; i++) _lead('id$i', 'Business $i', category: i.isEven ? category : 'Bakery')];

    PagedLeadsBloc bloc(_FakeRepository repo, {int pageSize = 50}) => PagedLeadsBloc(
          repo,
          LeadCollection.emailLeads,
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
      'counts': {'reviewLeads': 886, 'websiteLeads': 21208, 'whatsappLeads': 55, 'emailLeads': 5},
      'recent': [
        {'dbId': 'x', 'business': 'X'}
      ],
    });
    expect(o.total, 886);
    expect(o.websiteLeads, 21208);
    expect(o.topCategories.single.count, 300);
    expect(o.recent.single.business, 'X');
    expect(o.isEmpty, isFalse);
  });

  testWidgets('EmailLeadCard leads with the email and shows where it was found', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            height: 262,
            child: EmailLeadCard(
              lead: _lead('a', 'Alpha Cafe', email: 'hello@alpha.example'),
              onTap: () => tapped = true,
              onDelete: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Alpha Cafe'), findsOneWidget);
    expect(find.text('hello@alpha.example'), findsOneWidget);
    expect(find.text('Contact page'), findsOneWidget);
    expect(find.text('a.example'), findsOneWidget); // scheme stripped

    await tester.tap(find.text('Alpha Cafe'));
    expect(tapped, isTrue);
  });

  testWidgets('EmailLeadCard fits its grid cell with every field populated', (tester) async {
    const lead = Lead(
      id: 'long',
      dbId: 'long',
      business: 'The Extraordinarily Long Named Neighbourhood Bakery & Coffee House',
      category: 'Bakery and Pastry Shops (United States)',
      location: 'Austin',
      address: '1234 Some Very Long Boulevard Name, Suite 500, Austin, TX 78701, United States',
      phone: '+1 512 555 0100',
      website: 'https://www.the-extraordinarily-long-named-bakery-and-coffee-house.example/menu/',
      email: 'customer.relations.and.catering@the-extraordinarily-long-named-bakery.example',
      emails: [
        'customer.relations.and.catering@the-extraordinarily-long-named-bakery.example',
        'b@x.example',
        'c@x.example',
      ],
      emailSource: 'about_page',
      badReview: BadReview(stars: 1, text: '', date: 'Unknown'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 262,
              child: EmailLeadCard(lead: lead, onTap: () {}, onDelete: () {}),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('+2 more'), findsOneWidget);
  });

  group('EmailLeadsPage', () {
    Future<void> pumpPage(WidgetTester tester, _FakeRepository repo, {Size size = const Size(1280, 900)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepositoryProvider<LeadRepository>.value(
          value: repo,
          child: const MaterialApp(home: EmailLeadsPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders the populated list and copy-all action', (tester) async {
      final repo = _FakeRepository(leads: [
        for (var i = 0; i < 7; i++) _lead('id$i', 'Business $i', category: i.isEven ? 'Cafe' : 'Bakery'),
      ]);
      await pumpPage(tester, repo);

      expect(tester.takeException(), isNull);
      expect(find.text('Email leads'), findsOneWidget);
      expect(find.text('7 businesses'), findsOneWidget);
      expect(find.text('Copy 7 emails'), findsOneWidget);
      expect(find.text('Business 0'), findsOneWidget);
      expect(find.text('info@id0.example'), findsOneWidget);
    });

    testWidgets('only builds the cards near the viewport and loads more on scroll', (tester) async {
      final repo = _FakeRepository(leads: [
        for (var i = 0; i < 400; i++) _lead('id$i', 'Business $i'),
      ]);
      await pumpPage(tester, repo);

      // One page requested, 400 in the collection.
      expect(repo.pageCalls, hasLength(1));
      expect(repo.pageCalls.single['limit'], 50);
      expect(find.text('400 businesses'), findsOneWidget);

      // Lazily rendered: far fewer card widgets exist than leads loaded.
      final built = find.byType(EmailLeadCard).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(30), reason: 'a sliver grid builds only what is on screen');

      // Scrolling toward the end requests the next page, with the cursor.
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -2500));
        await tester.pumpAndSettle();
      }
      expect(repo.pageCalls.length, greaterThan(1));
      expect(repo.pageCalls[1]['cursor'], '50');
      expect(repo.pageCalls.every((c) => c['limit'] == 50), isTrue);
    });

    testWidgets('a window taller than the first page keeps loading until it is full', (tester) async {
      final repo = _FakeRepository(leads: [
        for (var i = 0; i < 400; i++) _lead('id$i', 'Business $i'),
      ]);
      tester.view.physicalSize = const Size(1280, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepositoryProvider<LeadRepository>.value(value: repo, child: const MaterialApp(home: EmailLeadsPage())),
      );
      await tester.pumpAndSettle();

      expect(repo.pageCalls.length, greaterThan(1), reason: 'did not stop at an unscrollable first page');
    });

    testWidgets('typing in search asks the server and shows what it returns', (tester) async {
      final repo = _FakeRepository(leads: [
        _lead('a', 'Alpha Cafe'),
        _lead('b', 'Beta Bakery'),
        _lead('c', 'Gamma Garage'),
      ]);
      await pumpPage(tester, repo);

      await tester.enterText(find.byType(TextField), 'bakery');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(repo.pageCalls.last['query'], 'bakery');
      expect(find.text('Beta Bakery'), findsOneWidget);
      expect(find.text('Alpha Cafe'), findsNothing);
    });

    testWidgets('lays out on a narrow window without overflowing', (tester) async {
      final repo = _FakeRepository(leads: [_lead('a', 'Alpha Cafe'), _lead('b', 'Beta Bakery')]);
      await pumpPage(tester, repo, size: const Size(420, 900));
      expect(tester.takeException(), isNull);
      expect(find.text('Alpha Cafe'), findsOneWidget);
    });

    testWidgets('empty state points at the Excel Archive validator', (tester) async {
      await pumpPage(tester, _FakeRepository());
      expect(find.text('No email leads yet'), findsOneWidget);
      expect(find.textContaining('tap Email'), findsOneWidget);
    });

    testWidgets('shows the error state with retry when loading fails', (tester) async {
      await pumpPage(tester, _FakeRepository(listFails: true));
      expect(find.text('Could not load email leads'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  testWidgets('EmailLeadDetailsPage lists every email found, primary first, at mobile width', (tester) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const lead = Lead(
      id: 'a',
      dbId: 'a',
      business: 'Alpha Cafe',
      category: 'Cafe',
      location: 'Austin',
      address: '1234 Some Very Long Boulevard Name, Suite 500, Austin, TX 78701',
      website: 'https://alpha.example',
      email: 'customer.relations.and.catering@alpha-cafe-and-bakery.example',
      emails: [
        'customer.relations.and.catering@alpha-cafe-and-bakery.example',
        'sales@alpha-cafe-and-bakery.example',
      ],
      emailSource: 'contact_page',
      badReview: BadReview(stars: 1, text: '', date: 'Unknown'),
    );
    await tester.pumpWidget(
      RepositoryProvider<LeadRepository>.value(
        value: _FakeRepository(leads: const [lead]),
        child: const MaterialApp(home: EmailLeadDetailsPage(lead: lead)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Emails found'), findsOneWidget);
    expect(find.text('Found on: Contact page'), findsOneWidget);
    expect(find.text('sales@alpha-cafe-and-bakery.example'), findsOneWidget);
  });

  group('ExcelArchiveEmailValidatorPage', () {
    Future<void> pumpValidator(WidgetTester tester, _FakeRepository repo) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepositoryProvider<LeadRepository>.value(
          value: repo,
          child: const MaterialApp(home: ExcelArchiveEmailValidatorPage(archive: _archive)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sends only businesses with a website, then uploads the verified ones', (tester) async {
      final repo = _FakeRepository(
        archiveLeads: [
          _archiveLead('a', 'Alpha Cafe', website: 'https://alpha.example'),
          _archiveLead('b', 'Beta Cafe', website: 'https://beta.example'),
          _archiveLead('c', 'No Site Cafe'), // no website — can't be checked
        ],
        snapshot: const EmailValidationSnapshot(
          active: false,
          status: 'done',
          total: 2,
          checked: 2,
          validCount: 1,
          noEmailCount: 1,
          results: {
            'a': EmailValidationResult(
              valid: true,
              email: 'info@alpha.example',
              emails: ['info@alpha.example', 'sales@alpha.example'],
              source: 'contact_page',
              result: 'valid',
            ),
            'b': EmailValidationResult(valid: false, reason: 'no_email_found'),
          },
        ),
      );
      await pumpValidator(tester, repo);

      // The sole category is auto-selected, so the validate button is live.
      expect(find.text('Validate emails for "Cafe"'), findsOneWidget);
      expect(find.textContaining('2 businesses with a website'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Validate'));
      await tester.pumpAndSettle();
      expect(find.text('Validate emails?'), findsOneWidget);
      expect(find.textContaining('1 without a website will be skipped'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Validate'));
      await tester.pump(); // validateEmailLeads
      await tester.pump(); // first poll → job already done in the fake
      await tester.pumpAndSettle();

      expect(repo.validated!.map((l) => l['id']), ['a', 'b']);
      expect(repo.validated!.first['website'], 'https://alpha.example');

      // Only the verified business is uploaded, with its email attached.
      expect(repo.uploadedSourceArchiveId, 'arch1');
      final sheet = repo.uploadedSheets!.single;
      expect(sheet['name'], 'Cafe');
      final leads = (sheet['leads'] as List).cast<Map<String, dynamic>>();
      expect(leads, hasLength(1));
      expect(leads.single['business'], 'Alpha Cafe');
      expect(leads.single['email'], 'info@alpha.example');
      expect(leads.single['emails'], ['info@alpha.example', 'sales@alpha.example']);
      expect(leads.single['emailSource'], 'contact_page');

      expect(find.text('Email Verified (1)'), findsOneWidget);
      expect(find.text('1 no email on site'), findsOneWidget);
    });

    testWidgets('tells the user when nothing in the scope has a website', (tester) async {
      final repo = _FakeRepository(archiveLeads: [_archiveLead('a', 'No Site Cafe')]);
      await pumpValidator(tester, repo);

      await tester.tap(find.widgetWithText(FilledButton, 'Validate'));
      await tester.pump();

      expect(find.text('None of these businesses have a website to check.'), findsOneWidget);
      expect(repo.validated, isNull);
    });
  });

  group('ExcelArchivePage', () {
    // The archive row carries WhatsApp + email validate buttons next to
    // view/download/delete (and Resume on partial scans) — it has to
    // reflow on a phone-width window instead of overflowing.
    for (final width in [380.0, 560.0, 820.0]) {
      testWidgets('offers Validate emails and fits at ${width.toInt()}px', (tester) async {
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
        expect(find.byTooltip('Validate emails'), findsOneWidget);
        expect(find.byTooltip('Validate WhatsApp'), findsOneWidget);
      });
    }
  });

  group('Lead validation bar (No-website leads)', () {
    Lead websiteLead(String id, String name, {String? email, String category = 'Cafe'}) => Lead(
          id: id,
          dbId: id,
          business: name,
          category: category,
          location: 'TX',
          phone: '+1 512 555 0100',
          address: '12 Main St, Austin, TX',
          email: email,
          badReview: const BadReview(stars: 1, text: '', date: 'Unknown'),
        );

    Future<void> pumpPage(WidgetTester tester, _FakeRepository repo) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepositoryProvider<LeadRepository>.value(
          value: repo,
          child: const MaterialApp(home: WebsiteLeadsPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('validates only the leads without an email, then reloads the list', (tester) async {
      final repo = _FakeRepository()
        ..websiteLeads = [
          websiteLead('a', 'Alpha Cafe'),
          websiteLead('b', 'Beta Cafe', email: 'hi@beta.example'),
          websiteLead('c', 'Gamma Cafe'),
        ]
        ..snapshot = const EmailValidationSnapshot(
          active: false,
          status: 'done',
          total: 2,
          checked: 2,
          validCount: 1,
          noEmailCount: 1,
        );
      await pumpPage(tester, repo);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Email: 2 to check'), findsOneWidget);
      expect(find.text('hi@beta.example'), findsOneWidget); // shown on the card
      final loadsBefore = repo.pageCalls.length;

      await tester.tap(find.widgetWithText(FilledButton, 'Email'));
      await tester.pumpAndSettle();
      expect(find.text('Validate emails?'), findsOneWidget);
      // None of these have a website, so both are looked up on the web.
      expect(find.textContaining('0 by reading their website, 2 by searching the web'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Validate'));
      await tester.pump(); // start request
      await tester.pump(); // first poll — the fake job is already done
      await tester.pumpAndSettle();

      expect(repo.validatedCollection, 'websiteLeads');
      expect(repo.validatedWebsiteLeadIds, ['a', 'c']);
      expect(repo.pageCalls.length, greaterThan(loadsBefore), reason: 'list reloads when the run ends');
      expect(find.text('1 verified'), findsOneWidget);
      expect(find.text('1 no email on site'), findsOneWidget);
    });

    testWidgets('"Has email" asks the server for only leads that have one', (tester) async {
      final repo = _FakeRepository()
        ..websiteLeads = [
          websiteLead('a', 'Alpha Cafe'),
          websiteLead('b', 'Beta Cafe', email: 'hi@beta.example'),
        ];
      await pumpPage(tester, repo);
      expect(find.text('Alpha Cafe'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Has email'));
      await tester.pumpAndSettle();

      expect(repo.pageCalls.last['emailOnly'], isTrue);
      expect(repo.pageCalls.last['cursor'], isNull);
      expect(find.text('Alpha Cafe'), findsNothing);
      expect(find.text('Beta Cafe'), findsOneWidget);
    });

    testWidgets('disables Email when every lead already has one', (tester) async {
      final repo = _FakeRepository()
        ..websiteLeads = [websiteLead('b', 'Beta Cafe', email: 'hi@beta.example')];
      await pumpPage(tester, repo);

      expect(find.textContaining('Email: 0 to check'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Email'));
      expect(button.onPressed, isNull);
    });

    testWidgets('WhatsApp validates only never-checked leads with a phone and reports the outcome',
        (tester) async {
      final repo = _FakeRepository()
        ..websiteLeads = [
          websiteLead('a', 'Alpha Cafe'),
          websiteLead('b', 'Beta Cafe'),
          Lead(
            id: 'c',
            dbId: 'c',
            business: 'Gamma Cafe',
            category: 'Cafe',
            location: 'TX',
            phone: '+1 512 555 0101',
            whatsAppCheckedAt: DateTime(2026, 10, 1), // already checked
            badReview: const BadReview(stars: 1, text: '', date: 'Unknown'),
          ),
        ]
        ..whatsAppSnapshot = const WhatsAppValidationSnapshot(
          active: false,
          status: 'done',
          total: 2,
          checked: 2,
          validCount: 1,
          invalidCount: 1,
        );
      await pumpPage(tester, repo);

      await tester.tap(find.widgetWithText(OutlinedButton, 'WhatsApp'));
      await tester.pumpAndSettle();
      expect(find.text('Validate WhatsApp numbers?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Validate'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(repo.validatedCollection, 'websiteLeads');
      expect(repo.whatsAppValidatedIds, ['a', 'b']);
      expect(find.text('1 on WhatsApp'), findsOneWidget);
      expect(find.text('1 not on WhatsApp'), findsOneWidget);
    });

    testWidgets('WhatsApp asks to connect first when no session is linked', (tester) async {
      final repo = _FakeRepository()
        ..websiteLeads = [websiteLead('a', 'Alpha Cafe')]
        ..whatsAppStatus = const WhatsAppWebStatus(status: WhatsAppWebConnectionStatus.disconnected);
      await pumpPage(tester, repo);

      await tester.tap(find.widgetWithText(OutlinedButton, 'WhatsApp'));
      await tester.pumpAndSettle();

      expect(find.text('WhatsApp Web not connected'), findsOneWidget);
      expect(repo.whatsAppValidatedIds, isNull);
    });

    testWidgets('the validation bar reflows on a phone-width window', (tester) async {
      tester.view.physicalSize = const Size(340, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(28),
              child: LeadValidationBar(
                collection: 'websiteLeads',
                leads: [websiteLead('a', 'Alpha'), websiteLead('b', 'Beta', email: 'b@b.example')],
                onFinished: () {},
                filters: [FilterChip(label: const Text('Has email (1)'), selected: false, onSelected: (_) {})],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
    });

    testWidgets('a lead card with every field, including email, fits the 248px grid cell', (tester) async {
      final lead = Lead(
        id: 'x',
        dbId: 'x',
        business: 'The Extraordinarily Long Named Neighbourhood Bakery & Coffee House',
        category: 'Bakery and Pastry Shops (United States)',
        location: 'TX',
        phone: '+1 512 555 0100',
        address: '1234 Some Very Long Boulevard Name, Suite 500, Austin, TX 78701, United States',
        email: 'customer.relations.and.catering@the-extraordinarily-long-named-bakery.example',
        rating: 4.6,
        hasWhatsApp: true,
        badReview: const BadReview(stars: 1, text: '', date: 'Unknown'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 300, height: 248, child: SavedBusinessCard(lead: lead, onTap: () {})),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
