import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// "Clean modern" design language: cool white surfaces on a soft slate
/// ground, one indigo accent, an emerald for success, hairline borders
/// instead of shadows, Inter throughout.
///
/// Colors come from three ramps (slate, indigo, emerald). Widgets never read
/// ramp steps directly — they read semantic slots from [AppTokens] via
/// `context.tokens`, which resolves per brightness. The slot names
/// (`neutral*`, `accent*`, `sage*`) are historical: `sage*` is the success /
/// positive color, now emerald.
class AppTheme {
  AppTheme._();

  // ── Neutral ramp: slate ───────────────────────────────────────
  static const Color neutral100 = Color(0xFFF1F5F9);
  static const Color neutral200 = Color(0xFFE2E8F0);
  static const Color neutral300 = Color(0xFFCBD5E1);
  static const Color neutral400 = Color(0xFF94A3B8);
  static const Color neutral500 = Color(0xFF64748B);
  static const Color neutral600 = Color(0xFF475569);
  static const Color neutral700 = Color(0xFF334155);
  static const Color neutral800 = Color(0xFF1E293B);
  static const Color neutral900 = Color(0xFF0F172A);

  // ── Accent ramp: indigo ───────────────────────────────────────
  static const Color accent100 = Color(0xFFE0E7FF);
  static const Color accent200 = Color(0xFFC7D2FE);
  static const Color accent300 = Color(0xFFA5B4FC);
  static const Color accent400 = Color(0xFF818CF8);
  static const Color accent500 = Color(0xFF6366F1);
  static const Color accent600 = Color(0xFF4F46E5);
  static const Color accent700 = Color(0xFF4338CA);
  static const Color accent800 = Color(0xFF3730A3);
  static const Color accent900 = Color(0xFF312E81);

  // ── Success ramp: emerald (kept under the historical "sage" name) ─
  static const Color sage100 = Color(0xFFD1FAE5);
  static const Color sage200 = Color(0xFFA7F3D0);
  static const Color sage300 = Color(0xFF6EE7B7);
  static const Color sage400 = Color(0xFF34D399);
  static const Color sage500 = Color(0xFF10B981);
  static const Color sage600 = Color(0xFF059669);
  static const Color sage700 = Color(0xFF047857);
  static const Color sage800 = Color(0xFF065F46);
  static const Color sage900 = Color(0xFF064E3B);

  // ── Light anchors ─────────────────────────────────────────────
  static const Color _ground = Color(0xFFF6F7FB); // page background
  static const Color _surface = Color(0xFFFFFFFF); // cards, sheets
  static const Color _ink = Color(0xFF0F172A); // primary text
  static const Color _error = Color(0xFFDC2626);

  // ── Dark anchors (deep navy, same cool hue) ───────────────────
  static const Color _groundDark = Color(0xFF0B1020);
  static const Color _surfaceDark = Color(0xFF131A2E);
  static const Color _tintDark = Color(0xFF1B2440);
  static const Color _borderDark = Color(0xFF263052);
  static const Color _inkDark = Color(0xFFE8ECF8);
  static const Color _errorDark = Color(0xFFF87171);

  // ── Shape ─────────────────────────────────────────────────────
  /// Controls (buttons, inputs, chips, small blocks).
  static const double radius = 12;

  /// Cards and sheets.
  static const double radiusCard = 16;

  /// Badges and segmented pills.
  static const double radiusPill = 999;

  static const AppTokens lightTokens = AppTokens(
    ground: _ground,
    surface: _surface,
    ink: _ink,
    subtle: neutral600,
    // Slate-500 darkened a step so hints and timestamps clear 4.5:1 on the
    // ground and on tinted fills (theme_test checks every pair).
    faint: Color(0xFF5E6E86),
    neutralTint: neutral100,
    neutralTintStrong: neutral200,
    border: neutral200,
    accent: accent600,
    accentDeep: accent700,
    accentText: accent700,
    accentTextStrong: accent800,
    accentTint: Color(0xFFEEF2FF),
    sage: sage600,
    sageDeep: sage700,
    sageText: sage700,
    sageTextStrong: sage800,
    sageTint: Color(0xFFECFDF5),
    sageTintStrong: sage100,
    onFill: Colors.white,
    danger: _error,
  );

