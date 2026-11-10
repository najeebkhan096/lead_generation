import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'app_palette.dart';

/// The console's design tokens and its [ThemeData].
///
/// Every color, radius, space and shadow a widget uses comes from here — never
/// a raw hex or `Colors.x` in a page. Colors are *getters* that read the live
/// [AppPalette], so the same `AppTheme.surface` is white in light mode and
/// navy in dark mode. [ThemeController] switches the palette and rebuilds the
/// tree; see theme_controller.dart.
///
/// Scales (named by role, see [Ramp]): `neutral`, `primary`, `success`,
/// `warning`, `error`, `info`, each `100`…`900`.
class AppTheme {
  AppTheme._();

  /// The palette in use. Set by [ThemeController] (and tests).
  static AppPalette palette = AppPalette.light;
  static AppPalette get _p => palette;
  static Brightness get brightness => _p.brightness;
  static bool get isDark => _p.isDark;

  // ── Surfaces ──────────────────────────────────────────────────
  static Color get background => _p.background;
  static Color get surface => _p.surface;
  static Color get surfaceElevated => _p.surfaceElevated;
  static Color get sidebar => _p.sidebar;
  static Color get sidebarSurface => _p.sidebarSurface;
  static Color get onSidebar => _p.onSidebar;
  static Color get onSidebarMuted => _p.onSidebarMuted;
  static Color get sidebarAccent => _p.sidebarAccent;
  static Color get sidebarIndicator => _p.sidebarIndicator;

  // ── Lines ─────────────────────────────────────────────────────
  static Color get border => _p.neutral.s200;
  static Color get borderStrong => _p.neutral.s300;
  static Color get divider => _p.neutral.s200;

  // ── Text ──────────────────────────────────────────────────────
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textMuted => _p.textMuted;
  static Color get onPrimary => _p.onPrimary;

  // ── Brand & semantic (solid colors) ───────────────────────────
  static Color get primary => _p.primary.s500;
  static Color get primaryHover => _p.primary.s600;
  static Color get primarySurface => _p.primary.s100;
  static Color get secondary => _p.neutral.s700;
  static Color get success => _p.success.s500;
  static Color get warning => _p.warning.s500;
  static Color get error => _p.error.s500;
  static Color get info => _p.info.s500;

  // ── Scales ────────────────────────────────────────────────────
  static Color get neutral100 => _p.neutral.s100;
  static Color get neutral200 => _p.neutral.s200;
  static Color get neutral300 => _p.neutral.s300;
  static Color get neutral400 => _p.neutral.s400;
  static Color get neutral500 => _p.neutral.s500;
  static Color get neutral600 => _p.neutral.s600;
  static Color get neutral700 => _p.neutral.s700;
  static Color get neutral800 => _p.neutral.s800;
  static Color get neutral900 => _p.neutral.s900;

  static Color get primary100 => _p.primary.s100;
  static Color get primary200 => _p.primary.s200;
  static Color get primary300 => _p.primary.s300;
  static Color get primary400 => _p.primary.s400;
  static Color get primary500 => _p.primary.s500;
  static Color get primary600 => _p.primary.s600;
  static Color get primary700 => _p.primary.s700;
  static Color get primary800 => _p.primary.s800;
  static Color get primary900 => _p.primary.s900;

  static Color get success100 => _p.success.s100;
  static Color get success200 => _p.success.s200;
  static Color get success300 => _p.success.s300;
  static Color get success400 => _p.success.s400;
  static Color get success500 => _p.success.s500;
  static Color get success600 => _p.success.s600;
  static Color get success700 => _p.success.s700;
  static Color get success800 => _p.success.s800;
  static Color get success900 => _p.success.s900;

  static Color get warning100 => _p.warning.s100;
  static Color get warning200 => _p.warning.s200;
  static Color get warning300 => _p.warning.s300;
  static Color get warning400 => _p.warning.s400;
  static Color get warning500 => _p.warning.s500;
  static Color get warning600 => _p.warning.s600;
  static Color get warning700 => _p.warning.s700;
  static Color get warning800 => _p.warning.s800;
  static Color get warning900 => _p.warning.s900;

  static Color get error100 => _p.error.s100;
  static Color get error200 => _p.error.s200;
  static Color get error300 => _p.error.s300;
  static Color get error400 => _p.error.s400;
  static Color get error500 => _p.error.s500;
  static Color get error600 => _p.error.s600;
  static Color get error700 => _p.error.s700;
  static Color get error800 => _p.error.s800;
  static Color get error900 => _p.error.s900;

