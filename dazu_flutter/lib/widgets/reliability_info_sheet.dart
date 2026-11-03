import 'package:flutter/material.dart';

import '../models/reliability_score.dart';
import '../theme/dazu_colors.dart';

/// Detail-Sheet zum Reliability-Score. Portiert aus iOS
/// `DesignSystem.swift` → `ReliabilityInfoSheet` (DesignSystem.swift:841).
///
/// Vereinfachte Fassung: Hero-Karte, Progress-Bar bis zur nächsten
/// Tier-Schwelle, 5-Tier-Liste mit markiertem aktuellen Tier und ein
/// kleiner Counter-Overview. iOS hat zusätzlich noch Bonus-Breakdown
/// und Punkte-Events-Log — die portieren wir erst wenn im UI gebraucht.
///
/// Verwendung:
/// ```dart
/// await showModalBottomSheet<void>(
///   context: context,
///   isScrollControlled: true,
///   backgroundColor: Colors.transparent,
///   useSafeArea: true,
///   builder: (_) => ReliabilityInfoSheet(score: score),
/// );
/// ```
class ReliabilityInfoSheet extends StatefulWidget {
  const ReliabilityInfoSheet({super.key, required this.score});
  final ReliabilityScore score;

  @override
  State<ReliabilityInfoSheet> createState() => _ReliabilityInfoSheetState();
}

class _ReliabilityInfoSheetState extends State<ReliabilityInfoSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _progressCtrl.forward();
    });
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final s = widget.score;
    return Container(
      height: size.height * 0.86,
      decoration: const BoxDecoration(
        color: DazuColors.brandCream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _dragHandle(),
          _header(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
              children: [
                _heroCard(s),
                const SizedBox(height: 14),
                _progressCard(s),
                const SizedBox(height: 14),
                _tiersCard(s),
                const SizedBox(height: 14),
                _statsRow(s),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dragHandle() => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Container(
          width: 36,
          height: 5,
          decoration: BoxDecoration(
            color: DazuColors.textTertiary.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(100),
          ),
        ),
      );

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 10, 12),
        child: Row(
          children: [
            const Text(
              'Zuverlässigkeit',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: DazuColors.textPrimary,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Fertig',
                style: TextStyle(
                  color: DazuColors.brandViolet,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _heroCard(ReliabilityScore s) {
    final tierColor = s.tier.color;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: tierColor.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(s.tier.icon, color: tierColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.displayLabel,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: DazuColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${s.points}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: tierColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Pkt',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DazuColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressCard(ReliabilityScore s) {
    final remaining = s.pointsToNextTier;
    final next = s.tier.next;
    if (remaining == null || next == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: const Row(
          children: [
            Icon(Icons.workspace_premium,
                color: DazuColors.brandViolet, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Top-Tier erreicht — danke, dass du zuverlässig bist!',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DazuColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Noch $remaining Pkt bis ${next.label}',
            style: const TextStyle(
              fontSize: 13,
              color: DazuColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: AnimatedBuilder(
              animation: _progressCtrl,
              builder: (_, _) {
                return LinearProgressIndicator(
                  value: s.tierProgress * _progressCtrl.value,
                  minHeight: 6,
                  backgroundColor:
                      DazuColors.textTertiary.withValues(alpha: 0.15),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(s.tier.color),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tiersCard(ReliabilityScore s) {
    final tiers = ReliabilityTier.values;
    final thresholds = <ReliabilityTier, int>{
      ReliabilityTier.dropout: -999,
      ReliabilityTier.restart: 0,
      ReliabilityTier.explorer: 50,
      ReliabilityTier.regular: 200,
      ReliabilityTier.legend: 500,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          for (int i = 0; i < tiers.length; i++) ...[
            _tierRow(
              tier: tiers[i],
              threshold: thresholds[tiers[i]]!,
              isCurrent: tiers[i] == s.tier,
            ),
            if (i < tiers.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(
                  height: 1,
                  color: DazuColors.textTertiary.withValues(alpha: 0.15),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _tierRow({
    required ReliabilityTier tier,
    required int threshold,
    required bool isCurrent,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tier.color.withValues(alpha: isCurrent ? 0.18 : 0.08),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(tier.icon, size: 16, color: tier.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tier.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                    color: DazuColors.textPrimary,
                  ),
                ),
                Text(
                  threshold <= 0 ? 'unter 0 Pkt' : 'ab $threshold Pkt',
                  style: const TextStyle(
                    fontSize: 11,
                    color: DazuColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (isCurrent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: tier.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                'Aktuell',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: tier.color,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statsRow(ReliabilityScore s) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatCell(value: s.showUps, label: 'Vor Ort'),
          _StatCell(value: s.hostSuccesses, label: 'Als Host'),
          _StatCell(
              value: s.currentStreak, label: 'Streak', accent: s.currentStreak > 0),
          _StatCell(value: s.noShows, label: 'No-Shows'),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: DazuColors.brandLavender.withValues(alpha: 0.5),
        ),
      );
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.value,
    required this.label,
    this.accent = false,
  });

  final int value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: accent ? DazuColors.brandOrange : DazuColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: DazuColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