  static const AppTokens darkTokens = AppTokens(
    ground: _groundDark,
    surface: _surfaceDark,
    ink: _inkDark,
    subtle: Color(0xFFA9B4CE),
    faint: Color(0xFF8A97B5),
    neutralTint: _tintDark,
    neutralTintStrong: Color(0xFF232C4C),
    border: _borderDark,
    accent: accent400,
    accentDeep: accent300,
    accentText: accent300,
    accentTextStrong: accent200,
    accentTint: Color(0xFF1E2352),
    sage: sage400,
    sageDeep: sage300,
    sageText: sage300,
    sageTextStrong: sage200,
    sageTint: Color(0xFF0F2A22),
    sageTintStrong: Color(0xFF14382D),
    onFill: _groundDark,
    danger: _errorDark,
  );

  static ThemeData light() => _theme(Brightness.light, lightTokens);
  static ThemeData dark() => _theme(Brightness.dark, darkTokens);

  static ThemeData _theme(Brightness brightness, AppTokens t) {
    final isLight = brightness == Brightness.light;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: t.accent,
        onPrimary: t.onFill,
        primaryContainer: t.accentTint,
        onPrimaryContainer: t.accentTextStrong,
        secondary: t.sage,
        onSecondary: t.onFill,
        secondaryContainer: t.sageTint,
        onSecondaryContainer: t.sageTextStrong,
        surface: t.surface,
        onSurface: t.ink,
        onSurfaceVariant: t.subtle,
        outline: t.border,
        outlineVariant: t.neutralTintStrong,
        error: t.danger,
        onError: t.onFill,
        errorContainer: isLight ? const Color(0xFFFEF2F2) : const Color(0xFF3B1620),
        onErrorContainer: t.danger,
        inverseSurface: isLight ? neutral900 : _inkDark,
        onInverseSurface: isLight ? Colors.white : _groundDark,
        shadow: Colors.black,
        scrim: Colors.black,
        inversePrimary: isLight ? accent300 : accent700,
        surfaceTint: Colors.transparent,
      ),
      extensions: [t],
    );

    final body = GoogleFonts.interTextTheme(base.textTheme);
    TextStyle heading(double size, {FontWeight weight = FontWeight.w700}) => GoogleFonts.inter(
          fontSize: size,
          fontWeight: weight,
          color: t.ink,
          height: 1.2,
          letterSpacing: -0.4,
        );
    TextStyle text(double size, Color color, {FontWeight weight = FontWeight.w400, double height = 1.4}) =>
        GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: height);

    final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    OutlineInputBorder inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      scaffoldBackgroundColor: t.ground,
      splashColor: t.accent.withValues(alpha: 0.08),
      highlightColor: t.accent.withValues(alpha: 0.05),
      focusColor: t.accent.withValues(alpha: 0.14),
      disabledColor: t.ink.withValues(alpha: 0.4),
      dividerColor: t.border,
      dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
      textTheme: body.copyWith(
        displayLarge: heading(36, weight: FontWeight.w800),
        displayMedium: heading(30, weight: FontWeight.w800),
        displaySmall: heading(26, weight: FontWeight.w800),
        headlineMedium: heading(22),
        headlineSmall: heading(19),
        titleLarge: text(18, t.ink, weight: FontWeight.w700, height: 1.25),
        titleMedium: text(16, t.ink, weight: FontWeight.w700, height: 1.3),
        titleSmall: text(14, t.ink, weight: FontWeight.w600),
        bodyLarge: text(16, t.subtle, height: 1.5),
        bodyMedium: text(14, t.subtle, height: 1.45),
        bodySmall: text(12.5, t.faint, height: 1.4),
        labelLarge: text(15, t.ink, weight: FontWeight.w600),
      ),
      iconTheme: IconThemeData(color: t.ink, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: t.ground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: heading(20),
        iconTheme: IconThemeData(color: t.ink, size: 22),
      ),
      cardTheme: CardThemeData(
        color: t.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: t.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return t.accent.withValues(alpha: 0.4);
            if (states.contains(WidgetState.pressed)) return t.accentDeep;
            return t.accent;
          }),
          foregroundColor: WidgetStatePropertyAll(t.onFill),
          overlayColor: WidgetStatePropertyAll(t.onFill.withValues(alpha: 0.08)),
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(64, 50)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
          shape: WidgetStatePropertyAll(controlShape),
          textStyle: WidgetStatePropertyAll(text(15, t.onFill, weight: FontWeight.w600)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return t.accent.withValues(alpha: 0.4);
            if (states.contains(WidgetState.pressed)) return t.accentDeep;
            return t.accent;
          }),
          foregroundColor: WidgetStatePropertyAll(t.onFill),
          overlayColor: WidgetStatePropertyAll(t.onFill.withValues(alpha: 0.08)),
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(48, 46)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
          shape: WidgetStatePropertyAll(controlShape),
          textStyle: WidgetStatePropertyAll(text(14.5, t.onFill, weight: FontWeight.w600)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled) ? t.ink.withValues(alpha: 0.4) : t.ink),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.pressed) ? t.neutralTint : t.surface),
          overlayColor: WidgetStatePropertyAll(t.accent.withValues(alpha: 0.06)),
          minimumSize: const WidgetStatePropertyAll(Size(48, 46)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
          shape: WidgetStatePropertyAll(controlShape),
          textStyle: WidgetStatePropertyAll(text(14.5, t.ink, weight: FontWeight.w600)),
          side: WidgetStateProperty.resolveWith((states) => BorderSide(
                color: states.contains(WidgetState.focused) ? t.accent : (isLight ? neutral300 : t.border),
                width: states.contains(WidgetState.focused) ? 2 : 1,
              )),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.pressed) ? t.accentTextStrong : t.accentText),
          overlayColor: WidgetStatePropertyAll(t.accentTint),
          shape: WidgetStatePropertyAll(controlShape),
          textStyle: WidgetStatePropertyAll(text(14.5, t.accentText, weight: FontWeight.w600)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(controlShape),
          overlayColor: WidgetStatePropertyAll(t.accent.withValues(alpha: 0.08)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: text(15, t.subtle, weight: FontWeight.w500),
        hintStyle: text(15, t.faint),
        border: inputBorder(isLight ? neutral300 : t.border),
        enabledBorder: inputBorder(isLight ? neutral300 : t.border),
        focusedBorder: inputBorder(t.accent, 2),
        errorBorder: inputBorder(t.danger, 1.5),
        focusedErrorBorder: inputBorder(t.danger, 2),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(t.surface),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: BorderSide(color: t.border),
          )),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.surface,
        selectedColor: t.accentTint,
        labelStyle: text(13, t.subtle, weight: FontWeight.w600),
        secondaryLabelStyle: text(13, t.accentTextStrong, weight: FontWeight.w600),
        side: BorderSide(color: t.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        indicatorColor: t.accentTint,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 22,
              color: states.contains(WidgetState.selected) ? t.accentText : t.faint,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => text(
              12,
              states.contains(WidgetState.selected) ? t.accentText : t.faint,
              weight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            )),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: t.accentText,
        unselectedLabelColor: t.faint,
        indicatorColor: t.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: text(14, t.accentText, weight: FontWeight.w700),
        unselectedLabelStyle: text(14, t.faint, weight: FontWeight.w500),
        overlayColor: WidgetStatePropertyAll(t.accent.withValues(alpha: 0.06)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isLight ? neutral900 : t.neutralTintStrong,
        contentTextStyle: text(14, isLight ? Colors.white : _inkDark, weight: FontWeight.w500),
        actionTextColor: isLight ? accent300 : t.accentText,
        behavior: SnackBarBehavior.floating,
        shape: controlShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard + 4),
          side: BorderSide(color: t.border),
        ),
        titleTextStyle: heading(19),
        contentTextStyle: text(15, t.subtle, height: 1.45),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.accent,
        circularTrackColor: t.accentTint,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: t.subtle,
        titleTextStyle: text(15, t.ink, weight: FontWeight.w600),
        shape: controlShape,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? t.onFill : t.surface),
        trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? t.accent : t.neutralTintStrong),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}

