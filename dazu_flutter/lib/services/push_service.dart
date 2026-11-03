// Firebase-Messaging v17 hat einige APIs auf `register()` / `onRegistered`
// umgestellt, die Signaturen sind aber im Flux. Für v1 bleiben wir bei den
// stabilen `getToken()` / `onTokenRefresh`, die weiterlaufen.
// ignore_for_file: deprecated_member_use

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'toast_center.dart';

/// FCM-Setup für Android: Permission anfragen, Device-Token holen und
/// unter `/users/<uid>/fcmTokens/<token>` ablegen — pendant zu iOS
/// `PushNotificationManager`. Foreground-Messages zeigt der Service
/// via `flutter_local_notifications` als System-Toast an.
class PushService {
  PushService._();
  static final instance = PushService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _setupLocalChannel();

    // Permission (Android 13+ zeigt den System-Dialog erst beim ersten
    // Request). Vor Android 13 gibt's keine Runtime-Permission → der
    // Call liefert einfach `authorized` zurück.
    await _fcm.requestPermission();

    // Foreground-Messages direkt als lokale Notification anzeigen —
    // Android zeigt FCM-Pushes im Vordergrund sonst nicht.
    FirebaseMessaging.onMessage.listen(_handleForeground);

    FirebaseAuth.instance.authStateChanges().listen((u) {
      if (u != null) _syncTokenToDb(u.uid);
    });
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) await _syncTokenToDb(current.uid);

    _fcm.onTokenRefresh.listen((_) {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) _syncTokenToDb(u.uid);
    });
  }

  Future<void> _setupLocalChannel() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: androidInit);
    await _local.initialize(settings: init);

    const channel = AndroidNotificationChannel(
      'dazu_push',
      'dazu-Benachrichtigungen',
      description: 'Runden, Einladungen und Reengage-Pushes.',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> _syncTokenToDb(String uid) async {
    try {
      final token = await _fcm.getToken();
      if (token == null || token.isEmpty) return;
      await FirebaseDatabase.instance
          .ref('users')
          .child(uid)
          .child('fcmTokens')
          .child(token)
          .set({
        'platform': 'android',
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('PushService._syncTokenToDb: $e');
    }
  }

  Future<void> _handleForeground(RemoteMessage msg) async {
    final n = msg.notification;
    if (n == null) return;
    // iOS-Pattern: im Foreground keine System-Benachrichtigung, sondern
    // ein In-App-Toast — der FCM-Payload `data.kind` gibt uns die
    // passende Icon-Pastille.
    final kind = _kindFromData(msg.data['kind']?.toString());
    ToastCenter.instance.show(DazuToast(
      title: n.title ?? 'dazu',
      subtitle: n.body,
      kind: kind,
    ));
  }

  DazuToastKind _kindFromData(String? raw) {
    switch (raw) {
      case 'join':
        return DazuToastKind.join;
      case 'friend':
        return DazuToastKind.friend;
      case 'nearby':
        return DazuToastKind.nearby;
      case 'success':
        return DazuToastKind.success;
      default:
        return DazuToastKind.info;
    }
  }
}
