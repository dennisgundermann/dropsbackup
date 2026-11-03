import 'package:geolocator/geolocator.dart';

/// Dünner Wrapper um `geolocator` — Permission-Handling + Caching der
/// letzten bekannten Position. Fallback-Koordinate ist München
/// (Marienplatz), identisch zum Fallback in iOS.
class LocationService {
  static const double fallbackLat = 48.1371;
  static const double fallbackLng = 11.5754;

  /// Fragt bei Bedarf Permission ab und liefert die aktuelle Position.
  /// Gibt `null` zurück wenn der User abgelehnt hat oder Services aus
  /// sind — der Caller nutzt dann den München-Fallback.
  Future<Position?> getCurrent() async {
    final servicesOn = await Geolocator.isLocationServiceEnabled();
    if (!servicesOn) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      // Timeout oder Service-Fehler → Fallback-Logik beim Caller.
      return null;
    }
  }
}
