import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/runde.dart';
import '../theme/dazu_colors.dart';
import 'mini_map_snapshot.dart';

/// Card für eine öffentliche Runde in der „Alle Runden"-Sektion
/// (Umgebung-Tab). Hero-Lavendel-Fläche + Aktivitäts-Icon + Name
/// (violett + oranger Punkt) + Jetzt-Pille + ETA + „Komm dazu"-Button.
class OffeneRundeCard extends StatelessWidget {
  const OffeneRundeCard({
    super.key,
    required this.runde,
    required this.onJoin,
    this.joined = false,
    this.disabled = false,
  });

  final Runde runde;
  final VoidCallback onJoin;
  final bool joined;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final isNow = runde.scheduledTime == 'Jetzt';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: DazuColors.brandViolet.withValues(alpha: 0.12),
        ),
      ),
      child: Stack(
        children: [
          // Mini-Map-Hintergrund (Google Static). Zieht die Card an die
          // Standort-Herkunft — iOS-Pattern aus MyDropFeedCard /
          // StrangerDropFeedCard.
          Positioned.fill(
            child: MiniMapSnapshot(
              lat: runde.lat,
              lng: runde.lng,
              zoom: 15,
              width: 400,
              height: 120,
            ),
          ),
          // Lavender→Peach Gradient drüber damit Text lesbar bleibt.
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xE6EFEAFC), Color(0xCCF7E6DB)],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _activityIcon(),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: _activityLabel(runde.activityName)),
                      const SizedBox(width: 8),
                      if (isNow) _jetztPill(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _nameMitPunkt(runde.hostName),
                      if (runde.hostAge != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${runde.hostAge}',
                          style: GoogleFonts.bricolageGrotesque(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: DazuColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${runde.currentParticipants} / ${runde.maxParticipants}',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: DazuColors.brandViolet,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _joinButton(),
          ],
        ),
          ),
        ],
      ),
    );
  }

  Widget _activityIcon() {
    return Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.local_activity_outlined,
        size: 28,
        color: DazuColors.brandViolet,
      ),
    );
  }

  Widget _activityLabel(String activity) {
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: GoogleFonts.bricolageGrotesque(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: DazuColors.brandViolet,
        ),
        children: [
          TextSpan(text: activity),
          const TextSpan(
            text: '.',
            style: TextStyle(color: DazuColors.brandOrange),
          ),
        ],
      ),
    );
  }

  Widget _nameMitPunkt(String name) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.bricolageGrotesque(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: DazuColors.brandViolet,
        ),
        children: [
          TextSpan(text: name),
          const TextSpan(
            text: '.',
            style: TextStyle(color: DazuColors.brandOrange),
          ),
        ],
      ),
    );
  }

  Widget _jetztPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DazuColors.brandOrange,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Jetzt',
        style: GoogleFonts.bricolageGrotesque(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _joinButton() {
    final bg = joined
        ? DazuColors.brandLavender
        : disabled
            ? DazuColors.brandLavender
            : DazuColors.brandOrange;
    final fg = joined
        ? DazuColors.brandViolet
        : disabled
            ? DazuColors.textTertiary
            : Colors.white;
    return TextButton(
      onPressed: disabled ? null : onJoin,
      style: TextButton.styleFrom(
        backgroundColor: bg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: const StadiumBorder(),
      ),
      child: Text(
        joined ? 'Schon dabei' : 'Komm dazu',
        style: GoogleFonts.bricolageGrotesque(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}
