import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Warm, rounded "organic" design language.
///
/// All colors come from three OKLCH tonal ramps (neutral, accent, sage)
/// generated on a shared lightness scale. Never introduce ad-hoc hexes or
/// greys: neutrals stay warm in both light and dark mode.
///
/// Widgets never read ramp steps directly — they read semantic slots from
/// [AppTokens] via `context.tokens`, which resolves per brightness.
class AppTheme {
  AppTheme._();

  // ── Neutral ramp (warm, OKLCH h≈80) ───────────────────────────
  static const Color neutral100 = Color(0xFFF2ECE1);
  static const Color neutral200 = Color(0xFFE3DBCF);
  static const Color neutral300 = Color(0xFFCEC6B9);
  static const Color neutral400 = Color(0xFFACA396);
  static const Color neutral500 = Color(0xFF8C8375);
  static const Color neutral600 = Color(0xFF776F62);
  static const Color neutral700 = Color(0xFF5F584D);
  static const Color neutral800 = Color(0xFF464038);
  static const Color neutral900 = Color(0xFF2D2A24);

  // ── Accent ramp: terracotta (OKLCH h≈52) ──────────────────────
  static const Color accent100 = Color(0xFFFDE8DC);
  static const Color accent200 = Color(0xFFFBD3BC);
  static const Color accent300 = Color(0xFFF2B998);
  static const Color accent400 = Color(0xFFDB9063);
  static const Color accent500 = Color(0xFFC67139);
  static const Color accent600 = Color(0xFFA9561A);
  static const Color accent700 = Color(0xFF8C4101);
  static const Color accent800 = Color(0xFF682F00);
  static const Color accent900 = Color(0xFF451D00);

  // ── Accent-2 ramp: sage (OKLCH h≈125) ─────────────────────────
  static const Color sage100 = Color(0xFFEAEFE4);
  static const Color sage200 = Color(0xFFD8E0CC);
  static const Color sage300 = Color(0xFFC1CCB0);
  static const Color sage400 = Color(0xFF9DAB85);
  static const Color sage500 = Color(0xFF7A8A5E);
  static const Color sage600 = Color(0xFF68774C);
  static const Color sage700 = Color(0xFF526038);
  static const Color sage800 = Color(0xFF3A4624);
  static const Color sage900 = Color(0xFF252E13);

  // ── Light anchors ─────────────────────────────────────────────
  static const Color _cream = Color(0xFFF5EAD8); // brand ground
  static const Color _ink = Color(0xFF201E1D); // brand text
  static const Color _creamRaised = Color(0xFFFBF6EE); // oklch(.975 .012 80)

  // ── Dark anchors (same warm hue, deep lightness) ──────────────
  static const Color _groundDark = Color(0xFF1A1711); // oklch(.205 .012 80)
  static const Color _surfaceDark = Color(0xFF26221B); // oklch(.255 .014 80)
  static const Color _tintDark = Color(0xFF363129); // oklch(.315 .016 80)

  // ── Shape ─────────────────────────────────────────────────────
  static const double radius = 16;
  static const double radiusCard = 24;
  static const double radiusPill = 999;

  static const AppTokens lightTokens = AppTokens(
    ground: _cream,
    surface: _creamRaised,
    ink: _ink,
    subtle: neutral700,
    faint: neutral500,
    neutralTint: neutral100,
    neutralTintStrong: neutral200,
    border: neutral300,
    accent: accent500,
    accentDeep: accent600,
    accentText: accent700,
    accentTextStrong: accent800,
    accentTint: accent100,
    sage: sage500,
    sageDeep: sage600,
    sageText: sage700,
    sageTextStrong: sage800,
    sageTint: sage100,
    sageTintStrong: sage200,
    onFill: _creamRaised,
    danger: accent700,
  );

