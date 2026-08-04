import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/theme/app_theme.dart';

void main() {
  group('AppTheme tokens', () {
    testWidgets('light theme resolves light tokens via context', (tester) async {
      late AppTokens tokens;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Builder(builder: (context) {
          tokens = context.tokens;
          return const SizedBox();
        }),
      ));

      expect(tokens.ground, const Color(0xFFF5EAD8));
      expect(tokens.ink, const Color(0xFF201E1D));
      expect(tokens.accent, AppTheme.accent500);
      expect(tokens.sage, AppTheme.sage500);
    });

    testWidgets('dark theme resolves warm dark tokens via context', (tester) async {
      late AppTokens tokens;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(builder: (context) {
          tokens = context.tokens;
          return const SizedBox();
        }),
      ));

      // Dark ground stays on the warm hue (cream text on deep brown, not grey).
      expect(tokens.ground, const Color(0xFF1A1711));
      expect(tokens.ink, const Color(0xFFF5EAD8));
      // Accents lighten one step for dark-surface contrast.
      expect(tokens.accent, AppTheme.accent400);
      expect(tokens.sage, AppTheme.sage400);
    });

    test('scaffold backgrounds come from the tokens', () {
      expect(AppTheme.light().scaffoldBackgroundColor,
          AppTheme.lightTokens.ground);
      expect(
          AppTheme.dark().scaffoldBackgroundColor, AppTheme.darkTokens.ground);
    });
  });
}
