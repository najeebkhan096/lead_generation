import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/core/theme/app_theme.dart';
import 'package:lead_generation_app/domain/entities/lead.dart';
import 'package:lead_generation_app/domain/entities/lead_page.dart';
import 'package:lead_generation_app/domain/repositories/lead_repository.dart';
import 'package:lead_generation_app/presentation/pages/lead_hubs.dart';
import 'package:lead_generation_app/presentation/pages/whatsapp_leads_page.dart';

/// Serves a different business per list, and records what each tab asked for.
class _Repo implements LeadRepository {
  final pages = <LeadCollection>[];
  final categories = <LeadCollection>[];

  Lead _lead(String name) => Lead(
        id: name,
        dbId: name,
        business: name,
        category: 'Cafe USA',
        location: 'Austin, TX',
        phone: '+15125550100',
        hasWhatsApp: true,
        badReview: const BadReview(stars: 1, text: '', date: 'Unknown'),
      );

  @override
  Future<LeadPage> getLeadsPage(
    LeadCollection collection, {
    String? cursor,
    String? category,
    String? query,
    int limit = 50,
    bool verifiedOnly = false,
  }) async {
    pages.add(collection);
    final name = switch (collection) {
      LeadCollection.websiteVerified => 'Site Salon',
      LeadCollection.whatsappReviewLeads => 'Review Cafe',
      _ => 'Other',
    };
    return LeadPage(leads: [_lead(name)], total: 1);
  }

  @override
  Future<List<LeadCategory>> getLeadCategories(LeadCollection collection) async {
    categories.add(collection);
    return const [LeadCategory(name: 'Cafe USA', count: 1)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_Repo> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo();
  await tester.pumpWidget(RepositoryProvider<LeadRepository>.value(
    value: repo,
    child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: page)),
  ));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('WhatsApp Verified has two tabs: no website, and 1-star reviews', (tester) async {
    await _pump(tester, const WhatsAppLeadsPage());
    expect(find.widgetWithText(Tab, 'No website'), findsOneWidget);
    expect(find.widgetWithText(Tab, '1-star reviews'), findsOneWidget);
  });

  testWidgets('each tab lists only its own kind, with the categories of that kind', (tester) async {
    final repo = await _pump(tester, const WhatsAppLeadsPage());

    // No website first: the no-website scan's leads confirmed on WhatsApp.
    expect(find.text('Site Salon'), findsWidgets);
    expect(find.text('Review Cafe'), findsNothing);
    expect(repo.pages, [LeadCollection.websiteVerified]);
    expect(repo.categories, [LeadCollection.websiteVerified]);

    await tester.tap(find.widgetWithText(Tab, '1-star reviews'));
    await tester.pumpAndSettle();
    expect(find.text('Review Cafe'), findsWidgets);
    expect(repo.pages, [LeadCollection.websiteVerified, LeadCollection.whatsappReviewLeads]);
    expect(repo.categories, [LeadCollection.websiteVerified, LeadCollection.whatsappReviewLeads]);
  });

  testWidgets('the tab can be chosen by link, and the first tab is kept alive when leaving it', (tester) async {
    final repo = await _pump(tester, const VerifiedHubPage(tab: 'review'));
    expect(repo.pages, [LeadCollection.whatsappReviewLeads]);
    expect(find.text('Review Cafe'), findsWidgets);

    await tester.tap(find.widgetWithText(Tab, 'No website'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, '1-star reviews'));
    await tester.pumpAndSettle();
    // Back on the first-opened tab: not loaded a second time.
    expect(repo.pages.where((c) => c == LeadCollection.whatsappReviewLeads), hasLength(1));
  });
}
