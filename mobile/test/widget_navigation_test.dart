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
  /// The first pump starts the tab/route animation, the second runs it out.
  Future<void> animate(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: const MainNavigationPage(),
      ));

  NavigationBar navBar(WidgetTester tester) => tester.widget<NavigationBar>(find.byType(NavigationBar));

  testWidgets('bottom bar: 1-star reviews and No website, each with WhatsApp and Email tabs', (tester) async {
    await pumpApp(tester);

    expect(navBar(tester).destinations, hasLength(2));
    expect(navBar(tester).selectedIndex, 0);
    final labels = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((d) => d.label)
        .toList();
    expect(labels, ['1-star reviews', 'No website']);

    // 1-star reviews is showing, on its WhatsApp tab.
    expect(find.text('WhatsApp · 1-star reviews'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'WhatsApp'), findsWidgets);
    expect(find.widgetWithText(Tab, 'Email'), findsWidgets);
    // New / Contacted is a switch inside each list, not a tab.
    expect(find.widgetWithText(ChoiceChip, 'New'), findsWidgets);
    expect(find.widgetWithText(ChoiceChip, 'Contacted'), findsWidgets);
    expect(find.widgetWithText(Tab, 'Contacted'), findsNothing);

    // Its Email tab.
    await tester.tap(find.widgetWithText(Tab, 'Email').first);
    await animate(tester);
    expect(find.text('Email · 1-star reviews'), findsOneWidget);

    // No website: its own pair of tabs, back on WhatsApp.
    await tester.tap(find.byIcon(AppIcons.globe));
    await animate(tester);
    expect(navBar(tester).selectedIndex, 1);
    expect(find.text('WhatsApp · No website'), findsOneWidget);

    // Back to 1-star reviews: it kept its Email tab.
    await tester.tap(find.byIcon(AppIcons.star));
    await animate(tester);
    expect(navBar(tester).selectedIndex, 0);
    expect(find.text('Email · 1-star reviews'), findsOneWidget);
  });

  testWidgets('the account button opens More, with Sign out, and goes back', (tester) async {
    await pumpApp(tester);

    expect(find.text('Sign Out'), findsNothing);
    await tester.tap(find.byTooltip('More').first);
    await animate(tester);

    expect(find.text('Sign Out'), findsOneWidget);
    expect(find.text('Outreach chat'), findsOneWidget);

    await tester.pageBack();
    await animate(tester);
    expect(find.text('Sign Out'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
