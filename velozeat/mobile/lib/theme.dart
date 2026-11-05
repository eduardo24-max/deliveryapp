import 'package:flutter/material.dart';

const Color kBrand = Color(0xFFFF6A00);
const Color kBrandDark = Color(0xFFE55A00);
const Color kBrandSoft = Color(0xFFFFE8D6);
const Color kAccent = Color(0xFFFFC107);
const Color kInk = Color(0xFF1A1A1A);
const Color kMuted = Color(0xFF757575);
const Color kBg = Color(0xFFF5F5F5);
const Color kLine = Color(0xFFE8E8E8);
const Color kGreen = Color(0xFF16A34A);
const Color kRed = Color(0xFFDC2626);
const Color kBlue = Color(0xFF2563EB);

String money(num value) {
  final hasCents = value % 1 != 0;
  return hasCents ? '\$${value.toStringAsFixed(2)}' : '\$${value.toInt()}';
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrand,
    primary: kBrand,
    secondary: kAccent,
    surface: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    fontFamily: null,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: kInk,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: kInk, letterSpacing: -0.8),
      headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kInk, letterSpacing: -0.5),
      titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: kInk),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kInk),
      bodyMedium: TextStyle(fontSize: 14, height: 1.35, color: kInk),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.3, color: kMuted),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: kLine),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: const TextStyle(color: kMuted, fontSize: 14),
      labelStyle: const TextStyle(color: kMuted, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kBrand, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kRed),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kInk,
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: kLine),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kInk,
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(color: kLine, thickness: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      indicatorColor: kBrand.withValues(alpha: 0.14),
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: states.contains(WidgetState.selected) ? kBrand : kMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? kBrand : kMuted,
          size: 24,
        ),
      ),
    ),
  );
}
