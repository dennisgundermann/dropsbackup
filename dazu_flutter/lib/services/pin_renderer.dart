import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../theme/dazu_colors.dart';

/// Rendert einen custom Google-Maps-Marker im dazu-Look: Lila Puck mit
/// cream-weißem Zentrum und dem Aktivitäts-Initial-Buchstaben. Ersetzt
/// den Default-Google-Marker-Tropfen, damit die Karte sofort dazu-vibe
/// hat ohne komplette Activity-Icon-Pipeline.
class PinRenderer {
  PinRenderer._();
  static final instance = PinRenderer._();

  final Map<String, BitmapDescriptor> _cache = {};
  final Map<String, BitmapDescriptor> _friendCache = {};

  /// Mini-Freundes-Pin — Monogram-Avatar in Marken-Farbe, umrahmt vom
  /// halb-offenen Orange-Ring (gleiches Pattern wie Umgebung-Feed).
  /// Cache-Key = uid, damit derselbe Freund nicht pro Position neu
  /// gerendert wird.
  Future<BitmapDescriptor> pinForFriend({
    required String uid,
    required String name,
  }) async {
    if (_friendCache.containsKey(uid)) return _friendCache[uid]!;

    const size = 108.0;
    final initial = (name.isEmpty ? '•' : name).characters.first.toUpperCase();
    final color = DazuColors.monogramPalette[
        name.hashCode.abs() % DazuColors.monogramPalette.length];

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Weißer Hintergrund-Puck für Lesbarkeit auf der Karte.
    final white = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 4, white);

    // Monogram-Kreis.
    final avatar = Paint()..color = color;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 16, avatar);

    // Halb-offener Oranger Ring außen (Lücke oben rechts).
    final ring = Paint()
      ..color = DazuColors.brandOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final start = -math.pi / 2 + 0.08 * 2 * math.pi;
    final sweep = (0.84 - 0.08) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(
          center: const Offset(size / 2, size / 2), radius: size / 2 - 7),
      start,
      sweep,
      false,
      ring,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 36,
          fontWeight: FontWeight.w800,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
        canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final descriptor = BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
    _friendCache[uid] = descriptor;
    return descriptor;
  }

  Future<BitmapDescriptor> pinForActivity(String activityName) async {
    final initial = (activityName.isEmpty ? '•' : activityName)
        .characters
        .first
        .toUpperCase();
    if (_cache.containsKey(initial)) return _cache[initial]!;

    final descriptor = await _paint(initial);
    _cache[initial] = descriptor;
    return descriptor;
  }

  Future<BitmapDescriptor> _paint(String initial) async {
    const size = 108.0; // 2x des on-screen 54pt — scharf auf hochauflösenden Displays.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Lila-Kreis mit Schatten (als separater Blur-Kreis darunter).
    final shadowPaint = Paint()
      ..color = DazuColors.brandViolet.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(
      const Offset(size / 2, size / 2 + 4),
      size / 2 - 10,
      shadowPaint,
    );

    final violet = Paint()..color = DazuColors.brandViolet;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 6, violet);

    // Cream-Inlay zum Kontrast.
    final cream = Paint()..color = DazuColors.brandCream;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 18, cream);

    // Oranger Pulse-Dot oben rechts (wie dazu-Logo-Punkt).
    final orange = Paint()..color = DazuColors.brandOrange;
    canvas.drawCircle(
      Offset(size / 2 + size / 2 - 20, size / 2 - size / 2 + 20),
      8,
      orange,
    );

    // Buchstabe mittig.
    final tp = TextPainter(
      text: TextSpan(
        text: initial,
        style: TextStyle(
          color: DazuColors.brandViolet,
          fontSize: 36,
          fontWeight: FontWeight.w800,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset((size - tp.width) / 2, (size - tp.height) / 2),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }
}
