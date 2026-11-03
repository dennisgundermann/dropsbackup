/// Umgebungs-Tab-Distanzfilter.
///
/// iOS hat das auf eine einzige Case `.city` reduziert (siehe
/// `Drops/Models.swift` → `enum FeedDistanceFilter`). Die alten
/// Radius-Pillen (500m / 2km / 5km) wurden entfernt, weil die
/// Service-Zone sowieso schon den Perimeter definiert.
enum FeedDistanceFilter {
  city;

  /// Reichweite in Metern. `city` = quasi unendlich — die
  /// Service-Zone grenzt an sich schon ab.
  double get meters => double.infinity;

  /// Kurzlabel für Pills (TODO: Localization-Keys einbinden
  /// `models.range_city_short`).
  String get label => 'Stadt';

  /// Langlabel für Einstellungen.
  String get detailLabel => 'Ganze Stadt';
}
