// ignore_for_file: use_null_aware_elements
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/join_request.dart';
import '../models/runde.dart';
import '../models/teilnehmer.dart';
import 'presence_service.dart';
import 'reliability_service.dart';

/// Abstraktion über Firebase RTDB. Spiegelt das iOS-Pattern. Die RTDB-
/// Pfade `/drops` und `/dropins` sind Legacy-Namen und bleiben, weil
/// beide Apps auf dasselbe Schema schreiben.
class RundenService {
  RundenService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  DatabaseReference get _runden => _db.ref('drops');
  DatabaseReference _teilnehmer(String rundeID) =>
      _db.ref('dropins').child(rundeID);

  /// Live-Stream aller aktiven Runden. Filtert bereits abgelaufene raus.
  Stream<List<Runde>> watchAktiveRunden() {
    return _runden.onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) return <Runde>[];
      final list = <Runde>[];
      raw.forEach((key, value) {
        if (value is Map) {
          final r = Runde.fromMap(
            key.toString(),
            value as Map<Object?, Object?>,
          );
          if (r.active && !r.isExpired) list.add(r);
        }
      });
      list.sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
      return list;
    });
  }

  /// Live-Teilnehmer einer Runde (Host NICHT inkludiert).
  Stream<List<Teilnehmer>> watchTeilnehmer(String rundeID) {
    return _teilnehmer(rundeID).onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) return <Teilnehmer>[];
      final list = <Teilnehmer>[];
      raw.forEach((key, value) {
        if (value is Map) {
          list.add(Teilnehmer.fromMap(
            key.toString(),
            value as Map<Object?, Object?>,
          ));
        }
      });
      list.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
      return list;
    });
  }

  /// Neue Runde anlegen — Schema identisch zur iOS-App.
  Future<String> starteRunde({
    required String activityName,
    required double lat,
    required double lng,
    required double radius,
    required int maxParticipants,
    required int durationMinutes,
    String scheduledTime = 'Jetzt',
    String emoji = '',
    String? hostProfileImageURL,
    int? hostAge,
    int? hostReliabilityPoints,
    String? hostGender,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Kein eingeloggter User — starteRunde abgebrochen.');
    }
    final ref = _runden.push();
    final createdAt = DateTime.now();
    final startOffsetSec = _scheduledOffsetSec(scheduledTime);
    final startAt =
        createdAt.add(Duration(seconds: startOffsetSec)).millisecondsSinceEpoch /
            1000;
    // iOS-Parität zu `DropEvent.expiresAt`:
    //   durationMinutes > 0  → startAt + duration*60
    //   = 0 && "Heute Abend" → heute 23:59:59
    //   = 0 && sonst         → createdAt + 12h (Fallback)
    final double expiresAt;
    if (durationMinutes > 0) {
      expiresAt = startAt + (durationMinutes * 60);
    } else if (scheduledTime == 'Heute Abend') {
      final endOfDay = DateTime(createdAt.year, createdAt.month, createdAt.day,
          23, 59, 59);
      expiresAt = endOfDay.millisecondsSinceEpoch / 1000;
    } else {
      expiresAt = createdAt
              .add(const Duration(hours: 12))
              .millisecondsSinceEpoch /
          1000;
    }

    final payload = <String, Object?>{
      'userID': user.uid,
      'displayName': user.displayName ?? 'dazu',
      'emoji': emoji,
      'activityName': activityName,
      'lat': lat,
      'lng': lng,
      'radius': radius,
      'timestamp': ServerValue.timestamp,
      'expiresAt': expiresAt,
      'scheduledTime': scheduledTime,
      'startAt': startAt,
      'maxParticipants': maxParticipants,
      'currentParticipants': 1,
      'active': true,
      // Flutter-Debug-Marker — iOS „Demo-Runden löschen" räumt sie
      // mit. Vor Produktiv-Launch raus.
      'isDemoLive': true,
      if (hostGender != null && hostGender.isNotEmpty) 'hostGender': hostGender,
      if (hostAge != null) 'hostAge': hostAge,
      if (hostReliabilityPoints != null)
        'hostReliabilityPoints': hostReliabilityPoints,
      if (hostProfileImageURL != null && hostProfileImageURL.isNotEmpty)
        'hostProfileImageURL': hostProfileImageURL,
    };
    await ref.set(payload);
    return ref.key!;
  }

  /// Request-to-Join — Pendant zu iOS `publishJoinRequest`. Schreibt
  /// nach `/joinRequests/{dropID}/{joinerID}` mit `status: pending`;
  /// Host akzeptiert über [respondToJoinRequest], das löst dann den
  /// eigentlichen `/dropins`-Write aus. Optional nimmt der Joiner eine
  /// kurze Vorstellungs-Message mit.
  Future<void> tritRundeBei({
    required String rundeID,
    required String name,
    int age = 0,
    double? lat,
    double? lng,
    String emoji = '',
    String? profileImageURL,
    int? reliabilityPoints,
    String? message,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Kein eingeloggter User — tritRundeBei abgebrochen.');
    }
    final payload = <String, Object?>{
      'name': name,
      'emoji': emoji,
      'age': age,
      'status': 'pending',
      'requestedAt': ServerValue.timestamp,
      if (profileImageURL != null) 'profileImageURL': profileImageURL,
      if (reliabilityPoints != null) 'reliabilityPoints': reliabilityPoints,
      if (message != null && message.trim().isNotEmpty)
        'message': message.trim().substring(
            0,
            message.trim().length > 200 ? 200 : message.trim().length),
    };
    final ref = _joinRequests(rundeID).child(user.uid);
    // iOS-Trick: Erst Remove, dann 100ms später neu setzen. Host-Observer
    // feuert so sauber ein neues childAdded und zeigt die Anfrage.
    await ref.remove();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await ref.set(payload);

    // GPS-Presence starten — Target-Koordinaten frisch aus /drops holen,
    // damit auch eine seit dem Join verlegte Runde das korrekte Ziel hat.
    final dropSnap = await _runden.child(rundeID).get();
    final v = dropSnap.value;
    if (v is Map) {
      final tLat = (v['lat'] as num?)?.toDouble();
      final tLng = (v['lng'] as num?)?.toDouble();
      if (tLat != null && tLng != null) {
        await PresenceService.instance.start(
          rundeID: rundeID,
          targetLat: tLat,
          targetLng: tLng,
        );
      }
    }
  }

  /// Joiner-seitig: beobachtet den Status der eigenen Anfrage. Host
  /// akzeptiert → `accepted`, Host lehnt ab → `declined`, Host beendet
  /// Runde → der Pfad wird komplett entfernt.
  Stream<String?> watchMyJoinStatus(String rundeID) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _joinRequests(rundeID)
        .child(uid)
        .child('status')
        .onValue
        .map((e) => e.snapshot.value?.toString());
  }

  /// Joiner nimmt die eigene Pending-Anfrage zurück. Löst den
  /// `/joinRequests/...`-Pfad.
  Future<void> cancelJoinRequest(String rundeID) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _joinRequests(rundeID).child(uid).remove();
    await PresenceService.instance.stop();
  }

  Future<void> verlasseRunde(String rundeID) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _teilnehmer(rundeID).child(user.uid).remove();
    await PresenceService.instance.stop();
  }

  Future<void> beendeRunde(String rundeID) async {
    // Reliability-Logik (iOS Models.swift:6210-6355) — vor dem Löschen
    // noch Teilnehmer + Pending-Join-Requests zählen, dann entscheiden:
    //   • ≥2 Teilnehmer (Host + ≥1 Joiner angekommen) → recordHostSuccess
    //   • pending joiner wartet ≥12 Min → recordNoShow
    //   • sonst (kein Joiner oder frische Anfrage <12 Min) → nix buchen
    //     (Launch-Phase-Toleranz, damit Städte mit wenig Aktivität nicht
    //      durch reines Trying „bestraft" werden)
    try {
      final teilnehmerSnap = await _teilnehmer(rundeID).get();
      final participantCount = teilnehmerSnap.children.length;
      if (participantCount >= 2) {
        unawaited(ReliabilityService.instance.recordHostSuccess());
      } else {
        final pendingSnap = await _joinRequests(rundeID).get();
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        const twelveMinMs = 12 * 60 * 1000;
        final hasOldPending = pendingSnap.children.any((c) {
          final v = c.value;
          if (v is! Map) return false;
          final status = v['status']?.toString();
          if (status != 'pending' && status != null) return false;
          final ts = v['requestedAt'];
          if (ts is! num) return false;
          return (nowMs - ts.toInt()) >= twelveMinMs;
        });
        if (hasOldPending) {
          unawaited(ReliabilityService.instance.recordNoShow());
        }
      }
    } catch (_) {
      // Reliability-Buchung ist nice-to-have — niemals den Beende-Flow
      // deswegen abbrechen.
    }

    // Nach iOS-Pattern: aktiv:false ZUERST, danach erst nach kurzer
    // Verzögerung komplett entfernen. Clients, die noch zuhören, sehen
    // dadurch zuerst den "ende"-Zustand und können sauber räumen.
    await _runden.child(rundeID).update({'active': false});
    await Future.delayed(const Duration(seconds: 3));
    await _runden.child(rundeID).remove();
    await _teilnehmer(rundeID).remove();
  }

  /// Verlängert die Runde um [minutes] Minuten. Hostet nur der Host-UID.
  Future<void> verlaengereRunde(String rundeID, int minutes) async {
    final snap = await _runden.child(rundeID).child('expiresAt').get();
    final currentExp =
        snap.value is num ? (snap.value as num).toDouble() : null;
    if (currentExp == null) return;
    final newExp = currentExp + minutes * 60;
    await _runden.child(rundeID).update({'expiresAt': newExp});
  }

  DatabaseReference _joinRequests(String rundeID) =>
      FirebaseDatabase.instance.ref('joinRequests').child(rundeID);

  /// Zählt aktive Runden im Umkreis von `radiusKm` um `lat,lng`.
  /// Grobe Approximation via `0.009° ≈ 1 km` (Lat-Grad), für Bayern
  /// genau genug für die Boost-Bonus-Logik („Umgebung leer").
  Future<int> countNearbyRunden({
    required double lat,
    required double lng,
    double radiusKm = 2,
  }) async {
    try {
      final snap = await _runden.get();
      final v = snap.value;
      if (v is! Map) return 0;
      final latDelta = radiusKm * 0.009;
      final lngDelta = radiusKm * 0.009;
      var count = 0;
      for (final entry in v.entries) {
        final child = entry.value;
        if (child is! Map) continue;
        if (child['active'] != true) continue;
        final cLat = child['lat'];
        final cLng = child['lng'];
        if (cLat is! num || cLng is! num) continue;
        if ((cLat - lat).abs() <= latDelta &&
            (cLng - lng).abs() <= lngDelta) {
          count++;
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  /// Host-seite: alle Pending-Anfragen für die eigene Runde live.
  Stream<List<JoinRequest>> watchIncomingJoinRequests(String rundeID) {
    return _joinRequests(rundeID).onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) return <JoinRequest>[];
      final out = <JoinRequest>[];
      raw.forEach((k, v) {
        if (v is Map) {
          final r = JoinRequest.fromMap(
              k.toString(), v.cast<Object?, Object?>());
          if (r.isPending) out.add(r);
        }
      });
      out.sort((a, b) =>
          (a.requestedAtMs ?? 0).compareTo(b.requestedAtMs ?? 0));
      return out;
    });
  }

  /// Host-seite: akzeptiert oder lehnt eine Anfrage ab. Bei Accept
  /// werden `/dropins/<rundeID>/<joinerID>` + `/drops/<id>/joinerIDs`
  /// aktualisiert — exakt dasselbe Pattern wie iOS.
  Future<void> respondToJoinRequest({
    required String rundeID,
    required JoinRequest request,
    required bool accepted,
  }) async {
    await _joinRequests(rundeID).child(request.joinerID).update({
      'status': accepted ? 'accepted' : 'declined',
      'respondedAt': ServerValue.timestamp,
    });
    if (accepted) {
      await _teilnehmer(rundeID).child(request.joinerID).update({
        'status': 'accepted',
        'timestamp': ServerValue.timestamp,
        if (request.name.isNotEmpty) 'name': request.name,
        if (request.profileImageURL != null)
          'profileImageURL': request.profileImageURL,
      });
      await _runden
          .child(rundeID)
          .child('joinerIDs')
          .child(request.joinerID)
          .set(true);
    }
  }

  /// Verlegt den Treffpunkt der Runde zur neuen GPS-Position. Setzt
  /// zusätzlich `locationChangedAt`, damit die Cloud Function
  /// `onDropLocationChangedPush` den Push an alle Joiner auslöst.
  Future<void> verlegeStandort({
    required String rundeID,
    required double lat,
    required double lng,
    String? addressTitle,
  }) async {
    final updates = <String, Object?>{
      'lat': lat,
      'lng': lng,
      'locationChangedAt': ServerValue.timestamp,
    };
    if (addressTitle != null && addressTitle.isNotEmpty) {
      updates['locationTitle'] = addressTitle;
    }
    await _runden.child(rundeID).update(updates);
  }

  int _scheduledOffsetSec(String scheduledTime) {
    switch (scheduledTime) {
      case 'In 30 Min':
        return 30 * 60;
      case 'In 1 Std':
        return 60 * 60;
      case 'In 2 Std':
        return 120 * 60;
      default:
        return 0;
    }
  }
}
