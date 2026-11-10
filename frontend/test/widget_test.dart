import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/core/theme/app_theme.dart';
import 'package:lead_generation_app/core/theme/theme_controller.dart';
import 'package:lead_generation_app/main.dart';

void main() {
  testWidgets('Admin shell lists every module in its group and loads the Dashboard', (tester) async {
    tester.view.physicalSize = const Size(1400, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(LeadGenerationApp(themeController: ThemeController(initial: ThemeMode.light)));
    // Network calls fail immediately under the test binding, so the
    // dashboard should settle straight into its error state rather than
    // hang or throw.
    await tester.pumpAndSettle();

    for (final group in ['OVERVIEW', 'LEAD GENERATION', 'LEADS', 'MANAGEMENT', 'SYSTEM']) {
      expect(find.text(group), findsOneWidget, reason: '$group nav group');
    }
    for (final label in [
      'Dashboard',
      '1-Star Scan',
      'No-Website Scan',
      'Jobs Finder',
      '1-Star Reviews',
      'No Website',
      'Email Leads',
      'WhatsApp Verified',
      'Scan Archive',
      'More',
    ]) {
      expect(find.text(label), findsWidgets, reason: '$label nav item');
    }
    // Removed in the simplification and never reinstated.
    expect(find.text('Outreach'), findsNothing);
  });

  testWidgets('Switching to dark mode swaps the palette and rebuilds the tree', (tester) async {
    tester.view.physicalSize = const Size(1400, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = ThemeController(initial: ThemeMode.light);
    await tester.pumpWidget(LeadGenerationApp(themeController: controller));
    await tester.pumpAndSettle();
    expect(AppTheme.isDark, isFalse);

    await tester.tap(find.text('Dark mode').first);
    await tester.pumpAndSettle();

    expect(AppTheme.isDark, isTrue);
    expect(find.text('Light mode'), findsWidgets);
    expect(tester.takeException(), isNull);

    controller.setMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(AppTheme.isDark, isFalse);
  });
}
