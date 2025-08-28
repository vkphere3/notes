import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  final ThemeData light;
  final ThemeData dark;
  AppTheme(this.light, this.dark);
}

AppTheme buildTheme() {
  // Tweak this seed color to taste
  final seed = const Color(0xFF4F46E5); // Indigo-ish accent

  final textTheme = TextTheme(
    displayLarge: GoogleFonts.plusJakartaSans(),
    displayMedium: GoogleFonts.plusJakartaSans(),
    displaySmall: GoogleFonts.plusJakartaSans(),
    headlineLarge: GoogleFonts.plusJakartaSans(),
    headlineMedium: GoogleFonts.plusJakartaSans(),
    headlineSmall: GoogleFonts.plusJakartaSans(),
    titleLarge: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
    titleMedium: GoogleFonts.plusJakartaSans(),
    titleSmall: GoogleFonts.plusJakartaSans(),
    bodyLarge: GoogleFonts.inter(),
    bodyMedium: GoogleFonts.inter(),
    bodySmall: GoogleFonts.inter(),
    labelLarge: GoogleFonts.inter(),
    labelMedium: GoogleFonts.inter(),
    labelSmall: GoogleFonts.inter(),
  );

  final light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ),
    textTheme: textTheme,
    visualDensity: VisualDensity.comfortable,
  );

  final dark = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ),
    textTheme: textTheme,
    visualDensity: VisualDensity.comfortable,
  );
  return AppTheme(light, dark);
}
