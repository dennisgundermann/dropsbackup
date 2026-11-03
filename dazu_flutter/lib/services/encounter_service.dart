// ignore_for_file: use_null_aware_elements
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/encounter.dart';

/// Observiert `/encounters/*` und filtert nach dem aktuellen User.
/// Schema iOS RealtimeDBManager.swift:1704:
///   `/encounters/{partnerA}_{partnerB}_{ts}` →
///     partnerA, partnerB, activityEmoji, activityName, timestamp,
///     confirmedA, confirmedB
///
/// Flutter liefert eine Liste `Encounter` fürs UI, mit der dynamischen
/// Zuordnung „friend = der Partner, der nicht ich bin" + Confirmation-
/// Status aus `confirmedA/B` abhängig davon welche Rolle ich habe.
class EncounterService {
  EncounterService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  DatabaseReference get _ref => _db.ref('encounters');

  /// Live-Stream aller Encounter, in denen der aktuelle User mitwirkt.
  /// Sortiert nach Timestamp absteigend (neueste zuerst).
  Stream<List<Encounter>> watchMine() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _ref.onValue.map((event) {
      final v = event.snapshot.value;
      if (v is! Map) return <Encounter>[];
      final out = <Encounter>[];
      v.forEach((k, raw) {
        if (raw is! Map) return;
        final partnerA = raw['partnerA']?.toString();
        final partnerB = raw['partnerB']?.toString();
        if (partnerA == null || partnerB == null) return;
        final mine = partnerA == uid || partnerB == uid;
        if (!mine) return;
        final friendUID = partnerA == uid ? partnerB : partnerA;
        final confirmed = partnerA == uid
            ? raw['confirmedA'] == true
            : raw['confirmedB'] == true;
        final denied = partnerA == uid
            ? raw['deniedA'] == true
            : raw['deniedB'] == true;
        final ts = raw['timestamp'];
        final createdAtMs = ts is num ? ts.toInt() : 0;
        out.add(Encounter(
          id: k.toString(),
          friendName: raw['friendName']?.toString() ?? '',
          friendEmoji: raw['friendEmoji']?.toString() ?? '',
          activityEmoji: raw['activityEmoji']?.toString() ?? '',
          activityName: raw['activityName']?.toString() ?? '',
          createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
          confirmed: confirmed,
          denied: denied,
          friendUID: friendUID,
          friendProfileImageURL: raw['friendProfileImageURL']?.toString(),
          dropID: raw['dropID']?.toString(),
          seenByUser: raw['seenByUser'] == true,
        ));
      });
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out;
    });
  }

  /// Bestätigt einen Encounter als „ja, war ein echtes Treffen".
  /// Schreibt den eigenen Confirmed-Flag — iOS räumt den Encounter aus
  /// dem Prompt-Feed, sobald mindestens eine Seite ihn bestätigt.
  Future<void> confirm(String encounterID) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await _ref.child(encounterID).get();
    final v = snap.value;
    if (v is! Map) return;
    final isPartnerA = v['partnerA']?.toString() == uid;
    await _ref.child(encounterID).update({
      isPartnerA ? 'confirmedA' : 'confirmedB': true,
    });
  }

  /// Verneint einen Encounter.
  Future<void> deny(String encounterID) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await _ref.child(encounterID).get();
    final v = snap.value;
    if (v is! Map) return;
    final isPartnerA = v['partnerA']?.toString() == uid;
    await _ref.child(encounterID).update({
      isPartnerA ? 'deniedA' : 'deniedB': true,
    });
  }

  /// Markiert einen Encounter als „gesehen" damit er beim nächsten
  /// Ablauf-Check nicht als No-Show gezählt wird (iOS-Verhalten).
  Future<void> markSeen(String encounterID) async {
    await _ref.child(encounterID).update({'seenByUser': true});
  }

  /// Schreibt einen neuen Encounter nach einem gemeinsamen Drop-Besuch.
  /// Pendant zu iOS `RealtimeDBManager.recordEncounter`.
  Future<void> recordEncounter({
    required String partnerA,
    required String partnerB,
    required String activityEmoji,
    required String activityName,
    String? dropID,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final encounterID = '${partnerA}_${partnerB}_$ts';
    await _ref.child(encounterID).set({
      'partnerA': partnerA,
      'partnerB': partnerB,
      'activityEmoji': activityEmoji,
      'activityName': activityName,
      'timestamp': ServerValue.timestamp,
      'confirmedA': false,
      'confirmedB': false,
      if (dropID != null) 'dropID': dropID,
    });
  }
}
