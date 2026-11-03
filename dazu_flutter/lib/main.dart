import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'l10n/l10n.dart';
import 'screens/app_router.dart';
import 'screens/force_update_screen.dart';
import 'services/deep_link_service.dart';
import 'services/force_update_service.dart';
import 'services/push_service.dart';
import 'theme/dazu_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await PushService.instance.init();
  // Deep-Links fire-and-forget starten — `getInitialLink()` kann auf
  // manchen Geräten lange blocken, soll aber nicht den Main-Thread
  // beim App-Start festhalten (ANR-Fix).
  unawaited(DeepLinkService.instance.start());
  runApp(const DazuApp());
}

class DazuApp extends StatefulWidget {
  const DazuApp({super.key});

  @override
  State<DazuApp> createState() => _DazuAppState();
}

class _DazuAppState extends State<DazuApp> with WidgetsBindingObserver {
  final ForceUpdateService _forceUpdate = ForceUpdateService();
  bool? _requiresUpdate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Beim Zurückkehren aus dem Hintergrund neu prüfen — nach iOS-Pattern.
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final blocked = await _forceUpdate.requiresForceUpdate();
    if (!mounted) return;
    setState(() => _requiresUpdate = blocked);
  }

  @override
  Widget build(BuildContext context) {
    // Nur Light-Theme — Dennis braucht keinen Dark-Mode in v1.
    return L10nProvider(
      child: MaterialApp(
        title: 'dazu',
        debugShowCheckedModeBanner: false,
        theme: DazuTheme.light(),
        home: _requiresUpdate == true
            ? const ForceUpdateScreen()
            : const AppRouter(),
      ),
    );
  }
}