  static Color get info100 => _p.info.s100;
  static Color get info200 => _p.info.s200;
  static Color get info300 => _p.info.s300;
  static Color get info400 => _p.info.s400;
  static Color get info500 => _p.info.s500;
  static Color get info600 => _p.info.s600;
  static Color get info700 => _p.info.s700;
  static Color get info800 => _p.info.s800;
  static Color get info900 => _p.info.s900;

  // ── Shape: a small, consistent radius scale ───────────────────
  static const double radiusXs = 4;
  static const double radiusSm = 6;

  /// Buttons, inputs, menu items.
  static const double radius = 8;
  static const double radiusMd = 10;

  /// Cards, tables, panels.
  static const double radiusCard = 12;

  /// Dialogs and sheets.
  static const double radiusLg = 16;

  /// Badges, progress bars, avatars only.
  static const double radiusPill = 999;

  // ── Elevation ─────────────────────────────────────────────────
  /// A resting card: a hairline of shadow (none in dark mode, where the
  /// border alone separates surfaces).
  static List<BoxShadow> get shadowCard => [
        BoxShadow(color: _p.shadow, blurRadius: 2, offset: const Offset(0, 1)),
      ];

  /// A hovered / raised card.
  static List<BoxShadow> get shadowRaised => [
        BoxShadow(color: _p.shadow, blurRadius: 12, offset: const Offset(0, 4)),
        BoxShadow(color: _p.shadow, blurRadius: 3, offset: const Offset(0, 1)),
      ];

  /// Menus, popovers, dialogs.
  static List<BoxShadow> get shadowPopover => [
        BoxShadow(
          color: _p.isDark ? const Color(0x66000000) : const Color(0x1F101828),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  /// The standard card surface: fill, hairline border, 12px radius, resting shadow.
  static BoxDecoration cardDecoration({Color? color, Color? borderColor}) => BoxDecoration(
        color: color ?? surface,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: borderColor ?? border),
        boxShadow: shadowCard,
      );

  static ThemeData light() => _build(AppPalette.light);
  static ThemeData dark() => _build(AppPalette.dark);

  static ThemeData _build(AppPalette p) {
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.primary.s500,
      onPrimary: p.onPrimary,
      primaryContainer: p.primary.s100,
      onPrimaryContainer: p.primary.s800,
      secondary: p.neutral.s700,
      onSecondary: p.surface,
      secondaryContainer: p.neutral.s100,
      onSecondaryContainer: p.neutral.s800,
      tertiary: p.info.s500,
      onTertiary: Colors.white,
      error: p.error.s500,
      onError: Colors.white,
      errorContainer: p.error.s100,
      onErrorContainer: p.error.s700,
      surface: p.surface,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surfaceElevated,
      surfaceContainerHighest: p.neutral.s100,
      outline: p.neutral.s300,
      outlineVariant: p.neutral.s200,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: p.neutral.s900,
      onInverseSurface: p.background,
      inversePrimary: p.primary.s400,
    );

    final base = ThemeData(brightness: p.brightness, useMaterial3: true, colorScheme: scheme);
    final text = AppText.theme(p, base.textTheme);

    RoundedRectangleBorder rect([double r = radius]) =>
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

    OutlineInputBorder outline(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: c, width: w),
        );

    final focusRing = p.primary.s500.withValues(alpha: 0.18);

