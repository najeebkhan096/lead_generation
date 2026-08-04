import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/pages/main_navigation_page.dart';
import 'package:lead_mobile/theme/app_theme.dart';

// Firebase core is mocked so pages that create Firestore streams can build;
// the streams themselves surface errors, which the pages render as states.

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  testWidgets('MainNavigationPage has 4 tabs and switches content', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const MainNavigationPage(),
    ));

    // Verify all four destinations are present.
    expect(find.text('Leads'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Deals'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    NavigationBar navBar() => tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar().selectedIndex, 0);

    // Tap through the tabs and verify selection follows. Plain pump():
    // pumpAndSettle never settles while stream spinners are animating.
    await tester.tap(find.byIcon(AppIcons.heart));
    await tester.pump(const Duration(milliseconds: 400));
    expect(navBar().selectedIndex, 1);

    await tester.tap(find.byIcon(AppIcons.handshake));
    await tester.pump(const Duration(milliseconds: 400));
    expect(navBar().selectedIndex, 2);

    await tester.tap(find.byIcon(AppIcons.user));
    await tester.pump(const Duration(milliseconds: 400));
    expect(navBar().selectedIndex, 3);
  });
}
