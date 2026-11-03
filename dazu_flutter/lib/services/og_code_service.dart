import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Client für die OG-Code-Einlöse-Cloud-Function (`redeemOGCode`).
///
/// Analog zu iOS' OGCodeService: User tippt in Einstellungen den Code ein,
/// Function claimed atomisch eine Nummer von 1–50 und schreibt
/// `users/<uid>/badges/ogNumber`.
class OGCodeService {
  static const _functionsBase =
      'https://europe-west1-drops-858d1.cloudfunctions.net';

  /// Löst einen Code ein. Rückgabe = {number: int} bei Erfolg.
  /// Wirft `OGCodeError` bei bekanntem Server-Fehler.
  static Future<int> redeem(String code) async {
    final token = await _idToken();
    if (token == null) throw const OGCodeError.notSignedIn();
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) throw const OGCodeError.invalidCodeFormat();

    final resp = await http.post(
      Uri.parse('$_functionsBase/redeemOGCode'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'code': trimmed}),
    );

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final n = data['number'];
      if (n is int && n >= 1 && n <= 50) return n;
      throw const OGCodeError.unknown('invalid response');
    }

    final body = _tryDecode(resp.body);
    final err = body['error']?.toString() ?? '';
    switch ('${resp.statusCode}:$err') {
      case '400:invalid_code_format':
        throw const OGCodeError.invalidCodeFormat();
      case '401:unauthorized':
        throw const OGCodeError.notSignedIn();
      case '409:invalid_code':
        throw const OGCodeError.invalidCode();
      case '409:already_claimed':
        throw const OGCodeError.alreadyClaimed();
      case '409:already_has_number':
        final n = body['number'];
        throw OGCodeError.alreadyHasNumber(n is int ? n : 0);
      default:
        throw OGCodeError.unknown('Status ${resp.statusCode}: $err');
    }
  }

  /// Admin-only: generiert fehlende Codes und listet sie zurück.
  static Future<List<GeneratedCode>> seedCodes() async {
    final token = await _idToken();
    if (token == null) throw const OGCodeError.notSignedIn();
    final resp = await http.post(
      Uri.parse('$_functionsBase/seedOGCodes'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: '{}',
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = (data['generated'] as List? ?? []);
      return list
          .map((e) => GeneratedCode(
                code: (e as Map)['code'].toString(),
                number: (e)['number'] as int,
              ))
          .toList();
    }
    if (resp.statusCode == 403) throw const OGCodeError.notAdmin();
    throw OGCodeError.unknown('Status ${resp.statusCode}');
  }

  static Future<String?> _idToken() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;
    return await u.getIdToken();
  }

  static Map<String, dynamic> _tryDecode(String body) {
    try {
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }
}

class GeneratedCode {
  final String code;
  final int number;
  const GeneratedCode({required this.code, required this.number});
}

class OGCodeError implements Exception {
  final String message;
  final int? number;
  const OGCodeError.notSignedIn()
      : message = 'Nicht eingeloggt.',
        number = null;
  const OGCodeError.invalidCodeFormat()
      : message = 'Code hat ein ungültiges Format.',
        number = null;
  const OGCodeError.invalidCode()
      : message = 'Dieser Code existiert nicht.',
        number = null;
  const OGCodeError.alreadyClaimed()
      : message = 'Dieser Code wurde bereits eingelöst.',
        number = null;
  const OGCodeError.alreadyHasNumber(int n)
      : message = 'Du hast schon eine OG-Nummer.',
        number = n;
  const OGCodeError.notAdmin()
      : message = 'Nicht autorisiert.',
        number = null;
  const OGCodeError.unknown(this.message) : number = null;

  @override
  String toString() => message;
}
