import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reliability_score.dart';

/// Zentrale Mutations-API für den Reliability-Score. Spiegelt die
/// verteilten Side-Effects aus iOS `AppStore` (Models.swift ~2835-6355)
/// an einem einzigen Ort: Views und Services rufen hier `record*`-
/// Methoden auf, der Service persistiert sofort und notified Listener.
///
/// Beispiel-Hooks (noch nicht alle gewired):
///   • CreateScreen._publish → `recordDropCreated()`
///   • Joiner-OnSite-Trigger  → `recordJoinerArrival()`
///   • Host-Cancel (≥2 Teilnehmer) → `recordHostSuccess()`
///   • Host-Cancel (ohne Teilnehmer, pending ≥12 min) → `recordNoShow()`
///   • Freund-Install (deep-link Attribution) → `recordAppInvite()`
class ReliabilityService extends ChangeNotifier {
  ReliabilityService._() {
    _bootstrap();
  }
  static final ReliabilityService instance = ReliabilityService._();

  ReliabilityScore _score = const ReliabilityScore();
  ReliabilityScore get score => _score;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> _bootstrap() async {
    _score = await ReliabilityScore.loadFromPrefs();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _apply(ReliabilityScore next) async {
    _score = next;
    notifyListeners();
    await _score.saveToPrefs();
  }

  // ── Core Events ─────────────────────────────────────────────────────

  /// Joiner ist beim Drop angekommen (Vor-Ort via GPS/BLE bestätigt).
  /// iOS schreibt +20 Pkt (`pointsPerShowUp`), hier über Counter-Inkrement.
  Future<void> recordJoinerArrival() async {
    await _apply(_score.copyWith(
      showUps: _score.showUps + 1,
      currentStreak: _score.currentStreak + 1,
    ));
    await _checkStreakMilestone();
  }

  /// Host hat einen Drop erfolgreich gehostet (≥1 Teilnehmer kam).
  /// iOS zählt auch showUps hoch, damit das als Anwesenheit zählt.
  Future<void> recordHostSuccess() async {
    await _apply(_score.copyWith(
      hostSuccesses: _score.hostSuccesses + 1,
      showUps: _score.showUps + 1,
      currentStreak: _score.currentStreak + 1,
    ));
    await _checkStreakMilestone();
  }

  /// Jeder 5er-Block ohne No-Show löst +20 Pkt aus
  /// (iOS Models.swift: ReliabilityScore.currentStreak docs).
  Future<void> _checkStreakMilestone() async {
    if (_score.currentStreak > 0 && _score.currentStreak % 5 == 0) {
      await recordStreakMilestone();
    }
  }

  /// No-Show (Joiner nicht erschienen, oder Host hat ohne gewarteten
  /// Joiner abgebrochen). Setzt Streak zurück.
  Future<void> recordNoShow() => _apply(_score.copyWith(
        noShows: _score.noShows + 1,
        currentStreak: 0,
      ));

  // ── Bonus Events ────────────────────────────────────────────────────

  /// +10 Pkt für Drop-Erstellung (Launch-Phase-Motivation).
  Future<void> recordDropCreated() => _apply(_score.copyWith(
        creationBonusPoints: _score.creationBonusPoints + 10,
      ));

  // ── First-Drop Flags ────────────────────────────────────────────────
  // iOS persistiert diese Flags separat von den Score-Countern (UDKey
  // `firstHostBonusReceived`), damit der Erst-Bonus nur EINMAL pro
  // Account vergeben wird. `claimFirstHostBonus()` liefert true genau
  // beim ersten Mal — Caller zeigt dann die Celebration-UI an.
  static const String _kFirstHostBonusReceived = 'ud_firstHostBonusReceived';
  static const String _kFirstJoinBonusReceived = 'ud_firstJoinBonusReceived';

  /// Claimt den Erst-Host-Bonus. Rückgabe true nur beim ersten Mal.
  Future<bool> claimFirstHostBonus() =>
      _claimFirstBonus(_kFirstHostBonusReceived);

  /// Claimt den Erst-Join-Bonus. Rückgabe true nur beim ersten Mal.
  Future<bool> claimFirstJoinBonus() =>
      _claimFirstBonus(_kFirstJoinBonusReceived);

  Future<bool> _claimFirstBonus(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(key) == true) return false;
      await prefs.setBool(key, true);
      // Bonus-Punkte zusätzlich (iOS gibt beim ersten Host-Success +10).
      await _apply(_score.copyWith(
        creationBonusPoints: _score.creationBonusPoints + 10,
      ));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// +10 Pkt für „als Erster vor Ort gewesen".
  Future<void> recordFirstArrival() => _apply(_score.copyWith(
        firstArrivalPoints: _score.firstArrivalPoints + 10,
      ));

  /// +N Pkt wenn ein Freund einem per Deep-Link angelegten Drop beitritt.
  Future<void> recordDropInviteAccepted({int bonus = 10}) =>
      _apply(_score.copyWith(
        dropInvitesPoints: _score.dropInvitesPoints + bonus,
      ));

  /// +3 pro neuem User (first-time Joiner) bei meinem Drop.
  Future<void> recordNewcomerHosted({int bonus = 3}) =>
      _apply(_score.copyWith(
        newcomerHostPoints: _score.newcomerHostPoints + bonus,
      ));

  /// +25 pro Freund der die App frisch installiert + onboarded hat.
  Future<void> recordAppInviteSucceeded() => _apply(_score.copyWith(
        appInvitesPoints: _score.appInvitesPoints + 25,
      ));

  /// Variabler Boost-Bonus (iOS: +5–10 wenn Umgebung „leer" ist).
  Future<void> recordBoostBonus(int bonus) => _apply(_score.copyWith(
        boostBonusPoints: _score.boostBonusPoints + bonus,
      ));

  /// Streak-Bonus-Trigger (iOS: alle 5 Drops ohne No-Show +20 Pkt).
  /// Caller prüft die 5er-Logik und ruft explizit auf.
  Future<void> recordStreakMilestone() => _apply(_score.copyWith(
        streakBonusPoints: _score.streakBonusPoints + 20,
      ));

  // ── Debug / Admin ───────────────────────────────────────────────────

  /// Reset — nur für Admin-Panel-Testing. Nicht in User-UI zeigen.
  Future<void> resetAll() => _apply(const ReliabilityScore());
}
