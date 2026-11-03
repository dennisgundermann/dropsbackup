import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/dazu_colors.dart';
import 'login_screen.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';

/// Zentraler Router mit drei Zuständen:
///   - nicht eingeloggt       → LoginScreen
///   - eingeloggt, nicht onboarded → OnboardingScreen (Birthday + Age-Gate)
///   - eingeloggt + onboarded → MainShell
///
/// Onboarding-Status wird live gestreamt (`/users/<uid>/onboardedAt`),
/// damit nach dem Abschluss im Flutter sofort weitergeroutet wird ohne
/// Reload.
class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  final AuthService _auth = AuthService();
  StreamSubscription<DatabaseEvent>? _profileSub;
  bool? _onboarded;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  void _onAuthChanged() {
    _profileSub?.cancel();
    _profileSub = null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _onboarded = null);
      return;
    }
    _profileSub = FirebaseDatabase.instance
        .ref('users')
        .child(uid)
        .onValue
        .listen((e) {
      final v = e.snapshot.value;
      final done = v is Map &&
          v['birthday'] is String &&
          (v['birthday'] as String).length >= 10 &&
          v['onboardedAt'] != null;
      if (!mounted) return;
      setState(() => _onboarded = done);
    });
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _profileSub?.cancel();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _auth,
      builder: (context, _) {
        if (!_auth.isSignedIn) return LoginScreen(auth: _auth);
        if (_onboarded == null) {
          // Kurzer Splash während RTDB antwortet.
          return const Scaffold(
            backgroundColor: DazuColors.brandCream,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!_onboarded!) return OnboardingScreen(auth: _auth);
        return MainShell(auth: _auth);
      },
    );
  }
}
