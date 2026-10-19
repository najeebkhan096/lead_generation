import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/pages/main_navigation_page.dart';
import 'package:lead_mobile/theme/app_theme.dart';

// Firebase core is mocked so pages that create Firestore reads can build;
// the reads surface errors, which the pages render as states.

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  /// Plain pumps: pumpAndSettle never settles while list spinners animate.
  /// The first pump starts the route animation, the second runs it out.
  Future<void> animate(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: const MainNavigationPage(),
      ));

  /// Taps a destination in the bottom bar (its label, inside the bar only).
  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
    await animate(tester);
  }

  int shownTab(WidgetTester tester) => tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;

  testWidgets('the bottom bar has Leads, Sales and More, and opens on the WhatsApp leads', (tester) async {
    await pumpApp(tester);

    final labels = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((d) => d.label)
        .toList();
    expect(labels, ['Leads', 'Sales', 'More']);
    expect(shownTab(tester), 0);
    expect(find.text('WhatsApp · 1-star reviews'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'New'), findsWidgets);
    expect(find.widgetWithText(ChoiceChip, 'Contacted'), findsWidgets);
    // Email and no-website leads are not part of the app.
    expect(find.widgetWithText(Tab, 'Email'), findsNothing);
    expect(find.textContaining('No website'), findsNothing);
  });

  testWidgets('Sales is its own tab, and More holds the account with Sign out but no outreach chat', (tester) async {
    await pumpApp(tester);

    await tapTab(tester, 'Sales');
    expect(shownTab(tester), 1);

    await tapTab(tester, 'More');
    expect(shownTab(tester), 2);
    expect(find.text('Sign Out'), findsOneWidget);
    expect(find.text('Outreach chat'), findsNothing);
    expect(find.text('My sales'), findsNothing);

    await tapTab(tester, 'Leads');
    expect(shownTab(tester), 0);
    expect(find.text('WhatsApp · 1-star reviews'), findsOneWidget);
  });
}