    return base.copyWith(
      scaffoldBackgroundColor: p.background,
      canvasColor: p.surface,
      splashFactory: InkRipple.splashFactory,
      splashColor: p.primary.s500.withValues(alpha: 0.06),
      highlightColor: p.primary.s500.withValues(alpha: 0.04),
      hoverColor: p.neutral.s100,
      focusColor: focusRing,
      disabledColor: p.textMuted.withValues(alpha: 0.5),
      dividerColor: p.neutral.s200,
      textTheme: text,
      primaryTextTheme: text,
      iconTheme: IconThemeData(color: p.textSecondary, size: 20),
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: 60,
        titleSpacing: 20,
        actionsPadding: const EdgeInsets.only(right: AppSpace.lg),
        shape: Border(bottom: BorderSide(color: p.neutral.s200)),
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: p.textSecondary, size: 20),
        actionsIconTheme: IconThemeData(color: p.textSecondary, size: 20),
      ),
      // ── Buttons ─────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(style: _filledStyle(p, text)),
      filledButtonTheme: FilledButtonThemeData(style: _filledStyle(p, text)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled) ? p.textMuted.withValues(alpha: 0.6) : p.textPrimary),
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return Colors.transparent;
            if (s.contains(WidgetState.pressed)) return p.neutral.s200;
            if (s.contains(WidgetState.hovered)) return p.neutral.s100;
            return p.surface;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(64, 40)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
          shape: WidgetStatePropertyAll(rect()),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          iconSize: const WidgetStatePropertyAll(18),
          side: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.focused)) return BorderSide(color: p.primary.s500, width: 2);
            if (s.contains(WidgetState.disabled)) return BorderSide(color: p.neutral.s200);
            return BorderSide(color: p.neutral.s300);
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return p.textMuted.withValues(alpha: 0.6);
            return s.contains(WidgetState.pressed) ? p.primary.s800 : p.primary.s700;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.pressed)) return p.primary.s200;
            if (s.contains(WidgetState.hovered)) return p.primary.s100;
            return Colors.transparent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          minimumSize: const WidgetStatePropertyAll(Size(48, 36)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          shape: WidgetStatePropertyAll(rect()),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          iconSize: const WidgetStatePropertyAll(18),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled) ? p.textMuted.withValues(alpha: 0.5) : p.textSecondary),
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.pressed)) return p.neutral.s200;
            if (s.contains(WidgetState.hovered)) return p.neutral.s100;
            return null;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          minimumSize: const WidgetStatePropertyAll(Size(36, 36)),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
          iconSize: const WidgetStatePropertyAll(20),
          shape: WidgetStatePropertyAll(rect()),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(rect()),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          side: WidgetStatePropertyAll(BorderSide(color: p.neutral.s300)),
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? p.primary.s800 : p.textSecondary),
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? p.primary.s100 : p.surface),
        ),
      ),
      // ── Inputs ──────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        labelStyle: text.bodyMedium?.copyWith(color: p.textSecondary),
        floatingLabelStyle: text.labelMedium?.copyWith(color: p.primary.s700),
        hintStyle: text.bodyMedium?.copyWith(color: p.textMuted),
        helperStyle: text.bodySmall,
        errorStyle: text.bodySmall?.copyWith(color: p.error.s600),
        prefixIconColor: p.textMuted,
        suffixIconColor: p.textMuted,
        border: outline(p.neutral.s300),
        enabledBorder: outline(p.neutral.s300),
        disabledBorder: outline(p.neutral.s200),
        focusedBorder: outline(p.primary.s500, 1.6),
        errorBorder: outline(p.error.s500),
        focusedErrorBorder: outline(p.error.s500, 1.6),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.primary.s500,
        selectionColor: p.primary.s500.withValues(alpha: 0.25),
        selectionHandleColor: p.primary.s500,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: text.bodyMedium?.copyWith(color: p.textPrimary),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.surfaceElevated),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(8),
          shadowColor: WidgetStatePropertyAll(p.isDark ? Colors.black : const Color(0x33101828)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
              side: BorderSide(color: p.neutral.s200),
            ),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: p.isDark ? Colors.black : const Color(0x33101828),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: p.neutral.s200),
        ),
        textStyle: text.bodyMedium?.copyWith(color: p.textPrimary),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.surfaceElevated),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
              side: BorderSide(color: p.neutral.s200),
            ),
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXs)),
        side: BorderSide(color: p.neutral.s400, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.primary.s500 : Colors.transparent),
        checkColor: WidgetStatePropertyAll(p.onPrimary),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.primary.s500 : p.neutral.s400),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : p.neutral.s400),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.primary.s500 : p.neutral.s200),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.primary.s500,
        inactiveTrackColor: p.neutral.s200,
        thumbColor: p.primary.s500,
        overlayColor: focusRing,
      ),
      // ── Chips, tabs ─────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: p.neutral.s100,
        selectedColor: p.primary.s100,
        disabledColor: p.neutral.s100,
        labelStyle: text.labelMedium?.copyWith(color: p.textPrimary),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: p.primary.s800),
        side: BorderSide(color: p.neutral.s200),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.primary.s700,
        unselectedLabelColor: p.textMuted,
        indicatorColor: p.primary.s500,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: p.neutral.s200,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge,
        overlayColor: WidgetStatePropertyAll(p.neutral.s100),
      ),
      // ── Feedback & overlays ─────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.isDark ? p.surfaceElevated : p.neutral.s900,
        contentTextStyle: text.bodyMedium?.copyWith(color: p.isDark ? p.textPrimary : Colors.white),
        actionTextColor: p.isDark ? p.primary.s700 : p.primary.s300,
        behavior: SnackBarBehavior.floating,
        width: 440,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: p.isDark ? BorderSide(color: p.neutral.s200) : BorderSide.none,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: p.isDark ? Colors.black : const Color(0x33101828),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: p.neutral.s200),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surfaceElevated,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg))),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.isDark ? p.neutral.s300 : p.neutral.s900,
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        textStyle: text.labelSmall?.copyWith(color: Colors.white),
        waitDuration: const Duration(milliseconds: 400),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary.s500,
        circularTrackColor: p.primary.s100,
        linearTrackColor: p.neutral.s200,
        linearMinHeight: 6,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(p.neutral.s300),
        radius: const Radius.circular(radiusPill),
        thickness: const WidgetStatePropertyAll(6),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
        shape: rect(),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: p.neutral.s200),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.neutral.s200, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.primary.s100,
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
      ),
    );
  }

  static ButtonStyle _filledStyle(AppPalette p, TextTheme text) => ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return p.primary.s500.withValues(alpha: 0.4);
          if (s.contains(WidgetState.pressed)) return p.primary.s700;
          if (s.contains(WidgetState.hovered)) return p.primary.s600;
          return p.primary.s500;
        }),
        foregroundColor: WidgetStatePropertyAll(p.onPrimary),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        minimumSize: const WidgetStatePropertyAll(Size(64, 40)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius))),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        iconSize: const WidgetStatePropertyAll(18),
        side: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.focused) ? BorderSide(color: p.primary.s300, width: 2) : BorderSide.none),
      );
}

