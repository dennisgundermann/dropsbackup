import 'package:flutter/foundation.dart';

/// Teilnehmer eines beendeten Drops, wie er im Verlauf im Profil
/// angezeigt wird. iOS: `PastDropParticipant` in `Drops/Models.swift`.
@immutable
class PastDropParticipant {
  const PastDropParticipant({
    required this.name,
    required this.emoji,
    required this.reliabilityScore,
    this.wasHost = false,
    this.didShowUp = true,
    this.profileImageURL,
  });

  final String name;
  final String emoji;
  final int reliabilityScore;
  final bool wasHost;
  final bool didShowUp;
  final String? profileImageURL;

  Map<String, dynamic> toJson() => {
        'name': name,
        'emoji': emoji,
        'reliabilityScore': reliabilityScore,
        'wasHost': wasHost,
        'didShowUp': didShowUp,
        if (profileImageURL != null) 'profileImageURL': profileImageURL,
      };

  factory PastDropParticipant.fromJson(Map<String, dynamic> j) {
    return PastDropParticipant(
      name: j['name']?.toString() ?? '',
      emoji: j['emoji']?.toString() ?? '',
      reliabilityScore: (j['reliabilityScore'] as num?)?.toInt() ?? 100,
      wasHost: j['wasHost'] == true,
      didShowUp: j['didShowUp'] != false,
      profileImageURL: j['profileImageURL']?.toString(),
    );
  }
}

/// Ein beendeter Drop im User-Verlauf — in `SharedPreferences` persistiert
/// (Key `ud_pastDrops` als JSON-Array, wie iOS).
@immutable
class PastDrop {
  const PastDrop({
    required this.id,
    required this.activityEmoji,
    required this.activityName,
    required this.locationName,
    required this.date,
    required this.wasHost,
    required this.participants,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String activityEmoji;
  final String activityName;
  final String locationName;
  final DateTime date;
  final bool wasHost;
  final List<PastDropParticipant> participants;
  final double? latitude;
  final double? longitude;

  int get participantCount => participants.length;

  /// Durchschnittliche Reliability aller Teilnehmer, auf 100 gekappt.
  int get avgReliability {
    if (participants.isEmpty) return 100;
    final total = participants
        .map((p) => p.reliabilityScore.clamp(0, 100))
        .fold<int>(0, (a, b) => a + b);
    return (total / participants.length).round();
  }

  /// „Heute · 18:42" / „Gestern · 20:15" / „Mi · 14:30".
  String dateLabel() {
    final now = DateTime.now();
    final sameDay = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    if (sameDay) return 'Heute';
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day;
    if (isYesterday) return 'Gestern';
    const wd = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return wd[date.weekday - 1];
  }

  String timeLabel() {
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'activityEmoji': activityEmoji,
        'activityName': activityName,
        'locationName': locationName,
        'date': date.toIso8601String(),
        'wasHost': wasHost,
        'participants': participants.map((p) => p.toJson()).toList(),
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      };

  factory PastDrop.fromJson(Map<String, dynamic> j) {
    final rawParts = (j['participants'] as List?) ?? const [];
    return PastDrop(
      id: j['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      activityEmoji: j['activityEmoji']?.toString() ?? '',
      activityName: j['activityName']?.toString() ?? '',
      locationName: j['locationName']?.toString() ?? '',
      date: DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime.now(),
      wasHost: j['wasHost'] == true,
      participants: rawParts
          .whereType<Map>()
          .map((m) => PastDropParticipant.fromJson(Map<String, dynamic>.from(m)))
          .toList(growable: false),
      latitude: (j['latitude'] as num?)?.toDouble(),
      longitude: (j['longitude'] as num?)?.toDouble(),
    );
  }
}
