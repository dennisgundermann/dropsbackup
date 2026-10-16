import Foundation
import CoreLocation

/// Ein „Presence"-Eintrag = die zuletzt bekannte Position eines Users, die er
/// freiwillig mit allen Drops-Nutzern teilt (Opt-in Setting).
///
/// Wichtig: die tatsächliche Position im RTDB-Node ist bereits auf ein
/// ~500m-Grid gerundet (siehe `PresenceGrid.snap`). Rohkoordinaten werden
/// niemals nach RTDB geschrieben.
struct PresenceEntry: Identifiable, Equatable {
    let uid: String              // Firebase UID des Users
    let lat: Double              // bereits gefuzzt
    let lng: Double              // bereits gefuzzt
    let updatedAt: Date          // Server-Zeit vom RTDB
    let emoji: String            // z.B. "😊"
    let name: String?            // nur bei Freunden befüllt, sonst nil
    let profileImageURL: String? // nur bei Freunden

    var id: String { uid }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// Zeigt der Client den Eintrag noch an? Nein wenn älter als 4h.
    var isExpired: Bool {
        Date().timeIntervalSince(updatedAt) > 4 * 60 * 60
    }

    /// 20-Min-Delay: Client zeigt Positionen erst, wenn sie mindestens 20 min
    /// alt sind. So bleibt "was passiert JETZT" privat, aber "wo waren die
    /// Nutzer heute" bleibt sichtbar.
    var isDelayReached: Bool {
        Date().timeIntervalSince(updatedAt) >= 20 * 60
    }

    /// Präsentierbares Alter, z.B. "vor 22 min" / "vor 2 h".
    var ageLabel: String {
        let secs = Date().timeIntervalSince(updatedAt)
        if secs < 3600 { return "vor \(Int(secs / 60)) min" }
        return "vor \(Int(secs / 3600)) h"
    }
}

/// Rundet Koordinaten auf ein ~500m-Grid, damit die geteilte Position keine
/// Straßen-Genauigkeit hat. 3 Nachkommastellen ≈ 110m, 500m ≈ 0.0045 Grad
/// bei mittleren Breiten. Wir runden auf 0.005 sowohl Lat als auch Lng.
enum PresenceGrid {
    static let gridStep: Double = 0.005

    static func snap(_ coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let lat = (coord.latitude / gridStep).rounded() * gridStep
        let lng = (coord.longitude / gridStep).rounded() * gridStep
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

/// Client-seitiger Filter: nur Positionen innerhalb DE anzeigen.
/// Grobe BoundingBox — reicht für den Zweck (kein Katasteramt).
enum GermanyBoundingBox {
    static let minLat: Double = 47.2   // Bodensee
    static let maxLat: Double = 55.1   // Sylt
    static let minLng: Double = 5.8    // Aachen
    static let maxLng: Double = 15.1   // Görlitz

    static func contains(_ coord: CLLocationCoordinate2D) -> Bool {
        coord.latitude  >= minLat && coord.latitude  <= maxLat &&
        coord.longitude >= minLng && coord.longitude <= maxLng
    }
}
