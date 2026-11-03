import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Aggregat der Zahlen für den Profil-Tab.
@immutable
class ProfilStats {
  const ProfilStats({
    this.roundsHosted = 0,
    this.roundsJoined = 0,
    this.friends = 0,
  });

  final int roundsHosted;
  final int roundsJoined;
  final int friends;
}

/// Hält drei RTDB-Zähler live (`/users/<uid>/pastDrops`,
/// `/users/<uid>/pastJoins`, `/friends/<uid>`) und publiziert einen
/// aggregierten `ProfilStats`-Wert als ChangeNotifier.
class StatsNotifier extends ChangeNotifier {
  StatsNotifier({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance {
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuth);
    _onAuth(FirebaseAuth.instance.currentUser);
  }

  final FirebaseDatabase _db;
  StreamSubscription<User?>? _authSub;
  final List<StreamSubscription<DatabaseEvent>> _dbSubs = [];

  int _hosted = 0;
  int _joined = 0;
  int _friends = 0;

  ProfilStats get stats => ProfilStats(
        roundsHosted: _hosted,
        roundsJoined: _joined,
        friends: _friends,
      );

  void _onAuth(User? user) {
    _resetDbSubs();
    _hosted = 0;
    _joined = 0;
    _friends = 0;
    notifyListeners();
    if (user == null) return;

    _dbSubs.add(
      _db.ref('users').child(user.uid).child('pastDrops').onValue.listen((e) {
        _hosted = e.snapshot.children.length;
        notifyListeners();
      }),
    );
    _dbSubs.add(
      _db.ref('users').child(user.uid).child('pastJoins').onValue.listen((e) {
        _joined = e.snapshot.children.length;
        notifyListeners();
      }),
    );
    _dbSubs.add(
      _db.ref('friends').child(user.uid).onValue.listen((e) {
        _friends = e.snapshot.children.length;
        notifyListeners();
      }),
    );
  }

  void _resetDbSubs() {
    for (final s in _dbSubs) {
      s.cancel();
    }
    _dbSubs.clear();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _resetDbSubs();
    super.dispose();
  }
}
