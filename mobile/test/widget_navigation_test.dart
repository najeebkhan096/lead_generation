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

  testWidgets('the app is one page with two tabs: WhatsApp and Email', (tester) async {
    await pumpApp(tester);

    // Exactly two tabs, no bottom bar, and none of the unvalidated lead views.
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.widget<TabBar>(find.byType(TabBar)).tabs, hasLength(2));
    expect(find.widgetWithText(Tab, 'WhatsApp'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Email'), findsOneWidget);
    expect(find.text('Leads'), findsNothing);
    expect(find.text('Discover leads'), findsNothing);
    expect(find.text('Website leads'), findsNothing);

    // WhatsApp is first.
    expect(find.text('WhatsApp leads'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Email'));
    await animate(tester);
    expect(find.text('Email leads'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'WhatsApp'));
    await animate(tester);
    expect(find.text('WhatsApp leads'), findsOneWidget);
  });

  testWidgets('the account button opens More, with Sign out, and goes back', (tester) async {
    await pumpApp(tester);

    expect(find.text('Sign Out'), findsNothing);
    await tester.tap(find.byTooltip('More'));
    await animate(tester);

    expect(find.text('Sign Out'), findsOneWidget);
    expect(find.text('Outreach chat'), findsOneWidget);

    await tester.pageBack();
    await animate(tester);
    expect(find.text('Sign Out'), findsNothing);
    expect(find.widgetWithText(Tab, 'Email'), findsOneWidget);
  });
}
