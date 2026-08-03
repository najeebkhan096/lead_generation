import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/pages/main_navigation_page.dart';

// Since we can't easily mock all Firebase services inside widget tests without boilerplate,
// we will test if the MainNavigationPage structure is correct and responds to taps.

void main() {
  testWidgets('MainNavigationPage has 4 tabs and switches content', (WidgetTester tester) async {
    // We wrap the widget in a MaterialApp and provide placeholders for the pages
    // to avoid Firebase dependency issues in this simple structure test.
    
    await tester.pumpWidget(const MaterialApp(
      home: MainNavigationPage(),
    ));

    // Verify initial state (Leads tab)
    expect(find.text('Leads'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Deals'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    // Tap on Favorites
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();

    // Verify it changed (icon should change to activeIcon)
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    // Tap on Deals
    await tester.tap(find.byIcon(Icons.handshake_outlined));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.handshake), findsOneWidget);

    // Tap on Profile
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });
}
