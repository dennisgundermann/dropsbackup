/// Variante des First-Drop-Celebration-Sheets — einmal pro Variante
/// pro User getriggert. iOS: `Drops/Models.swift` → `FirstDropCelebration`.
enum FirstDropCelebration {
  /// Erster eigener Drop erstellt.
  created,

  /// Erstem fremden Drop beigetreten.
  joined;

  String get id {
    switch (this) {
      case FirstDropCelebration.created:
        return 'created';
      case FirstDropCelebration.joined:
        return 'joined';
    }
  }

  /// TODO: in Localization-ARBs ablegen
  /// (`models.first_drop_created` / `models.first_drop_joined`).
  String get title {
    switch (this) {
      case FirstDropCelebration.created:
        return 'Deine erste Runde läuft!';
      case FirstDropCelebration.joined:
        return 'Du bist dabei!';
    }
  }

  String get body {
    switch (this) {
      case FirstDropCelebration.created:
        return 'Freunde in der Nähe sehen deine Runde jetzt in ihrer App '
            'und können dazukommen. Keep it chill — es muss nichts '
            'perfektes sein.';
      case FirstDropCelebration.joined:
        return 'Du hast deine erste Runde bestätigt. Der Host weiß dass '
            'du vorbeikommst — schau einfach vorbei, wenn du da bist.';
    }
  }
}
