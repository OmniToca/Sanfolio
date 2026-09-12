import 'package:flutter/material.dart';

class AppTheme {
  static const Color ink = Color(0xFF1C1917);
  static const Color paper = Color(0xFFFAF7F2);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color rule = Color(0xFFD6D3D1);
  static const Color accent = Color(0xFF1D4E4A);
  static const double radiusMd = 8;

  static ThemeData get light {
    final base = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      surface: paper,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: paper,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }
}
