import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/core/theme/app_theme.dart';
import 'package:lead_generation_app/domain/entities/email_validation.dart';
import 'package:lead_generation_app/domain/entities/lead.dart';
import 'package:lead_generation_app/domain/entities/lead_page.dart';
import 'package:lead_generation_app/domain/entities/whatsapp_web_status.dart';
import 'package:lead_generation_app/domain/repositories/lead_repository.dart';
import 'package:lead_generation_app/presentation/pages/no_website_validation_page.dart';

UnvalidatedWhatsAppSummary _summary({required bool email}) => UnvalidatedWhatsAppSummary.fromJson({
      'total': 3,
      'locations': [
        {'name': 'FL', 'total': 4, 'eligible': 4, 'checked': 4, 'found': 3, 'count': 0, 'status': 'validated'},
        {'name': 'TX', 'total': 10, 'eligible': 9, 'checked': 6, 'found': 2, 'count': 3, 'status': 'partial'},
        {'name': 'OH', 'total': 5, 'eligible': 5, 'checked': 0, 'found': 0, 'count': 5, 'status': 'not_validated'},
      ],
    });

/// Only what the page touches; anything else fails loudly via [noSuchMethod].
class _Repo implements LeadRepository {
  final waStarts = <({List<String>? states, String? collection, String? category})>[];
  final emailStarts = <({List<String>? states, String? category, bool recheck})>[];
  final summaryCalls = <({String? collection, String? category})>[];
  final emailSummaryCategories = <String?>[];
  final leadPageCalls = <({LeadCollection collection, String? category})>[];

  /// Serve a long list: a full first page of Miami leads, then one Austin lead on the second.
  bool longList = false;
  final resumed = <String>[];
  final discarded = <String>[];
  List<ValidationRun> runs = [];
  bool waReady = true;

  @override
  Future<List<LeadCategory>> getLeadCategories(LeadCollection collection) async {
    expect(collection, LeadCollection.websiteLeads);
    return const [LeadCategory(name: 'Cafe USA', count: 19), LeadCategory(name: 'Bakery USA', count: 7)];
  }

  @override
  Future<LeadPage> getLeadsPage(
    LeadCollection collection, {
    String? cursor,
    String? category,
    String? query,
    int limit = 50,
    bool verifiedOnly = false,
  }) async {
    leadPageCalls.add((collection: collection, category: category));
    if (longList) {
      Lead at(String name, String where) => Lead(
            id: name,
            dbId: name,
            business: name,
            category: category ?? '',
            location: where,
            phone: '+15125550100',
            badReview: const BadReview(stars: 1, text: '', date: 'Unknown'),
          );
      return cursor == null
          ? LeadPage(leads: [for (var i = 0; i < 50; i++) at('Miami $i', 'Miami, FL')], nextCursor: 'p2', total: 51)
          : LeadPage(leads: [at('Austin Late', 'Austin, TX')]);
    }
    Lead lead(String name, String where, {String? email}) => Lead(
          id: name,
          dbId: name,
          business: name,
          category: category ?? '',
          location: where,
          phone: '+15125550100',
          email: email,
          badReview: const BadReview(stars: 1, text: '', date: 'Unknown'),
        );
    final withEmail = collection == LeadCollection.websiteWithEmail;
    final leads = [
      lead('Alpha Cafe', 'Austin, TX', email: withEmail ? 'hi@alpha.test' : null),
      lead('Bravo Cafe', 'Miami, FL', email: withEmail ? 'hi@bravo.test' : null),
    ];
    return LeadPage(leads: leads, total: 2);
  }

  @override
  Future<List<ValidationRun>> listValidationRuns({String? collection, String? kind}) async =>
      [for (final r in runs) if (r.kind == kind) r];

  @override
  Future<String?> resumeValidationRun(String id) async {
    resumed.add(id);
    return 'Resumed. Started validation for 60 leads.';
  }

  @override
  Future<void> discardValidationRun(String id) async {
    discarded.add(id);
    runs = [for (final r in runs) if (r.id != id) r];
  }

