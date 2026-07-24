import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color ink = Color(0xFF1A2332);
  static const Color slate = Color(0xFF3D4F66);
  static const Color mist = Color(0xFFF0F4F8);
  static const Color accent = Color(0xFF0F766E);
  static const Color warn = Color(0xFFB45309);
  static const Color line = Color(0xFFD6DEE8);
  static const Color whatsApp = Color(0xFF25D366);

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
          fontSize: 32,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        titleLarge: GoogleFonts.sourceSans3(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleMedium: GoogleFonts.sourceSans3(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        bodyLarge: GoogleFonts.sourceSans3(
          fontSize: 16,
          color: slate,
          height: 1.4,
        ),
        bodyMedium: GoogleFonts.sourceSans3(
          fontSize: 14,
          color: slate,
          height: 1.35,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: mist,
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
