import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/dazu_colors.dart';

/// Reliability-Tier-Label — matcht iOS `ReliabilityScore.badge`.
enum ReliabilityTier {
  dropout,  // < 0  Punkte
  restart,  // 0–49
  explorer, // 50–199
  regular,  // 200–499
  legend;   // ≥ 500

  /// TODO: via L10n `tier.<key>` ersetzen sobald Views migriert sind.
  String get label {
    switch (this) {
      case ReliabilityTier.dropout:
        return 'Vorsicht';
      case ReliabilityTier.restart:
        return 'Neu dabei';
      case ReliabilityTier.explorer:
        return 'Drop-Entdecker';
      case ReliabilityTier.regular:
        return 'Drop-Stammgast';
      case ReliabilityTier.legend:
        return 'Drop-Legende';
    }
  }

  IconData get icon {
    switch (this) {
      case ReliabilityTier.dropout:
        return Icons.warning_amber_rounded;
      case ReliabilityTier.restart:
        return Icons.eco;
      case ReliabilityTier.explorer:
        return Icons.visibility;
      case ReliabilityTier.regular:
        return Icons.star;
      case ReliabilityTier.legend:
        return Icons.workspace_premium;
    }
  }

  Color get color {
    switch (this) {
      case ReliabilityTier.dropout:
        return const Color(0xFFEF4444); // Rot
      case ReliabilityTier.restart:
        return DazuColors.brandOrange;
      case ReliabilityTier.explorer:
        return const Color(0xFFF59E0B); // Amber
      case ReliabilityTier.regular:
        return const Color(0xFF22C55E); // Grün
      case ReliabilityTier.legend:
        return DazuColors.brandViolet;
    }
  }

  ReliabilityTier? get next {
    final idx = ReliabilityTier.values.indexOf(this);
    if (idx + 1 >= ReliabilityTier.values.length) return null;
    return ReliabilityTier.values[idx + 1];
  }
}

/// Zuverlässigkeits-Score eines Users — vollständige iOS-Parität zu
/// `ReliabilityScore` in `Drops/DesignSystem.swift:560-672`.
///
/// Punkteschema (2.0.2, Launch-Phase):
///   Start                100
///   + Join + Vor Ort     +20  pro Joiner-Ankunft
///   + Host + hat Erfolg  +12  pro Host-Erfolg
///   - No-Show            -25  pro ausgefallenem Drop
///   + Streak-Bonus       +20  pro 5er-Block ohne No-Show (siehe
///                             `streakBonusPoints` als Akkumulator)
///   + Erster vor Ort     +5
///   + Drop-Einladung     +10  pro Einladung die ankam
///   + Neuling-Host-Bonus +3   pro neuem User bei deinem Drop
///   + App-Einladung      +25  pro Freund der neu installiert hat
///   + Create-Bonus       +5   pro erstelltem Drop (Launch-Motivation)
///   + Boost-Bonus        +5   wenn Create/Confirm während „Umgebung-
///                             leer"-Boost-Phase
///
/// Persistiert in `SharedPreferences` als Serie von Keys mit `ud_`-
/// Prefix (iOS-identisch für Dual-App-Testing).
@immutable
class ReliabilityScore {
  const ReliabilityScore({
    this.showUps = 0,
    this.noShows = 0,
    this.hostSuccesses = 0,
    this.streakBonusPoints = 0,
    this.firstArrivalPoints = 0,
    this.dropInvitesPoints = 0,
    this.newcomerHostPoints = 0,
    this.appInvitesPoints = 0,
    this.creationBonusPoints = 0,
    this.boostBonusPoints = 0,
    this.currentStreak = 0,
  });

  // ── Grund-Counter ──────────────────────────────────────────────────
  final int showUps;
  final int noShows;
  final int hostSuccesses;

  // ── Bonus-Akkumulatoren ────────────────────────────────────────────
  final int streakBonusPoints;
  final int firstArrivalPoints;
  final int dropInvitesPoints;
  final int newcomerHostPoints;
  final int appInvitesPoints;
  final int creationBonusPoints;
  final int boostBonusPoints;

  final int currentStreak;

  // ── Konstanten (iOS DesignSystem.swift:579-582) ────────────────────
  static const int startingPoints = 100;
  static const int pointsPerShowUp = 20;
  static const int pointsPerHostSuccess = 12;
  static const int pointsPerNoShow = -25;

  /// Trust-Schwelle (iOS 2.0.2 vereinfachtes Modell, DesignSystem:682):
  /// Statt 5 sichtbarer Tier-Stufen zeigt die 2.0.2-UI nur noch ein
  /// binäres ✓-Badge, sobald der User diese Punktzahl erreicht hat.
  /// Der volle Score läuft intern weiter (Spam-Detection, später evtl.
  /// wieder sichtbar).
  static const int trustThreshold = 200;

  // ── Abgeleitete Werte ──────────────────────────────────────────────
  int get totalCommits => showUps + hostSuccesses;

  int get bonusPoints =>
      streakBonusPoints +
      firstArrivalPoints +
      dropInvitesPoints +
      newcomerHostPoints +
      appInvitesPoints +
      creationBonusPoints +
      boostBonusPoints;

  int get points {
    final joinArrivals = (showUps - hostSuccesses).clamp(0, 1 << 30);
    return startingPoints +
        joinArrivals * pointsPerShowUp +
        hostSuccesses * pointsPerHostSuccess +
        noShows * pointsPerNoShow +
        bonusPoints;
  }

