import 'package:flutter/material.dart';

import '../theme/dazu_colors.dart';

/// Altersgruppen-Filter für Umgebungs-Tab + Einstellungen.
/// Portiert aus iOS `Models.swift` → `enum AgeGroup`.
enum AgeGroup {
  young('18–24', 18, 24, Icons.directions_run, Color(0xFF22C55E)),
  twenties('25–34', 25, 34, Icons.work, Color(0xFF06B6D4)),
  thirties('35–44', 35, 44, Icons.eco, DazuColors.brandOrange),
  forties('45–59', 45, 59, Icons.coffee, Color(0xFF8B5CF6)),
  seniors('60–99', 60, 99, Icons.star, Color(0xFFEC4899));

  const AgeGroup(
    this.label,
    this.minAge,
    this.maxAge,
    this.icon,
    this.color,
  );

  /// Anzeigetext — identisch zu iOS `rawValue` / `label`.
  final String label;
  final int minAge;
  final int maxAge;
  final IconData icon;
  final Color color;

  /// Nützlich für JSON-Persistenz; matcht iOS `rawValue`.
  String get rawValue => label;

  /// Umkehrung von `rawValue` — tolerant gegenüber alten Dashes.
  static AgeGroup? fromRawValue(String? raw) {
    if (raw == null) return null;
    final norm = raw.replaceAll('-', '–');
    for (final g in AgeGroup.values) {
      if (g.label == norm) return g;
    }
    return null;
  }

  /// Altersgruppe für ein konkretes Alter — matcht iOS `AgeGroup.group(for:)`.
  static AgeGroup groupFor(int age) {
    if (age <= 24) return AgeGroup.young;
    if (age <= 34) return AgeGroup.twenties;
    if (age <= 44) return AgeGroup.thirties;
    if (age <= 59) return AgeGroup.forties;
    return AgeGroup.seniors;
  }

  /// Default-Sichtbarkeit: eigene Gruppe + direkt angrenzende.
  /// iOS `AgeGroup.defaultVisible(for:)`.
  static List<AgeGroup> defaultVisible(int age) {
    final own = groupFor(age);
    final all = AgeGroup.values;
    final idx = all.indexOf(own);
    final result = <AgeGroup>[own];
    if (idx > 0) result.add(all[idx - 1]);
    if (idx < all.length - 1) result.add(all[idx + 1]);
    return result;
  }
}
