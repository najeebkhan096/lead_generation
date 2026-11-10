import 'package:flutter/material.dart';

/// One nine-step tonal ramp. Steps are named by ROLE, not by lightness, so the
/// same name works in light and dark mode:
///
///  * `s100` – the faintest tint (a tinted surface, a hover fill)
///  * `s200` – a tint border / pressed fill
///  * `s300` – a stronger border on a tint
///  * `s400` – a mid tone (icons on a tint, subtle strokes)
///  * `s500` – the SOLID color (buttons, bars, dots) – white text sits on it
///  * `s600` – the solid color's hover / pressed state
///  * `s700` – text and icons ON a tint (`s100`)
///  * `s800` – strong text on a tint
///  * `s900` – the deepest tone
class Ramp {
  const Ramp({
    required this.s100,
    required this.s200,
    required this.s300,
    required this.s400,
    required this.s500,
    required this.s600,
    required this.s700,
    required this.s800,
    required this.s900,
  });

  final Color s100, s200, s300, s400, s500, s600, s700, s800, s900;
}

/// Every color the console uses, for one brightness. The values are plain data;
/// [AppTheme] decides which palette is live and the rest of the app reads
/// colors only through `AppTheme.<token>` – never a raw hex in a widget.
///
/// Dark mode is its own designed palette (deep navy surfaces, lifted accents,
/// borders instead of shadows), not an inverted light one.
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.sidebar,
    required this.sidebarSurface,
    required this.onSidebar,
    required this.onSidebarMuted,
    required this.sidebarAccent,
    required this.sidebarIndicator,
    required this.neutral,
    required this.primary,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.onPrimary,
    required this.shadow,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });

  final Brightness brightness;

  /// The page behind everything.
  final Color background;

  /// Cards, tables, inputs and dialogs.
  final Color surface;

  /// Surfaces that float above [surface]: menus, popovers, dialogs.
  final Color surfaceElevated;

  /// The navigation rail: deep navy in both themes.
  final Color sidebar;

  /// Hover / selected fill inside the navigation rail.
  final Color sidebarSurface;
  final Color onSidebar;
  final Color onSidebarMuted;

  /// Icon color of the selected nav item, and its left indicator bar.
  final Color sidebarAccent;
  final Color sidebarIndicator;

  final Ramp neutral;
  final Ramp primary;
  final Ramp success;
  final Ramp warning;
  final Ramp error;
  final Ramp info;

  /// Text on a solid [primary] fill.
  final Color onPrimary;

  /// Card shadow color (transparent where a border does the job).
  final Color shadow;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  bool get isDark => brightness == Brightness.dark;

  // ── Light: white surfaces on a cool grey page, deep-navy sidebar ──────
  static const light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF6F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    sidebar: Color(0xFF0F172A),
    sidebarSurface: Color(0xFF1E293B),
    onSidebar: Color(0xFFF1F5F9),
    onSidebarMuted: Color(0xFF94A3B8),
    sidebarAccent: Color(0xFFA5B4FC),
    sidebarIndicator: Color(0xFF818CF8),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF5B6B82),
    onPrimary: Color(0xFFFFFFFF),
    shadow: Color(0x0F101828),
    neutral: Ramp(
      s100: Color(0xFFF1F5F9),
      s200: Color(0xFFE2E8F0),
      s300: Color(0xFFCBD5E1),
      s400: Color(0xFF94A3B8),
      s500: Color(0xFF5B6B82),
      s600: Color(0xFF475569),
      s700: Color(0xFF334155),
      s800: Color(0xFF1E293B),
      s900: Color(0xFF0F172A),
    ),
    primary: Ramp(
      s100: Color(0xFFEEF2FF),
      s200: Color(0xFFE0E7FF),
      s300: Color(0xFFC7D2FE),
      s400: Color(0xFF818CF8),
      s500: Color(0xFF4F46E5),
      s600: Color(0xFF4338CA),
      s700: Color(0xFF3730A3),
      s800: Color(0xFF312E81),
      s900: Color(0xFF1E1B4B),
    ),
    success: Ramp(
      s100: Color(0xFFECFDF3),
      s200: Color(0xFFD1FADF),
      s300: Color(0xFFA6F4C5),
      s400: Color(0xFF6CE9A6),
      s500: Color(0xFF12B76A),
      s600: Color(0xFF079455),
      s700: Color(0xFF027A48),
      s800: Color(0xFF05603A),
      s900: Color(0xFF054F31),
    ),
    warning: Ramp(
      s100: Color(0xFFFFFAEB),
      s200: Color(0xFFFEF0C7),
      s300: Color(0xFFFEDF89),
      s400: Color(0xFFFEC84B),
      s500: Color(0xFFF79009),
      s600: Color(0xFFDC6803),
      s700: Color(0xFFB54708),
      s800: Color(0xFF93370D),
      s900: Color(0xFF7A2E0E),
    ),
    error: Ramp(
      s100: Color(0xFFFEF3F2),
      s200: Color(0xFFFEE4E2),
      s300: Color(0xFFFECDCA),
      s400: Color(0xFFF97066),
      s500: Color(0xFFD92D20),
      s600: Color(0xFFB42318),
      s700: Color(0xFFB42318),
      s800: Color(0xFF912018),
      s900: Color(0xFF7A271A),
    ),
    info: Ramp(
      s100: Color(0xFFEFF8FF),
      s200: Color(0xFFD1E9FF),
      s300: Color(0xFFB2DDFF),
      s400: Color(0xFF53B1FD),
      s500: Color(0xFF1570EF),
      s600: Color(0xFF175CD3),
      s700: Color(0xFF175CD3),
      s800: Color(0xFF1849A9),
      s900: Color(0xFF194185),
    ),
  );

  // ── Dark: navy surfaces, tints become deep washes, text lifts ─────────
  static const dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0B1020),
    surface: Color(0xFF121A2E),
    surfaceElevated: Color(0xFF1A2440),
    sidebar: Color(0xFF080D1A),
    sidebarSurface: Color(0xFF16203A),
    onSidebar: Color(0xFFE8ECF6),
    onSidebarMuted: Color(0xFF8793B0),
    sidebarAccent: Color(0xFFA5B4FC),
    sidebarIndicator: Color(0xFF818CF8),
    textPrimary: Color(0xFFEEF1F8),
    textSecondary: Color(0xFFB4BDD2),
    textMuted: Color(0xFF8A95B0),
    onPrimary: Color(0xFFFFFFFF),
    shadow: Color(0x00000000),
    neutral: Ramp(
      s100: Color(0xFF1A2440),
      s200: Color(0xFF26314F),
      s300: Color(0xFF36426A),
      s400: Color(0xFF5B6891),
      s500: Color(0xFF8A95B0),
      s600: Color(0xFFA3ADC6),
      s700: Color(0xFFBBC3D6),
      s800: Color(0xFFD5DAE7),
      s900: Color(0xFFEEF1F8),
    ),
    primary: Ramp(
      s100: Color(0xFF1C2150),
      s200: Color(0xFF272D6E),
      s300: Color(0xFF3A42A0),
      s400: Color(0xFF6C74F2),
      s500: Color(0xFF5B5FEE),
      s600: Color(0xFF7378F4),
      s700: Color(0xFFA5ABFD),
      s800: Color(0xFFC4C8FE),
      s900: Color(0xFFE0E2FF),
    ),
    success: Ramp(
      s100: Color(0xFF0E2A20),
      s200: Color(0xFF123C2C),
      s300: Color(0xFF1A5A41),
      s400: Color(0xFF2FA06E),
      s500: Color(0xFF22B573),
      s600: Color(0xFF3CCB88),
      s700: Color(0xFF6CE9A6),
      s800: Color(0xFFA6F4C5),
      s900: Color(0xFFD1FADF),
    ),
    warning: Ramp(
      s100: Color(0xFF2E2108),
      s200: Color(0xFF42300A),
      s300: Color(0xFF69490C),
      s400: Color(0xFFC98A0A),
      s500: Color(0xFFE59A0C),
      s600: Color(0xFFF2AC2B),
      s700: Color(0xFFFEC84B),
      s800: Color(0xFFFEDF89),
      s900: Color(0xFFFEF0C7),
    ),
    error: Ramp(
      s100: Color(0xFF35141A),
      s200: Color(0xFF4A1B22),
      s300: Color(0xFF732A33),
      s400: Color(0xFFE5484D),
      s500: Color(0xFFE5484D),
      s600: Color(0xFFF2686C),
      s700: Color(0xFFFF9C9A),
      s800: Color(0xFFFFC2C0),
      s900: Color(0xFFFFE0DE),
    ),
    info: Ramp(
      s100: Color(0xFF0E2340),
      s200: Color(0xFF123259),
      s300: Color(0xFF1B4C8C),
      s400: Color(0xFF3B8BEA),
      s500: Color(0xFF3B82F6),
      s600: Color(0xFF5B9BF8),
      s700: Color(0xFF8DBBFB),
      s800: Color(0xFFB7D3FD),
      s900: Color(0xFFDBE8FE),
    ),
  );
}
