import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Online-/Offline-Status mit „gerade wieder verbunden"-Pulse.
/// Portiert aus iOS `Drops/NetworkMonitor.swift` (NWPathMonitor).
///
/// Verwendung:
/// ```dart
/// ListenableBuilder(
///   listenable: NetworkMonitor.instance,
///   builder: (ctx, _) => OfflineBanner(…),
/// )
/// ```
class NetworkMonitor extends ChangeNotifier {
  NetworkMonitor._() {
    _init();
  }

  static final NetworkMonitor instance = NetworkMonitor._();

  bool _isConnected = true;
  bool _justReconnected = false;
  bool _wasDisconnected = false;
  Timer? _reconnectBannerTimer;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool get isConnected => _isConnected;
  bool get justReconnected => _justReconnected;

  Future<void> _init() async {
    try {
      final initial = await Connectivity().checkConnectivity();
      _apply(initial);
    } catch (_) {
      // Plugin kann in Tests / auf unbekannten Plattformen scheitern —
      // dann bleibt isConnected auf true (Fail-Open).
    }
    try {
      _sub = Connectivity().onConnectivityChanged.listen(_apply);
    } catch (_) {}
  }

  void _apply(List<ConnectivityResult> results) {
    final connected = results.any((r) => r != ConnectivityResult.none);
    if (connected && _wasDisconnected) {
      _justReconnected = true;
      _reconnectBannerTimer?.cancel();
      _reconnectBannerTimer = Timer(const Duration(milliseconds: 2500), () {
        _justReconnected = false;
        notifyListeners();
      });
    }
    _wasDisconnected = !connected;
    final changed = connected != _isConnected || _justReconnected;
    _isConnected = connected;
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reconnectBannerTimer?.cancel();
    super.dispose();
  }
}
