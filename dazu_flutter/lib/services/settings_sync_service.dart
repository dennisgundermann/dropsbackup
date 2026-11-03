import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Spiegelt die User-Settings nach `/users/<uid>/settings` damit iOS +
/// Android dieselben Werte sehen. Lokale `SharedPreferences` bleibt als
/// schneller Cache für Offline/Boot — bei Signin wird aus Firebase
/// nachgezogen und overwritten.
class SettingsSyncService {
  SettingsSyncService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  DatabaseReference? _ref() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return _db.ref('users').child(uid).child('settings');
  }

  /// Nach Login einmal: Firebase → SharedPreferences überschreiben.
  /// Sorgt dafür dass z.B. ein User, der iOS seine Radius-Einstellung
  /// gesetzt hat, auf Android dieselbe sieht.
  Future<void> hydrateFromFirebase() async {
    final ref = _ref();
    if (ref == null) return;
    try {
      final snap = await ref.get();
      final v = snap.value;
      if (v is! Map) return;
      final p = await SharedPreferences.getInstance();
      await _applyIfExists(p, v, 'visible', 'ud_visible');
      await _applyIfExists(p, v, 'push', 'ud_push');
      await _applyIfExists(p, v, 'notifyRadiusM', 'ud_notifyRadiusM');
      await _applyIfExists(p, v, 'runRadiusKm', 'ud_runRadiusKm');
      await _applyIfExists(p, v, 'minAge', 'ud_minAge');
      await _applyIfExists(p, v, 'maxAge', 'ud_maxAge');
    } catch (_) {
      // Firebase down/offline → wir leben mit den lokalen Werten weiter.
    }
  }

  Future<void> _applyIfExists(
      SharedPreferences p, Map src, String key, String prefKey) async {
    final v = src[key];
    if (v == null) return;
    if (v is bool) {
      await p.setBool(prefKey, v);
    } else if (v is int) {
      await p.setInt(prefKey, v);
    } else if (v is double) {
      await p.setDouble(prefKey, v);
    } else if (v is String) {
      await p.setString(prefKey, v);
    } else if (v is num) {
      await p.setDouble(prefKey, v.toDouble());
    }
  }

  /// Push eines einzelnen Felds nach Firebase.
  Future<void> push(String key, Object value) async {
    final ref = _ref();
    if (ref == null) return;
    try {
      await ref.update({key: value});
    } catch (_) {}
  }
}