/// Semantic color slots, resolved per brightness. Read via `context.tokens`.
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.ground,
    required this.surface,
    required this.ink,
    required this.subtle,
    required this.faint,
    required this.neutralTint,
    required this.neutralTintStrong,
    required this.border,
    required this.accent,
    required this.accentDeep,
    required this.accentText,
    required this.accentTextStrong,
    required this.accentTint,
    required this.sage,
    required this.sageDeep,
    required this.sageText,
    required this.sageTextStrong,
    required this.sageTint,
    required this.sageTintStrong,
    required this.onFill,
    required this.danger,
  });

  /// Page background.
  final Color ground;

  /// Raised cards and sheets.
  final Color surface;

  /// Primary text.
  final Color ink;

  /// Secondary body text.
  final Color subtle;

  /// Hints and timestamps.
  final Color faint;

  /// Quiet fills: icon circles, unselected pills.
  final Color neutralTint;

  /// Stronger quiet fills: state badges, sheet handles.
  final Color neutralTintStrong;

  /// Subtle strokes and empty rating stars.
  final Color border;

  /// Indigo base — buttons, icons, active states.
  final Color accent;

  /// One step past base, for pressed states and dark-mode icons.
  final Color accentDeep;

  /// Indigo text that is safe at body size on the ground.
  final Color accentText;

  /// Indigo text on [accentTint] fills.
  final Color accentTextStrong;

  /// Tinted indigo fill (badges, selected rows).
  final Color accentTint;

  /// Emerald base — the safe/positive/verified voice.
  final Color sage;
  final Color sageDeep;
  final Color sageText;
  final Color sageTextStrong;
  final Color sageTint;
  final Color sageTintStrong;

  /// Text/icons sitting on a filled accent or sage shape.
  final Color onFill;

  /// Errors and destructive actions.
  final Color danger;

  @override
  AppTokens copyWith({
    Color? ground,
    Color? surface,
    Color? ink,
    Color? subtle,
    Color? faint,
    Color? neutralTint,
    Color? neutralTintStrong,
    Color? border,
    Color? accent,
    Color? accentDeep,
    Color? accentText,
    Color? accentTextStrong,
    Color? accentTint,
    Color? sage,
    Color? sageDeep,
    Color? sageText,
    Color? sageTextStrong,
    Color? sageTint,
    Color? sageTintStrong,
    Color? onFill,
    Color? danger,
  }) {
    return AppTokens(
      ground: ground ?? this.ground,
      surface: surface ?? this.surface,
      ink: ink ?? this.ink,
      subtle: subtle ?? this.subtle,
      faint: faint ?? this.faint,
      neutralTint: neutralTint ?? this.neutralTint,
      neutralTintStrong: neutralTintStrong ?? this.neutralTintStrong,
      border: border ?? this.border,
      accent: accent ?? this.accent,
      accentDeep: accentDeep ?? this.accentDeep,
      accentText: accentText ?? this.accentText,
      accentTextStrong: accentTextStrong ?? this.accentTextStrong,
      accentTint: accentTint ?? this.accentTint,
      sage: sage ?? this.sage,
      sageDeep: sageDeep ?? this.sageDeep,
      sageText: sageText ?? this.sageText,
      sageTextStrong: sageTextStrong ?? this.sageTextStrong,
      sageTint: sageTint ?? this.sageTint,
      sageTintStrong: sageTintStrong ?? this.sageTintStrong,
      onFill: onFill ?? this.onFill,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      ground: mix(ground, other.ground),
      surface: mix(surface, other.surface),
      ink: mix(ink, other.ink),
      subtle: mix(subtle, other.subtle),
      faint: mix(faint, other.faint),
      neutralTint: mix(neutralTint, other.neutralTint),
      neutralTintStrong: mix(neutralTintStrong, other.neutralTintStrong),
      border: mix(border, other.border),
      accent: mix(accent, other.accent),
      accentDeep: mix(accentDeep, other.accentDeep),
      accentText: mix(accentText, other.accentText),
      accentTextStrong: mix(accentTextStrong, other.accentTextStrong),
      accentTint: mix(accentTint, other.accentTint),
      sage: mix(sage, other.sage),
      sageDeep: mix(sageDeep, other.sageDeep),
      sageText: mix(sageText, other.sageText),
      sageTextStrong: mix(sageTextStrong, other.sageTextStrong),
      sageTint: mix(sageTint, other.sageTint),
      sageTintStrong: mix(sageTintStrong, other.sageTintStrong),
      onFill: mix(onFill, other.onFill),
      danger: mix(danger, other.danger),
    );
  }
}