/// The type scale. Inter throughout; figures are tabular so columns of numbers
/// line up. Page code asks for a style by role (`Theme.of(context).textTheme`),
/// the roles map as:
///
///  * `displaySmall`  – page title
///  * `headlineSmall` – section heading
///  * `titleMedium`   – card title
///  * `titleSmall`    – row title, table header emphasis
///  * `bodyMedium`    – body / table content
///  * `bodySmall`     – caption
///  * `labelLarge`    – buttons; `labelMedium` – field labels; `labelSmall` – badges
///  * [AppText.stat]  – the big number on a stat card
class AppText {
  AppText._();

  static const _tabular = [FontFeature.tabularFigures()];

  static TextTheme theme(AppPalette p, TextTheme base) {
    TextStyle inter(double size, FontWeight weight, Color color, {double? height, double spacing = 0}) =>
        GoogleFonts.inter(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: height,
          letterSpacing: spacing,
        );

    return GoogleFonts.interTextTheme(base).copyWith(
      displayLarge: inter(32, FontWeight.w700, p.textPrimary, height: 1.2, spacing: -0.6),
      displayMedium: inter(28, FontWeight.w700, p.textPrimary, height: 1.2, spacing: -0.5),
      displaySmall: inter(24, FontWeight.w700, p.textPrimary, height: 1.25, spacing: -0.4),
      headlineMedium: inter(20, FontWeight.w700, p.textPrimary, height: 1.3, spacing: -0.3),
      headlineSmall: inter(18, FontWeight.w600, p.textPrimary, height: 1.3, spacing: -0.2),
      titleLarge: inter(17, FontWeight.w600, p.textPrimary, height: 1.3, spacing: -0.2),
      titleMedium: inter(15, FontWeight.w600, p.textPrimary, height: 1.35, spacing: -0.1),
      titleSmall: inter(13.5, FontWeight.w600, p.textPrimary, height: 1.35),
      bodyLarge: inter(15, FontWeight.w400, p.textSecondary, height: 1.5),
      bodyMedium: inter(13.5, FontWeight.w400, p.textSecondary, height: 1.45),
      bodySmall: inter(12, FontWeight.w400, p.textMuted, height: 1.4),
      labelLarge: inter(13.5, FontWeight.w600, p.textPrimary, height: 1.2),
      labelMedium: inter(12, FontWeight.w600, p.textSecondary, height: 1.2),
      labelSmall: inter(11, FontWeight.w600, p.textSecondary, height: 1.2, spacing: 0.1),
    );
  }

  /// The headline number on a stat card.
  static TextStyle get stat => GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
        height: 1.1,
        letterSpacing: -0.6,
        fontFeatures: _tabular,
      );

  /// A table cell's text.
  static TextStyle get cell => GoogleFonts.inter(
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        color: AppTheme.textPrimary,
        height: 1.35,
        fontFeatures: _tabular,
      );

  /// A table column header.
  static TextStyle get columnHeader => GoogleFonts.inter(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.textMuted,
        letterSpacing: 0.4,
      );
}

/// Spacing tokens (4-pt grid). Pages use these instead of ad-hoc numbers.
class AppSpace {
  AppSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// The gutter around a page's content, by window width.
  static double pageGutter(double width) => width < 600 ? 16 : (width < 1024 ? 24 : 32);

  /// The widest a page's content grows, so lines stay readable on big screens.
  static const double pageMaxWidth = 1280;
}

