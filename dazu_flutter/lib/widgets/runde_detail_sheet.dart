import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../models/runde.dart';
import '../models/teilnehmer.dart';
import '../services/block_report_service.dart';
import '../services/runden_service.dart';
import '../theme/dazu_colors.dart';
import 'dazu_icons.dart';
import 'mini_map_snapshot.dart';

/// Bottom-Sheet, geht beim Tap auf einen Karten-Marker auf. Zeigt
/// Aktivität, Host, Live-Teilnehmer und einen Primär-Button:
///  - Host: „Runde beenden" (`beendeRunde`)
///  - User:  „Komm dazu" / „Schon dabei — verlassen"
/// Teilnehmer-Liste streamt live aus `/dropins/{rundeID}`.
class RundeDetailSheet extends StatelessWidget {
  const RundeDetailSheet({super.key, required this.runde});

  final Runde runde;

  @override
  Widget build(BuildContext context) {
    final service = RundenService();
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isHost = runde.hostUID == myUid;
    final isNow = runde.scheduledTime == 'Jetzt';

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: DazuColors.brandCream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: EdgeInsets.zero,
          children: [
            _buildHero(runde, isNow),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHostLine(runde),
                  const SizedBox(height: 16),
                  _buildTeilnehmerCard(service, runde),
                  const SizedBox(height: 24),
                  _buildPrimaryButton(
                    context: context,
                    service: service,
                    runde: runde,
                    isHost: isHost,
                    myUid: myUid,
                  ),
                  const SizedBox(height: 10),
                  _buildShareButton(runde),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(Runde runde, bool isNow) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SizedBox(
        height: 180,
        child: Stack(
          children: [
            // Live-Standort als Mini-Map-Hintergrund — ersetzt den
            // Lavender-Gradient aus v1. Darüber liegt eine Cream-Lasur
            // damit der Text lesbar bleibt.
            Positioned.fill(
              child: MiniMapSnapshot(
                lat: runde.lat,
                lng: runde.lng,
                zoom: 15,
                width: 600,
                height: 300,
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCCEFEAFC), Color(0x80F7E6DB)],
                  ),
                ),
              ),
            ),
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: DazuColors.brandNight.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            top: 36,
            right: 24,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: DazuColors.brandViolet,
                        height: 1.1,
                      ),
                      children: [
                        TextSpan(text: runde.activityName),
                        const TextSpan(
                          text: '.',
                          style: TextStyle(color: DazuColors.brandOrange),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isNow) _livePill(),
              ],
            ),
          ),
          Positioned(
            left: 24,
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                runde.scheduledTime,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: DazuColors.brandNight,
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _livePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: DazuColors.brandOrange,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostLine(Runde runde) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: DazuColors.monogramPalette[
                runde.hostName.hashCode.abs() %
                    DazuColors.monogramPalette.length],
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            runde.hostName.isEmpty
                ? '?'
                : runde.hostName.characters.first.toUpperCase(),
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: DazuColors.brandViolet,
                  ),
                  children: [
                    TextSpan(text: runde.hostName),
                    const TextSpan(
                      text: '.',
                      style: TextStyle(color: DazuColors.brandOrange),
                    ),
                  ],
                ),
              ),
              if (runde.hostAge != null)
                Text(
                  '${runde.hostAge} Jahre',
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 13,
                    color: DazuColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 4),
              UserBadgesCompactRow(
                uid: runde.hostUID,
                reliabilityPoints: runde.hostReliabilityPoints,
                isHost: true,
              ),
            ],
          ),
        ),
        Builder(builder: (menuCtx) => _buildHostMenu(menuCtx, runde)),
      ],
    );
  }

  Widget _buildHostMenu(BuildContext context, Runde runde) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || me == runde.hostUID) return const SizedBox.shrink();
    final svc = BlockReportService();
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        color: DazuColors.brandNight.withValues(alpha: 0.55),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (action) async {
        if (action == 'block') {
          await svc.block(runde.hostUID);
          if (!context.mounted) return;
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${runde.hostName} blockiert.')),
          );
        } else if (action == 'report') {
          await _openReportDialog(context, svc, runde);
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'report',
          child: Row(
            children: [
              const Icon(Icons.flag_outlined,
                  color: DazuColors.brandNight, size: 18),
              const SizedBox(width: 10),
              Text(
                'Melden',
                style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'block',
          child: Row(
            children: [
              const Icon(Icons.block, color: Colors.red, size: 18),
              const SizedBox(width: 10),
              Text(
                'Blockieren',
                style: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w700, color: Colors.red),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openReportDialog(
      BuildContext context, BlockReportService svc, Runde runde) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: DazuColors.brandCream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Was stimmt nicht?',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: DazuColors.brandNight,
                ),
              ),
              const SizedBox(height: 14),
              for (final r in BlockReportService.reportReasons)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    r,
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: DazuColors.brandNight,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, r),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    await svc.report(reportedUID: runde.hostUID, reason: chosen);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Danke — $chosen gemeldet.')),
    );
  }

  Widget _buildTeilnehmerCard(RundenService service, Runde runde) {
    return StreamBuilder<List<Teilnehmer>>(
      stream: service.watchTeilnehmer(runde.id),
      builder: (ctx, snap) {
        final list = snap.data ?? const <Teilnehmer>[];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: DazuColors.brandLavender.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Wer kommt',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: DazuColors.brandNight,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${1 + list.length} / ${runde.maxParticipants}',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: DazuColors.brandViolet,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _joinerAvatar(
                    runde.hostName,
                    photoURL: runde.hostProfileImageURL,
                    uid: runde.hostUID,
                    reliabilityPoints: runde.hostReliabilityPoints,
                    isHost: true,
                  ),
                  for (final t in list)
                    _joinerAvatar(
                      t.name,
                      photoURL: t.profileImageURL,
                      uid: t.id,
                      reliabilityPoints: t.reliabilityPoints,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _joinerAvatar(
    String name, {
    String? photoURL,
    required String uid,
    int? reliabilityPoints,
    bool isHost = false,
  }) {
    final color = DazuColors.monogramPalette[
        name.hashCode.abs() % DazuColors.monogramPalette.length];
    final hasPhoto = photoURL != null && photoURL.isNotEmpty;
    return SizedBox(
      width: 56,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: hasPhoto ? Colors.transparent : color,
              shape: BoxShape.circle,
              border: isHost
                  ? Border.all(color: DazuColors.brandOrange, width: 2.5)
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: hasPhoto
                ? Image.network(photoURL, fit: BoxFit.cover,
                    width: 40, height: 40,
                    errorBuilder: (_, obj, stack) => _monogramFallback(name))
                : _monogramFallback(name),
          ),
          const SizedBox(height: 4),
          RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: DazuColors.brandViolet,
              ),
              children: [
                TextSpan(text: name.characters.take(8).toString()),
                const TextSpan(
                  text: '.',
                  style: TextStyle(color: DazuColors.brandOrange),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          UserBadgesCompactRow(
            uid: uid,
            reliabilityPoints: reliabilityPoints,
            isHost: isHost,
            iconSize: 10,
          ),
        ],
      ),
    );
  }

  Widget _monogramFallback(String name) {
    return Text(
      name.isEmpty ? '?' : name.characters.first.toUpperCase(),
      style: GoogleFonts.bricolageGrotesque(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    );
  }

  /// Share-Button: öffnet System-Share-Sheet mit `dazuapp.com/d/<id>`.
  /// Spiegelt NEXT_UPDATE-Roadmap #3 (Strava-Pattern): wer den Link
  /// antippt, landet in der App auf genau dieser Runde oder sieht sie
  /// im Browser.
  Widget _buildShareButton(Runde runde) {
    final link = 'https://dazuapp.com/d/${runde.id}';
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: () {
          SharePlus.instance.share(ShareParams(
            text:
                '${runde.hostName} macht gerade "${runde.activityName}". Komm vorbei: $link',
          ));
        },
        icon: const Icon(Icons.ios_share, size: 16),
        label: Text(
          'Runde teilen',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: DazuColors.brandViolet,
          side: BorderSide(
            color: DazuColors.brandViolet.withValues(alpha: 0.3),
          ),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required BuildContext context,
    required RundenService service,
    required Runde runde,
    required bool isHost,
    required String? myUid,
  }) {
    if (isHost) {
      return SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: () async {
            await service.beendeRunde(runde.id);
            if (!context.mounted) return;
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Runde beendet')),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade400,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: const StadiumBorder(),
            elevation: 0,
          ),
          child: Text(
            'Runde beenden',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    return StreamBuilder<List<Teilnehmer>>(
      stream: service.watchTeilnehmer(runde.id),
      builder: (ctx, snap) {
        final list = snap.data ?? const <Teilnehmer>[];
        final joined = myUid != null && list.any((t) => t.id == myUid);
        return SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return;
              if (joined) {
                await service.verlasseRunde(runde.id);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Aus "${runde.activityName}" raus')),
                );
              } else {
                await service.tritRundeBei(
                  rundeID: runde.id,
                  name: user.displayName ?? 'dazu',
                  lat: runde.lat,
                  lng: runde.lng,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Bei "${runde.activityName}" dabei 🎉')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: joined
                  ? DazuColors.brandLavender
                  : DazuColors.brandOrange,
              foregroundColor:
                  joined ? DazuColors.brandViolet : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: const StadiumBorder(),
              elevation: 0,
            ),
            child: Text(
              joined ? 'Schon dabei — verlassen' : 'Komm dazu',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
      },
    );
  }
}
