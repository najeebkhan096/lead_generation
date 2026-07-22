import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color ink = Color(0xFF1A2332);
  static const Color slate = Color(0xFF3D4F66);
  static const Color mist = Color(0xFFF0F4F8);
  static const Color accent = Color(0xFF0F766E);
  static const Color accentSoft = Color(0xFFCCFBF1);
  static const Color warn = Color(0xFFB45309);
  static const Color warnSoft = Color(0xFFFEF3C7);
  static const Color line = Color(0xFFD6DEE8);

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
        primary: accent,
        surface: Colors.white,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: mist,
      textTheme: GoogleFonts.sourceSans3TextTheme(base.textTheme).copyWith(
        displaySmall: GoogleFonts.fraunces(
          fontSize: 36,
          fontWeight: FontWeight.w600,
          color: ink,
          height: 1.15,
        ),
        headlineMedium: GoogleFonts.fraunces(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        titleLarge: GoogleFonts.sourceSans3(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        bodyLarge: GoogleFonts.sourceSans3(
          fontSize: 16,
          color: slate,
          height: 1.45,
        ),
        bodyMedium: GoogleFonts.sourceSans3(
          fontSize: 14,
          color: slate,
          height: 1.4,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: GoogleFonts.sourceSans3(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        iconTheme: const IconThemeData(color: ink),
      ),
    );
  }
}
