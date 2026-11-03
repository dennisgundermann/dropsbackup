import 'package:flutter/material.dart';

import '../theme/dazu_colors.dart';

/// 2.0.2 Trust-Badge — binäres ✓-Siegel für User mit „ausreichender
/// Historie" (≥ 200 Reliability-Punkte). Portiert aus iOS
/// `DesignSystem.swift` → `ReliabilityScore.badge(forPoints:)`.
///
/// Darstellt in zwei Varianten:
///   - `TrustedBadge.inline()` — kleines Chip neben einem Namen
///     (Feed, Map-Pin-Popup, Freundesliste)
///   - `TrustedBadge.full()` — größere Pill mit „Verlässlich" Label
///     für Profil-Hero
///
/// Zeigt sich NUR wenn `isTrusted` true ist — iOS-Verhalten: unsichtbar
/// unter dem Schwellwert, damit es nicht wie ein Ranking wirkt.
class TrustedBadge extends StatelessWidget {
  const TrustedBadge({
    super.key,
    required this.isTrusted,
    this.size = TrustedBadgeSize.inline,
  });

  /// Convenience: nur das Icon (ohne Label), gleich wie `inline()`
  /// aber ohne Padding/Hintergrund — nützlich neben Namen.
  const TrustedBadge.inline({super.key, required this.isTrusted})
      : size = TrustedBadgeSize.inline;

  const TrustedBadge.full({super.key, required this.isTrusted})
      : size = TrustedBadgeSize.full;

  final bool isTrusted;
  final TrustedBadgeSize size;

  @override
  Widget build(BuildContext context) {
    if (!isTrusted) return const SizedBox.shrink();
    switch (size) {
      case TrustedBadgeSize.inline:
        return _InlineChip();
      case TrustedBadgeSize.full:
        return _FullPill();
    }
  }
}

enum TrustedBadgeSize { inline, full }

class _InlineChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 4),
      child: Icon(
        Icons.verified_rounded,
        size: 16,
        color: DazuColors.brandViolet,
        semanticLabel: 'Verlässlich',
      ),
    );
  }
}

class _FullPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: DazuColors.brandViolet.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_rounded,
            size: 14,
            color: DazuColors.brandViolet,
          ),
          SizedBox(width: 4),
          Text(
            'Verlässlich',
            style: TextStyle(
              color: DazuColors.brandViolet,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
