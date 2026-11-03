import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Eingehende Freundschaftsanfrage — der Sender hat
/// `/friendRequests/<meUID>/<senderUID> = {ts, name}` geschrieben.
@immutable
class FriendRequest {
  const FriendRequest({
    required this.senderUID,
    required this.senderName,
    required this.timestampMs,
  });
  final String senderUID;
  final String senderName;
  final int timestampMs;
}

/// Anfragen senden, lesen, akzeptieren, ablehnen. Pendant zu iOS
/// `RealtimeDBManager`-Friend-Request-Flow. Beide Schreib-Pfade
/// (`/friendRequests/*` + `/friends/*`) folgen den existierenden
/// Rules.
class FriendRequestsService {
  FriendRequestsService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  String? get _me => FirebaseAuth.instance.currentUser?.uid;
  String get _myName =>
      FirebaseAuth.instance.currentUser?.displayName ?? 'dazu';

  /// Anfrage an einen Fremden senden.
  Future<void> sendRequest(String recipientUID) async {
    final me = _me;
    if (me == null || me == recipientUID) return;
    await _db
        .ref('friendRequests')
        .child(recipientUID)
        .child(me)
        .set({
      'name': _myName,
      'timestamp': ServerValue.timestamp,
    });
  }

  /// Alle eingehenden Anfragen live.
  Stream<List<FriendRequest>> watchIncoming() {
    final me = _me;
    if (me == null) return const Stream.empty();
    return _db.ref('friendRequests').child(me).onValue.map((e) {
      final raw = e.snapshot.value;
      if (raw is! Map) return const <FriendRequest>[];
      final list = <FriendRequest>[];
      raw.forEach((k, v) {
        if (v is Map) {
          final ts = v['timestamp'];
          list.add(FriendRequest(
            senderUID: k.toString(),
            senderName: v['name']?.toString() ?? 'Jemand',
            timestampMs: ts is num ? ts.toInt() : 0,
          ));
        }
      });
      list.sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
      return list;
    });
  }

  /// Akzeptieren: beide Seiten in `/friends` setzen + Request löschen.
  Future<void> accept(String senderUID) async {
    final me = _me;
    if (me == null) return;
    await _db.ref('friends').child(me).child(senderUID).set(true);
    await _db.ref('friends').child(senderUID).child(me).set(true);
    await _db.ref('friendRequests').child(me).child(senderUID).remove();
  }

  Future<void> decline(String senderUID) async {
    final me = _me;
    if (me == null) return;
    await _db.ref('friendRequests').child(me).child(senderUID).remove();
  }

  /// Nachschlag: ist dieser User schon Freund von mir?
  Future<bool> isAlreadyFriend(String otherUID) async {
    final me = _me;
    if (me == null) return false;
    final snap = await _db.ref('friends').child(me).child(otherUID).get();
    return snap.value == true;
  }
}
