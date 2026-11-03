import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/runde.dart';
import 'runden_service.dart';

/// Hält die eigene aktive Runde live im Blick. Wenn der User gerade
/// hostet, liefert `aktiveRunde` != null; MainShell zeigt dann den
/// LiveScreen statt CreateScreen im mittleren Tab. Pendant zum iOS-
/// Pattern `store.isInActiveDrop`.
class AktiveRundeNotifier extends ChangeNotifier {
  AktiveRundeNotifier({RundenService? service})
      : _service = service ?? RundenService() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuth);
    _onAuth(FirebaseAuth.instance.currentUser);
  }

  final RundenService _service;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<Runde>>? _rundenSub;

  Runde? _aktive;
  Runde? get aktiveRunde => _aktive;
  bool get hatAktiveRunde => _aktive != null;

  void _onAuth(User? user) {
    _rundenSub?.cancel();
    _rundenSub = null;
    if (user == null) {
      _setAktive(null);
      return;
    }
    _rundenSub = _service.watchAktiveRunden().listen((runden) {
      try {
        final mine = runden.firstWhere((r) => r.hostUID == user.uid);
        _setAktive(mine);
      } catch (_) {
        _setAktive(null);
      }
    });
  }

  void _setAktive(Runde? runde) {
    if (_aktive?.id == runde?.id &&
        _aktive?.timestampMs == runde?.timestampMs) {
      return;
    }
    _aktive = runde;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _rundenSub?.cancel();
    super.dispose();
  }
}