  static const AppTokens darkTokens = AppTokens(
    ground: _groundDark,
    surface: _surfaceDark,
    ink: _cream,
    subtle: neutral300,
    faint: neutral400,
    neutralTint: _tintDark,
    neutralTintStrong: neutral800,
    border: neutral600,
    accent: accent400,
    accentDeep: accent300,
    accentText: accent300,
    accentTextStrong: accent200,
    accentTint: accent900,
    sage: sage400,
    sageDeep: sage300,
    sageText: sage300,
    sageTextStrong: sage200,
    sageTint: sage900,
    sageTintStrong: sage800,
    onFill: _groundDark,
    danger: accent300,
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
        errorContainer: t.accentTint,
        onErrorContainer: t.accentTextStrong,
        inverseSurface: isLight ? neutral900 : _cream,
        onInverseSurface: isLight ? _cream : _ink,
        shadow: Colors.black,
        scrim: Colors.black,
        inversePrimary: isLight ? accent300 : accent700,
        surfaceTint: Colors.transparent,
      ),
      extensions: [t],
    );

    final body = GoogleFonts.figtreeTextTheme(base.textTheme);
    TextStyle display(double size) => GoogleFonts.caprasimo(
          fontSize: size,
          fontWeight: FontWeight.w400,
          color: t.ink,
          height: 1.15,
        );

    return base.copyWith(
      scaffoldBackgroundColor: t.ground,
      splashColor: t.accent.withValues(alpha: 0.08),
      highlightColor: t.accent.withValues(alpha: 0.06),
      focusColor: t.accent.withValues(alpha: 0.16),
      disabledColor: t.ink.withValues(alpha: 0.45),
      dividerColor: t.neutralTintStrong,
      textTheme: body.copyWith(
        displayLarge: display(40),
        displayMedium: display(34),
        displaySmall: display(28),
        headlineMedium: display(24),
        headlineSmall: display(21),
        titleLarge: GoogleFonts.figtree(
            fontSize: 20, fontWeight: FontWeight.w700, color: t.ink),
        titleMedium: GoogleFonts.figtree(
            fontSize: 17, fontWeight: FontWeight.w700, color: t.ink),
        titleSmall: GoogleFonts.figtree(
            fontSize: 14, fontWeight: FontWeight.w600, color: t.ink),
        bodyLarge:
            GoogleFonts.figtree(fontSize: 16, color: t.subtle, height: 1.45),
        bodyMedium:
            GoogleFonts.figtree(fontSize: 14, color: t.subtle, height: 1.4),
        bodySmall:
            GoogleFonts.figtree(fontSize: 12, color: t.faint, height: 1.35),
        labelLarge: GoogleFonts.figtree(
            fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
      iconTheme: IconThemeData(color: t.ink, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: t.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: display(24),
        iconTheme: IconThemeData(color: t.ink, size: 22),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return t.accent.withValues(alpha: 0.45);
            }
            if (states.contains(WidgetState.pressed)) return t.accentDeep;
            return t.accent;
          }),
          foregroundColor: WidgetStatePropertyAll(t.onFill),
          overlayColor: WidgetStatePropertyAll(t.onFill.withValues(alpha: 0.08)),
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(64, 54)),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: WidgetStatePropertyAll(
              GoogleFonts.figtree(fontSize: 16, fontWeight: FontWeight.w700)),
          side: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.focused)
                  ? BorderSide(color: t.accentText, width: 2)
                  : BorderSide.none),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? t.ink.withValues(alpha: 0.45)
                  : t.ink),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.pressed)
                  ? t.neutralTint
                  : Colors.transparent),
          overlayColor:
              WidgetStatePropertyAll(t.accent.withValues(alpha: 0.06)),
          minimumSize: const WidgetStatePropertyAll(Size(64, 50)),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: WidgetStatePropertyAll(
              GoogleFonts.figtree(fontSize: 15, fontWeight: FontWeight.w700)),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: t.accent, width: 2);
            }
            return BorderSide(color: t.border, width: 1.5);
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.pressed)
                  ? t.accentTextStrong
                  : t.accentText),
          overlayColor: WidgetStatePropertyAll(t.accentTint),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: WidgetStatePropertyAll(
              GoogleFonts.figtree(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        labelStyle: GoogleFonts.figtree(
            color: t.subtle, fontWeight: FontWeight.w600, fontSize: 15),
        hintStyle: GoogleFonts.figtree(color: t.faint, fontSize: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusPill),
          borderSide: BorderSide(color: t.neutralTintStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusPill),
          borderSide: BorderSide(color: t.neutralTintStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusPill),
          borderSide: BorderSide(color: t.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusPill),
          borderSide: BorderSide(color: t.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusPill),
          borderSide: BorderSide(color: t.danger, width: 2),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(t.surface),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius))),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.neutralTint,
        selectedColor: t.accentTint,
        labelStyle: GoogleFonts.figtree(
            color: t.accentTextStrong,
            fontWeight: FontWeight.w700,
            fontSize: 13),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: t.accentTint,
        indicatorShape: const StadiumBorder(),
        height: 72,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 22,
              color: states.contains(WidgetState.selected)
                  ? t.accentText
                  : t.faint,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) =>
            GoogleFonts.figtree(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? t.accentText
                  : t.faint,
            )),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: t.accentText,
        unselectedLabelColor: t.faint,
        indicatorColor: t.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle:
            GoogleFonts.figtree(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            GoogleFonts.figtree(fontSize: 14, fontWeight: FontWeight.w600),
        overlayColor: WidgetStatePropertyAll(t.accent.withValues(alpha: 0.06)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isLight ? neutral900 : _cream,
        contentTextStyle: GoogleFonts.figtree(
            color: isLight ? _cream : _ink,
            fontSize: 14,
            fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusCard + 4)),
        titleTextStyle: display(22),
        contentTextStyle:
            GoogleFonts.figtree(fontSize: 15, color: t.subtle, height: 1.45),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.accent,
        circularTrackColor: t.accentTint,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: t.subtle,
        titleTextStyle: GoogleFonts.figtree(
            fontSize: 15, fontWeight: FontWeight.w600, color: t.ink),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
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

  /// Terracotta base — chrome, icons, large text (~3:1 on ground).
  final Color accent;

  /// One step past base, for pressed states and dark-mode icons.
  final Color accentDeep;

  /// Paragraph-safe terracotta text on the ground.
  final Color accentText;

  /// Terracotta text on [accentTint] fills.
  final Color accentTextStrong;

  /// Tinted terracotta fill.
  final Color accentTint;

  /// Sage base — the safe/positive/online voice.
  final Color sage;
  final Color sageDeep;
  final Color sageText;
  final Color sageTextStrong;
  final Color sageTint;
  final Color sageTintStrong;

  /// Text/icons sitting on a filled accent or sage shape.
  final Color onFill;

  /// Errors ride the terracotta ramp.
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
}
