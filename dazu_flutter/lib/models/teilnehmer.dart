import 'package:flutter/foundation.dart';

/// Live-Teilnehmer einer Runde in Firebase RTDB unter
/// `/dropins/{rundeID}/{teilnehmerID}`. Legacy-Pfadname bleibt, intern
/// und UI heißt es Teilnehmer.
@immutable
class Teilnehmer {
  const Teilnehmer({
    required this.id,
    required this.name,
    required this.emoji,
    required this.age,
    required this.lat,
    required this.lng,
    required this.timestampMs,
    this.profileImageURL,
    this.reliabilityPoints,
    this.locTimeMs,
    this.statusMessage = '',
  });

  final String id;
  final String name;
  final String emoji;
  final int age;
  final double lat;
  final double lng;

  /// Server-Timestamp vom Join-Zeitpunkt (`timestamp` in RTDB).
  final int timestampMs;

  final String? profileImageURL;
  final int? reliabilityPoints;

  /// Zeitpunkt der letzten Live-Standort-Aktualisierung (`locTime` in
  /// RTDB). iOS schreibt den beim initialen Join (falls GPS da war) und
  /// bei jedem `updateJoinerLiveLocation`. Flutter kann das für Stale-
  /// Erkennung nutzen (lat/lng älter als N Minuten = kein Live-Pin).
  final int? locTimeMs;

  /// „Unterwegs", „Vor Ort" o.ä. — in iOS DropParticipant.statusMessage.
  /// RTDB-Pfad noch nicht fixiert; Default leer.
  final String statusMessage;

  factory Teilnehmer.fromMap(String id, Map<Object?, Object?> raw) {
    double toD(Object? v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    int toI(Object? v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
    return Teilnehmer(
      id: id,
      name: raw['name']?.toString() ?? '',
      emoji: raw['emoji']?.toString() ?? '',
      age: toI(raw['age']),
      lat: toD(raw['lat']),
      lng: toD(raw['lng']),
      timestampMs: toI(raw['timestamp']),
      profileImageURL: raw['profileImageURL']?.toString(),
      reliabilityPoints: raw['reliabilityPoints'] == null
          ? null
          : toI(raw['reliabilityPoints']),
      locTimeMs: raw['locTime'] == null ? null : toI(raw['locTime']),
      statusMessage: raw['statusMessage']?.toString() ?? '',
    );
  }
}