/// Window breakpoints.
class AppBreakpoints {
  AppBreakpoints._();

  /// Below this the sidebar becomes a drawer.
  static const double mobile = 760;

  /// Below this the sidebar defaults to its icon rail.
  static const double compact = 1100;
}

/// Lucide icons at their regular stroke. Aliased here so pages never reach into
/// the raw package names.
class AppIcons {
  AppIcons._();

  static const dashboard = LucideIcons.layoutDashboard;
  static const leads = LucideIcons.building2;
  static const chat = LucideIcons.messageCircle;
  static const search = LucideIcons.search;
  static const plus = LucideIcons.plus;
  static const filter = LucideIcons.listFilter;
  static const chevronDown = LucideIcons.chevronDown;
  static const chevronUp = LucideIcons.chevronUp;
  static const chevronRight = LucideIcons.chevronRight;
  static const chevronLeft = LucideIcons.chevronLeft;
  static const mapPin = LucideIcons.mapPin;
  static const mapPinned = LucideIcons.mapPinned;
  static const star = LucideIcons.star;
  static const phone = LucideIcons.phone;
  static const globe = LucideIcons.globe;
  static const mail = LucideIcons.mail;
  static const tag = LucideIcons.tag;
  static const calendar = LucideIcons.calendar;
  static const clock = LucideIcons.clock;
  static const logIn = LucideIcons.logIn;
  static const check = LucideIcons.check;
  static const checkCircle = LucideIcons.circleCheck;
  static const alert = LucideIcons.circleAlert;
  static const refresh = LucideIcons.refreshCw;
  static const inbox = LucideIcons.inbox;
  static const searchX = LucideIcons.searchX;
  static const externalLink = LucideIcons.externalLink;
  static const sparkles = LucideIcons.sparkles;
  static const trendingUp = LucideIcons.trendingUp;
  static const users = LucideIcons.users;
  static const percent = LucideIcons.percent;
  static const copy = LucideIcons.copy;
  static const edit = LucideIcons.squarePen;
  static const download = LucideIcons.download;
  static const cloudUpload = LucideIcons.cloudUpload;
  static const arrowLeft = LucideIcons.arrowLeft;
  static const arrowUp = LucideIcons.arrowUp;
  static const arrowDown = LucideIcons.arrowDown;
  static const arrowUpDown = LucideIcons.arrowUpDown;
  static const close = LucideIcons.x;
  static const globe2 = LucideIcons.globe;
  static const barChart = LucideIcons.chartColumn;
  static const zap = LucideIcons.zap;
  static const flame = LucideIcons.flame;
  static const target = LucideIcons.target;
  static const award = LucideIcons.award;
  static const store = LucideIcons.store;
  static const thumbsDown = LucideIcons.thumbsDown;
  static const messageWarning = LucideIcons.messageSquareWarning;
  static const shieldCheck = LucideIcons.shieldCheck;
  static const badgeCheck = LucideIcons.badgeCheck;
  static const trash = LucideIcons.trash2;
  static const eye = LucideIcons.eye;
  static const settings = LucideIcons.settings;

  // Shell
  static const menu = LucideIcons.menu;
  static const panelLeft = LucideIcons.panelLeft;
  static const sun = LucideIcons.sun;
  static const moon = LucideIcons.moon;
  static const monitor = LucideIcons.monitor;
  static const folderArchive = LucideIcons.archive;
  static const layoutGrid = LucideIcons.layoutGrid;
  static const table = LucideIcons.table;
  static const wrench = LucideIcons.wrench;
  static const shield = LucideIcons.shield;

  // Jobs Finder
  static const briefcase = LucideIcons.briefcase;
  static const play = LucideIcons.play;
  static const pause = LucideIcons.pause;
  static const stop = LucideIcons.square;
  static const bookmark = LucideIcons.bookmark;
  static const send = LucideIcons.send;
  static const circleX = LucideIcons.circleX;
  static const more = LucideIcons.ellipsisVertical;
  static const building = LucideIcons.building;
  static const history = LucideIcons.history;
  static const key = LucideIcons.keyRound;
  static const link = LucideIcons.link;
  static const bell = LucideIcons.bell;
  static const fileText = LucideIcons.fileText;
  static const sliders = LucideIcons.slidersHorizontal;
  static const banknote = LucideIcons.banknote;
  static const graduationCap = LucideIcons.graduationCap;
  static const circleCheck = LucideIcons.circleCheck;
  static const triangleAlert = LucideIcons.triangleAlert;
  static const laptop = LucideIcons.laptop;
  static const layers = LucideIcons.layers;
}
