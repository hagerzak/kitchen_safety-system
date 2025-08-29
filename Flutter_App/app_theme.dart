import 'package:flutter/material.dart';

class AppColors {
  // Burgundy shades
  static const Color burgundy50 = Color(0xFFFDF7F8);
  static const Color burgundy100 = Color(0xFFF0E6E8);
  static const Color burgundy200 = Color(0xFFE2D0D4);
  static const Color burgundy300 = Color(0xFFD4C5C7);
  static const Color burgundy400 = Color(0xFFB8999E);
  static const Color burgundy500 = Color(0xFF9C6D75);
  static const Color burgundy600 = Color(0xFF8B4049);
  static const Color burgundy700 = Color(0xFF722F37);
  static const Color burgundy800 = Color(0xFF5A252B);
  static const Color burgundy900 = Color(0xFF42191E);
  static const Color burgundy950 = Color(0xFF2A1013);

  // Cream and grey
  static const Color cream = Color(0xFFFAF8F5);
  static const Color darkGrey = Color(0xFF2C2C2C);
  static const Color mediumGrey = Color(0xFF6B6B6B);
  static const Color lightGrey = Color(0xFFD1C7C0);

  // Status colors
  static const Color success = Color(0xFF28A745);
  static const Color warning = Color(0xFFFFC107);
  static const Color danger = Color(0xFFDC3545);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'OpenSans',
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.burgundy700,
        brightness: Brightness.light,
        primary: AppColors.burgundy700,
        secondary: AppColors.burgundy600,
        surface: AppColors.cream,
        background: AppColors.cream,
        onPrimary: AppColors.cream,
        onSecondary: AppColors.cream,
        onSurface: AppColors.darkGrey,
        onBackground: AppColors.darkGrey,
      ),
      scaffoldBackgroundColor: AppColors.cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.burgundy700,
        foregroundColor: AppColors.cream,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.burgundy700,
          foregroundColor: AppColors.cream,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.burgundy700,
          side: const BorderSide(color: AppColors.burgundy700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.lightGrey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.lightGrey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.burgundy700),
        ),
      ),
      iconTheme: const IconThemeData(
        color: AppColors.burgundy700,
      ),
    );
  }

  // Creamy mode instead of dark mode
  static ThemeData get creamyTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'OpenSans',
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.burgundy500,
        brightness: Brightness.light,
        primary: AppColors.burgundy500,
        secondary: AppColors.burgundy600,
        surface: AppColors.burgundy50,
        background: AppColors.cream,
        onPrimary: AppColors.cream,
        onSecondary: AppColors.cream,
        onSurface: AppColors.darkGrey,
        onBackground: AppColors.darkGrey,
      ),
      scaffoldBackgroundColor: AppColors.cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.burgundy500,
        foregroundColor: AppColors.cream,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.burgundy500,
          foregroundColor: AppColors.cream,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.burgundy500,
          side: const BorderSide(color: AppColors.burgundy500),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.burgundy50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.lightGrey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.lightGrey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.burgundy500),
        ),
      ),
      iconTheme: const IconThemeData(
        color: AppColors.burgundy500,
      ),
    );
  }
}
