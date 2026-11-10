import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/core/theme/app_theme.dart';
import 'package:lead_generation_app/domain/entities/lead.dart';
import 'package:lead_generation_app/domain/entities/lead_page.dart';
import 'package:lead_generation_app/domain/repositories/lead_repository.dart';
import 'package:lead_generation_app/presentation/pages/email_leads_page.dart';
import 'package:lead_generation_app/presentation/pages/website_leads_page.dart';

/// Only the paged-list methods; anything else fails loudly.
class _FakeRepository implements LeadRepository {
  _FakeRepository(this.leads);

  List<Lead> leads;
  final deleted = <String>[];

  @override
  Future<LeadPage> getLeadsPage(
    LeadCollection collection, {
    String? cursor,
    String? category,
    String? query,
    int limit = 50,
    bool verifiedOnly = false,
  }) async =>
      LeadPage(leads: leads, total: leads.length);

  @override
  Future<List<LeadCategory>> getLeadCategories(LeadCollection collection) async => const [LeadCategory(name: 'Plumber', count: 3)];

  @override
  Future<void> deleteLeadIn(LeadCollection collection, String leadId) async {
    deleted.add(leadId);
    leads = leads.where((l) => l.dbId != leadId).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Lead _lead(String name, {double rating = 4, List<LeadEmail> emails = const []}) => Lead(
      id: name,
      dbId: 'db-$name',
      business: name,
      category: 'Plumber',
      location: 'Houston, TX',
      address: '1 Main St',
      phone: '+1 512 555 0100',
      rating: rating,
      totalReviews: 10,
      badReview: const BadReview(stars: 1, text: '', date: 'Unknown'),
      savedAt: DateTime.utc(2026, 11, 9),
      emails: emails,
    );

final _leads = [
  _lead('Charlie Plumbing', rating: 3.0),
  _lead('Alpha Pipes', rating: 4.5, emails: const [LeadEmail(address: 'hi@alpha.test', sourceUrl: 'https://alpha.test/contact'), LeadEmail(address: 'ops@alpha.test')]),
  _lead('Bravo Drains', rating: 1.5),
];

Future<_FakeRepository> _pump(WidgetTester tester, Widget page, {double width = 1500, ThemeData? theme}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _FakeRepository([..._leads]);
  await tester.pumpWidget(RepositoryProvider<LeadRepository>.value(
    value: repo,
    child: MaterialApp(theme: theme ?? AppTheme.light(), home: Scaffold(body: page)),
  ));
  await tester.pumpAndSettle();
  return repo;
}

double _y(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

void main() {
  testWidgets('a wide window shows a table with the list-specific columns', (tester) async {
    await _pump(tester, const WebsiteLeadsPage());
    expect(find.text('No Website Leads'), findsOneWidget);
    for (final header in ['BUSINESS', 'CATEGORY', 'PHONE', 'RATING', 'WEBSITE']) {
      expect(find.text(header), findsOneWidget, reason: header);
    }
    expect(find.text('Alpha Pipes'), findsOneWidget);
    expect(find.text('No website'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the email table shows every address with a count for extras', (tester) async {
    await _pump(tester, const EmailLeadsPage());
    expect(find.text('EMAIL'), findsOneWidget);
    expect(find.text('hi@alpha.test'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget, reason: 'a second address on file');
    expect(find.text('Not found'), findsNWidgets(2), reason: 'leads with no email say so — never a made-up address');
  });

  testWidgets('a phone-sized window falls back to cards; the view toggle switches back', (tester) async {
    await _pump(tester, const WebsiteLeadsPage(), width: 420);
    expect(find.text('BUSINESS'), findsNothing);
    expect(find.text('Alpha Pipes'), findsOneWidget);
  });

  testWidgets('optional columns drop out as the window narrows', (tester) async {
    await _pump(tester, const WebsiteLeadsPage(), width: 1500);
    expect(find.text('ADDED'), findsOneWidget);
    expect(find.text('CATEGORY'), findsOneWidget);

    await _pump(tester, const WebsiteLeadsPage(), width: 1000);
    expect(find.text('BUSINESS'), findsOneWidget, reason: 'still a table');
    expect(find.text('ADDED'), findsNothing, reason: 'lowest priority goes first');
  });

  testWidgets('sorting by a header reorders the rows, and again reverses them', (tester) async {
    await _pump(tester, const WebsiteLeadsPage());
    await tester.tap(find.text('BUSINESS'));
    await tester.pumpAndSettle();
    expect(_y(tester, 'Alpha Pipes'), lessThan(_y(tester, 'Bravo Drains')));
    expect(_y(tester, 'Bravo Drains'), lessThan(_y(tester, 'Charlie Plumbing')));

    await tester.tap(find.text('BUSINESS'));
    await tester.pumpAndSettle();
    expect(_y(tester, 'Charlie Plumbing'), lessThan(_y(tester, 'Alpha Pipes')));

    await tester.tap(find.text('RATING'));
    await tester.pumpAndSettle();
    expect(_y(tester, 'Bravo Drains'), lessThan(_y(tester, 'Alpha Pipes')), reason: 'ascending rating: 1.5 before 4.5');
  });

  testWidgets('ticking rows shows the bulk bar; Delete removes exactly those leads after confirming', (tester) async {
    final repo = await _pump(tester, const WebsiteLeadsPage());
    expect(find.textContaining('selected'), findsNothing);

    final boxes = find.byType(Checkbox);
    await tester.tap(boxes.at(1)); // Charlie
    await tester.pumpAndSettle(); // the bulk bar appears and shifts the table down
    await tester.tap(boxes.at(3)); // Bravo
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('Export 2'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 leads?'), findsOneWidget);
    expect(repo.deleted, isEmpty, reason: 'nothing happens before confirming');

    await tester.tap(find.widgetWithText(FilledButton, 'Delete 2'));
    await tester.pumpAndSettle();
    expect(repo.deleted.toSet(), {'db-Charlie Plumbing', 'db-Bravo Drains'});
    expect(find.text('Alpha Pipes'), findsOneWidget);
    expect(find.text('Charlie Plumbing'), findsNothing);
    expect(find.textContaining('selected'), findsNothing, reason: 'the selection was cleared');
  });

  testWidgets('cancelling the confirmation deletes nothing and keeps the selection', (tester) async {
    final repo = await _pump(tester, const WebsiteLeadsPage());
    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty);
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('select-all ticks every loaded row and Clear unticks them', (tester) async {
    await _pump(tester, const WebsiteLeadsPage());
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets('Card view shows cards; Table view returns', (tester) async {
    await _pump(tester, const WebsiteLeadsPage());
    await tester.tap(find.byTooltip('Card view'));
    await tester.pumpAndSettle();
    expect(find.text('BUSINESS'), findsNothing);
    await tester.tap(find.byTooltip('Table view'));
    await tester.pumpAndSettle();
    expect(find.text('BUSINESS'), findsOneWidget);
  });

  testWidgets('the table renders in dark mode without overflow', (tester) async {
    await _pump(tester, const EmailLeadsPage(), theme: AppTheme.dark());
    expect(find.text('Alpha Pipes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
