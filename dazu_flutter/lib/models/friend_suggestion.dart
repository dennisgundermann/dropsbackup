import 'package:flutter/foundation.dart';

/// Vorschlag „Du kennst vielleicht …" im Freundes-Tab. iOS:
/// `FriendSuggestion` in `Drops/Models.swift`.
@immutable
class FriendSuggestion {
  const FriendSuggestion({
    required this.id,
    required this.name,
    required this.emoji,
    required this.mutualFriend,
    this.dismissed = false,
  });

  final String id;
  final String name;
  final String emoji;
  final String mutualFriend;
  final bool dismissed;

  FriendSuggestion copyWith({bool? dismissed}) => FriendSuggestion(
        id: id,
        name: name,
        emoji: emoji,
        mutualFriend: mutualFriend,
        dismissed: dismissed ?? this.dismissed,
      );
}