  /// 2.0.2 binäres Trust-Badge — true wenn Punkte ≥ `trustThreshold`.
  bool get isTrusted => points >= trustThreshold;

  /// Trust-Progress 0..1 für Settings-Progress-Balken (iOS
  /// DesignSystem:706 `tierProgress(forPoints:)`).
  double get trustProgress {
    final p = points;
    if (p <= 0) return 0;
    if (p >= trustThreshold) return 1;
    return p / trustThreshold;
  }

  ReliabilityTier get tier {
    final p = points;
    if (p < 0) return ReliabilityTier.dropout;
    if (p < 50) return ReliabilityTier.restart;
    if (p < 200) return ReliabilityTier.explorer;
    if (p < 500) return ReliabilityTier.regular;
    return ReliabilityTier.legend;
  }

  /// „Willkommen"-Pseudo-Tier wenn noch nichts passiert ist, sonst
  /// `tier.label`. iOS: `displayLabel`.
  String get displayLabel => totalCommits == 0 ? 'Willkommen bei dazu' : tier.label;

  /// Verbleibende Punkte bis zum nächsten Tier, oder `null` bei Legend.
  int? get pointsToNextTier {
    final p = points;
    if (p < 0) return -p;
    if (p < 50) return 50 - p;
    if (p < 200) return 200 - p;
    if (p < 500) return 500 - p;
    return null;
  }

  /// 0.0–1.0 Fortschritt innerhalb des aktuellen Tiers.
  double get tierProgress {
    final p = points;
    if (p < 0) return 0;
    if (p < 50) return p / 50.0;
    if (p < 200) return (p - 50) / 150.0;
    if (p < 500) return (p - 200) / 300.0;
    return 1.0;
  }

  // ── Mutations als copyWith (immutable Modell) ──────────────────────
  ReliabilityScore copyWith({
    int? showUps,
    int? noShows,
    int? hostSuccesses,
    int? streakBonusPoints,
    int? firstArrivalPoints,
    int? dropInvitesPoints,
    int? newcomerHostPoints,
    int? appInvitesPoints,
    int? creationBonusPoints,
    int? boostBonusPoints,
    int? currentStreak,
  }) =>
      ReliabilityScore(
        showUps: showUps ?? this.showUps,
        noShows: noShows ?? this.noShows,
        hostSuccesses: hostSuccesses ?? this.hostSuccesses,
        streakBonusPoints: streakBonusPoints ?? this.streakBonusPoints,
        firstArrivalPoints: firstArrivalPoints ?? this.firstArrivalPoints,
        dropInvitesPoints: dropInvitesPoints ?? this.dropInvitesPoints,
        newcomerHostPoints: newcomerHostPoints ?? this.newcomerHostPoints,
        appInvitesPoints: appInvitesPoints ?? this.appInvitesPoints,
        creationBonusPoints: creationBonusPoints ?? this.creationBonusPoints,
        boostBonusPoints: boostBonusPoints ?? this.boostBonusPoints,
        currentStreak: currentStreak ?? this.currentStreak,
      );

  // ── SharedPreferences I/O (iOS UDKey-Parität) ──────────────────────
  // Keys matchen 1:1 die privaten UDKey-Konstanten in iOS
  // `Models.swift:778-813`.
  static const _kShows = 'ud_reliabilityShows';
  static const _kNoShows = 'ud_reliabilityNoShows';
  static const _kHostOK = 'ud_reliabilityHostOK';
  static const _kStreakB = 'ud_reliabilityStreakB';
  static const _kFirstB = 'ud_reliabilityFirstB';
  static const _kInviteB = 'ud_reliabilityInviteB';
  static const _kNewcB = 'ud_reliabilityNewcB';
  static const _kAppInvB = 'ud_reliabilityAppInvB';
  static const _kCreateB = 'ud_reliabilityCreateB';
  static const _kBoostB = 'ud_reliabilityBoostB';
  static const _kStreak = 'ud_reliabilityStreak';

  static Future<ReliabilityScore> loadFromPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      return ReliabilityScore(
        showUps: p.getInt(_kShows) ?? 0,
        noShows: p.getInt(_kNoShows) ?? 0,
        hostSuccesses: p.getInt(_kHostOK) ?? 0,
        streakBonusPoints: p.getInt(_kStreakB) ?? 0,
        firstArrivalPoints: p.getInt(_kFirstB) ?? 0,
        dropInvitesPoints: p.getInt(_kInviteB) ?? 0,
        newcomerHostPoints: p.getInt(_kNewcB) ?? 0,
        appInvitesPoints: p.getInt(_kAppInvB) ?? 0,
        creationBonusPoints: p.getInt(_kCreateB) ?? 0,
        boostBonusPoints: p.getInt(_kBoostB) ?? 0,
        currentStreak: p.getInt(_kStreak) ?? 0,
      );
    } catch (_) {
      return const ReliabilityScore();
    }
  }

  Future<void> saveToPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await Future.wait([
        p.setInt(_kShows, showUps),
        p.setInt(_kNoShows, noShows),
        p.setInt(_kHostOK, hostSuccesses),
        p.setInt(_kStreakB, streakBonusPoints),
        p.setInt(_kFirstB, firstArrivalPoints),
        p.setInt(_kInviteB, dropInvitesPoints),
        p.setInt(_kNewcB, newcomerHostPoints),
        p.setInt(_kAppInvB, appInvitesPoints),
        p.setInt(_kCreateB, creationBonusPoints),
        p.setInt(_kBoostB, boostBonusPoints),
        p.setInt(_kStreak, currentStreak),
      ]);
    } catch (_) {}
  }
}
