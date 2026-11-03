import 'package:flutter/material.dart';

import '../theme/dazu_colors.dart';

/// Statisches Map-Snapshot via Google Static Maps API — ersetzt die
/// iOS-MKMapSnapshotter. Wird als Hintergrund für `OffeneRundeCard` und
/// `RundeDetailSheet` verwendet. Setzt den helleren dazu-Look mit
/// reduzierten POIs und entsättigten Farben via `style`-Params.
class MiniMapSnapshot extends StatelessWidget {
  const MiniMapSnapshot({
    super.key,
    required this.lat,
    required this.lng,
    this.zoom = 15,
    this.width = 400,
    this.height = 200,
    this.markers = const [],
  });

  final double lat;
  final double lng;
  final int zoom;
  final int width;
  final int height;

  /// Optional: `(lat, lng)`-Paare die als kleine lila Pins eingezeichnet
  /// werden. Für die Profil-Hotspots-Map.
  final List<(double, double)> markers;

  /// Google Static Maps API Key — kommt zur Build-Zeit via
  /// `--dart-define=STATIC_MAPS_KEY=AIza…`. Nicht hardcoded damit
  /// GitGuardian den String nicht als Secret im Source erkennt. Dieser
  /// Key ist in Google Cloud ausschließlich auf
  /// `static-maps-backend.googleapis.com` beschränkt (keine Firebase-
  /// APIs) — bei Missbrauch nur harmlose Map-Image-Abfragen möglich.
  static const _apiKey =
      String.fromEnvironment('STATIC_MAPS_KEY', defaultValue: '');

  String get _url {
    final buf = StringBuffer('https://maps.googleapis.com/maps/api/staticmap');
    if (markers.isEmpty) {
      buf.write('?center=$lat,$lng');
      buf.write('&zoom=$zoom');
    } else {
      // Auto-fit: Static-Map berechnet Zoom aus Marker-Spanne.
      buf.write('?');
    }
    buf.write('&size=${width}x$height');
    buf.write('&scale=2');
    buf.write('&style=feature:poi|visibility:off');
    buf.write('&style=feature:transit|visibility:off');
    buf.write('&style=element:labels.icon|visibility:off');
    buf.write('&style=saturation:-60|lightness:30');
    for (final m in markers) {
      // Kleiner lila dazu-Pin via Hex-Code (muss ohne #).
      buf.write('&markers=color:0x4F38F2|size:small|${m.$1},${m.$2}');
    }
    buf.write('&key=$_apiKey');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    // Falls kein Key via --dart-define übergeben → Platzhalter statt
    // kaputtes Image.network (sonst roter X auf grauem Grund).
    if (_apiKey.isEmpty) return _placeholder();
    return Image.network(
      _url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // Während-dem-Laden-Platzhalter und Fehlerfallback nutzen beide
      // die Lavendel-Grundfarbe, damit die Card nie leer aussieht.
      loadingBuilder: (ctx, child, prog) =>
          prog == null ? child : _placeholder(),
      errorBuilder: (_, obj, stack) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(color: DazuColors.brandLavender.withValues(alpha: 0.5));
  }
}
