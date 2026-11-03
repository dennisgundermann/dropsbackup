import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Blockierter User — Schlüssel ist die UID, `name` wird on-demand aus
/// `/users/<uid>` nachgeladen.
@immutable
class BlockedUser {
  const BlockedUser({required this.uid, required this.name});
  final String uid;
  final String name;
}

/// Nutzer blockieren + melden. Schema identisch zu iOS:
///   `/blocks/<myUID>/<otherUID> = true`
///   `/reports/<pushID> = { reporterUID, reportedUID, reason, note?, ts }`
/// Firebase Rules filtern deine Blocks für andere unsichtbar.
class BlockReportService {
  BlockReportService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  String? get _me => FirebaseAuth.instance.currentUser?.uid;

  Future<void> block(String otherUID) async {
    final me = _me;
    if (me == null || otherUID == me) return;
    await _db.ref('blocks').child(me).child(otherUID).set(true);
  }

  Future<void> unblock(String otherUID) async {
    final me = _me;
    if (me == null) return;
    await _db.ref('blocks').child(me).child(otherUID).remove();
  }

  /// Live-Liste aller UIDs die ich blockiert habe + Namen aus /users.
  Stream<List<BlockedUser>> watchBlocked() async* {
    final me = _me;
    if (me == null) {
      yield const [];
      return;
    }
    final events = _db.ref('blocks').child(me).onValue;
    await for (final e in events) {
      final raw = e.snapshot.value;
      if (raw is! Map) {
        yield const [];
        continue;
      }
      final list = <BlockedUser>[];
      for (final k in raw.keys) {
        final uid = k.toString();
        try {
          final snap = await _db.ref('users').child(uid).get();
          final v = snap.value;
          final name = (v is Map ? v['displayName'] ?? v['name'] : null)
                  ?.toString() ??
              'Nutzer';
          list.add(BlockedUser(uid: uid, name: name));
        } catch (_) {
          list.add(BlockedUser(uid: uid, name: 'Nutzer'));
        }
      }
      yield list;
    }
  }

  /// Ein paar vorgedachte Report-Reasons — gleich wie iOS.
  static const List<String> reportReasons = [
    'Fake-Profil / Identitätsklau',
    'Spam / Werbung',
    'Belästigung',
    'Hassrede',
    'Minderjährig',
    'Anderer Grund',
  ];

  Future<void> report({
    required String reportedUID,
    required String reason,
    String? note,
  }) async {
    final me = _me;
    if (me == null) return;
    final ref = _db.ref('reports').push();
    await ref.set({
      'reporterUID': me,
      'reportedUID': reportedUID,
      'reason': reason,
      if (note != null && note.isNotEmpty) 'note': note,
      'timestamp': ServerValue.timestamp,
    });
  }
}
