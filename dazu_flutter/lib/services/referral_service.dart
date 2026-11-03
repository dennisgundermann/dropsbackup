import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

/// Pendant zu iOS `ReferralManager`. Löst beim Login einmal die Cloud
/// Function `ensureReferralCode` aus (idempotent, antwortet mit dem Code
/// des Users). Lädt ihn danach aus `/users/<uid>/referralCode`.
class ReferralService {
  ReferralService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  static const _ensureEndpoint =
      'https://europe-west1-drops-858d1.cloudfunctions.net/ensureReferralCode';

  /// Holt den Referral-Code des eingeloggten Users. Wenn noch keiner
  /// existiert, triggert die Cloud Function einen frischen.
  Future<String?> ensureCode() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final idToken = await user.getIdToken();
    try {
      final res = await http.post(
        Uri.parse(_ensureEndpoint),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return body['code']?.toString();
      }
    } catch (_) {}
    // Fallback: direkt aus RTDB lesen, falls Call nicht möglich (offline).
    final snap = await _db.ref('users/${user.uid}/referralCode').get();
    return snap.value?.toString();
  }

  /// Löst einen fremden Code für den aktuellen User ein (z. B. nach
  /// Deep-Link `/r/XYZ`). Rückgabe: inviter-Name oder null.
  Future<String?> registerReferral(String code) async {
    final functions =
        FirebaseFunctions.instanceFor(region: 'europe-west1');
    try {
      final res = await functions
          .httpsCallable('registerReferral')
          .call<Map<Object?, Object?>>({'code': code.trim().toUpperCase()});
      return res.data['inviterName']?.toString();
    } catch (_) {
      return null;
    }
  }
}
