// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';

class AppTheme {
  // Warm, earthy palette — matches Freya exactly
  static const _teal = Color(0xFF00897B);
  static const _amber = Color(0xFFD4A04A);
  static const _amberDark = Color(0xFFE0B054);
  static const _warmBg = Color(0xFFFBF8F1);
  static const _warmSurface = Color(0xFFF5F0E8);
  static const _darkBg = Color(0xFF1A1C1E);
  static const _darkSurface = Color(0xFF252729);

  /// Use 'Inter' everywhere — bundled in assets/fonts/.
  static const _fontFamily = 'Inter';

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _teal,
      brightness: Brightness.light,
      surface: _warmBg,
      secondary: _amber,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme.copyWith(
        surfaceContainerLowest: _warmBg,
        surfaceContainerLow: _warmSurface,
        surfaceContainer: const Color(0xFFE8E0D0),
        surfaceContainerHigh: const Color(0xFFE5DECF),
        surfaceContainerHighest: const Color(0xFFD8D1C2),
      ),
      scaffoldBackgroundColor: _warmBg,
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontFamily: _fontFamily, fontSize: 16, height: 1.6),
        bodyMedium: TextStyle(fontFamily: _fontFamily, fontSize: 14, height: 1.5),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: _warmSurface,
        foregroundColor: const Color(0xFF1A1A1A),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1A1A1A),
        ),
      ),
      cardTheme: CardThemeData(
        color: _warmSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        shadowColor: Colors.black.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: const Color(0xFF1A1A1A).withValues(alpha: 0.08)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _warmSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: _teal.withValues(alpha: 0.15),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: const Color(0xFF1A1A1A).withValues(alpha: 0.08),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1A1A1A).withValues(alpha: 0.03),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFF1A1A1A).withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFF1A1A1A).withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _teal, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _teal,
      brightness: Brightness.dark,
      surface: _darkBg,
      secondary: _amberDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme.copyWith(
        surfaceContainerLowest: _darkBg,
        surfaceContainerLow: _darkSurface,
        surfaceContainer: const Color(0xFF2D2F31),
        surfaceContainerHigh: const Color(0xFF333537),
        surfaceContainerHighest: const Color(0xFF3B3D3F),
      ),
      scaffoldBackgroundColor: _darkBg,
      textTheme: TextTheme(
        bodyLarge: TextStyle(fontFamily: _fontFamily, fontSize: 16, height: 1.6, color: colorScheme.onSurface),
        bodyMedium: TextStyle(fontFamily: _fontFamily, fontSize: 14, height: 1.5, color: colorScheme.onSurfaceVariant),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: _darkSurface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: _darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: const Color(0xFFFFFFFF).withValues(alpha: 0.06)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: _teal.withValues(alpha: 0.2),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFFFF).withValues(alpha: 0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFFFFFFFF).withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFFFFFFFF).withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _teal, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
