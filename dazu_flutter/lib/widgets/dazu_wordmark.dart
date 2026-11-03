import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/dazu_colors.dart';

/// dazu-Wortmarke als Text — Nunito ExtraBold mit kleinem Punkt über
/// dem „a" und einem orangen Mikropunkt am Ende. Nähert sich der
/// SwiftUI-SVG-Wortmarke an und reicht als v1-Branding bis wir ein
/// echtes SVG einbinden.
class DazuWordmark extends StatelessWidget {
  const DazuWordmark({
    super.key,
    this.color = DazuColors.brandNight,
    this.dotColor = DazuColors.brandOrange,
    this.height = 24,
    this.showDot = false,
  });

  final Color color;
  final Color dotColor;
  final double height;

  /// iOS zeigt im App-Header die reine Wortmarke „dazu" ohne Punkt;
  /// der orangene Mikropunkt kommt nur in Hero-Headlines und auf
  /// Buttons. Default false — explizit `showDot: true` setzen wenn der
  /// Punkt gewollt ist.
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final fontSize = height * 1.0;
    return RichText(
      text: TextSpan(
        style: GoogleFonts.bricolageGrotesque(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: -0.5,
          height: 1,
        ),
        children: [
          const TextSpan(text: 'dazu'),
          if (showDot)
            TextSpan(
              text: '.',
              style: TextStyle(color: dotColor),
            ),
        ],
      ),
    );
  }
}
