import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// WASFA Rider design tokens — mirrors the HTML prototype's `T` object.
class WTheme {
  WTheme._();

  // ── Brand colours ────────────────────────────────────────────
  static const Color navy  = Color(0xFF023B60);
  static const Color navyD = Color(0xFF022A45);
  static const Color sky   = Color(0xFF1E9CD7);
  static const Color rose  = Color(0xFFE7609F);
  static const Color aqua  = Color(0xFF58C4E4);
  static const Color cloud = Color(0xFFE6EBF0);
  static const Color blush = Color(0xFFFFF7F9);
  static const Color ok    = Color(0xFF21B47A);
  static const Color warn  = Color(0xFFF5A524);
  static const Color err   = Color(0xFFE5484D);
  static const Color ink   = Color(0xFF0F2438);
  static const Color muted = Color(0xFF6A7D90);

  // ── MaterialApp ThemeData ────────────────────────────────────
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: navy,
      primary: navy,
      secondary: sky,
      error: err,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: Colors.white,
    textTheme: GoogleFonts.dmSansTextTheme().copyWith(
      displayLarge:  GoogleFonts.dmSans(fontWeight: FontWeight.w800),
      titleLarge:    GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: navy),
      bodyLarge:     GoogleFonts.dmSans(fontWeight: FontWeight.w500),
      bodySmall:     GoogleFonts.dmSans(fontWeight: FontWeight.w600, color: muted),
      labelSmall:    GoogleFonts.dmMono(fontWeight: FontWeight.w500),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: navy,
      foregroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: GoogleFonts.dmSans(
        fontWeight: FontWeight.w800,
        fontSize: 17,
        color: Colors.white,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cloud,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: sky, width: 2),
      ),
    ),
  );
}
