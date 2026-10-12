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

  testWidgets('MainNavigationPage follows the core flow: Leads, WhatsApp, Email, More', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const MainNavigationPage(),
    ));

    // Four destinations, in flow order (see main_navigation_page.dart).
    // `findsWidgets` for 'Leads': the tab label and the page's own tab bar.
    expect(find.text('Leads'), findsWidgets);
    expect(find.text('WhatsApp'), findsWidgets);
    expect(find.text('Email'), findsWidgets);
    expect(find.text('More'), findsWidgets);

    // The extras are no longer in the main bar.
    expect(find.text('Outreach'), findsNothing);
    expect(find.text('Sales'), findsNothing);
    expect(find.text('Profile'), findsNothing);

    NavigationBar navBar() => tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar().destinations, hasLength(4));
    expect(navBar().selectedIndex, 0);

    // Tap through the tabs and verify selection follows. Plain pump():
    // pumpAndSettle never settles while stream spinners are animating.
    await tester.tap(find.byIcon(AppIcons.chat));
    await tester.pump(const Duration(milliseconds: 400));
    expect(navBar().selectedIndex, 1);

    await tester.tap(find.byIcon(AppIcons.mail));
    await tester.pump(const Duration(milliseconds: 400));
    expect(navBar().selectedIndex, 2);

    await tester.tap(find.byIcon(AppIcons.more));
    await tester.pump(const Duration(milliseconds: 400));
    expect(navBar().selectedIndex, 3);
  });
}
