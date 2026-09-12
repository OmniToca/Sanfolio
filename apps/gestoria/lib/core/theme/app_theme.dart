import 'package:flutter/material.dart';

/// Tokeny kanceláře. Features nesmí kreslit nahodilé Color / radius.
class AppTheme {
  static const Color ink = Color(0xFF161412);
  static const Color paper = Color(0xFFF3EEE6);
  static const Color surface = Color(0xFFFFFCF8);
  static const Color surfaceMuted = Color(0xFFEDE8DF);
  static const Color rule = Color(0xFFDFD8CC);
  static const Color pencil = Color(0xFF6B645C);
  static const Color accent = Color(0xFF1B5F59);
  static const Color accentSoft = Color(0xFFD7EBE8);
  static const Color nav = Color(0xFF12201E);
  static const Color navSelected = Color(0xFF1E3C38);
  static const Color navInk = Color(0xFFF3EEE6);
  static const Color navMuted = Color(0xFF9AA8A6);
  static const Color chipOff = Color(0xFFF0EBE3);
  static const Color chipOn = Color(0xFFD7EBE8);
  static const Color stripeOn = Color(0xFF1B5F59);

  static const double radiusSm = 10;
  static const double radiusMd = 16;
  static const double radiusLg = 22;
  static const double radiusPill = 999;
  static const double railWidth = 92;
  static const double contentMax = 920;
  static const double contentWide = 1360;
  static const Color proposal = Color(0xFFFFF4C2);

  static const String _ui = 'Plus Jakarta Sans';
  static const String _display = 'Fraunces';

  static List<BoxShadow> get cardShadow => const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ];

  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: accent,
      onPrimary: Color(0xFFF7FFFE),
      secondary: Color(0xFF3F4A48),
      onSecondary: Color(0xFFF7FFFE),
      surface: paper,
      onSurface: ink,
      onSurfaceVariant: pencil,
      outline: rule,
      error: Color(0xFFB42318),
    );
    final text = TextTheme(
      headlineSmall: const TextStyle(
        fontFamily: _display,
        fontSize: 30,
        fontWeight: FontWeight.w600,
        height: 1.15,
        color: ink,
      ),
      titleLarge: const TextStyle(
        fontFamily: _display,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: ink,
      ),
      titleMedium: const TextStyle(
        fontFamily: _ui,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: ink,
      ),
      titleSmall: const TextStyle(
        fontFamily: _ui,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: pencil,
      ),
      bodyLarge: const TextStyle(
        fontFamily: _ui,
        fontSize: 15,
        height: 1.45,
        color: ink,
      ),
      bodyMedium: const TextStyle(
        fontFamily: _ui,
        fontSize: 14,
        height: 1.4,
        color: ink,
      ),
      bodySmall: const TextStyle(
        fontFamily: _ui,
        fontSize: 12.5,
        height: 1.35,
        color: pencil,
      ),
      labelLarge: const TextStyle(
        fontFamily: _ui,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      fontFamily: _ui,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: rule),
        ),
      ),
      dividerTheme: const DividerThemeData(color: rule, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: rule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: rule),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: accent, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          backgroundColor: accent,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(44, 40),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceMuted,
        selectedColor: accentSoft,
        side: const BorderSide(color: rule),
        labelStyle: text.bodySmall,
        selectedShadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPill),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accentSoft,
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          final selected = s.contains(WidgetState.selected);
          return text.bodySmall?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? accent : pencil,
          );
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return accent;
          return surface;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return accentSoft;
          return surfaceMuted;
        }),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: rule,
        indicatorColor: accent,
        labelColor: ink,
        unselectedLabelColor: pencil,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.bodyMedium,
        tabAlignment: TabAlignment.start,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
    );
  }
}
