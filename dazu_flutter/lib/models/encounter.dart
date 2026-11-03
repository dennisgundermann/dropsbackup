import 'package:flutter/foundation.dart';

/// „Du warst gerade mit X unterwegs — war das ein Treffen?"-Prompt.
/// iOS: `Encounter` in `Drops/Models.swift`.
@immutable
class Encounter {
  const Encounter({
    required this.id,
    required this.friendName,
    required this.friendEmoji,
    required this.activityEmoji,
    required this.activityName,
    required this.createdAt,
    this.confirmed = false,
    this.denied = false,
    this.friendUID,
    this.friendProfileImageURL,
    this.dropID,
    this.seenByUser = false,
  });

  final String id;
  final String friendName;
  final String friendEmoji;
  final String activityEmoji;
  final String activityName;
  final DateTime createdAt;
  final bool confirmed;
  final bool denied;
  final String? friendUID;
  final String? friendProfileImageURL;
  final String? dropID;
  final bool seenByUser;

  /// Nach 12 h läuft der Confirm-Prompt ab.
  static const Duration confirmationWindow = Duration(hours: 12);

  bool get isExpired =>
      DateTime.now().isAfter(createdAt.add(confirmationWindow));

  Duration get timeRemaining {
    final total = createdAt.add(confirmationWindow).difference(DateTime.now());
    return total.isNegative ? Duration.zero : total;
  }

  int get remainingHours => timeRemaining.inHours;
  int get remainingMinutes => timeRemaining.inMinutes % 60;

  String get timeAgoLabel {
    final mins = DateTime.now().difference(createdAt).inMinutes;
    if (mins < 1) return 'Gerade eben';
    if (mins < 60) return 'Vor $mins Min';
    final h = mins ~/ 60;
    return h == 1 ? 'Vor 1 Std' : 'Vor $h Std';
  }

  Encounter copyWith({
    bool? confirmed,
    bool? denied,
    bool? seenByUser,
  }) =>
      Encounter(
        id: id,
        friendName: friendName,
        friendEmoji: friendEmoji,
        activityEmoji: activityEmoji,
        activityName: activityName,
        createdAt: createdAt,
        confirmed: confirmed ?? this.confirmed,
        denied: denied ?? this.denied,
        friendUID: friendUID,
        friendProfileImageURL: friendProfileImageURL,
        dropID: dropID,
        seenByUser: seenByUser ?? this.seenByUser,
      );
}
