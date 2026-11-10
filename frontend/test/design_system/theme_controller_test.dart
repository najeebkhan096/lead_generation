import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/core/theme/app_palette.dart';
import 'package:lead_generation_app/core/theme/app_theme.dart';
import 'package:lead_generation_app/core/theme/prefs_storage.dart';
import 'package:lead_generation_app/core/theme/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AppTheme.palette = AppPalette.light);

  test('tokens follow the live palette', () {
    AppTheme.palette = AppPalette.light;
    final lightSurface = AppTheme.surface;
    final lightText = AppTheme.textPrimary;
    AppTheme.palette = AppPalette.dark;
    expect(AppTheme.surface, isNot(lightSurface));
    expect(AppTheme.textPrimary, isNot(lightText));
    expect(AppTheme.isDark, isTrue);
  });

  test('the sidebar stays navy in both themes', () {
    expect(AppPalette.light.sidebar.computeLuminance(), lessThan(0.05));
    expect(AppPalette.dark.sidebar.computeLuminance(), lessThan(0.05));
  });

  test('text meets contrast on its surface in both themes (WCAG AA, 4.5:1)', () {
    double ratio(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
    }

    for (final p in [AppPalette.light, AppPalette.dark]) {
      for (final surface in [p.surface, p.background]) {
        expect(ratio(p.textPrimary, surface), greaterThanOrEqualTo(4.5), reason: 'primary text, ${p.brightness}');
        expect(ratio(p.textSecondary, surface), greaterThanOrEqualTo(4.5), reason: 'secondary text, ${p.brightness}');
        expect(ratio(p.textMuted, surface), greaterThanOrEqualTo(4.5), reason: 'muted text, ${p.brightness}');
      }
      // Text on a solid brand button.
      expect(ratio(p.onPrimary, p.primary.s500), greaterThanOrEqualTo(4.5), reason: 'button label, ${p.brightness}');
      // Semantic text on its own tint.
      for (final r in [p.primary, p.success, p.warning, p.error, p.info]) {
        expect(ratio(r.s700, r.s100), greaterThanOrEqualTo(4.5), reason: 'tone text, ${p.brightness}');
      }
      // Sidebar labels.
      expect(ratio(p.onSidebarMuted, p.sidebar), greaterThanOrEqualTo(4.5), reason: 'sidebar text, ${p.brightness}');
    }
  });

  testWidgets('setMode swaps the palette, remembers the choice and notifies', (tester) async {
    PrefsStorage.write('leadfinder.themeMode', 'light');
    final controller = ThemeController();
    addTearDown(controller.dispose);
    expect(controller.mode, ThemeMode.light);
    expect(AppTheme.isDark, isFalse);

    var notified = 0;
    controller.addListener(() => notified++);
    controller.setMode(ThemeMode.dark);
    expect(AppTheme.isDark, isTrue);
    expect(PrefsStorage.read('leadfinder.themeMode'), 'dark');
    expect(notified, 1);

    controller.setMode(ThemeMode.dark); // no change → no notification
    expect(notified, 1);

    controller.toggle();
    expect(AppTheme.isDark, isFalse);
    expect(PrefsStorage.read('leadfinder.themeMode'), 'light');
  });

  testWidgets('a saved choice is restored by a new controller', (tester) async {
    PrefsStorage.write('leadfinder.themeMode', 'dark');
    final controller = ThemeController();
    addTearDown(controller.dispose);
    expect(controller.mode, ThemeMode.dark);
    expect(AppTheme.isDark, isTrue);
  });

  testWidgets('both ThemeData builds are complete Material 3 themes', (tester) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.primary, isNotNull);
      expect(theme.textTheme.bodyMedium?.fontFamily, contains('Inter'));
    }
    expect(AppTheme.dark().brightness, Brightness.dark);
  });
}
