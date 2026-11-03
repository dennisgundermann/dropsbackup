import 'package:flutter/foundation.dart';

/// Wie der User den Standort gewählt hat.
enum DropLocationType {
  /// Aktueller GPS-Standort.
  current,

  /// Über die Adress-Suche ausgewählt.
  searched,

  /// Auf der Karte gepinnt.
  pin,
}

/// Treffpunkt eines Drops — matcht iOS `DropLocation`.
@immutable
class DropLocation {
  const DropLocation({
    required this.title,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
    this.type = DropLocationType.current,
  });

  /// Primärer Anzeigename („Café Fiore", „Englischer Garten", …).
  final String title;

  /// Adress-Untertitel.
  final String subtitle;

  final double latitude;
  final double longitude;

  final DropLocationType type;

  DropLocation copyWith({
    String? title,
    String? subtitle,
    double? latitude,
    double? longitude,
    DropLocationType? type,
  }) =>
      DropLocation(
        title: title ?? this.title,
        subtitle: subtitle ?? this.subtitle,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        type: type ?? this.type,
      );
}
