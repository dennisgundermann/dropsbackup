import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Rendert ein custom dazu-SVG-Icon aus `assets/icons/{category}/`.
/// Nimmt den gleichen Dateinamen den die iOS-App im Asset-Catalog
/// benutzt (ohne `.svg`).
///
/// Standardverhalten: **Original-SVG-Farben bleiben erhalten** —
/// so bleiben orangene dazu-Punkte in den Tab-Icons sichtbar.
/// Wenn `color` gesetzt ist, wird monochrom getönt (für Set-Icons
/// in Einstellungen, die als simple Line-Icons gerendert werden).
class DazuIcon extends StatelessWidget {
  const DazuIcon(
    this.name, {
    super.key,
    this.category = 'set',
    this.size = 20,
    this.color,
  });

  /// Icon-Dateiname ohne `.svg` (z.B. `SetSchloss` oder `TabKarte`).
  final String name;

  /// `tab` oder `set` — mapped auf `assets/icons/{category}/`.
  final String category;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color;
    return SvgPicture.asset(
      'assets/icons/$category/$name.svg',
      width: size,
      height: size,
      colorFilter: c == null ? null : ColorFilter.mode(c, BlendMode.srcIn),
    );
  }
}
