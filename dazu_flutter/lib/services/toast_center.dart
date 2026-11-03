import 'package:flutter/foundation.dart';

/// Posted toast — ein kurz einfliegender Hinweis am oberen Bildschirmrand.
/// Nach iOS `DynamicToast`: lila/orange Pill mit Icon + 1-Zeiler + optional
/// einer zweiten dezenten Zeile.
@immutable
class DazuToast {
  const DazuToast({
    required this.title,
    this.subtitle,
    this.kind = DazuToastKind.info,
    this.duration = const Duration(seconds: 3),
  });

  final String title;
  final String? subtitle;
  final DazuToastKind kind;
  final Duration duration;
}

enum DazuToastKind { info, success, join, friend, nearby }

/// App-weiter Singleton. `MainShell` hört zu und zeigt den Toast als
/// Overlay. Jeder Service kann `ToastCenter.instance.show(...)` rufen —
/// FCM-Foreground, Join-Events, Freund-Requests, PresenceService.
class ToastCenter extends ChangeNotifier {
  ToastCenter._();
  static final ToastCenter instance = ToastCenter._();

  DazuToast? _current;
  DazuToast? get current => _current;

  int _generation = 0;

  void show(DazuToast toast) {
    _current = toast;
    final gen = ++_generation;
    notifyListeners();
    Future<void>.delayed(toast.duration, () {
      if (gen != _generation) return; // ein neuerer Toast ist bereits da
      _current = null;
      notifyListeners();
    });
  }

  void dismiss() {
    _generation++;
    _current = null;
    notifyListeners();
  }
}
