import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/domain/entities/email_validation_snapshot.dart';
import 'package:lead_generation_app/domain/entities/excel_archive.dart';
import 'package:lead_generation_app/domain/entities/lead.dart';
import 'package:lead_generation_app/domain/repositories/lead_repository.dart';
import 'package:lead_generation_app/presentation/bloc/email_leads/email_leads_bloc.dart';
import 'package:lead_generation_app/presentation/bloc/email_leads/email_leads_event.dart';
import 'package:lead_generation_app/presentation/bloc/email_leads/email_leads_state.dart';
import 'package:lead_generation_app/presentation/pages/email_lead_details_page.dart';
import 'package:lead_generation_app/presentation/pages/email_leads_page.dart';
import 'package:lead_generation_app/presentation/pages/email_validator_page.dart';
import 'package:lead_generation_app/presentation/pages/excel_archive_page.dart';
import 'package:lead_generation_app/presentation/pages/website_leads_page.dart';
import 'package:lead_generation_app/presentation/widgets/saved_business_card.dart';
import 'package:lead_generation_app/presentation/widgets/website_lead_email_validator.dart';
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

  final List<Lead> leads;
  final bool listFails;
  final deleted = <String>[];

  // Website-lead validator flow.
  List<Lead> websiteLeads = [];
  int websiteLeadLoads = 0;
  List<String>? validatedWebsiteLeadIds;

  // Archive validator flow.
  final List<Lead> archiveLeads;
  EmailValidationSnapshot? snapshot;
  List<Map<String, dynamic>>? validated;
  List<Map<String, dynamic>>? uploadedSheets;
  String? uploadedSourceArchiveId;

  @override
  Future<List<Lead>> getEmailLeads() async {
    if (listFails) throw Exception('Failed to load email leads');
    return leads;
  }

  @override
  Future<void> deleteEmailLead(String leadId) async => deleted.add(leadId);

  @override
  Future<List<Lead>> getWebsiteLeads() async {
    websiteLeadLoads += 1;
    return websiteLeads;
  }

  @override
  Future<void> validateWebsiteLeadEmails(List<String> ids) async => validatedWebsiteLeadIds = ids;

  @override
  Future<int> deleteEmailLeadsByCategory(String category) async =>
      leads.where((l) => l.category == category).length;

  @override
  Future<List<Lead>> getExcelArchiveLeads(String id) async => archiveLeads;

  @override
  Future<List<ExcelArchive>> listExcelArchives() async => [_archive];

  @override
  Future<void> validateEmailLeads(List<Map<String, dynamic>> leads) async => validated = leads;

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

  group('EmailLeadsBloc', () {
    test('loads the verified email leads', () async {
      final repo = _FakeRepository(leads: [_lead('a', 'A Cafe'), _lead('b', 'B Cafe')]);
      final bloc = EmailLeadsBloc(repo)..add(const EmailLeadsRequested());
      final state = await bloc.stream.firstWhere((s) => s.status == EmailLeadsStatus.success);

      expect(state.businesses.map((b) => b.dbId), ['a', 'b']);
      await bloc.close();
    });

    test('a failing list load surfaces the error message', () async {
      final bloc = EmailLeadsBloc(_FakeRepository(listFails: true))..add(const EmailLeadsRequested());
      final state = await bloc.stream.firstWhere((s) => s.status == EmailLeadsStatus.failure);
      expect(state.error, 'Failed to load email leads');
      await bloc.close();
    });

    test('search matches name, email, and website; delete removes the lead', () async {
      final repo = _FakeRepository(leads: [
        _lead('a', 'Alpha Cafe', email: 'hello@alpha.example'),
        _lead('b', 'Beta Bakery', category: 'Bakery'),
      ]);
      final bloc = EmailLeadsBloc(repo)..add(const EmailLeadsRequested());
      await bloc.stream.firstWhere((s) => s.status == EmailLeadsStatus.success);

      bloc.add(const EmailLeadsSearchChanged('hello@alpha'));
      var s = await bloc.stream.firstWhere((s) => s.query == 'hello@alpha');
      expect(s.filteredBusinesses.map((b) => b.dbId), ['a']);

      bloc.add(const EmailLeadsSearchChanged('b.example'));
      s = await bloc.stream.firstWhere((s) => s.query == 'b.example');
      expect(s.filteredBusinesses.map((b) => b.dbId), ['b']);

      bloc.add(const EmailLeadDeleted('a'));
      s = await bloc.stream.firstWhere((s) => s.businesses.length == 1);
      expect(repo.deleted, ['a']);
      expect(s.businesses.single.dbId, 'b');
      await bloc.close();
    });
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
      expect(find.text('Email Leads'), findsOneWidget);
      expect(find.text('7 businesses with a verified contact email.'), findsOneWidget);
      expect(find.text('Copy 7 emails'), findsOneWidget);
      expect(find.text('Business 0'), findsOneWidget);
      expect(find.text('info@id0.example'), findsOneWidget);
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
      expect(find.textContaining('Validate emails'), findsOneWidget);
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

  group('Website Leads email validation', () {
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
      expect(find.textContaining('2 without an email · 1 with one'), findsOneWidget);
      expect(find.text('hi@beta.example'), findsOneWidget); // shown on the card
      final loadsBefore = repo.websiteLeadLoads;

      await tester.tap(find.widgetWithText(FilledButton, 'Validate emails'));
      await tester.pumpAndSettle();
      expect(find.textContaining('have no website'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Validate'));
      await tester.pump(); // start request
      await tester.pump(); // first poll — the fake job is already done
      await tester.pumpAndSettle();

      expect(repo.validatedWebsiteLeadIds, ['a', 'c']);
      expect(repo.websiteLeadLoads, greaterThan(loadsBefore), reason: 'list reloads when the run ends');
      expect(find.text('1 verified'), findsOneWidget);
      expect(find.text('1 no email on site'), findsOneWidget);
    });

    testWidgets('"Has email" narrows the list to leads that have one', (tester) async {
      final repo = _FakeRepository()
        ..websiteLeads = [
          websiteLead('a', 'Alpha Cafe'),
          websiteLead('b', 'Beta Cafe', email: 'hi@beta.example'),
        ];
      await pumpPage(tester, repo);
      expect(find.text('Alpha Cafe'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Has email (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Alpha Cafe'), findsNothing);
      expect(find.text('Beta Cafe'), findsOneWidget);
    });

    testWidgets('disables the action when every lead already has an email', (tester) async {
      final repo = _FakeRepository()
        ..websiteLeads = [websiteLead('b', 'Beta Cafe', email: 'hi@beta.example')];
      await pumpPage(tester, repo);

      expect(find.text('Every lead in this list already has an email.'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Validate emails'));
      expect(button.onPressed, isNull);
    });

    testWidgets('the validator card reflows on a phone-width window', (tester) async {
      tester.view.physicalSize = const Size(340, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(28),
              child: WebsiteLeadEmailValidator(
                leads: [websiteLead('a', 'Alpha'), websiteLead('b', 'Beta', email: 'b@b.example')],
                onFinished: () {},
                onEmailOnlyChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Validate emails'), findsOneWidget);
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
