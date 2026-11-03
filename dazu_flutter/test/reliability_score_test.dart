import 'package:flutter_test/flutter_test.dart';
import 'package:dazu_flutter/models/reliability_score.dart';

void main() {
  group('ReliabilityScore', () {
    test('default start = 100 points, explorer tier', () {
      const r = ReliabilityScore();
      expect(r.points, 100);
      expect(r.tier, ReliabilityTier.explorer);
    });

    test('2 joiner arrivals (no host) = +40', () {
      const r = ReliabilityScore(showUps: 2);
      expect(r.points, 140);
    });

    test('1 host + 1 join (showUps=2, hostSuccesses=1) = +12 +20', () {
      const r = ReliabilityScore(showUps: 2, hostSuccesses: 1);
      expect(r.points, 132);
    });

    test('5 no-shows → dropout tier (negative points)', () {
      const r = ReliabilityScore(noShows: 5);
      expect(r.points, -25);
      expect(r.tier, ReliabilityTier.dropout);
    });

    test('legend at 500 points', () {
      const r = ReliabilityScore(showUps: 20);
      expect(r.points, 500);
      expect(r.tier, ReliabilityTier.legend);
      expect(r.pointsToNextTier, isNull);
      expect(r.tierProgress, 1.0);
    });

    test('explorer progress at 100 = 33%', () {
      const r = ReliabilityScore();
      expect((r.tierProgress * 100).round(), 33);
      expect(r.pointsToNextTier, 100);
    });

    test('showUps counts arrivals; hostSuccesses are subtracted', () {
      // showUps = 5, hostSuccesses = 2 → joinArrivals = 3, hostOK = 2
      // => 100 + 3*20 + 2*12 = 184
      const r = ReliabilityScore(showUps: 5, hostSuccesses: 2);
      expect(r.points, 184);
    });

    test('bonus points sum correctly', () {
      const r = ReliabilityScore(
        streakBonusPoints: 20,
        firstArrivalPoints: 5,
        dropInvitesPoints: 10,
      );
      // base 100 + 20 + 5 + 10 = 135
      expect(r.points, 135);
    });

    test('isTrusted flips at trustThreshold (200)', () {
      // 100 base + 100 bonus = 200
      const almost = ReliabilityScore(streakBonusPoints: 99);
      expect(almost.points, 199);
      expect(almost.isTrusted, isFalse);

      const exact = ReliabilityScore(streakBonusPoints: 100);
      expect(exact.points, 200);
      expect(exact.isTrusted, isTrue);
    });

    test('trustProgress linear from 0 to 1', () {
      // 100 base = 0.5
      const r = ReliabilityScore();
      expect(r.trustProgress, closeTo(0.5, 1e-9));

      // 200 base + bonus → 1.0 (geklippt)
      const over = ReliabilityScore(streakBonusPoints: 200);
      expect(over.trustProgress, 1.0);

      // negative → 0.0
      const neg = ReliabilityScore(noShows: 10);
      expect(neg.trustProgress, 0.0);
    });
  });
}
