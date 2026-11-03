import 'package:flutter/material.dart';

import '../services/network_monitor.dart';

/// Oben-schwebender Chip: Rot „Keine Verbindung" bzw. Grün „Wieder
/// verbunden" (2.5 s). Portiert aus iOS `Drops/NetworkMonitor.swift →
/// struct OfflineBanner`.
///
/// Platzieren in jedem Tab-Scaffold als `Positioned`-Overlay oder im
/// MainShell einmal zentral.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  static const Color _onlineGreen = Color(0xFF22C55E);
  static const Color _offlineRed = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    final nm = NetworkMonitor.instance;
    return ListenableBuilder(
      listenable: nm,
      builder: (context, _) {
        final show = !nm.isConnected || nm.justReconnected;
        return AnimatedSlide(
          offset: show ? Offset.zero : const Offset(0, -1.4),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: MediaQuery.of(context).padding.top + 8,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  color: (nm.isConnected ? _onlineGreen : _offlineRed)
                      .withValues(alpha: 0.94),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x38000000),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      nm.isConnected
                          ? Icons.wifi_rounded
                          : Icons.wifi_off_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      nm.isConnected
                          ? 'Wieder verbunden'
                          : 'Keine Verbindung',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
