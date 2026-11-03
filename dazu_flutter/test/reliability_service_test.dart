import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dazu_flutter/services/reliability_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    // Reset the singleton's state zwischen Tests, damit sich die
    // Counter nicht über Tests hinweg aufsummieren.
    await ReliabilityService.instance.resetAll();
  });

  group('ReliabilityService wiring', () {
    test('recordDropCreated bumps creationBonusPoints by 10', () async {
      final s = ReliabilityService.instance;
      final before = s.score.points;
      await s.recordDropCreated();
      expect(s.score.points, before + 10);
      expect(s.score.creationBonusPoints, 10);
    });

    test('recordJoinerArrival bumps showUps + streak', () async {
      final s = ReliabilityService.instance;
      await s.recordJoinerArrival();
      expect(s.score.showUps, 1);
      expect(s.score.currentStreak, 1);
    });

    test('recordNoShow resets streak', () async {
      final s = ReliabilityService.instance;
      await s.recordJoinerArrival();
      await s.recordJoinerArrival();
      expect(s.score.currentStreak, 2);
      await s.recordNoShow();
      expect(s.score.currentStreak, 0);
      expect(s.score.noShows, 1);
    });

    test('fifth arrival auto-triggers streak milestone (+20)', () async {
      final s = ReliabilityService.instance;
      // Vier Arrivals: 100 + 4*20 = 180, kein Milestone
      for (var i = 0; i < 4; i++) {
        await s.recordJoinerArrival();
      }
      expect(s.score.points, 180);
      expect(s.score.streakBonusPoints, 0);

      // Fünfte löst +20 aus → 100 + 5*20 + 20 = 220
      await s.recordJoinerArrival();
      expect(s.score.currentStreak, 5);
      expect(s.score.streakBonusPoints, 20);
      expect(s.score.points, 220);
      expect(s.score.isTrusted, isTrue);  // 220 ≥ 200
    });

    test('ten arrivals = two milestones (+40 total)', () async {
      final s = ReliabilityService.instance;
      for (var i = 0; i < 10; i++) {
        await s.recordJoinerArrival();
      }
      expect(s.score.streakBonusPoints, 40);
      expect(s.score.points, 100 + 10 * 20 + 40);  // 340
    });

    test('persistence survives round-trip', () async {
      final s = ReliabilityService.instance;
      await s.recordJoinerArrival();
      await s.recordDropCreated();
      // Reload directly from SharedPrefs via the model
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('ud_reliabilityShows'), 1);
      expect(prefs.getInt('ud_reliabilityCreateB'), 10);
    });

    test('claimFirstHostBonus fires once, grants +10, persists flag', () async {
      final s = ReliabilityService.instance;
      final beforePts = s.score.points;

      final firstClaim = await s.claimFirstHostBonus();
      expect(firstClaim, isTrue);
      expect(s.score.points, beforePts + 10);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('ud_firstHostBonusReceived'), isTrue);

      // Second claim is a no-op
      final secondClaim = await s.claimFirstHostBonus();
      expect(secondClaim, isFalse);
      expect(s.score.points, beforePts + 10);
    });

    test('claimFirstJoinBonus is independent of HostBonus', () async {
      final s = ReliabilityService.instance;
      await s.claimFirstHostBonus();
      final afterHost = s.score.points;

      final joinClaim = await s.claimFirstJoinBonus();
      expect(joinClaim, isTrue);
      expect(s.score.points, afterHost + 10);
    });
  });
}