  @override
  Future<UnvalidatedWhatsAppSummary> getUnvalidatedWhatsAppSummary({String? collection, String? category}) async {
    summaryCalls.add((collection: collection, category: category));
    return _summary(email: false);
  }

  @override
  Future<UnvalidatedWhatsAppSummary> getEmailValidationSummary({String? category}) async {
    emailSummaryCategories.add(category);
    return _summary(email: true);
  }

  @override
  Future<WhatsAppWebStatus> getWhatsAppWebStatus() async => WhatsAppWebStatus(
        status: waReady ? WhatsAppWebConnectionStatus.ready : WhatsAppWebConnectionStatus.disconnected,
        safety: const WhatsAppSafetyStatus(dailyCap: 100, remainingToday: 100),
      );

  @override
  Future<WhatsAppValidationSnapshot> getWhatsAppValidationStatus() async =>
      const WhatsAppValidationSnapshot(active: false, status: 'idle');

  @override
  Future<EmailValidationSnapshot> getEmailValidationStatus() async =>
      const EmailValidationSnapshot(active: false, status: 'idle');

  @override
  Future<String?> startWhatsAppAutoValidation({List<String>? states, String? collection, String? category}) async {
    waStarts.add((states: states, collection: collection, category: category));
    return 'Started';
  }

