import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Ein Freund in `/friends/<me>/<friendUID> == true`. Name + Alter
/// werden on-demand aus `/users/<friendUID>` nachgezogen.
@immutable
class Freund {
  const Freund({
    required this.uid,
    required this.name,
    this.age,
    this.profileImageURL,
    this.lat,
    this.lng,
  });

  final String uid;
  final String name;
  final int? age;
  final String? profileImageURL;

  /// Letzte bekannte Position aus `/users/<uid>/location`. null = unbekannt
  /// oder privat; auf der Karte wird der Freund dann nicht gepinnt.
  final double? lat;
  final double? lng;

  bool get hasLocation => lat != null && lng != null;
}

/// Listet Freunde live aus RTDB. Wenn `/users/<friendUID>` noch nicht
/// durch ist, zeigt der Service einen Platzhalter („Freund"), damit die
/// Liste nicht leer bleibt.
class FriendsService {
  FriendsService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  Stream<List<Freund>> watchFriends() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Stream.empty();
    }
    return _db.ref('friends').child(uid).onValue.asyncMap((event) async {
      final raw = event.snapshot.value;
      if (raw is! Map) return <Freund>[];
      final uids = raw.keys.map((k) => k.toString()).toList();
      final profiles = await Future.wait(uids.map(_loadProfile));
      return profiles;
    });
  }

  Future<Freund> _loadProfile(String friendUID) async {
    try {
      final snap = await _db.ref('users').child(friendUID).get();
      final v = snap.value;
      if (v is Map) {
        final m = v;
        final loc = m['location'];
        double? lat;
        double? lng;
        if (loc is Map) {
          lat = (loc['lat'] as num?)?.toDouble();
          lng = (loc['lng'] as num?)?.toDouble();
        }
        return Freund(
          uid: friendUID,
          name: m['name']?.toString() ??
              m['displayName']?.toString() ??
              'Freund',
          age: _toInt(m['age']),
          profileImageURL: m['profileImageURL']?.toString(),
          lat: lat,
          lng: lng,
        );
      }
    } catch (_) {
      // Fallback: nur UID + Default-Name
    }
    return Freund(uid: friendUID, name: 'Freund');
  }

  int? _toInt(Object? v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
}
