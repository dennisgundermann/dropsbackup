import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';

import 'reliability_service.dart';

/// GPS-basierter „Vor-Ort"-Fallback — Pendant zur iOS-2.0.2-Loosened
/// Rule: wenn der Joiner innerhalb von 50m zum Drop-Standort ist,
/// schreibt die App sofort `/dropins/{rundeID}/{joinerID}/onSite = true`.
/// BLE-Confirmation läuft parallel (eigenes Package, separate Session);
/// GPS deckt den Case ab, dass BLE 12 Minuten zum Greifen braucht.
///
/// Startet, sobald eine Runde beigetreten wurde, und stoppt beim
/// Verlassen oder Timer-Ende.
class PresenceService {
  PresenceService._({
    FirebaseDatabase? database,
    this.thresholdMeters = 50,
  }) : _db = database ?? FirebaseDatabase.instance;

  /// Singleton, damit Join → Live-Screen → Leave immer dieselbe Session
  /// steuern. Die GPS-Pipeline hält sonst mehrfach die Position gleich-
  /// zeitig gegen den Server und schreibt doppelt.
  static final PresenceService instance = PresenceService._();

  final FirebaseDatabase _db;
  final double thresholdMeters;

  StreamSubscription<Position>? _sub;
  String? _activeRundeID;
  double? _targetLat;
  double? _targetLng;

  /// Idempotenz-Flag: innerhalb einer Session nur EINMAL +Reliability
  /// buchen, auch wenn der GPS-Stream mehrfach „on-site" liefert.
  bool _reliabilityBooked = false;

  Future<void> start({
    required String rundeID,
    required double targetLat,
    required double targetLng,
  }) async {
    await stop();
    _activeRundeID = rundeID;
    _targetLat = targetLat;
    _targetLng = targetLng;
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(_onPosition);
    final current = await Geolocator.getCurrentPosition();
    _onPosition(current);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _activeRundeID = null;
    _reliabilityBooked = false;
  }

  void _onPosition(Position pos) {
    final rundeID = _activeRundeID;
    final tLat = _targetLat;
    final tLng = _targetLng;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (rundeID == null || tLat == null || tLng == null || uid == null) return;
    final d = Geolocator.distanceBetween(pos.latitude, pos.longitude, tLat, tLng);
    if (d <= thresholdMeters) {
      _db.ref('dropins/$rundeID/$uid').update({
        'onSite': true,
        'onSiteSince': ServerValue.timestamp,
        'onSiteSource': 'gps',
      });
      // iOS-Parität (Models.swift:4650): +20 Pkt beim ersten Vor-Ort-
      // Trigger pro Session. Erneutes Buchen beim selben Drop/Session
      // via _reliabilityBooked verhindert.
      if (!_reliabilityBooked) {
        _reliabilityBooked = true;
        ReliabilityService.instance.recordJoinerArrival();
      }
    }
  }
}
