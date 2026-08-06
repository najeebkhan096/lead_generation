import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Warm, rounded "organic" design language — the same system used across
/// the product's mobile app, ported to the admin web console.
///
/// All colors come from three OKLCH tonal ramps (neutral, accent, sage)
/// generated on a shared lightness scale. Never introduce ad-hoc hexes or
/// greys: neutrals stay warm.
class AppTheme {
  AppTheme._();

  // ── Brand anchors ─────────────────────────────────────────────
  static const Color ground = Color(0xFFF5EAD8);
  static const Color ink = Color(0xFF201E1D);
  static const Color surface = Color(0xFFFBF6EE);

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

  // ── Semantic aliases ──────────────────────────────────────────
  static const Color accent = accent500;
  static const Color sage = sage500;
  static const Color subtle = neutral700;
  static const Color faint = neutral500;
  static const Color danger = accent700;

  // ── Shape ─────────────────────────────────────────────────────
  static const double radius = 16;
  static const double radiusCard = 24;
  static const double radiusPill = 999;

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: accent500,
        onPrimary: surface,
        primaryContainer: accent100,
        onPrimaryContainer: accent800,
        secondary: sage500,
        onSecondary: surface,
        secondaryContainer: sage100,
        onSecondaryContainer: sage800,
        surface: surface,
        onSurface: ink,
        onSurfaceVariant: neutral700,
        outline: neutral300,
        outlineVariant: neutral200,
        error: danger,
        onError: surface,
        errorContainer: accent100,
        onErrorContainer: accent800,
      ),
    );

    final body = GoogleFonts.figtreeTextTheme(base.textTheme);
    TextStyle display(double size) => GoogleFonts.caprasimo(
          fontSize: size,
          fontWeight: FontWeight.w400,
          color: ink,
          height: 1.15,
        );

    return base.copyWith(
      scaffoldBackgroundColor: ground,
      splashColor: accent500.withValues(alpha: 0.08),
      highlightColor: accent500.withValues(alpha: 0.06),
      focusColor: accent500.withValues(alpha: 0.16),
      disabledColor: ink.withValues(alpha: 0.45),
      dividerColor: neutral200,
      textTheme: body.copyWith(
        displayLarge: display(40),
        displayMedium: display(34),
        displaySmall: display(28),
        headlineMedium: display(24),
        headlineSmall: display(21),
        titleLarge: GoogleFonts.figtree(
            fontSize: 20, fontWeight: FontWeight.w700, color: ink),
        titleMedium: GoogleFonts.figtree(
            fontSize: 17, fontWeight: FontWeight.w700, color: ink),
        titleSmall: GoogleFonts.figtree(
            fontSize: 14, fontWeight: FontWeight.w600, color: ink),
        bodyLarge: GoogleFonts.figtree(fontSize: 16, color: subtle, height: 1.45),
        bodyMedium: GoogleFonts.figtree(fontSize: 14, color: subtle, height: 1.4),
        bodySmall: GoogleFonts.figtree(fontSize: 12, color: faint, height: 1.35),
        labelLarge: GoogleFonts.figtree(
            fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
      iconTheme: const IconThemeData(color: ink, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: display(22),
        iconTheme: const IconThemeData(color: ink, size: 22),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return accent500.withValues(alpha: 0.45);
            }
            if (states.contains(WidgetState.pressed)) return accent600;
            return accent500;
          }),
          foregroundColor: const WidgetStatePropertyAll(surface),
          overlayColor: WidgetStatePropertyAll(surface.withValues(alpha: 0.08)),
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 26, vertical: 15)),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: WidgetStatePropertyAll(
              GoogleFonts.figtree(fontSize: 15.5, fontWeight: FontWeight.w700)),
          side: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.focused)
                  ? const BorderSide(color: accent700, width: 2)
                  : BorderSide.none),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return accent500.withValues(alpha: 0.45);
            }
            if (states.contains(WidgetState.pressed)) return accent600;
            return accent500;
          }),
          foregroundColor: const WidgetStatePropertyAll(surface),
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 22, vertical: 15)),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: WidgetStatePropertyAll(
              GoogleFonts.figtree(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? ink.withValues(alpha: 0.45)
                  : ink),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.pressed)
                  ? neutral100
                  : Colors.transparent),
          overlayColor: WidgetStatePropertyAll(accent500.withValues(alpha: 0.06)),
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 22, vertical: 13)),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: WidgetStatePropertyAll(
              GoogleFonts.figtree(fontSize: 14.5, fontWeight: FontWeight.w700)),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return const BorderSide(color: accent500, width: 2);
            }
            return const BorderSide(color: neutral300, width: 1.5);
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.pressed) ? accent800 : accent700),
          overlayColor: const WidgetStatePropertyAll(accent100),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: WidgetStatePropertyAll(
              GoogleFonts.figtree(fontSize: 14.5, fontWeight: FontWeight.w700)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        labelStyle: GoogleFonts.figtree(
            color: subtle, fontWeight: FontWeight.w600, fontSize: 15),
        hintStyle: GoogleFonts.figtree(color: faint, fontSize: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: neutral200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: neutral200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: accent500, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: danger, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: neutral100,
        selectedColor: accent100,
        labelStyle: GoogleFonts.figtree(
            color: accent800, fontWeight: FontWeight.w700, fontSize: 13),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent700,
        unselectedLabelColor: neutral500,
        indicatorColor: accent500,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: GoogleFonts.figtree(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            GoogleFonts.figtree(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: neutral900,
        contentTextStyle: GoogleFonts.figtree(
            color: ground, fontSize: 14, fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
        titleTextStyle: display(20),
        contentTextStyle: GoogleFonts.figtree(fontSize: 15, color: subtle, height: 1.45),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent500,
        circularTrackColor: accent100,
        linearTrackColor: accent100,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: subtle,
        titleTextStyle: GoogleFonts.figtree(
            fontSize: 15, fontWeight: FontWeight.w600, color: ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
      ),
    );
  }
}

/// Lucide icons at the heaviest stroke the icon font ships (3.0 — nearest
/// to the design language's 2.75). Alias here so pages never reach into
/// the raw weight-suffixed names.
class AppIcons {
  AppIcons._();

  static const dashboard = LucideIcons.layoutDashboard600;
  static const leads = LucideIcons.building2600;
  static const chat = LucideIcons.messageCircle600;
  static const search = LucideIcons.search600;
  static const plus = LucideIcons.plus600;
  static const filter = LucideIcons.listFilter600;
  static const chevronDown = LucideIcons.chevronDown600;
  static const chevronRight = LucideIcons.chevronRight600;
  static const mapPin = LucideIcons.mapPin600;
  static const mapPinned = LucideIcons.mapPinned600;
  static const star = LucideIcons.star600;
  static const phone = LucideIcons.phone600;
  static const globe = LucideIcons.globe600;
  static const mail = LucideIcons.mail600;
  static const tag = LucideIcons.tag600;
  static const calendar = LucideIcons.calendar600;
  static const clock = LucideIcons.clock600;
  static const check = LucideIcons.check600;
  static const checkCircle = LucideIcons.circleCheck600;
  static const alert = LucideIcons.circleAlert600;
  static const refresh = LucideIcons.refreshCw600;
  static const inbox = LucideIcons.inbox600;
  static const searchX = LucideIcons.searchX600;
  static const externalLink = LucideIcons.externalLink600;
  static const sparkles = LucideIcons.sparkles600;
  static const trendingUp = LucideIcons.trendingUp600;
  static const users = LucideIcons.users600;
  static const percent = LucideIcons.percent600;
  static const copy = LucideIcons.copy600;
  static const download = LucideIcons.download600;
  static const cloudUpload = LucideIcons.cloudUpload600;
  static const arrowLeft = LucideIcons.arrowLeft600;
  static const close = LucideIcons.x600;
  static const globe2 = LucideIcons.globe600;
  static const barChart = LucideIcons.barChart3600;
  static const zap = LucideIcons.zap600;
  static const flame = LucideIcons.flame600;
  static const target = LucideIcons.target600;
  static const award = LucideIcons.award600;
  static const store = LucideIcons.store600;
  static const thumbsDown = LucideIcons.thumbsDown600;
  static const messageWarning = LucideIcons.messageSquareWarning600;
  static const shieldCheck = LucideIcons.shieldCheck600;
  static const badgeCheck = LucideIcons.badgeCheck600;
}
