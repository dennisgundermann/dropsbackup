import 'dart:math' as math;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../theme/dazu_colors.dart';

/// Portiert aus iOS `SharedComponents.swift` — alle Badge-Icons der App im
/// dazu-Stil (lila Grundform + oranger Akzent). Design absichtlich 1:1 wie
/// in der SwiftUI-Variante, damit beide Plattformen identisch aussehen.

/// Verifiziert: lila Kreis mit Cream-Haken + kleiner orangener Signal-Dot.
class DazuVerifiedIcon extends StatelessWidget {
  final double size;
  const DazuVerifiedIcon({super.key, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final main = size * 0.85;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: size - main,
            child: Container(
              width: main,
              height: main,
              decoration: const BoxDecoration(
                color: DazuColors.brandViolet,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(Icons.check,
                    color: DazuColors.brandCream,
                    size: main * 0.6,
                    weight: 900),
              ),
            ),
          ),
          Positioned(
            right: -size * 0.05,
            top: -size * 0.05,
            child: Container(
              width: size * 0.3,
              height: size * 0.3,
              decoration: BoxDecoration(
                color: DazuColors.brandOrange,
                shape: BoxShape.circle,
                border: Border.all(
                    color: DazuColors.brandCream, width: size * 0.045),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Verlässlich: zwei Punkte verbunden mit Linie (Zusage → Erfüllung).
class DazuReliableIcon extends StatelessWidget {
  final double size;
  const DazuReliableIcon({super.key, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final dot = size * 0.46;
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: dot,
              height: dot,
              decoration: const BoxDecoration(
                color: DazuColors.brandViolet,
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: size - 2 * dot,
              height: size * 0.13,
              color: DazuColors.brandViolet,
            ),
            Container(
              width: dot,
              height: dot,
              decoration: const BoxDecoration(
                color: DazuColors.brandOrange,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Host: lila Fahne an orangem Mast — „ich stecke den Pfosten in den Boden".
class DazuHostIcon extends StatelessWidget {
  final double size;
  const DazuHostIcon({super.key, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: size * 0.11,
              height: size,
              decoration: BoxDecoration(
                color: DazuColors.brandOrange,
                borderRadius: BorderRadius.circular(size * 0.05),
              ),
            ),
          ),
          Positioned(
            left: size * 0.11,
            top: size * 0.04,
            child: CustomPaint(
              size: Size(size * 0.68, size * 0.46),
              painter: _FlagPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = DazuColors.brandViolet;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FlagPainter old) => false;
}

/// Weiblich-Filter-Icon: ♀-Symbol mit orangenem Mittelpunkt im Kreis.
class DazuFemaleIcon extends StatelessWidget {
  final double size;
  final Color main;
  final Color accent;
  const DazuFemaleIcon({
    super.key,
    this.size = 14,
    this.main = DazuColors.brandViolet,
    this.accent = DazuColors.brandOrange,
  });

  @override
  Widget build(BuildContext context) {
    final strokeWidth = size * 0.11;
    return SizedBox(
      width: size,
      height: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size * 0.58,
                height: size * 0.58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: main, width: strokeWidth),
                ),
              ),
              Container(
                width: size * 0.22,
                height: size * 0.22,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          Container(
            width: strokeWidth,
            height: size * 0.18,
            color: main,
          ),
          Container(
            width: size * 0.3,
            height: strokeWidth,
            color: main,
          ),
        ],
      ),
    );
  }
}

/// „Heute passiert"-Icon: doppelter Ring (orange außen, lila innen) + Dot.
class DazuTodayIcon extends StatelessWidget {
  final double size;
  const DazuTodayIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: DazuColors.brandOrange.withOpacity(0.35),
                width: size * 0.08,
              ),
            ),
          ),
          Container(
            width: size * 0.68,
            height: size * 0.68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: DazuColors.brandViolet,
                width: size * 0.11,
              ),
            ),
          ),
          Container(
            width: size * 0.28,
            height: size * 0.28,
            decoration: const BoxDecoration(
              color: DazuColors.brandOrange,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini-Polaroid-Signet für das Original-Badge — weißer Rahmen mit
/// Foto-Fleck in Orange plus dazu-Kreis-und-Punkt, leicht gekippt.
class MiniPolaroid extends StatelessWidget {
  final double size;
  const MiniPolaroid({super.key, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Transform.rotate(
        angle: -0.07, // ~-4°
        child: Container(
          width: size * 0.88,
          height: size,
          decoration: BoxDecoration(
            color: DazuColors.brandCream,
            borderRadius: BorderRadius.circular(size * 0.08),
            border: Border.all(
              color: DazuColors.brandNight.withOpacity(0.5),
              width: 0.7,
            ),
          ),
          padding: EdgeInsets.only(
            top: size * 0.10,
            left: size * 0.10,
            right: size * 0.10,
          ),
          child: Column(
            children: [
              Container(
                height: size * 0.58,
                decoration: const BoxDecoration(color: DazuColors.brandOrange),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Container(
                        width: size * 0.32,
                        height: size * 0.32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: DazuColors.brandCream,
                            width: size * 0.065,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: size * 0.08,
                      top: size * 0.06,
                      child: Container(
                        width: size * 0.13,
                        height: size * 0.13,
                        decoration: const BoxDecoration(
                          color: DazuColors.brandViolet,
                          shape: BoxShape.circle,
                        ),
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
}

/// „Da fehlt noch was"-Icon: halb-offener Lila-Ring mit pulsierendem
/// orangenem Dot an der Lücke. Pulsiert über eine AnimationController.
class DazuMissingDotIcon extends StatefulWidget {
  final double size;
  const DazuMissingDotIcon({super.key, this.size = 24});

  @override
  State<DazuMissingDotIcon> createState() => _DazuMissingDotIconState();
}

class _DazuMissingDotIconState extends State<DazuMissingDotIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 2600),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final pulse = 0.5 + 0.5 * math.sin(_ctrl.value * 2 * math.pi);
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _MissingDotPainter(pulse: pulse),
          ),
        );
      },
    );
  }
}

class _MissingDotPainter extends CustomPainter {
  final double pulse;
  _MissingDotPainter({required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = size.width * 0.14;

    // Halb-offener Lila-Ring (Lücke oben rechts, ~57° Lücke)
    final ringPaint = Paint()
      ..color = DazuColors.brandViolet
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Von 0.08 bis 0.84 der 2π rotiert um -70°
    final startAngle = -70 * math.pi / 180 + 0.08 * 2 * math.pi;
    final sweepAngle = (0.84 - 0.08) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      startAngle,
      sweepAngle,
      false,
      ringPaint,
    );

    // Orangener Dot an der Lücke (oben rechts, pulsiert)
    final dotScale = 0.6 + 0.4 * pulse;
    final dotSize = size.width * 0.28 * dotScale;
    final dotOffset = Offset(
      center.dx + size.width * 0.42,
      center.dy - size.width * 0.42,
    );
    final dotPaint = Paint()
      ..color = DazuColors.brandOrange.withOpacity(0.4 + 0.6 * pulse);
    canvas.drawCircle(dotOffset, dotSize / 2, dotPaint);
  }

  @override
  bool shouldRepaint(_MissingDotPainter old) => old.pulse != pulse;
}

/// Kompakte Badge-Row für ein beliebiges User-Profil — liest
/// `/users/<uid>/badges` + `createdAt` einmalig und rendert die
/// achievten Icons. Spiegelt iOS `UserBadgesCompactRow`. In jeder
/// Mini-Profil-Darstellung (Teilnehmer-Row, Detail-Sheet, Map-Mini-
/// Profile) wiederverwendbar.
class UserBadgesCompactRow extends StatelessWidget {
  const UserBadgesCompactRow({
    super.key,
    required this.uid,
    this.reliabilityPoints,
    this.isHost = false,
    this.iconSize = 14,
  });

  final String uid;
  final int? reliabilityPoints;
  final bool isHost;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, Object?>>(
      future: _loadUser(uid),
      builder: (ctx, snap) {
        final badges = (snap.data?['badges'] as Map?) ?? const {};
        final createdAtMs = snap.data?['createdAt'];
        final createdAt = createdAtMs is num
            ? DateTime.fromMillisecondsSinceEpoch(createdAtMs.toInt())
            : null;
        final isOriginal = createdAt != null &&
            createdAt.isBefore(DateTime(2026, 12, 1));
        final isVerified = badges['verified'] == true;
        final isReliable =
            badges['trusted'] == true || (reliabilityPoints ?? 0) >= 50;
        final isHostBadge = badges['host'] == true || isHost;

        final icons = <Widget>[
          if (isVerified)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: DazuVerifiedIcon(size: iconSize),
            ),
          if (isReliable)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: DazuReliableIcon(size: iconSize),
            ),
          if (isHostBadge)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: DazuHostIcon(size: iconSize),
            ),
          if (isOriginal) MiniPolaroid(size: iconSize),
        ];
        if (icons.isEmpty) return const SizedBox.shrink();
        return Row(children: icons);
      },
    );
  }

  Future<Map<String, Object?>> _loadUser(String uid) async {
    try {
      final snap = await FirebaseDatabase.instance.ref('users/$uid').get();
      final v = snap.value;
      if (v is Map) {
        return v.map((k, val) => MapEntry(k.toString(), val));
      }
    } catch (_) {}
    return const {};
  }
}
