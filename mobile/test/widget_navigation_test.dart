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

  testWidgets('the app opens on the WhatsApp 1-star review leads, New first, with no other sections', (tester) async {
    await pumpApp(tester);

    expect(find.text('WhatsApp · 1-star reviews'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'New'), findsWidgets);
    expect(find.widgetWithText(ChoiceChip, 'Contacted'), findsWidgets);
    // Email and no-website leads are not part of the app.
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.widgetWithText(Tab, 'Email'), findsNothing);
    expect(find.textContaining('No website'), findsNothing);
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
    expect(find.text('WhatsApp · 1-star reviews'), findsOneWidget);
  });
}