extension AppTokensContext on BuildContext {
  /// The active semantic color tokens (light or dark).
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
}

/// Lucide icons at the heaviest stroke the icon font ships (3.0 — nearest
/// to the design language's 2.75). Alias here so pages never reach into
/// the raw weight-suffixed names.
class AppIcons {
  AppIcons._();

  static const compass = LucideIcons.compass600;
  static const heart = LucideIcons.heart600;
  static const handshake = LucideIcons.handshake600;
  static const user = LucideIcons.userRound600;
  static const sparkles = LucideIcons.sparkles600;
  static const filter = LucideIcons.listFilter600;
  static const chevronDown = LucideIcons.chevronDown600;
  static const chevronRight = LucideIcons.chevronRight600;
  static const mapPin = LucideIcons.mapPin600;
  static const star = LucideIcons.star600;
  static const chat = LucideIcons.messageCircle600;
  static const more = LucideIcons.ellipsis600;
  static const send = LucideIcons.send600;
  static const calendarCheck = LucideIcons.calendarCheck600;
  static const packageCheck = LucideIcons.packageCheck600;
  static const circleCheck = LucideIcons.circleCheck600;
  static const check = LucideIcons.check600;
  static const inbox = LucideIcons.inbox600;
  static const search = LucideIcons.search600;
  static const searchX = LucideIcons.searchX600;
  static const x = LucideIcons.x600;
  static const alert = LucideIcons.circleAlert600;
  static const refresh = LucideIcons.refreshCw600;
  static const tag = LucideIcons.tag600;
  static const phone = LucideIcons.phone600;
  static const globe = LucideIcons.globe600;
  static const calendar = LucideIcons.calendar600;
  static const history = LucideIcons.history600;
  static const settings = LucideIcons.settings600;
  static const help = LucideIcons.circleHelp600;
  static const logOut = LucideIcons.logOut600;
  static const logIn = LucideIcons.logIn600;
  static const sprout = LucideIcons.sprout600;
  static const externalLink = LucideIcons.externalLink600;
  static const quote = LucideIcons.quote600;
  static const shieldCheck = LucideIcons.shieldCheck600;
  static const clock = LucideIcons.clock600;
  static const sun = LucideIcons.sun600;
  static const moon = LucideIcons.moon600;
  static const monitor = LucideIcons.monitor600;
  static const mail = LucideIcons.mail600;
  static const info = LucideIcons.info600;
  static const download = LucideIcons.download600;
  static const trash = LucideIcons.trash2600;
  static const wallet = LucideIcons.wallet600;
  static const hourglass = LucideIcons.hourglass600;
  static const edit = LucideIcons.pencil600;
  static const plus = LucideIcons.plus600;
  static const users = LucideIcons.users600;
  static const store = LucideIcons.store600;
  static const dashboard = LucideIcons.layoutDashboard600;
  static const banknote = LucideIcons.banknote600;
  static const trendingUp = LucideIcons.trendingUp600;
  static const userCheck = LucideIcons.userRoundCheck600;
  static const clipboardList = LucideIcons.clipboardList600;
  static const circleX = LucideIcons.circleX600;
}
