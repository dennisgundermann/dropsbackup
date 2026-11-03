import 'package:flutter/foundation.dart';

enum AlertStatus { pending, accepted, declined }

/// Benachrichtigungseintrag im Profile/Alerts-Tab (iOS
/// `ProfileAndAlertsView`). Rein lokale Repräsentation einer in Firebase
/// liegenden Alert-Quelle — die Alert-Items selbst werden gerade on-the-
/// fly aus Pushes, JoinRequests und Encountern aggregiert.
@immutable
class AlertItem {
  const AlertItem({
    required this.id,
    required this.emoji,
    required this.name,
    required this.activity,
    required this.eta,
    this.status = AlertStatus.pending,
  });

  final int id;
  final String emoji;
  final String name;
  final String activity;
  final String eta;
  final AlertStatus status;

  AlertItem copyWith({AlertStatus? status}) => AlertItem(
        id: id,
        emoji: emoji,
        name: name,
        activity: activity,
        eta: eta,
        status: status ?? this.status,
      );
}
