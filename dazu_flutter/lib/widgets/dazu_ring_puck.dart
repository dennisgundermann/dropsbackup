import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/dazu_colors.dart';

/// Großer dazu-Logo-Ring (lila-offener Kreis mit Gap oben rechts) plus
/// draggable orangener Puck darunter. Beim Ziehen des Pucks in die Lücke
/// löst `onLockedIn` aus — Signatur-Geste aus der iOS-App zum Starten
/// einer Runde.
class DazuRingPuck extends StatefulWidget {
  const DazuRingPuck({
    super.key,
    required this.onLockedIn,
    this.onTryWhileDisabled,
    this.enabled = true,
    this.ringSize = 180,
    this.puckSize = 48,
  });

  final VoidCallback onLockedIn;

  /// Wird gefeuert, wenn der User den Puck anfasst, obwohl der Flow noch
  /// nicht ready ist (z. B. activity-TextField noch leer). Der Puck bleibt
  /// dann stehen und der Caller kann z. B. das TextField shaken.
  final VoidCallback? onTryWhileDisabled;

  /// False heißt: Puck ist visuell gedimmt und nimmt keine Pan-Gestures
  /// mehr an — stattdessen wird [onTryWhileDisabled] gefeuert.
  final bool enabled;

  final double ringSize;
  final double puckSize;

  @override
  State<DazuRingPuck> createState() => _DazuRingPuckState();
}

class _DazuRingPuckState extends State<DazuRingPuck>
    with SingleTickerProviderStateMixin {
  Offset _puckOffset = Offset.zero;
  bool _dragging = false;
  bool _snapped = false;
  late AnimationController _snapCtrl;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  /// Zielpunkt der Lücke im Ring (relativ zum Zentrum des Rings).
  /// Gap ist oben-rechts bei ca. 30°, also sin/cos von -60° von vertical.
  Offset get _gapTarget {
    final r = widget.ringSize / 2;
    final angle = -math.pi / 3; // -60° (oben rechts)
    return Offset(r * math.cos(angle), r * math.sin(angle));
  }

  double get _distanceToGap => (_puckOffset - _gapTarget).distance;

  void _onPanStart(DragStartDetails _) {
    if (_snapped) return;
    if (!widget.enabled) {
      widget.onTryWhileDisabled?.call();
      return;
    }
    setState(() => _dragging = true);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_snapped) return;
    if (!widget.enabled) return;
    setState(() => _puckOffset += d.delta);
  }

  void _onPanEnd(DragEndDetails _) {
    if (_snapped) return;
    if (!widget.enabled) return;
    if (_distanceToGap < 32) {
      // In der Lücke → snap-in + Callback.
      setState(() {
        _snapped = true;
        _puckOffset = _gapTarget;
      });
      Future.delayed(const Duration(milliseconds: 180), widget.onLockedIn);
    } else {
      // Daneben → zurück zur Startposition.
      final startFrom = _puckOffset;
      _snapCtrl.forward(from: 0).then((_) {
        setState(() {
          _puckOffset = Offset.zero;
          _dragging = false;
        });
      });
      _snapCtrl.addListener(() {
        setState(() {
          _puckOffset = Offset.lerp(startFrom, Offset.zero, _snapCtrl.value)!;
        });
      });
    }
  }

  void reset() {
    setState(() {
      _snapped = false;
      _dragging = false;
      _puckOffset = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.ringSize + widget.puckSize + 180;
    return SizedBox(
      height: size * 0.75,
      width: double.infinity,
      child: Center(
        child: SizedBox(
          width: widget.ringSize + 80,
          height: widget.ringSize + 140,
          child: Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              // Ring selbst.
              Positioned(
                top: 0,
                child: SizedBox(
                  width: widget.ringSize,
                  height: widget.ringSize,
                  child: CustomPaint(painter: _DazuRingPainter()),
                ),
              ),
              // Puck. Startposition unten mittig; Position relativ zur
              // Puck-Start-Mitte (die liegt bei (ringSize/2, ringSize+40)).
              Positioned(
                top: widget.ringSize + 40 + _puckOffset.dy,
                left: (widget.ringSize + 80) / 2 -
                    widget.puckSize / 2 +
                    _puckOffset.dx,
                child: GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  onTap: widget.enabled
                      ? null
                      : widget.onTryWhileDisabled,
                  child: Opacity(
                    opacity: widget.enabled ? 1.0 : 0.35,
                    child: Container(
                      width: widget.puckSize,
                      height: widget.puckSize,
                      decoration: BoxDecoration(
                        color: DazuColors.brandOrange,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                DazuColors.brandOrange.withValues(alpha: 0.4),
                            blurRadius: _dragging ? 18 : 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zeichnet den offenen dazu-Logo-Ring: dicker lila Bogen mit Lücke
/// oben rechts. Nicht pixel-perfekt zum SVG — reicht als Flutter-
/// Pendant der dazu-Logo-Form.
class _DazuRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = DazuColors.brandViolet
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.14
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(
      paint.strokeWidth / 2,
      paint.strokeWidth / 2,
      size.width - paint.strokeWidth,
      size.height - paint.strokeWidth,
    );
    // Arc von 150° (unten links) über 240° bis zur Lücke oben rechts.
    const startAngle = math.pi * 150 / 180;
    const sweepAngle = math.pi * 240 / 180;
    canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(covariant _DazuRingPainter oldDelegate) => false;
}
