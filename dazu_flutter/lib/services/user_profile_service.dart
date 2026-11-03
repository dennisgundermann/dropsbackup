import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// Dünne Hülle um `/users/<uid>` — speichert Geburtsdatum, Name und
/// `onboardedAt`. Gleiche Felder-Namen wie iOS-App (`birthday` als
/// `yyyy-MM-dd`, `onboardedAt` als server-timestamp).
class UserProfileService {
  UserProfileService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  DatabaseReference _me() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('Kein eingeloggter User — UserProfileService');
    }
    return _db.ref('users').child(uid);
  }

  /// Liefert true wenn der User schon durch Onboarding durch ist
  /// (`onboardedAt` gesetzt + `birthday` vorhanden).
  Future<bool> isOnboarded() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final snap = await _db.ref('users').child(uid).get();
    final v = snap.value;
    if (v is! Map) return false;
    final birthday = v['birthday'];
    final onboardedAt = v['onboardedAt'];
    return birthday is String && birthday.length >= 10 && onboardedAt != null;
  }

  Future<void> saveBirthday(
    DateTime birthday, {
    String? name,
    String? gender,
  }) async {
    final iso = _toIsoDate(birthday);
    final payload = <String, Object?>{
      'birthday': iso,
      'onboardedAt': ServerValue.timestamp,
      if (name != null && name.isNotEmpty) 'displayName': name,
      // iOS speichert `gender` roh — 'weiblich' aktiviert den
      // Weiblich-Filter im Umgebung-Tab. Andere Werte oder null = kein
      // Filter sichtbar.
      if (gender != null && gender.isNotEmpty) 'gender': gender,
    };
    await _me().update(payload);
    if (name != null && name.isNotEmpty) {
      try {
        await FirebaseAuth.instance.currentUser?.updateDisplayName(name);
      } catch (_) {}
    }
  }

  static String _toIsoDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static int ageInYears(DateTime birthday, {DateTime? now}) {
    final n = now ?? DateTime.now();
    var age = n.year - birthday.year;
    if (n.month < birthday.month ||
        (n.month == birthday.month && n.day < birthday.day)) {
      age -= 1;
    }
    return age;
  }

  /// Lädt Admin-gesetzte Badges (`/users/<uid>/badges`). iOS liest hier
  /// `trusted` und `plus` — Admin markiert manuelle Verifizierungen
  /// via AdminPanel, die unabhängig vom Score-basierten Trust gelten.
  /// Fallback bei fehlendem Node: alle Felder false.
  Future<UserBadges> fetchBadges(String uid) async {
    try {
      final snap = await _db.ref('users').child(uid).child('badges').get();
      final v = snap.value;
      if (v is! Map) return const UserBadges();
      return UserBadges(
        trusted: v['trusted'] == true,
        plus: v['plus'] == true,
      );
    } catch (_) {
      return const UserBadges();
    }
  }
}

/// Admin-gesetzte Flags für einen User (iOS `AdminTrustedBadge`,
/// `isPlusUser`). Score-basiertes Trust-Badge (ReliabilityScore.isTrusted)
/// ist separat — ein User kann über beide Pfade „verlässlich" sein.
class UserBadges {
  const UserBadges({this.trusted = false, this.plus = false});
  final bool trusted;
  final bool plus;
}
