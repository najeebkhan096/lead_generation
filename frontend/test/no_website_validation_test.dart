import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/core/theme/app_theme.dart';
import 'package:lead_generation_app/domain/entities/email_validation.dart';
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
  bool waReady = true;

  @override
  Future<List<LeadCategory>> getLeadCategories(LeadCollection collection) async {
    expect(collection, LeadCollection.websiteLeads);
    return const [LeadCategory(name: 'Cafe USA', count: 19), LeadCategory(name: 'Bakery USA', count: 7)];
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

/// [search] is the category picked from the dropdown before anything else.
Future<_Repo> _pump(WidgetTester tester, {int tab = 0, bool waReady = true, String? search = 'Cafe USA'}) async {
  tester.view.physicalSize = const Size(1100, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo()..waReady = waReady;
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
}
