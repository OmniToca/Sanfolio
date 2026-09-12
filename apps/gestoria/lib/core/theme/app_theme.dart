import 'package:flutter/material.dart';

class AppTheme {
  static const Color ink = Color(0xFF1C1917);
  static const Color paper = Color(0xFFFAF7F2);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color rule = Color(0xFFD6D3D1);
  static const Color pencil = Color(0xFF57534E);
  static const Color accent = Color(0xFF1D4E4A);
  static const Color chipOff = Color(0xFFF5F5F4);
  static const Color chipOn = Color(0xFFE8F0EF);

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
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: paper,
        selectedIconTheme: IconThemeData(color: accent),
        selectedLabelTextStyle: TextStyle(
          color: accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