  @override
  Future<String?> startEmailValidation({List<String>? states, String? category, bool recheck = false}) async {
    emailStarts.add((states: states, category: category, recheck: recheck));
    return 'Started the email lookup';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_Repo> _pumpWith(WidgetTester tester, {bool longList = false}) => _pump(tester, longList: longList);

/// [search] is the category picked from the dropdown before anything else.
Future<_Repo> _pump(
  WidgetTester tester, {
  int tab = 0,
  bool waReady = true,
  String? search = 'Cafe USA',
  List<ValidationRun> runs = const [],
  bool longList = false,
}) async {
  tester.view.physicalSize = const Size(1100, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo()
    ..waReady = waReady
    ..longList = longList
    ..runs = [...runs];
  await tester.pumpWidget(
    RepositoryProvider<LeadRepository>.value(
      value: repo,
      child: MaterialApp(theme: AppTheme.light(), home: NoWebsiteValidationPage(initialTab: tab)),
    ),
  );
  await tester.pumpAndSettle();
  if (search != null) {
    await tester.tap(find.text('Select a search to validate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(search).last);
    await tester.pumpAndSettle();
  }
  return repo;
}

void main() {
  testWidgets('has a WhatsApp tab and an Email tab', (tester) async {
    await _pump(tester);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    // WhatsApp is the first tab and loads the no-website collection's states.
    expect(find.text('WhatsApp validation'), findsNothing); // blurb, not a heading
    expect(find.textContaining('your linked WhatsApp Web session'), findsOneWidget);
  });

  testWidgets('nothing is listed or validated until a search is picked', (tester) async {
    final repo = await _pump(tester, search: null);
    expect(find.text('Select a search to validate'), findsOneWidget);
    expect(find.text('Select a search above to see its states.'), findsOneWidget);
    expect(find.text('TX · 10'), findsNothing);
    expect(repo.summaryCalls, isEmpty);
  });

  testWidgets('choosing another search reloads the states for it', (tester) async {
    final repo = await _pump(tester);
    expect(repo.summaryCalls.map((c) => c.category), ['Cafe USA']);
    await tester.tap(find.text('Cafe USA').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bakery USA').last);
    await tester.pumpAndSettle();
    expect(repo.summaryCalls.map((c) => c.category), ['Cafe USA', 'Bakery USA']);
    expect(find.text('Showing the states of "Bakery USA".'), findsOneWidget);
  });

  testWidgets('lists each state with its progress and a Validate button', (tester) async {
    await _pump(tester);
    expect(find.text('FL · 4'), findsOneWidget);
    expect(find.text('TX · 10'), findsOneWidget);
    expect(find.text('OH · 5'), findsOneWidget);
    expect(find.textContaining('Partly validated · 6 of 9 checked · 2 on WhatsApp'), findsOneWidget);
    expect(find.text('Validate 3 left'), findsOneWidget);
    // A validated state can't be run again.
    final validated = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Validated'));
    expect(validated.onPressed, isNull);
  });

  testWidgets('WhatsApp: ticking states validates exactly those, against the no-website leads', (tester) async {
    final repo = await _pump(tester);
    expect(repo.summaryCalls, [(collection: 'websiteLeads', category: 'Cafe USA')]);

    await tester.tap(find.byType(Checkbox).at(2)); // TX (FL is disabled but still a checkbox)
    await tester.tap(find.byType(Checkbox).at(3)); // OH
    await tester.pump();
    expect(find.text('Validate selected (2)'), findsOneWidget);
    expect(find.textContaining('Will check 8 numbers in 2 states'), findsOneWidget);

    await tester.tap(find.text('Validate selected (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Validate WhatsApp numbers in 2 states of "Cafe USA"?'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(repo.waStarts, hasLength(1));
    expect(repo.waStarts.single.states, ['TX', 'OH']);
    expect(repo.waStarts.single.collection, 'websiteLeads');
    expect(repo.waStarts.single.category, 'Cafe USA');
  });

  testWidgets('WhatsApp: one state, and Validate all, send the right scope', (tester) async {
    final repo = await _pump(tester);
    await tester.tap(find.text('Validate').first); // OH's button (FL "Validated", TX "Validate 3 left")
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(repo.waStarts.single.states, ['OH']);

    await tester.tap(find.textContaining('Validate all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(repo.waStarts.last.states, isNull);
  });

  testWidgets('WhatsApp: not connected sends nothing and offers to connect', (tester) async {
    final repo = await _pump(tester, waReady: false);
    expect(find.text('WhatsApp Web is not connected'), findsOneWidget);
    await tester.tap(find.text('Validate').first);
    await tester.pumpAndSettle();
    expect(find.text('WhatsApp Web not connected'), findsOneWidget);
    expect(repo.waStarts, isEmpty);
  });

  testWidgets('Email: selected states start the email lookup, not the WhatsApp one', (tester) async {
    final repo = await _pump(tester, tab: 1);
    expect(find.textContaining('looked up on the public web'), findsOneWidget);
    expect(find.textContaining('2 with an email'), findsOneWidget);

    // Checkboxes: retry toggle, select-all, FL (nothing left), TX, OH.
    await tester.tap(find.byType(Checkbox).at(4)); // OH
    await tester.pump();
    await tester.tap(find.text('Validate selected (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Look up emails in OH · "Cafe USA"?'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(repo.emailSummaryCategories, everyElement('Cafe USA')); // reloaded after the start too
    expect(repo.emailStarts.single.states, ['OH']);
    expect(repo.emailStarts.single.category, 'Cafe USA');
    expect(repo.emailStarts.single.recheck, isFalse);
    expect(repo.waStarts, isEmpty);
  });

  testWidgets('Email: retrying earlier misses makes a validated state runnable again', (tester) async {
    final repo = await _pump(tester, tab: 1);
    expect(find.text('Re-check'), findsNothing);

    await tester.tap(find.byType(Checkbox).at(0)); // "Also retry businesses with no email found earlier"
    await tester.pump();
    expect(find.text('Re-check'), findsOneWidget); // FL

    await tester.tap(find.text('Re-check'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(repo.emailStarts.single.states, ['FL']);
    expect(repo.emailStarts.single.recheck, isTrue);
  });

  group('validated leads of the selected search', () {
    testWidgets('the WhatsApp tab lists the numbers confirmed on WhatsApp in that search', (tester) async {
      final repo = await _pump(tester);
      expect(repo.leadPageCalls, [(collection: LeadCollection.websiteVerified, category: 'Cafe USA')]);
      expect(find.text('Validated on WhatsApp · 2'), findsOneWidget);
      expect(find.text('Alpha Cafe'), findsOneWidget);
      expect(find.text('Bravo Cafe'), findsOneWidget);
      expect(find.text('On WhatsApp'), findsNWidgets(2));
      expect(find.textContaining('"Cafe USA"'), findsWidgets);
    });

    testWidgets('a ticked state with leads only on a later page is still found', (tester) async {
      final repo = await _pumpWith(tester, longList: true);
      expect(find.text('Austin Late'), findsNothing); // page two is not read yet

      await tester.tap(find.byType(Checkbox).at(2)); // TX
      await tester.pumpAndSettle();
      expect(repo.leadPageCalls, hasLength(2), reason: 'it read the next page on its own');
      expect(find.text('Austin Late'), findsOneWidget);
      expect(find.textContaining('None of the ticked states'), findsNothing);
      expect(find.text('Validated on WhatsApp · 1'), findsOneWidget); // the list ended, so the count is exact
    });

    testWidgets('nothing is listed until a search is picked', (tester) async {
      final repo = await _pump(tester, search: null);
      expect(repo.leadPageCalls, isEmpty);
      expect(find.textContaining('Validated on WhatsApp'), findsNothing);
    });

    testWidgets('the Email tab lists the emails found, from the no-website scan\'s leads', (tester) async {
      final repo = await _pump(tester, tab: 1);
      expect(repo.leadPageCalls.single, (collection: LeadCollection.websiteWithEmail, category: 'Cafe USA'));
      expect(find.text('Emails found · 2'), findsOneWidget);
      expect(find.textContaining('hi@alpha.test'), findsOneWidget);
      expect(find.text('Email found'), findsNWidgets(2));
    });

    testWidgets('ticking a state narrows the list to its leads', (tester) async {
      await _pump(tester);
      await tester.tap(find.byType(Checkbox).at(2)); // TX
      await tester.pump();
      expect(find.text('Alpha Cafe'), findsOneWidget); // Austin, TX
      expect(find.text('Bravo Cafe'), findsNothing); // Miami, FL
    });

    testWidgets('changing the search loads that search\'s leads', (tester) async {
      final repo = await _pump(tester);
      await tester.tap(find.text('Cafe USA').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bakery USA').last);
      await tester.pumpAndSettle();
      expect(repo.leadPageCalls.map((c) => c.category), ['Cafe USA', 'Bakery USA']);
    });
  });

  group('an interrupted validation', () {
    const stopped = ValidationRun(
      id: 'run1',
      kind: 'whatsapp',
      status: 'interrupted',
      category: 'Cafe USA',
      states: ['TX', 'OH'],
      total: 300,
      checked: 120,
      found: 80,
    );

    testWidgets('is shown with how far it got, and Resume carries it on', (tester) async {
      final repo = await _pump(tester, runs: [stopped]);
      expect(find.text('Interrupted validation'), findsOneWidget);
      expect(find.textContaining('"Cafe USA" · TX, OH · 120 of 300 checked · 80 on WhatsApp'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
      await tester.pumpAndSettle();
      expect(repo.resumed, ['run1']);
      expect(repo.waStarts, isEmpty, reason: 'a resume goes through the saved run, not a new scope');
    });

    testWidgets('a run stopped for a safety reason says why; Discard forgets it', (tester) async {
      final repo = await _pump(tester, runs: [
        const ValidationRun(
          id: 'run2',
          kind: 'whatsapp',
          status: 'stopped',
          category: 'Cafe USA',
          total: 50,
          checked: 10,
          stoppedReason: 'Daily check limit reached',
        ),
      ]);
      expect(find.text('Stopped validation'), findsOneWidget);
      expect(find.textContaining('every state · 10 of 50 checked · Daily check limit reached'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(repo.discarded, ['run2']);
      expect(find.text('Stopped validation'), findsNothing);
    });

    testWidgets('each tab shows only its own kind of run', (tester) async {
      await _pump(tester, tab: 1, runs: [stopped]); // a WhatsApp run, Email tab open
      expect(find.text('Interrupted validation'), findsNothing);
    });

    testWidgets('WhatsApp not connected: Resume sends nothing and offers to connect', (tester) async {
      final repo = await _pump(tester, waReady: false, runs: [stopped]);
      await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
      await tester.pumpAndSettle();
      expect(find.text('WhatsApp Web not connected'), findsOneWidget);
      expect(repo.resumed, isEmpty);
    });
  });
}
