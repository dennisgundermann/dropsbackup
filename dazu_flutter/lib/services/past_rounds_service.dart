import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Aggregat für Profil-„Dein Mix" + Hotspots.
@immutable
class MixActivity {
  const MixActivity({required this.name, required this.count});
  final String name;
  final int count;
}

@immutable
class HotspotPin {
  const HotspotPin({required this.lat, required this.lng});
  final double lat;
  final double lng;
}

@immutable
class PastRoundsStats {
  const PastRoundsStats({
    this.mix = const [],
    this.hotspots = const [],
  });
  final List<MixActivity> mix;
  final List<HotspotPin> hotspots;
}

/// Streamt `/users/<uid>/pastDrops`, zählt Aktivitäten für den „Dein
/// Mix"-Chip-Row (Top 6 nach Häufigkeit, stable sort) und extrahiert
/// Koordinaten für die Hotspot-Mini-Map.
class PastRoundsService {
  PastRoundsService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  Stream<PastRoundsStats> watchStats() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(const PastRoundsStats());
    return _db.ref('users').child(uid).child('pastDrops').onValue.map((e) {
      final v = e.snapshot.value;
      if (v is! Map) return const PastRoundsStats();
      final counts = <String, int>{};
      final pins = <HotspotPin>[];
      v.forEach((_, raw) {
        if (raw is Map) {
          final name = raw['activityName']?.toString() ??
              raw['activity']?.toString() ??
              '';
          if (name.isNotEmpty) {
            counts[name] = (counts[name] ?? 0) + 1;
          }
          final lat = (raw['lat'] is num) ? (raw['lat'] as num).toDouble() : null;
          final lng = (raw['lng'] is num) ? (raw['lng'] as num).toDouble() : null;
          if (lat != null && lng != null && (lat != 0 || lng != 0)) {
            pins.add(HotspotPin(lat: lat, lng: lng));
          }
        }
      });
      final mix = counts.entries
          .map((e) => MixActivity(name: e.key, count: e.value))
          .toList()
        ..sort((a, b) {
          if (a.count != b.count) return b.count.compareTo(a.count);
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      return PastRoundsStats(
        mix: mix.take(6).toList(),
        hotspots: pins,
      );
    });
  }
}
