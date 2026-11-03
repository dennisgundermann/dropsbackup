import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Dünner Wrapper um FirebaseAuth + GoogleSignIn. Pendant zum iOS-
/// `FirebaseAuthManager` / `GoogleSignInManager`. Für die Android-App
/// steht Google Sign-In im Vordergrund (Apple-SSO folgt wenn iOS-Flutter
/// echter Build-Target wird).
class AuthService extends ChangeNotifier {
  AuthService() {
    _firebase.authStateChanges().listen((user) {
      _user = user;
      notifyListeners();
    });
  }

  final FirebaseAuth _firebase = FirebaseAuth.instance;
  // GoogleSignIn ist in >=6.3 ein Singleton via .instance.
  final GoogleSignIn _google = GoogleSignIn.instance;
  bool _googleInitialized = false;

  User? _user;
  User? get user => _user;
  bool get isSignedIn => _user != null;

  /// Google-Sign-In-Flow → Firebase-Credential → Session.
  Future<User?> signInWithGoogle() async {
    if (!_googleInitialized) {
      await _google.initialize();
      _googleInitialized = true;
    }
    final account = await _google.authenticate(
      scopeHint: const ['email', 'profile'],
    );
    final auth = account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: auth.idToken,
    );
    final result = await _firebase.signInWithCredential(credential);
    return result.user;
  }

  /// Startet SMS-Verifikation. `onCodeSent` kriegt die verificationId
  /// die später an `verifyCode(...)` übergeben wird. Firebase pingt die
  /// Nummer, der User kriegt eine 6-stellige PIN. Auf einigen Android-
  /// Geräten (Google Play Services) wird die PIN sogar automatisch
  /// ausgelesen → dann feuert `onAutoVerified`.
  Future<void> startPhoneVerification({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
    void Function()? onAutoVerified,
  }) async {
    await _firebase.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (credential) async {
        try {
          await _firebase.signInWithCredential(credential);
          onAutoVerified?.call();
        } catch (e) {
          onError('$e');
        }
      },
      verificationFailed: (e) => onError(e.message ?? 'Unbekannter Fehler'),
      codeSent: (verificationId, _) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (_) {},
      timeout: const Duration(seconds: 60),
    );
  }

  Future<User?> verifyPhoneCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final cred = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final result = await _firebase.signInWithCredential(cred);
    // Phone-Index für Freunde-Import matchen. Nur +Ziffern, damit die
    // Normalisierung in ContactsMatchService dasselbe Key liefert.
    final user = result.user;
    final phone = user?.phoneNumber ?? '';
    if (user != null && phone.isNotEmpty) {
      try {
        final norm = _normalizePhone(phone);
        await FirebaseDatabase.instance
            .ref('phoneIndex')
            .child(norm)
            .set({'uid': user.uid, 'name': user.displayName ?? ''});
      } catch (_) {}
    }
    return user;
  }

  String _normalizePhone(String raw) {
    final buf = StringBuffer();
    for (final c in raw.runes) {
      final ch = String.fromCharCode(c);
      if (ch == '+' && buf.isEmpty) buf.write(ch);
      if ('0123456789'.contains(ch)) buf.write(ch);
    }
    return buf.toString();
  }

  Future<void> signOut() async {
    if (_googleInitialized) {
      await _google.signOut();
    }
    await _firebase.signOut();
  }
}
