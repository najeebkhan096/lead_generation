import 'dart:math' as math;

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

      expect(tokens.ground, const Color(0xFFF6F7FB));
      expect(tokens.surface, const Color(0xFFFFFFFF));
      expect(tokens.ink, const Color(0xFF0F172A));
      expect(tokens.accent, AppTheme.accent600); // indigo
      expect(tokens.sage, AppTheme.sage600); // emerald (success)
    });

    testWidgets('dark theme resolves deep navy tokens via context', (tester) async {
      late AppTokens tokens;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(builder: (context) {
          tokens = context.tokens;
          return const SizedBox();
        }),
      ));

      // Deep navy ground, near-white text.
      expect(tokens.ground, const Color(0xFF0B1020));
      expect(tokens.ink, const Color(0xFFE8ECF8));
      // Accents lighten for dark-surface contrast.
      expect(tokens.accent, AppTheme.accent400);
      expect(tokens.sage, AppTheme.sage400);
    });

    group('text contrast (WCAG AA, 4.5:1)', () {
      double luminance(Color c) {
        double channel(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
      }

      double contrast(Color a, Color b) {
        final la = luminance(a);
        final lb = luminance(b);
        final hi = math.max(la, lb);
        final lo = math.min(la, lb);
        return (hi + 0.05) / (lo + 0.05);
      }

      void check(String mode, AppTokens t) {
        final pairs = <String, (Color, Color)>{
          'ink on ground': (t.ink, t.ground),
          'ink on surface': (t.ink, t.surface),
          'subtle on ground': (t.subtle, t.ground),
          'subtle on surface': (t.subtle, t.surface),
          'faint on ground': (t.faint, t.ground),
          'faint on surface': (t.faint, t.surface),
          'faint on neutral tint': (t.faint, t.neutralTint),
          'accent text on ground': (t.accentText, t.ground),
          'accent text on surface': (t.accentText, t.surface),
          'accent text on accent tint': (t.accentTextStrong, t.accentTint),
          'accent pill text on accent tint': (t.accentText, t.accentTint),
          'neutral pill text on neutral tint': (t.subtle, t.neutralTint),
          'label on accent fill': (t.onFill, t.accent),
          'success text on success tint': (t.sageText, t.sageTint),
          'success text on surface': (t.sageText, t.surface),
          'danger on surface': (t.danger, t.surface),
          'danger on ground': (t.danger, t.ground),
        };
        for (final e in pairs.entries) {
          final ratio = contrast(e.value.$1, e.value.$2);
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '$mode: ${e.key} is ${ratio.toStringAsFixed(2)}:1');
        }
      }

      test('light theme', () => check('light', AppTheme.lightTokens));
      test('dark theme', () => check('dark', AppTheme.darkTokens));
    });

    test('scaffold backgrounds come from the tokens', () {
      expect(AppTheme.light().scaffoldBackgroundColor,
          AppTheme.lightTokens.ground);
      expect(
          AppTheme.dark().scaffoldBackgroundColor, AppTheme.darkTokens.ground);
    });
  });
}
