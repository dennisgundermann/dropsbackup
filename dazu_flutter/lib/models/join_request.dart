import 'package:flutter/foundation.dart';

/// Pending-Beitrittsanfrage unter `/joinRequests/{dropID}/{joinerID}`.
/// Status: `pending` | `accepted` | `declined`.
@immutable
class JoinRequest {
  const JoinRequest({
    required this.joinerID,
    required this.name,
    required this.status,
    this.emoji,
    this.age,
    this.profileImageURL,
    this.reliabilityPoints,
    this.message,
    this.requestedAtMs,
  });

  final String joinerID;
  final String name;
  final String status;
  final String? emoji;
  final int? age;
  final String? profileImageURL;
  final int? reliabilityPoints;
  final String? message;
  final int? requestedAtMs;

  factory JoinRequest.fromMap(String joinerID, Map<Object?, Object?> raw) {
    int? toI(Object? v) {
      if (v is num) return v.toInt();
      final s = v?.toString();
      return s == null ? null : int.tryParse(s);
    }

    return JoinRequest(
      joinerID: joinerID,
      name: raw['name']?.toString() ?? '',
      status: raw['status']?.toString() ?? 'pending',
      emoji: raw['emoji']?.toString(),
      age: toI(raw['age']),
      profileImageURL: raw['profileImageURL']?.toString(),
      reliabilityPoints: toI(raw['reliabilityPoints']),
      message: raw['message']?.toString(),
      requestedAtMs: toI(raw['requestedAt']),
    );
  }

  bool get isPending => status == 'pending';
}
