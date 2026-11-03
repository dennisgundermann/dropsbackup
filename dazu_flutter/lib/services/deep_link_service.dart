import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../models/runde.dart';
import 'referral_service.dart';
import 'toast_center.dart';

/// Nimmt eingehende Deep-Links auf dazuapp.com entgegen und übersetzt
/// sie in App-Aktionen:
///
/// - `/r/<CODE>` → `ReferralService.registerReferral(code)` und Toast.
/// - `/d/<rundeID>` → signalisiert via [pendingRunde], das `MainShell`
///   öffnet dann das `RundeDetailSheet` für diese Runde.
///
/// Hält den aktiven Stream, damit auch Links, die *während* die App
/// läuft reinkommen, gezogen werden.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _links = AppLinks();
  StreamSubscription<Uri>? _sub;

  /// Setzt sich auf eine Pending-Runde, sobald ein /d/-Link reinkommt.
  /// `MainShell` hört zu und öffnet das Sheet.
  final ValueNotifier<Runde?> pendingRunde = ValueNotifier(null);

  Future<void> start() async {
    try {
      final initial = await _links.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {}
    _sub = _links.uriLinkStream.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  void _handle(Uri uri) {
    if (uri.host != 'dazuapp.com' || uri.pathSegments.length < 2) return;
    final head = uri.pathSegments.first;
    final value = uri.pathSegments[1];
    if (head == 'r' && value.isNotEmpty) {
      _redeemReferral(value);
    } else if (head == 'd' && value.isNotEmpty) {
      _openRunde(value);
    }
  }

  Future<void> _redeemReferral(String code) async {
    final inviter = await ReferralService().registerReferral(code);
    if (inviter != null && inviter.isNotEmpty) {
      ToastCenter.instance.show(DazuToast(
        title: '$inviter hat dich eingeladen',
        subtitle: 'Du bist mit dabei auf dazu — willkommen!',
        kind: DazuToastKind.friend,
      ));
    } else {
      ToastCenter.instance.show(const DazuToast(
        title: 'Code eingelöst',
        kind: DazuToastKind.success,
      ));
    }
  }

  Future<void> _openRunde(String rundeID) async {
    try {
      final snap =
          await FirebaseDatabase.instance.ref('drops').child(rundeID).get();
      final v = snap.value;
      if (v is Map) {
        pendingRunde.value =
            Runde.fromMap(rundeID, v.cast<Object?, Object?>());
      } else {
        ToastCenter.instance.show(const DazuToast(
          title: 'Runde nicht mehr verfügbar',
          subtitle: 'Vielleicht ist sie schon vorbei.',
        ));
      }
    } catch (_) {}
  }
}
