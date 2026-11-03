import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dazu_colors.dart';

/// Theme-Factory für dazu. Portiert die Grundhaltung aus der iOS-App:
/// warme Creme-Fläche, lila Primär, orangene Mikro-Akzente, Rounded-
/// Design-System via SF-Rounded-Pendant (Nunito auf Android).
class DazuTheme {
  DazuTheme._();

  /// Haupt-Font. Bricolage Grotesque ist die Marken-Schrift der iOS-App
  /// (eingebunden als TTF unter `Drops/Fonts/`). Google Fonts liefert
  /// dieselbe Familie frei, inkl. aller nötigen Weights.
  static TextTheme _buildTextTheme(TextTheme base) {
    final rounded = GoogleFonts.bricolageGrotesqueTextTheme(base);
    return rounded.copyWith(
      displayLarge: rounded.displayLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: DazuColors.brandNight,
        height: 1.02,
      ),
      displayMedium: rounded.displayMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: DazuColors.brandNight,
        height: 1.02,
      ),
      headlineLarge: rounded.headlineLarge?.copyWith(
        fontSize: 42,
        fontWeight: FontWeight.w800,
        color: DazuColors.brandNight,
        height: 1.02,
      ),
      headlineMedium: rounded.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: DazuColors.brandNight,
      ),
      titleLarge: rounded.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: DazuColors.brandNight,
      ),
      bodyLarge: rounded.bodyLarge?.copyWith(
        color: DazuColors.textPrimary,
      ),
      bodyMedium: rounded.bodyMedium?.copyWith(
        color: DazuColors.textSecondary,
      ),
      labelLarge: rounded.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: DazuColors.brandViolet,
      brightness: Brightness.dark,
      primary: DazuColors.brandViolet,
      secondary: DazuColors.brandOrange,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF14101E),
      textTheme: _buildTextTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF14101E),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
    );
  }

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: DazuColors.brandViolet,
      brightness: Brightness.light,
      primary: DazuColors.brandViolet,
      secondary: DazuColors.brandOrange,
      surface: DazuColors.brandCream,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: DazuColors.brandCream,
      textTheme: _buildTextTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: DazuColors.brandCream,
        foregroundColor: DazuColors.brandNight,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: DazuColors.brandLavender,
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.bricolageGrotesque(
            fontWeight: FontWeight.w700,
            fontSize: 11,
            color: DazuColors.brandNight,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DazuColors.brandViolet,
          foregroundColor: DazuColors.brandCream,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.bricolageGrotesque(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
          shape: const StadiumBorder(),
          elevation: 0,
        ),
      ),
    );
  }
}
