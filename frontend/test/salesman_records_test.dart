import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/core/theme/app_theme.dart';
import 'package:lead_generation_app/domain/entities/contacted_lead.dart';
import 'package:lead_generation_app/domain/entities/salesman_stats.dart';
import 'package:lead_generation_app/domain/repositories/lead_repository.dart';
import 'package:lead_generation_app/presentation/pages/salesman_contacted_leads_page.dart';

class _Repo implements LeadRepository {
  _Repo(this.leads);

  List<ContactedLead> leads;
  final moves = <({String userId, String leadId, String kind})>[];

  @override
  Future<List<ContactedLead>> getSalesmanContactedLeads(String userId) async => leads;

  @override
  Future<bool> moveContactedLeadBack(String userId, String leadId, {String kind = 'review'}) async {
    moves.add((userId: userId, leadId: leadId, kind: kind));
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ContactedLead _lead(String name, String kind, {String id = 'same-id'}) => ContactedLead(
      id: id,
      kind: kind,
      business: name,
      category: 'Cafe USA',
      location: 'TX',
      contactedAt: DateTime(2026, 11, 11, 10),
    );

void main() {
  test('salesman stats read the per-kind split, and default to zero for an older server', () {
    final stats = SalesmanStats.fromJson({
      'totals': {
        'contactedToday': 3,
        'websiteLeads': 40,
        'websiteNewLeft': 25,
        'byKind': {
          'review': {'today': 2, 'last7': 9, 'total': 30},
          'website': {'today': 1, 'last7': 4, 'total': 6},
        },
      },
      'salesmen': [
        {
          'id': 'ali',
          'name': 'Ali',
          'contactedToday': 3,
          'contactedTotal': 36,
          'byKind': {
            'review': {'today': 2, 'last7': 9, 'total': 30},
            'website': {'today': 1, 'last7': 4, 'total': 6},
          },
        },
        {'id': 'old', 'name': 'Old'},
      ],
    });
    final ali = stats.salesmen.first;
    expect((ali.review.today, ali.review.total, ali.website.today, ali.website.last7, ali.website.total), (2, 30, 1, 4, 6));
    expect(stats.totals.website.total, 6);
    expect(stats.totals.websiteLeads, 40);
    expect(stats.totals.websiteNewLeft, 25);
    expect(stats.salesmen.last.website.total, 0);
  });

  test('a contacted lead knows its kind, and the two kinds never share a key', () {
    final a = ContactedLead.fromJson({'id': 'x', 'kind': 'website', 'business': 'A'});
    final b = ContactedLead.fromJson({'id': 'x', 'business': 'B'});
    expect(a.isWebsite, isTrue);
    expect(b.kind, 'review');
    expect(a.key == b.key, isFalse);
  });

  Future<_Repo> pump(WidgetTester tester, List<ContactedLead> leads) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo(leads);
    await tester.pumpWidget(RepositoryProvider<LeadRepository>.value(
      value: repo,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const SalesmanContactedLeadsPage(userId: 'ali', salesmanName: 'Ali'),
      ),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('the admin sees every contacted lead, each marked 1-star or no website, and can filter by kind', (tester) async {
    await pump(tester, [_lead('Review Cafe', 'review'), _lead('Site Salon', 'website')]);

    expect(find.text('Review Cafe'), findsOneWidget);
    expect(find.text('Site Salon'), findsOneWidget);
    expect(find.text('1-star'), findsOneWidget);
    expect(find.text('No website'), findsWidgets);
    expect(find.text('All · 2'), findsOneWidget);

    await tester.tap(find.text('No website · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Site Salon'), findsOneWidget);
    expect(find.text('Review Cafe'), findsNothing);

    await tester.tap(find.text('1-star reviews · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Review Cafe'), findsOneWidget);
    expect(find.text('Site Salon'), findsNothing);
  });

  testWidgets('moving a no-website lead back sends its kind, and only that lead leaves — even with a 1-star twin', (tester) async {
    final repo = await pump(tester, [_lead('Review Cafe', 'review'), _lead('Site Salon', 'website')]);

    await tester.tap(find.widgetWithText(TextButton, 'Move to New').last); // the no-website card is second
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Move to New'));
    await tester.pumpAndSettle();

    expect(repo.moves.single.kind, 'website');
    expect(repo.moves.single.leadId, 'same-id');
    expect(find.text('Site Salon'), findsNothing);
    expect(find.text('Review Cafe'), findsOneWidget); // the twin shares the id, not the record
  });
}
