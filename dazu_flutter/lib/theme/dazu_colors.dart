import 'package:flutter/material.dart';

/// dazu-Markenfarben — portiert aus `Drops/DesignSystem.swift` der iOS-App.
/// Namen bewusst identisch zu SwiftUI, damit beide Codebases die gleiche
/// Palette führen.
class DazuColors {
  DazuColors._();

  /// Primär-Lila der Marke. Hero-Headlines, Buttons, Navigation-Accent.
  /// Exakt gematched mit iOS `brandViolet` (DesignSystem.swift).
  static const Color brandViolet = Color(0xFF6253ED);

  /// Akzent-Orange. Immer in Mikrodosis einsetzen (Punkt am Logo, „?",
  /// „LIVE"-Pulse, Jetzt-Pille). Nie als Flächenfarbe.
  static const Color brandOrange = Color(0xFFFFA02E);

  /// Warmer Creme-Hintergrund — das Grundrauschen der App.
  static const Color brandCream = Color(0xFFFFF6EA);

  /// Dunkles Beinahe-Schwarz für Text. Mit leichtem Blau-Lila-Stich.
  static const Color brandNight = Color(0xFF17112E);

  /// Zartes Lavendel für Pillen, Cards, Hintergründe von Chip-Rows.
  static const Color brandLavender = Color(0xFFE9E3FF);

  /// Pink-Akzent für Statistik-Pills, Punkte-Toast, Monogram-Avatare.
  static const Color brandPink = Color(0xFFF263B6);

  /// Koralle für Avatare und Sekundärakzente aus der Monogram-Palette.
  static const Color brandCoral = Color(0xFFFF7372);

  /// Textfarben-Hierarchie — gleiche Namensgebung wie SwiftUI
  /// (textPrimary / textSecondary / textTertiary).
  static const Color textPrimary = brandNight;
  static const Color textSecondary = Color(0xFF55456F);
  static const Color textTertiary = Color(0xFF8A7CA4);

  /// Monogram-Avatar-Palette — gleiche Reihenfolge wie `MonogramAvatar`
  /// im Admin-Panel, damit Freundeslisten in beiden Apps identisch
  /// aussehen.
  static const List<Color> monogramPalette = [
    brandViolet,
    brandCoral,
    brandPink,
    Color(0xFFA86BF2),
    Color(0xFF7C5BE5),
    Color(0xFFFF9A6E),
    Color(0xFFB155E0),
    Color(0xFFE946A7),
    Color(0xFF5C3DD9),
    Color(0xFFFF6B9A),
    brandOrange,
  ];
}
