import 'package:flutter/foundation.dart';

/// Eine aktive Runde in Firebase RTDB unter `/drops/{id}`. Der RTDB-
/// Pfad behält den iOS-Legacy-Namen „drops" weil das Schema mit der
/// iOS-App geteilt wird — intern und UI-seitig heißt es überall
/// „Runde".
@immutable
class Runde {
  const Runde({
    required this.id,
    required this.hostUID,
    required this.hostName,
    required this.emoji,
    required this.activityName,
    required this.lat,
    required this.lng,
    required this.radius,
    required this.timestampMs,
    required this.expiresAt,
    required this.scheduledTime,
    required this.startAt,
    required this.maxParticipants,
    required this.currentParticipants,
    required this.active,
    this.hostGender,
    this.hostAge,
    this.hostReliabilityPoints,
    this.communityID,
    this.hostProfileImageURL,
    this.femaleOnly = false,
    this.durationMinutes = 120,
    this.dropDescription = '',
  });

  final String id;
  final String hostUID;
  final String hostName;
  final String emoji;
  final String activityName;
  final double lat;
  final double lng;
  final double radius;

  /// Server-Timestamp als ms since epoch.
  final int timestampMs;

  /// Unix-sec (nicht ms!), passt zu `expiresAt.timeIntervalSince1970`
  /// in iOS.
  final double expiresAt;
  final String scheduledTime;
  final double startAt;
  final int maxParticipants;
  final int currentParticipants;
  final bool active;

  final String? hostGender;
  final int? hostAge;
  final int? hostReliabilityPoints;
  final String? communityID;
  final String? hostProfileImageURL;
  final bool femaleOnly;

  /// Drop-Dauer in Minuten; 0 = kein Limit (12 h Fallback). Von iOS seit
  /// CreateDropView-Rework konfigurierbar (2/4/8/12 h). Flutter liest es
  /// aus RTDB falls geschrieben, sonst 120 min = 2 h als iOS-Default.
  final int durationMinutes;

  /// Freitext-Beschreibung des Drops; wird in Detail-Sheet angezeigt.
  final String dropDescription;

  DateTime get expiresAtDate =>
      DateTime.fromMillisecondsSinceEpoch((expiresAt * 1000).round());

  DateTime get startAtDate =>
      DateTime.fromMillisecondsSinceEpoch((startAt * 1000).round());

  bool get isExpired => DateTime.now().isAfter(expiresAtDate);

  /// iOS-Parität zu `DropEvent.scheduledStartOffset`.
  static Duration scheduledStartOffset(String scheduledTime) {
    switch (scheduledTime) {
      case 'In 30 Min':
        return const Duration(minutes: 30);
      case 'In 1 Std':
        return const Duration(hours: 1);
      case 'In 2 Std':
        return const Duration(hours: 2);
      default:
        return Duration.zero; // "Jetzt", "Heute Abend" oder unbekannt
    }
  }

  /// Baut eine Runde aus einem RTDB-Snapshot-Map. `id` ist der Firebase-
  /// Key den Snapshot.key liefert — nicht in der Map selbst.
  factory Runde.fromMap(String id, Map<Object?, Object?> raw) {
    double toD(Object? v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    int toI(Object? v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
    String toS(Object? v) => v?.toString() ?? '';

    return Runde(
      id: id,
      hostUID: toS(raw['userID']),
      hostName: toS(raw['displayName']),
      emoji: toS(raw['emoji']),
      activityName: toS(raw['activityName']),
      lat: toD(raw['lat']),
      lng: toD(raw['lng']),
      radius: toD(raw['radius']),
      timestampMs: toI(raw['timestamp']),
      expiresAt: toD(raw['expiresAt']),
      scheduledTime: toS(raw['scheduledTime']),
      startAt: toD(raw['startAt']),
      maxParticipants: toI(raw['maxParticipants']),
      currentParticipants: raw['currentParticipants'] == null
          ? 1
          : toI(raw['currentParticipants']),
      active: raw['active'] == true,
      hostGender: raw['hostGender']?.toString(),
      hostAge: raw['hostAge'] == null ? null : toI(raw['hostAge']),
      hostReliabilityPoints: raw['hostReliabilityPoints'] == null
          ? null
          : toI(raw['hostReliabilityPoints']),
      communityID: raw['communityID']?.toString(),
      hostProfileImageURL: raw['hostProfileImageURL']?.toString(),
      femaleOnly: raw['femaleOnly'] == true,
      durationMinutes: raw['durationMinutes'] == null
          ? 120
          : toI(raw['durationMinutes']),
      dropDescription: raw['dropDescription']?.toString() ??
          raw['description']?.toString() ??
          '',
    );
  }
}
