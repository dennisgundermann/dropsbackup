import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/first_drop_celebration.dart';
import '../models/runde.dart';
import '../services/friends_service.dart';
import '../services/reliability_service.dart';
import '../services/runden_service.dart';
import '../theme/dazu_colors.dart';
import '../widgets/dazu_icon.dart';
import '../widgets/dazu_icons.dart';
import '../widgets/dazu_wordmark.dart';
import '../widgets/first_drop_celebration_sheet.dart';
import '../widgets/offene_runde_card.dart';
import '../widgets/sticky_dazu_header.dart';

/// Umgebung — Hero oben, Puls-Zahlen aus Live-Daten, dann alle offenen
/// Runden aus RTDB als Cards. Beitreten/Verlassen schreibt in
/// `/dropins/{rundeID}`.
class UmgebungScreen extends StatefulWidget {
  const UmgebungScreen({super.key});

  @override
  State<UmgebungScreen> createState() => _UmgebungScreenState();
}

class _UmgebungScreenState extends State<UmgebungScreen>
    with StickyDazuHeaderMixin {
  final RundenService _service = RundenService();
  final FriendsService _friendsService = FriendsService();
  AuthorizationStatus? _pushStatus;
  String? _userGender;
  bool _femaleOnly = false;
  double _radiusKm = 10;

  @override
  void initState() {
    super.initState();
    _loadPushStatus();
    _loadUserGender();
  }

  Future<void> _loadPushStatus() async {
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      if (!mounted) return;
      setState(() => _pushStatus = s.authorizationStatus);
    } catch (_) {}
  }

  Future<void> _loadUserGender() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap =
          await FirebaseDatabase.instance.ref('users/$uid/gender').get();
      if (!mounted) return;
      setState(() => _userGender = snap.value?.toString());
    } catch (_) {}
  }

  Future<void> _requestPush() async {
    await FirebaseMessaging.instance.requestPermission();
    _loadPushStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<List<Runde>>(
          stream: _service.watchAktiveRunden(),
          builder: (context, snapshot) {
            final allRunden = snapshot.data ?? const <Runde>[];
            final runden = _femaleOnly
                ? allRunden.where((r) => r.femaleOnly == true).toList()
                : allRunden;
            return CustomScrollView(
              controller: dazuScrollController,
              slivers: [
                SliverToBoxAdapter(child: _buildHeroBlock(runden.length)),
                SliverToBoxAdapter(child: _buildPushBanner()),
                const SliverToBoxAdapter(child: SizedBox(height: 6)),
                if (_userGender == 'weiblich')
                  SliverToBoxAdapter(child: _buildFemaleFilterBar()),
                SliverToBoxAdapter(child: _buildFriendsRow()),
                if (runden.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  )
                else
                  SliverToBoxAdapter(child: _buildSectionHeader(runden.length)),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final runde = runden[i];
                      final myUid = FirebaseAuth.instance.currentUser?.uid;
                      final isHost = runde.hostUID == myUid;
                      return OffeneRundeCard(
                        runde: runde,
                        joined: isHost,
                        disabled: isHost,
                        onJoin: () => _joinRunde(runde),
                      );
                    },
                    childCount: runden.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            );
          },
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: StickyDazuHeader(isScrolled: dazuIsScrolled),
        ),
      ],
    );
  }

  Future<void> _joinRunde(Runde runde) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await _service.tritRundeBei(
        rundeID: runde.id,
        name: user.displayName ?? 'dazu',
      );
      // Erst-Join-Celebration (einmal pro Account). Zeigt das Sheet
      // und vergibt +10 Pkt Erst-Bonus. iOS: Models.swift
      // `firstJoinBonusReceived` Flag.
      final isFirstJoin =
          await ReliabilityService.instance.claimFirstJoinBonus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Anfrage an "${runde.hostName}" gesendet — warte kurz auf Zusage.'),
        ),
      );
      if (isFirstJoin) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            useSafeArea: true,
            builder: (_) => const FirstDropCelebrationSheet(
              variant: FirstDropCelebration.joined,
            ),
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konnte Anfrage nicht senden: $e')),
      );
    }
  }

  Widget _buildPushBanner() {
    final denied = _pushStatus == AuthorizationStatus.denied ||
        _pushStatus == AuthorizationStatus.notDetermined;
    if (!denied) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _requestPush,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DazuColors.brandOrange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: DazuColors.brandOrange.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              const DazuIcon('SetGlocke',
                  color: DazuColors.brandOrange, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Push aus — du verpasst Runden',
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: DazuColors.brandNight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Antippen zum Aktivieren.',
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DazuColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBlock(int liveCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DazuWordmark(height: 24),
          const SizedBox(height: 20),
          _buildHeroHeadline(),
          const SizedBox(height: 20),
          _buildPulsCards(liveCount),
        ],
      ),
    );
  }

  Widget _buildHeroHeadline() {
    final base = GoogleFonts.bricolageGrotesque(
      fontSize: 42,
      fontWeight: FontWeight.w800,
      height: 1.02,
    );
    return RichText(
      text: TextSpan(
        style: base.copyWith(color: DazuColors.brandNight),
        children: [
          const TextSpan(text: 'Was läuft\n'),
          TextSpan(
            text: 'bei dir',
            style: base.copyWith(color: DazuColors.brandViolet),
          ),
          TextSpan(
            text: '?',
            style: base.copyWith(color: DazuColors.brandOrange),
          ),
        ],
      ),
    );
  }

  Widget _buildPulsCards(int liveCount) {
    return Row(
      children: [
        Expanded(
          child: _pulseCard(
            label: liveCount == 1 ? 'Runde live' : 'Runden live',
            value: '$liveCount',
            icon: SizedBox(
              width: 24, height: 24,
              child: CustomPaint(painter: _DazuRunRingPainter()),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StreamBuilder<DatabaseEvent>(
            // Server-Zähler aus Cloud-Function `stats/dropsToday/<ISO>`.
            // Berlin-Date = einfach Local-Date; reicht für CET-Launch.
            stream: FirebaseDatabase.instance
                .ref('stats/dropsToday/${_todayIsoDate()}')
                .onValue,
            builder: (ctx, snap) {
              final v = snap.data?.snapshot.value;
              final count = v is num ? v.toInt() : 0;
              return _pulseCard(
                label: 'heute passiert',
                value: '$count',
                icon: SizedBox(
                  width: 24, height: 24,
                  child: CustomPaint(painter: _SparkleIconPainter()),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _todayIsoDate() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Widget _pulseCard({
    required String label,
    required String value,
    required Widget icon,
  }) {
    // iOS: solid Lavender ohne Border/Schatten, Icon direkt im BG (keine
    // Pastille), großer Value prominent.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: DazuColors.brandLavender,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          SizedBox(width: 24, height: 24, child: Center(child: icon)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: DazuColors.brandNight,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 12,
                    color: DazuColors.brandNight.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Distance-Filter — iOS `distanceTimeFilterBar`. Chip-Row mit
  /// Default „≤ 10 km". Tap öffnet BottomSheet mit vier Werten.
  Widget _buildDistanceFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: _pickRadius,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: DazuColors.brandLavender,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.my_location,
                      size: 14, color: DazuColors.brandViolet),
                  const SizedBox(width: 6),
                  Text(
                    '≤ ${(_radiusKm).toStringAsFixed(_radiusKm < 1 ? 1 : 0)} km',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: DazuColors.brandViolet,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down,
                      size: 14, color: DazuColors.brandViolet),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickRadius() async {
    final val = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: DazuColors.brandCream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: DazuColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            for (final km in const [2.0, 5.0, 10.0, 25.0, 50.0])
              ListTile(
                leading: const Icon(Icons.my_location,
                    color: DazuColors.brandViolet),
                title: Text('≤ ${km.toStringAsFixed(0)} km',
                    style: GoogleFonts.bricolageGrotesque(
                      fontWeight: FontWeight.w800,
                      color: DazuColors.brandNight,
                    )),
                onTap: () => Navigator.pop(ctx, km),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (val != null) setState(() => _radiusKm = val);
  }

  Widget _buildFemaleFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _femaleOnly = !_femaleOnly),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _femaleOnly
                ? DazuColors.brandOrange.withValues(alpha: 0.18)
                : DazuColors.brandLavender,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _femaleOnly
                  ? DazuColors.brandOrange
                  : DazuColors.brandViolet.withValues(alpha: 0.18),
              width: _femaleOnly ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              DazuFemaleIcon(
                size: 22,
                main: _femaleOnly
                    ? DazuColors.brandOrange
                    : DazuColors.brandViolet,
                accent: _femaleOnly
                    ? DazuColors.brandViolet
                    : DazuColors.brandOrange,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _femaleOnly
                          ? 'Nur Runden mit Frauen'
                          : 'Nur weiblich-Filter',
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: DazuColors.brandNight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _femaleOnly
                          ? 'Tippen zum Deaktivieren.'
                          : 'Nur Runden, die ausschließlich für Frauen offen sind.',
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DazuColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _femaleOnly,
                onChanged: (v) => setState(() => _femaleOnly = v),
                activeThumbColor: DazuColors.brandOrange,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendsRow() {
    return StreamBuilder<List<Freund>>(
      stream: _friendsService.watchFriends(),
      builder: (ctx, snap) {
        final list = snap.data ?? const <Freund>[];
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(left: 24, top: 8, right: 24, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deine Freunde',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: DazuColors.brandNight,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: list.length,
                  separatorBuilder: (_, i) => const SizedBox(width: 14),
                  itemBuilder: (ctx, i) => _friendChip(list[i], i),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _friendChip(Freund f, int i) {
    final hasPhoto = f.profileImageURL != null && f.profileImageURL!.isNotEmpty;
    const avatar = 72.0;
    return SizedBox(
      width: avatar + 10,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: avatar,
            height: avatar,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Lavender-Kreis als Avatar-Grund + Monogram oder Foto
                Container(
                  width: avatar,
                  height: avatar,
                  decoration: BoxDecoration(
                    color: hasPhoto
                        ? Colors.transparent
                        : DazuColors.brandLavender,
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  child: hasPhoto
                      ? Image.network(f.profileImageURL!,
                          fit: BoxFit.cover, width: avatar, height: avatar)
                      : CustomPaint(
                          size: const Size(avatar, avatar),
                          painter: _MonoPersonPainter(),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: DazuColors.brandViolet,
              ),
              children: [
                TextSpan(text: f.name),
                const TextSpan(
                  text: '.',
                  style: TextStyle(color: DazuColors.brandOrange),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ÖFFENTLICH · $count',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: DazuColors.brandViolet.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Alle Runden',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: DazuColors.brandNight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          SizedBox(
            width: 260,
            height: 220,
            child: CustomPaint(painter: _EmptyArtPainter()),
          ),
          const SizedBox(height: 24),
          Text(
            'Hier ist noch nichts los',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: DazuColors.brandNight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Starte die erste Runde — spontan, in der Nähe, ohne Chat.',
            textAlign: TextAlign.center,
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: DazuColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => launchUrl(
              Uri.parse('https://instagram.com/dazuapp'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.camera_alt_outlined,
                size: 18, color: DazuColors.brandViolet),
            label: Text(
              'Folg dazu auf Instagram',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: DazuColors.brandViolet,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 14),
              shape: const StadiumBorder(),
              side: BorderSide(
                color: DazuColors.brandViolet.withValues(alpha: 0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Portiert die iOS `DazuNearbyEmptyArt`-Komposition 1:1 in Flutter:
/// drei dicke Lavender-Straßen (zwei vertikal, eine horizontal), ein
/// zentraler halb-offener Lila-Ring mit Gap oben rechts, ein oranger
/// Dot in der Gap, drei dekorative Partikel. Koordinatensystem ist
/// 720×540 wie in iOS; wir skalieren proportional.
class _EmptyArtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const vb = Size(720, 540);
    final k = math.min(size.width / vb.width, size.height / vb.height);
    final ox = (size.width - vb.width * k) / 2;
    final oy = (size.height - vb.height * k) / 2;
    Offset p(double x, double y) => Offset(ox + x * k, oy + y * k);

    // Lavender-Straßen (iOS 38pt Stroke, butt caps)
    final road = Paint()
      ..color = DazuColors.brandLavender
      ..style = PaintingStyle.stroke
      ..strokeWidth = 38 * k
      ..strokeCap = StrokeCap.butt;
    final roadsPath = Path()
      ..moveTo(p(182, -10).dx, p(182, -10).dy)
      ..quadraticBezierTo(
          p(200, 300).dx, p(200, 300).dy, p(128, 550).dx, p(128, 550).dy)
      ..moveTo(p(580, -10).dx, p(580, -10).dy)
      ..quadraticBezierTo(
          p(560, 300).dx, p(560, 300).dy, p(615, 550).dx, p(615, 550).dy)
      ..moveTo(p(-10, 375).dx, p(-10, 375).dy)
      ..cubicTo(p(250, 330).dx, p(250, 330).dy, p(470, 440).dx,
          p(470, 440).dy, p(730, 325).dx, p(730, 325).dy);
    canvas.drawPath(roadsPath, road);

    // Dekorative Specks (iOS: 288/78 r12, 90/180 r15, 666/444 r15)
    final speck = Paint()..color = DazuColors.brandLavender;
    final specks = <List<double>>[
      [288, 78, 12],
      [90, 180, 15],
      [666, 444, 15],
    ];
    for (final s in specks) {
      canvas.drawCircle(p(s[0], s[1]), s[2] * k, speck);
    }

    // Floor-Shadow unter dem Ring (iOS Ellipse 228×36)
    final shadow = Paint()
      ..color = DazuColors.brandLavender.withValues(alpha: 0.9);
    final sc = p(360, 473);
    final sw = 228 * k;
    final sh = 36 * k;
    canvas.drawOval(
      Rect.fromCenter(center: sc, width: sw, height: sh),
      shadow,
    );

    // Lila halb-offener Ring (iOS: center 360/275, r 120, Gap oben rechts
    // ca -1° bis 265°, Stroke 42pt heavy rounded)
    final ring = Paint()
      ..color = DazuColors.brandViolet
      ..style = PaintingStyle.stroke
      ..strokeWidth = 42 * k
      ..strokeCap = StrokeCap.round;
    final cx = 360.0, cy = 275.0, rr = 120.0;
    final ringPath = Path();
    for (var j = 0; j <= 96; j++) {
      final a = (-1.0 + 266.0 * j / 96.0) * math.pi / 180.0;
      final q = p(cx + rr * math.cos(a), cy + rr * math.sin(a));
      if (j == 0) {
        ringPath.moveTo(q.dx, q.dy);
      } else {
        ringPath.lineTo(q.dx, q.dy);
      }
    }
    canvas.drawPath(ringPath, ring);

    // Oranger Dot an der Gap (-1°, direkt am Ring)
    final dotPaint = Paint()..color = DazuColors.brandOrange;
    final a0 = -1.0 * math.pi / 180.0;
    final dotPos = p(cx + rr * math.cos(a0), cy + rr * math.sin(a0));
    canvas.drawCircle(dotPos, 22 * k, dotPaint);
  }

  @override
  bool shouldRepaint(_EmptyArtPainter old) => false;
}

/// Pulse-Card-Icon „Runden live" — lila Ring + oranger Dot in der Mitte,
/// Mini-Variante des iOS-Live-Signets.
class _DazuRunRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final strokeWidth = size.width * 0.16;
    final r = size.width / 2 - strokeWidth / 2;
    // Halb-offener Lila-Ring — Lücke oben rechts wie das dazu-Logo.
    final ring = Paint()
      ..color = DazuColors.brandViolet
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final start = math.pi * 150 / 180;
    final sweep = math.pi * 240 / 180;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r), start, sweep, false, ring);
    // Oranger Punkt in der Lücke oben rechts.
    final dot = Paint()..color = DazuColors.brandOrange;
    final dotCenter = Offset(
      c.dx + r * math.cos(-math.pi / 3),
      c.dy + r * math.sin(-math.pi / 3),
    );
    canvas.drawCircle(dotCenter, size.width * 0.12, dot);
  }

  @override
  bool shouldRepaint(_DazuRunRingPainter old) => false;
}

/// Sparkle-Icon für die „heute passiert"-Puls-Card. Matcht das iOS
/// `sparkles` SF Symbol: ein großer 4-zackiger Stern plus zwei kleine
/// Sterne. Alles lila/brandViolet.
class _SparkleIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = DazuColors.brandViolet;
    void sparkle(Offset c, double r) {
      final path = Path();
      // 4-zackiger Stern via Rombus-Form
      path.moveTo(c.dx, c.dy - r);
      path.quadraticBezierTo(c.dx + r * 0.2, c.dy, c.dx + r, c.dy);
      path.quadraticBezierTo(c.dx + r * 0.2, c.dy, c.dx, c.dy + r);
      path.quadraticBezierTo(c.dx - r * 0.2, c.dy, c.dx - r, c.dy);
      path.quadraticBezierTo(c.dx - r * 0.2, c.dy, c.dx, c.dy - r);
      path.close();
      canvas.drawPath(path, paint);
    }

    sparkle(Offset(size.width * 0.5, size.height * 0.55), size.width * 0.38);
    sparkle(Offset(size.width * 0.18, size.height * 0.22), size.width * 0.16);
    sparkle(Offset(size.width * 0.82, size.height * 0.28), size.width * 0.12);
  }

  @override
  bool shouldRepaint(_SparkleIconPainter old) => false;
}

/// Generische Person-Silhouette im Monogram-Avatar: halb-offener lila
/// Ring (wie das iOS DazuAShape) + oranger Dot — Platzhalter wenn der
/// Freund noch kein Foto gesetzt hat. Spiegelt iOS DazuPersonIcon.
class _MonoPersonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final strokeWidth = size.width * 0.09;
    final r = size.width * 0.26;
    final ring = Paint()
      ..color = DazuColors.brandViolet
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final start = math.pi * 160 / 180;
    final sweep = math.pi * 220 / 180;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r), start, sweep, false, ring);
    final dot = Paint()..color = DazuColors.brandOrange;
    canvas.drawCircle(
      Offset(c.dx + r * 0.75, c.dy - r * 0.85), size.width * 0.07, dot);
  }

  @override
  bool shouldRepaint(_MonoPersonPainter old) => false;
}

/// Halb-offener oranger Ring um einen Freundes-Avatar — Lücke oben rechts,
/// genau wie das iOS-Pattern mit `.trim(from: 0.08, to: 0.84)`.
class _OpenRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final strokeWidth = size.width * 0.055;
    final radius = size.width / 2 - strokeWidth / 2;
    final paint = Paint()
      ..color = DazuColors.brandOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final start = -math.pi / 2 + 0.08 * 2 * math.pi;
    final sweep = (0.84 - 0.08) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: radius),
      start, sweep, false, paint,
    );
  }

  @override
  bool shouldRepaint(_OpenRingPainter old) => false;
}
