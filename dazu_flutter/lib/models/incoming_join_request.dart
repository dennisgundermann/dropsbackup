import 'package:flutter/foundation.dart';

/// Host-Perspektive einer Beitrittsanfrage. Zeigt dem Host den Joiner
/// mit Entfernung, Reliability-Score und optionaler Nachricht, bevor
/// er Accept/Decline drückt.
///
/// Unterschied zum bestehenden `JoinRequest` (Joiner-Status in Drop-
/// Detail-Sheet): dieses Modell wird vom Host-Device beobachtet und
/// kennt zusätzlich `joinerDistanceMeters` + Auto-Accept-Timer.
///
/// iOS: `IncomingJoinRequest` in `Drops/Models.swift`.
@immutable
class IncomingJoinRequest {
  const IncomingJoinRequest({
    required this.joinerID,
    required this.dropID,
    required this.joinerName,
    required this.joinerEmoji,
    required this.requestedAt,
    this.joinerAge,
    this.joinerProfileImageURL,
    this.joinerReliabilityPoints = 100,
    this.joinerIsPlus = false,
    this.joinerDistanceMeters,
    this.joinerMessage,
  });

  /// Firebase-Key des Joiners — matcht iOS `id`.
  final String joinerID;
  final String dropID;
  final String joinerName;
  final String joinerEmoji;
  final int? joinerAge;
  final String? joinerProfileImageURL;
  final int joinerReliabilityPoints;
  final bool joinerIsPlus;

  /// Vom Host clientseitig berechnet aus `/dropins/.../lat,lng` ↔
  /// `/drops/.../lat,lng`.
  final double? joinerDistanceMeters;

  final String? joinerMessage;
  final DateTime requestedAt;

  /// Nach 5 Min Auto-Accept wenn Host nicht reagiert.
  static const Duration autoAcceptDelay = Duration(minutes: 5);

  DateTime get autoAcceptAt => requestedAt.add(autoAcceptDelay);

  bool get shouldAutoAccept => DateTime.now().isAfter(autoAcceptAt) ||
      DateTime.now().isAtSameMomentAs(autoAcceptAt);

  int get waitingMinutes {
    final mins = DateTime.now().difference(requestedAt).inMinutes;
    return mins < 0 ? 0 : mins;
  }

  factory IncomingJoinRequest.fromMap(
    String joinerID,
    String dropID,
    Map<Object?, Object?> raw,
  ) {
    int? toI(Object? v) {
      if (v is num) return v.toInt();
      final s = v?.toString();
      return s == null ? null : int.tryParse(s);
    }

    double? toD(Object? v) {
      if (v is num) return v.toDouble();
      final s = v?.toString();
      return s == null ? null : double.tryParse(s);
    }

    final tsMs = toI(raw['requestedAt']) ?? toI(raw['timestamp']) ?? 0;
    return IncomingJoinRequest(
      joinerID: joinerID,
      dropID: dropID,
      joinerName: raw['name']?.toString() ?? '',
      joinerEmoji: raw['emoji']?.toString() ?? '',
      joinerAge: toI(raw['age']),
      joinerProfileImageURL: raw['profileImageURL']?.toString(),
      joinerReliabilityPoints: toI(raw['reliabilityPoints']) ?? 100,
      joinerIsPlus: raw['isPlusUser'] == true,
      joinerDistanceMeters: toD(raw['distanceMeters']),
      joinerMessage: raw['message']?.toString(),
      requestedAt: DateTime.fromMillisecondsSinceEpoch(tsMs),
    );
  }
}
