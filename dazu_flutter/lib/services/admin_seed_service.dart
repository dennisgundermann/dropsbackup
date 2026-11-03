import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// Lightweight-Demo-Seed für App-Store-Screenshots. Pendant zum iOS-
/// Admin-Panel-Button. Schreibt 4 Mock-Runden mit `isDemoLive: true`
/// um Dennis-Zentrum herum — iOS räumt sie via Admin-Button
/// „Demo-Runden löschen" wieder weg.
class AdminSeedService {
  AdminSeedService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  /// Löscht alle Mock-Freunde aus `/friends/<me>/mock_*`. Pendant zu
  /// iOS-AdminPanel-Räumbutton — die Seeder-UIDs haben alle Prefix
  /// `mock_`.
  Future<int> purgeMockFriends() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return 0;
    final snap = await _db.ref('friends').child(me).get();
    final v = snap.value;
    if (v is! Map) return 0;
    var removed = 0;
    for (final k in v.keys.toList()) {
      final uid = k.toString();
      if (uid.startsWith('mock_')) {
        await _db.ref('friends').child(me).child(uid).remove();
        removed++;
      }
    }
    return removed;
  }

  /// Räumt alle Runden mit `isDemoLive: true` auf — pendant zu iOS
  /// Admin-Button „Demo-Runden löschen".
  Future<int> purgeDemoRunden() async {
    final snap = await _db.ref('drops').get();
    final v = snap.value;
    if (v is! Map) return 0;
    var removed = 0;
    for (final e in v.entries) {
      final child = e.value;
      if (child is Map && child['isDemoLive'] == true) {
        await _db.ref('drops').child(e.key.toString()).remove();
        await _db.ref('dropins').child(e.key.toString()).remove();
        removed++;
      }
    }
    return removed;
  }

  Future<int> seedDemoRunden({
    required double centerLat,
    required double centerLng,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return 0;
    final rand = Random();
    final seeds = <_Seed>[
      _Seed(activity: 'Kaffee', emoji: '☕', host: 'Sophie', age: 27, mins: 60),
      _Seed(activity: 'Yoga', emoji: '🧘', host: 'Lea', age: 28, mins: 90),
      _Seed(activity: 'Lauftreff', emoji: '🏃', host: 'Felix', age: 31, mins: 60),
      _Seed(activity: 'Padel', emoji: '🏓', host: 'Jana', age: 26, mins: 120),
    ];
    final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    double jitter() => (rand.nextDouble() - 0.5) * 0.012;
    for (final s in seeds) {
      final ref = _db.ref('drops').push();
      await ref.set({
        'userID': me.uid,
        'displayName': s.host,
        'emoji': s.emoji,
        'activityName': s.activity,
        'lat': centerLat + jitter(),
        'lng': centerLng + jitter(),
        'radius': 500,
        'timestamp': ServerValue.timestamp,
        'startAt': createdAt,
        'expiresAt': createdAt + s.mins * 60,
        'scheduledTime': 'Jetzt',
        'maxParticipants': 10,
        'currentParticipants': 1 + rand.nextInt(4),
        'active': true,
        'isDemoLive': true,
        'hostAge': s.age,
      });
    }
    return seeds.length;
  }
}

class _Seed {
  _Seed(
      {required this.activity,
      required this.emoji,
      required this.host,
      required this.age,
      required this.mins});
  final String activity;
  final String emoji;
  final String host;
  final int age;
  final int mins;
}
