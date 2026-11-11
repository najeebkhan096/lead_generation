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

  testWidgets('the bottom bar is only No Website and Profile, and opens on No Website', (tester) async {
    await pumpApp(tester);

    final labels = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((d) => d.label)
        .toList();
    expect(labels, ['No Website', 'Profile']);
    expect(shownTab(tester), 0);
    expect(find.text('WhatsApp · no website'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'New'), findsWidgets);
    expect(find.widgetWithText(ChoiceChip, 'Contacted'), findsWidgets);
    // Email leads are not part of the app.
    expect(find.widgetWithText(Tab, 'Email'), findsNothing);
  });

  testWidgets('Profile holds the 1-star leads, Deals and Sales, and the account with Sign out', (tester) async {
    await pumpApp(tester);

    await tapTab(tester, 'Profile');
    expect(shownTab(tester), 1);
    expect(find.text('Profile'), findsWidgets);
    expect(find.text('1-star review leads'), findsOneWidget);
    expect(find.text('Deals'), findsOneWidget);
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
    expect(find.text('Outreach chat'), findsNothing);

    // The 1-star leads open from here, with New / Contacted and a way back.
    await tester.tap(find.text('1-star review leads'));
    await animate(tester);
    expect(find.text('WhatsApp · 1-star reviews'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'New'), findsWidgets);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await animate(tester);
    expect(find.text('Sign Out'), findsOneWidget);
  });
}
