import SwiftUI
import CoreLocation

// ─────────────────────────────────────────────────
// MARK: – Beta-Stadt Konfiguration
// ─────────────────────────────────────────────────

enum BetaConfig {
    /// Steuert die Drop-Erstellen- und Drop-Join-Beschränkung auf die 5
    /// Service-Städte (Berlin/Hamburg/München/Köln/Frankfurt).
    ///
    /// **Default `false`** für den App-Store-Submit-Build, damit der Apple
    /// Reviewer die App von überall testen kann. Nach Approval setzt du in
    /// der Firebase Console unter `/config/cityRestrictionEnabled` den Wert
    /// `true` — alle Apps ziehen das innerhalb von Sekunden via RTDB-Listener.
    ///
    /// Wird beim App-Start in `bootstrapRemoteFlags()` aus RTDB überschrieben.
    static var cityRestrictionEnabled: Bool = false

    /// Anzeige-Name der Service-Zone (für Gate-Text + Map-Overlay-Logik).
    static let cityName    = "Deutschland"
    /// Fallback-Mittelpunkt (nur für Default-Zoom der Karte).
    static let cityLat     = 51.1657
    static let cityLon     = 10.4515
    static let radiusKm    = 0.0           // deprecated — nicht mehr benutzt
    /// Wie lange (Sek.) auf einen Standort gewartet wird, bevor der Gate übersprungen wird
    static let timeoutSecs: Double = 6

    /// Auf `false` setzen für App Store Release — überspringt Ausweis-Scan in Beta-Builds
    static let skipIDVerification = false
}

// ─────────────────────────────────────────────────
// MARK: – Top-5-Städte Service-Zones
// ─────────────────────────────────────────────────

/// Launch-Städte mit je einer Bounding-Box die das Kern-Stadtgebiet abdeckt.
/// Reihenfolge = Einwohnerzahl absteigend.
/// Jede Zone wird sowohl für Access-Gate als auch für die "Max-Radius = alle
/// Drops in deiner Stadt"-Logik im Filter verwendet.
struct ServiceCity: Identifiable {
    let id: String      // interner Schlüssel, z.B. "berlin"
    let name: String    // Anzeige-Name
    let center: CLLocationCoordinate2D
    /// Echtes Stadtgrenz-Polygon (aus OpenStreetMap, per Ramer-Douglas-Peucker
    /// auf ca. 100-150 Punkte reduziert).
    let polygon: [CLLocationCoordinate2D]

    /// Ray-Casting-Point-in-Polygon-Check.
    func contains(_ coord: CLLocationCoordinate2D) -> Bool {
        let pts = polygon
        let n = pts.count
        guard n >= 3 else { return false }
        var inside = false
        var j = n - 1
        for i in 0..<n {
            let xi = pts[i].longitude, yi = pts[i].latitude
            let xj = pts[j].longitude, yj = pts[j].latitude
            let intersect = ((yi > coord.latitude) != (yj > coord.latitude)) &&
                (coord.longitude < (xj - xi) * (coord.latitude - yi) / (yj - yi) + xi)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }
}

enum ServiceCities {
    static let all: [ServiceCity] = [
        ServiceCity(
            id: "berlin", name: "Berlin",
            center: .init(latitude: 52.52, longitude: 13.405),
            polygon: [
                .init(latitude: 52.41963, longitude: 13.08835),
                .init(latitude: 52.41156, longitude: 13.09076),
                .init(latitude: 52.40942, longitude: 13.09739),
                .init(latitude: 52.41309, longitude: 13.09645),
                .init(latitude: 52.41376, longitude: 13.10086),
                .init(latitude: 52.40956, longitude: 13.10619),
                .init(latitude: 52.41294, longitude: 13.10962),
                .init(latitude: 52.41048, longitude: 13.11180),
                .init(latitude: 52.40869, longitude: 13.10638),
                .init(latitude: 52.39687, longitude: 13.12478),
                .init(latitude: 52.39786, longitude: 13.13810),
                .init(latitude: 52.39161, longitude: 13.12729),
                .init(latitude: 52.38725, longitude: 13.13108),
                .init(latitude: 52.39710, longitude: 13.14182),
                .init(latitude: 52.39564, longitude: 13.17176),
                .init(latitude: 52.39636, longitude: 13.15780),
                .init(latitude: 52.40277, longitude: 13.15924),
                .init(latitude: 52.41554, longitude: 13.19724),
                .init(latitude: 52.42117, longitude: 13.24595),
                .init(latitude: 52.40498, longitude: 13.24978),
                .init(latitude: 52.40479, longitude: 13.27421),
                .init(latitude: 52.41625, longitude: 13.29675),
                .init(latitude: 52.39911, longitude: 13.31206),
                .init(latitude: 52.41172, longitude: 13.34335),
                .init(latitude: 52.40769, longitude: 13.34306),
                .init(latitude: 52.39380, longitude: 13.37195),
                .init(latitude: 52.38843, longitude: 13.37035),
                .init(latitude: 52.38857, longitude: 13.38730),
                .init(latitude: 52.37786, longitude: 13.38843),
                .init(latitude: 52.37614, longitude: 13.42081),
                .init(latitude: 52.38617, longitude: 13.42745),
                .init(latitude: 52.40998, longitude: 13.41875),
                .init(latitude: 52.42108, longitude: 13.46355),
                .init(latitude: 52.42003, longitude: 13.46802),
                .init(latitude: 52.39595, longitude: 13.47976),
                .init(latitude: 52.40063, longitude: 13.53843),
                .init(latitude: 52.38899, longitude: 13.53549),
                .init(latitude: 52.38814, longitude: 13.56416),
                .init(latitude: 52.39381, longitude: 13.59269),
                .init(latitude: 52.37912, longitude: 13.60640),
                .init(latitude: 52.37362, longitude: 13.60582),
                .init(latitude: 52.38136, longitude: 13.62851),
                .init(latitude: 52.37625, longitude: 13.63322),
                .init(latitude: 52.37751, longitude: 13.64268),
                .init(latitude: 52.37081, longitude: 13.64210),
                .init(latitude: 52.36703, longitude: 13.64719),
                .init(latitude: 52.36098, longitude: 13.63908),
                .init(latitude: 52.34682, longitude: 13.63632),
                .init(latitude: 52.33824, longitude: 13.64773),
                .init(latitude: 52.36649, longitude: 13.67119),
                .init(latitude: 52.36721, longitude: 13.69220),
                .init(latitude: 52.37559, longitude: 13.69996),
                .init(latitude: 52.38150, longitude: 13.69884),
                .init(latitude: 52.38530, longitude: 13.68683),
                .init(latitude: 52.39969, longitude: 13.71587),
                .init(latitude: 52.40001, longitude: 13.73114),
                .init(latitude: 52.40734, longitude: 13.73903),
                .init(latitude: 52.41635, longitude: 13.72981),
                .init(latitude: 52.42676, longitude: 13.74128),
                .init(latitude: 52.43247, longitude: 13.74010),
                .init(latitude: 52.43714, longitude: 13.72281),
                .init(latitude: 52.43294, longitude: 13.74289),
                .init(latitude: 52.44148, longitude: 13.75051),
                .init(latitude: 52.44161, longitude: 13.75630),
                .init(latitude: 52.43668, longitude: 13.75445),
                .init(latitude: 52.43771, longitude: 13.76116),
                .init(latitude: 52.43842, longitude: 13.75532),
                .init(latitude: 52.44618, longitude: 13.75645),
                .init(latitude: 52.45078, longitude: 13.72908),
                .init(latitude: 52.46292, longitude: 13.71596),
                .init(latitude: 52.46822, longitude: 13.70126),
                .init(latitude: 52.45476, longitude: 13.70461),
                .init(latitude: 52.45526, longitude: 13.69835),
                .init(latitude: 52.46419, longitude: 13.69543),
                .init(latitude: 52.47873, longitude: 13.64831),
                .init(latitude: 52.47370, longitude: 13.62534),
                .init(latitude: 52.46645, longitude: 13.62276),
                .init(latitude: 52.47046, longitude: 13.62117),
                .init(latitude: 52.47065, longitude: 13.61137),
                .init(latitude: 52.47483, longitude: 13.61649),
                .init(latitude: 52.48076, longitude: 13.61489),
                .init(latitude: 52.49304, longitude: 13.62971),
                .init(latitude: 52.49420, longitude: 13.62401),
                .init(latitude: 52.51088, longitude: 13.63248),
                .init(latitude: 52.52595, longitude: 13.65850),
                .init(latitude: 52.52984, longitude: 13.65691),
                .init(latitude: 52.53018, longitude: 13.62569),
                .init(latitude: 52.53810, longitude: 13.62483),
                .init(latitude: 52.53765, longitude: 13.63395),
                .init(latitude: 52.54226, longitude: 13.63738),
                .init(latitude: 52.54978, longitude: 13.58638),
                .init(latitude: 52.57111, longitude: 13.58154),
                .init(latitude: 52.57310, longitude: 13.56857),
                .init(latitude: 52.58785, longitude: 13.54713),
                .init(latitude: 52.59214, longitude: 13.50812),
                .init(latitude: 52.60667, longitude: 13.49712),
                .init(latitude: 52.62575, longitude: 13.50586),
                .init(latitude: 52.62957, longitude: 13.51782),
                .init(latitude: 52.64504, longitude: 13.52302),
                .init(latitude: 52.65480, longitude: 13.49076),
                .init(latitude: 52.65943, longitude: 13.48536),
                .init(latitude: 52.67079, longitude: 13.48843),
                .init(latitude: 52.66807, longitude: 13.47459),
                .init(latitude: 52.67551, longitude: 13.47949),
                .init(latitude: 52.66267, longitude: 13.45078),
                .init(latitude: 52.65653, longitude: 13.47351),
                .init(latitude: 52.65186, longitude: 13.46996),
                .init(latitude: 52.64927, longitude: 13.44082),
                .init(latitude: 52.64428, longitude: 13.43401),
                .init(latitude: 52.63795, longitude: 13.43426),
                .init(latitude: 52.63547, longitude: 13.42435),
                .init(latitude: 52.64756, longitude: 13.39456),
                .init(latitude: 52.62838, longitude: 13.37638),
                .init(latitude: 52.62298, longitude: 13.35765),
                .init(latitude: 52.62719, longitude: 13.30261),
                .init(latitude: 52.63001, longitude: 13.31028),
                .init(latitude: 52.63735, longitude: 13.30578),
                .init(latitude: 52.64273, longitude: 13.30941),
                .init(latitude: 52.65351, longitude: 13.30043),
                .init(latitude: 52.65740, longitude: 13.31010),
                .init(latitude: 52.66074, longitude: 13.28277),
                .init(latitude: 52.64112, longitude: 13.28383),
                .init(latitude: 52.64069, longitude: 13.26215),
                .init(latitude: 52.62686, longitude: 13.26423),
                .init(latitude: 52.62832, longitude: 13.22054),
                .init(latitude: 52.60655, longitude: 13.20162),
                .init(latitude: 52.59237, longitude: 13.21886),
                .init(latitude: 52.58748, longitude: 13.21740),
                .init(latitude: 52.58685, longitude: 13.20537),
                .init(latitude: 52.59880, longitude: 13.16453),
                .init(latitude: 52.58730, longitude: 13.12896),
                .init(latitude: 52.57961, longitude: 13.13247),
                .init(latitude: 52.58336, longitude: 13.14961),
                .init(latitude: 52.57326, longitude: 13.15354),
                .init(latitude: 52.55272, longitude: 13.14557),
                .init(latitude: 52.55597, longitude: 13.13047),
                .init(latitude: 52.51706, longitude: 13.11738),
                .init(latitude: 52.51970, longitude: 13.14318),
                .init(latitude: 52.50923, longitude: 13.16882),
                .init(latitude: 52.47982, longitude: 13.12833),
                .init(latitude: 52.47732, longitude: 13.11769),
                .init(latitude: 52.46566, longitude: 13.11056),
                .init(latitude: 52.45063, longitude: 13.10929),
                .init(latitude: 52.43871, longitude: 13.12315),
                .init(latitude: 52.42398, longitude: 13.10457),
                .init(latitude: 52.41963, longitude: 13.08835),
            ]
        ),
        ServiceCity(
            id: "hamburg", name: "Hamburg",
            center: .init(latitude: 53.5511, longitude: 9.9937),
            polygon: [
                .init(latitude: 53.55764, longitude: 9.73012),
                .init(latitude: 53.55433, longitude: 9.77439),
                .init(latitude: 53.54352, longitude: 9.77232),
                .init(latitude: 53.54110, longitude: 9.76556),
                .init(latitude: 53.52953, longitude: 9.76987),
                .init(latitude: 53.51864, longitude: 9.78129),
                .init(latitude: 53.52185, longitude: 9.77107),
                .init(latitude: 53.50826, longitude: 9.76358),
                .init(latitude: 53.50001, longitude: 9.78462),
                .init(latitude: 53.49232, longitude: 9.78199),
                .init(latitude: 53.49384, longitude: 9.80276),
                .init(latitude: 53.46943, longitude: 9.79981),
                .init(latitude: 53.45092, longitude: 9.83654),
                .init(latitude: 53.42962, longitude: 9.86183),
                .init(latitude: 53.43999, longitude: 9.86222),
                .init(latitude: 53.45579, longitude: 9.89419),
                .init(latitude: 53.45405, longitude: 9.90020),
                .init(latitude: 53.45796, longitude: 9.89874),
                .init(latitude: 53.44656, longitude: 9.91718),
                .init(latitude: 53.43636, longitude: 9.92293),
                .init(latitude: 53.43002, longitude: 9.91407),
                .init(latitude: 53.42481, longitude: 9.91626),
                .init(latitude: 53.41595, longitude: 9.90670),
                .init(latitude: 53.41404, longitude: 9.91094),
                .init(latitude: 53.42148, longitude: 9.92995),
                .init(latitude: 53.42102, longitude: 9.94213),
                .init(latitude: 53.42690, longitude: 9.94695),
                .init(latitude: 53.42945, longitude: 9.94384),
                .init(latitude: 53.42189, longitude: 9.97593),
                .init(latitude: 53.41377, longitude: 9.97649),
                .init(latitude: 53.41462, longitude: 9.98335),
                .init(latitude: 53.42588, longitude: 9.99590),
                .init(latitude: 53.42878, longitude: 10.01743),
                .init(latitude: 53.43530, longitude: 10.02921),
                .init(latitude: 53.44202, longitude: 10.01465),
                .init(latitude: 53.44755, longitude: 10.02224),
                .init(latitude: 53.44640, longitude: 10.04539),
                .init(latitude: 53.44985, longitude: 10.04918),
                .init(latitude: 53.45160, longitude: 10.04124),
                .init(latitude: 53.45655, longitude: 10.04197),
                .init(latitude: 53.46391, longitude: 10.05162),
                .init(latitude: 53.45079, longitude: 10.08496),
                .init(latitude: 53.42637, longitude: 10.10943),
                .init(latitude: 53.42194, longitude: 10.13700),
                .init(latitude: 53.39933, longitude: 10.16555),
                .init(latitude: 53.39527, longitude: 10.23351),
                .init(latitude: 53.39899, longitude: 10.24306),
                .init(latitude: 53.41847, longitude: 10.26017),
                .init(latitude: 53.43530, longitude: 10.31784),
                .init(latitude: 53.43973, longitude: 10.31448),
                .init(latitude: 53.44983, longitude: 10.32528),
                .init(latitude: 53.45224, longitude: 10.31227),
                .init(latitude: 53.44308, longitude: 10.30968),
                .init(latitude: 53.44273, longitude: 10.30073),
                .init(latitude: 53.44816, longitude: 10.29423),
                .init(latitude: 53.45159, longitude: 10.29787),
                .init(latitude: 53.46407, longitude: 10.26935),
                .init(latitude: 53.46664, longitude: 10.27189),
                .init(latitude: 53.46900, longitude: 10.26492),
                .init(latitude: 53.47510, longitude: 10.26441),
                .init(latitude: 53.48255, longitude: 10.23854),
                .init(latitude: 53.49026, longitude: 10.23454),
                .init(latitude: 53.49634, longitude: 10.23685),
                .init(latitude: 53.49923, longitude: 10.21828),
                .init(latitude: 53.50562, longitude: 10.22389),
                .init(latitude: 53.51993, longitude: 10.21041),
                .init(latitude: 53.51151, longitude: 10.18784),
                .init(latitude: 53.52246, longitude: 10.16240),
                .init(latitude: 53.53739, longitude: 10.16878),
                .init(latitude: 53.53548, longitude: 10.15187),
                .init(latitude: 53.54598, longitude: 10.14844),
                .init(latitude: 53.56097, longitude: 10.16049),
                .init(latitude: 53.56425, longitude: 10.14775),
                .init(latitude: 53.57791, longitude: 10.15247),
                .init(latitude: 53.58579, longitude: 10.16187),
                .init(latitude: 53.58232, longitude: 10.16532),
                .init(latitude: 53.58400, longitude: 10.20129),
                .init(latitude: 53.59559, longitude: 10.19178),
                .init(latitude: 53.59932, longitude: 10.19703),
                .init(latitude: 53.61307, longitude: 10.18885),
                .init(latitude: 53.62614, longitude: 10.21749),
                .init(latitude: 53.63126, longitude: 10.21617),
                .init(latitude: 53.63365, longitude: 10.22199),
                .init(latitude: 53.63837, longitude: 10.18964),
                .init(latitude: 53.64673, longitude: 10.19885),
                .init(latitude: 53.65475, longitude: 10.19589),
                .init(latitude: 53.65653, longitude: 10.18719),
                .init(latitude: 53.66343, longitude: 10.18376),
                .init(latitude: 53.66431, longitude: 10.17398),
                .init(latitude: 53.66870, longitude: 10.17280),
                .init(latitude: 53.66993, longitude: 10.15579),
                .init(latitude: 53.67132, longitude: 10.16120),
                .init(latitude: 53.68036, longitude: 10.13996),
                .init(latitude: 53.68254, longitude: 10.15191),
                .init(latitude: 53.69026, longitude: 10.15894),
                .init(latitude: 53.70451, longitude: 10.15694),
                .init(latitude: 53.71240, longitude: 10.17230),
                .init(latitude: 53.70890, longitude: 10.18156),
                .init(latitude: 53.72270, longitude: 10.19174),
                .init(latitude: 53.73100, longitude: 10.19369),
                .init(latitude: 53.73932, longitude: 10.16775),
                .init(latitude: 53.72004, longitude: 10.12713),
                .init(latitude: 53.71316, longitude: 10.12113),
                .init(latitude: 53.72044, longitude: 10.08198),
                .init(latitude: 53.71094, longitude: 10.06924),
                .init(latitude: 53.70972, longitude: 10.07294),
                .init(latitude: 53.70615, longitude: 10.06938),
                .init(latitude: 53.70390, longitude: 10.07899),
                .init(latitude: 53.69942, longitude: 10.07747),
                .init(latitude: 53.68831, longitude: 10.06038),
                .init(latitude: 53.67953, longitude: 10.06927),
                .init(latitude: 53.68152, longitude: 9.99962),
                .init(latitude: 53.67639, longitude: 9.99244),
                .init(latitude: 53.64824, longitude: 9.98581),
                .init(latitude: 53.65552, longitude: 9.92103),
                .init(latitude: 53.65248, longitude: 9.90688),
                .init(latitude: 53.64174, longitude: 9.90574),
                .init(latitude: 53.62707, longitude: 9.88769),
                .init(latitude: 53.62287, longitude: 9.88920),
                .init(latitude: 53.61361, longitude: 9.86930),
                .init(latitude: 53.59937, longitude: 9.85787),
                .init(latitude: 53.59504, longitude: 9.83965),
                .init(latitude: 53.58768, longitude: 9.83665),
                .init(latitude: 53.58423, longitude: 9.82484),
                .init(latitude: 53.60127, longitude: 9.79132),
                .init(latitude: 53.60397, longitude: 9.78971),
                .init(latitude: 53.60793, longitude: 9.79902),
                .init(latitude: 53.61032, longitude: 9.79626),
                .init(latitude: 53.61603, longitude: 9.77055),
                .init(latitude: 53.63140, longitude: 9.77127),
                .init(latitude: 53.62428, longitude: 9.76004),
                .init(latitude: 53.61295, longitude: 9.75359),
                .init(latitude: 53.61101, longitude: 9.75922),
                .init(latitude: 53.60267, longitude: 9.75543),
                .init(latitude: 53.60386, longitude: 9.74833),
                .init(latitude: 53.59815, longitude: 9.74383),
                .init(latitude: 53.58898, longitude: 9.74560),
                .init(latitude: 53.58256, longitude: 9.73455),
                .init(latitude: 53.57798, longitude: 9.74252),
                .init(latitude: 53.57628, longitude: 9.73602),
                .init(latitude: 53.55764, longitude: 9.73012),
            ]
        ),
        ServiceCity(
            id: "muenchen", name: "München",
            center: .init(latitude: 48.1371, longitude: 11.5754),
            polygon: [
                .init(latitude: 48.15807, longitude: 11.36078),
                .init(latitude: 48.15842, longitude: 11.37120),
                .init(latitude: 48.15683, longitude: 11.36982),
                .init(latitude: 48.15598, longitude: 11.37491),
                .init(latitude: 48.15355, longitude: 11.37391),
                .init(latitude: 48.15308, longitude: 11.38289),
                .init(latitude: 48.14967, longitude: 11.38318),
                .init(latitude: 48.14793, longitude: 11.38914),
                .init(latitude: 48.13666, longitude: 11.39218),
                .init(latitude: 48.13458, longitude: 11.38819),
                .init(latitude: 48.12974, longitude: 11.38872),
                .init(latitude: 48.12551, longitude: 11.39442),
                .init(latitude: 48.12749, longitude: 11.41288),
                .init(latitude: 48.13756, longitude: 11.42998),
                .init(latitude: 48.13359, longitude: 11.44747),
                .init(latitude: 48.13115, longitude: 11.44812),
                .init(latitude: 48.13314, longitude: 11.45337),
                .init(latitude: 48.12993, longitude: 11.46369),
                .init(latitude: 48.11851, longitude: 11.46567),
                .init(latitude: 48.10525, longitude: 11.46297),
                .init(latitude: 48.10461, longitude: 11.47485),
                .init(latitude: 48.09938, longitude: 11.47085),
                .init(latitude: 48.09538, longitude: 11.47411),
                .init(latitude: 48.09011, longitude: 11.47207),
                .init(latitude: 48.08877, longitude: 11.47634),
                .init(latitude: 48.08319, longitude: 11.47092),
                .init(latitude: 48.07635, longitude: 11.48703),
                .init(latitude: 48.07422, longitude: 11.48580),
                .init(latitude: 48.07626, longitude: 11.48724),
                .init(latitude: 48.06929, longitude: 11.50356),
                .init(latitude: 48.06239, longitude: 11.50421),
                .init(latitude: 48.06162, longitude: 11.50876),
                .init(latitude: 48.06898, longitude: 11.52825),
                .init(latitude: 48.07768, longitude: 11.53348),
                .init(latitude: 48.07786, longitude: 11.54237),
                .init(latitude: 48.06813, longitude: 11.54542),
                .init(latitude: 48.08502, longitude: 11.55397),
                .init(latitude: 48.08360, longitude: 11.56249),
                .init(latitude: 48.09388, longitude: 11.58692),
                .init(latitude: 48.08507, longitude: 11.59262),
                .init(latitude: 48.08811, longitude: 11.62375),
                .init(latitude: 48.07821, longitude: 11.66557),
                .init(latitude: 48.07749, longitude: 11.68565),
                .init(latitude: 48.08380, longitude: 11.68096),
                .init(latitude: 48.09180, longitude: 11.68277),
                .init(latitude: 48.10257, longitude: 11.70934),
                .init(latitude: 48.11085, longitude: 11.71459),
                .init(latitude: 48.11424, longitude: 11.70892),
                .init(latitude: 48.11556, longitude: 11.71067),
                .init(latitude: 48.11935, longitude: 11.69404),
                .init(latitude: 48.12118, longitude: 11.69757),
                .init(latitude: 48.12310, longitude: 11.69419),
                .init(latitude: 48.12535, longitude: 11.69774),
                .init(latitude: 48.12144, longitude: 11.70427),
                .init(latitude: 48.12298, longitude: 11.71199),
                .init(latitude: 48.12817, longitude: 11.71617),
                .init(latitude: 48.13007, longitude: 11.71171),
                .init(latitude: 48.13137, longitude: 11.71437),
                .init(latitude: 48.13338, longitude: 11.71227),
                .init(latitude: 48.13712, longitude: 11.72291),
                .init(latitude: 48.14185, longitude: 11.71013),
                .init(latitude: 48.14552, longitude: 11.71346),
                .init(latitude: 48.14818, longitude: 11.71012),
                .init(latitude: 48.14429, longitude: 11.67816),
                .init(latitude: 48.15325, longitude: 11.67980),
                .init(latitude: 48.15647, longitude: 11.67393),
                .init(latitude: 48.16749, longitude: 11.68566),
                .init(latitude: 48.17176, longitude: 11.68579),
                .init(latitude: 48.17057, longitude: 11.69326),
                .init(latitude: 48.17429, longitude: 11.69610),
                .init(latitude: 48.17816, longitude: 11.69070),
                .init(latitude: 48.17998, longitude: 11.69555),
                .init(latitude: 48.18253, longitude: 11.69198),
                .init(latitude: 48.18037, longitude: 11.68683),
                .init(latitude: 48.18289, longitude: 11.66220),
                .init(latitude: 48.17970, longitude: 11.66105),
                .init(latitude: 48.17618, longitude: 11.66553),
                .init(latitude: 48.17369, longitude: 11.64585),
                .init(latitude: 48.17730, longitude: 11.62771),
                .init(latitude: 48.20377, longitude: 11.63912),
                .init(latitude: 48.21338, longitude: 11.65049),
                .init(latitude: 48.21701, longitude: 11.65051),
                .init(latitude: 48.22175, longitude: 11.63915),
                .init(latitude: 48.22596, longitude: 11.63899),
                .init(latitude: 48.22924, longitude: 11.62461),
                .init(latitude: 48.22555, longitude: 11.60939),
                .init(latitude: 48.22816, longitude: 11.60708),
                .init(latitude: 48.21914, longitude: 11.61158),
                .init(latitude: 48.21686, longitude: 11.60183),
                .init(latitude: 48.21335, longitude: 11.60183),
                .init(latitude: 48.21348, longitude: 11.58747),
                .init(latitude: 48.22400, longitude: 11.58716),
                .init(latitude: 48.22856, longitude: 11.58230),
                .init(latitude: 48.22711, longitude: 11.54683),
                .init(latitude: 48.23134, longitude: 11.53112),
                .init(latitude: 48.24132, longitude: 11.52539),
                .init(latitude: 48.24812, longitude: 11.50120),
                .init(latitude: 48.24542, longitude: 11.49069),
                .init(latitude: 48.23973, longitude: 11.49192),
                .init(latitude: 48.23208, longitude: 11.48775),
                .init(latitude: 48.22310, longitude: 11.49108),
                // ── Karlsfeld + Dachau-Lobe ──
                // Eine zusammenhängende Lobe nach NW: bindet Karlsfeld und Dachau
                // ohne Lücke an München an (kein Loch zwischen den Orten).
                .init(latitude: 48.23200, longitude: 11.49500),  // Karlsfeld-NO
                .init(latitude: 48.25500, longitude: 11.48800),  // Übergang Karlsfeld → Dachau
                .init(latitude: 48.27500, longitude: 11.48000),  // Dachau-NE
                .init(latitude: 48.28500, longitude: 11.46000),  // Dachau-N-O
                .init(latitude: 48.28800, longitude: 11.43500),  // Dachau-N
                .init(latitude: 48.28800, longitude: 11.40500),  // Dachau-NW
                .init(latitude: 48.26500, longitude: 11.39200),  // Dachau-W
                .init(latitude: 48.24500, longitude: 11.39500),  // Karlsfeld/Dachau-W
                .init(latitude: 48.22000, longitude: 11.45800),  // Bridge zurück Richtung 482
                .init(latitude: 48.21850, longitude: 11.47026),
                .init(latitude: 48.20880, longitude: 11.45760),
                .init(latitude: 48.20046, longitude: 11.39083),
                .init(latitude: 48.19084, longitude: 11.38854),
                .init(latitude: 48.18956, longitude: 11.39228),
                .init(latitude: 48.18446, longitude: 11.39326),
                .init(latitude: 48.17757, longitude: 11.38530),
                .init(latitude: 48.17828, longitude: 11.37110),
                .init(latitude: 48.15807, longitude: 11.36078),
            ]
        ),
        ServiceCity(
            id: "koeln", name: "Köln",
            center: .init(latitude: 50.9375, longitude: 6.9603),
            polygon: [
                .init(latitude: 51.06162, longitude: 6.77253),
                .init(latitude: 51.04992, longitude: 6.78824),
                .init(latitude: 51.03673, longitude: 6.79820),
                .init(latitude: 51.03949, longitude: 6.80538),
                .init(latitude: 51.03523, longitude: 6.80844),
                .init(latitude: 51.03536, longitude: 6.81400),
                .init(latitude: 51.03853, longitude: 6.82054),
                .init(latitude: 51.02885, longitude: 6.83996),
                .init(latitude: 51.02714, longitude: 6.83560),
                .init(latitude: 51.02471, longitude: 6.84153),
                .init(latitude: 51.01787, longitude: 6.83387),
                .init(latitude: 51.01214, longitude: 6.84151),
                .init(latitude: 51.01115, longitude: 6.83732),
                .init(latitude: 51.00407, longitude: 6.84478),
                .init(latitude: 50.99976, longitude: 6.83533),
                .init(latitude: 50.99095, longitude: 6.83948),
                .init(latitude: 50.98882, longitude: 6.84462),
                .init(latitude: 50.97476, longitude: 6.82786),
                .init(latitude: 50.97195, longitude: 6.83072),
                .init(latitude: 50.96524, longitude: 6.81872),
                .init(latitude: 50.95705, longitude: 6.82425),
                .init(latitude: 50.94853, longitude: 6.80950),
                .init(latitude: 50.94060, longitude: 6.81442),
                .init(latitude: 50.93868, longitude: 6.80515),
                .init(latitude: 50.93868, longitude: 6.81782),
                .init(latitude: 50.92938, longitude: 6.82088),
                .init(latitude: 50.92602, longitude: 6.84190),
                .init(latitude: 50.91723, longitude: 6.84107),
                .init(latitude: 50.90975, longitude: 6.84696),
                .init(latitude: 50.90382, longitude: 6.86045),
                .init(latitude: 50.91158, longitude: 6.88000),
                .init(latitude: 50.89324, longitude: 6.91998),
                .init(latitude: 50.88261, longitude: 6.91286),
                .init(latitude: 50.86543, longitude: 6.92325),
                .init(latitude: 50.85857, longitude: 6.91636),
                .init(latitude: 50.85288, longitude: 6.92058),
                .init(latitude: 50.85006, longitude: 6.91854),
                .init(latitude: 50.84909, longitude: 6.92343),
                .init(latitude: 50.84365, longitude: 6.92493),
                .init(latitude: 50.84396, longitude: 6.92851),
                .init(latitude: 50.83749, longitude: 6.93043),
                .init(latitude: 50.83834, longitude: 6.93991),
                .init(latitude: 50.84026, longitude: 6.94155),
                .init(latitude: 50.84429, longitude: 6.93816),
                .init(latitude: 50.84543, longitude: 6.94492),
                .init(latitude: 50.83473, longitude: 6.95466),
                .init(latitude: 50.84413, longitude: 6.97368),
                .init(latitude: 50.84096, longitude: 6.98060),
                .init(latitude: 50.84394, longitude: 6.98395),
                .init(latitude: 50.83717, longitude: 6.99252),
                .init(latitude: 50.83707, longitude: 7.00601),
                .init(latitude: 50.83994, longitude: 7.01184),
                .init(latitude: 50.83776, longitude: 7.01555),
                .init(latitude: 50.83924, longitude: 7.02335),
                .init(latitude: 50.84695, longitude: 7.02724),
                .init(latitude: 50.85009, longitude: 7.05112),
                .init(latitude: 50.84928, longitude: 7.05790),
                .init(latitude: 50.84409, longitude: 7.06138),
                .init(latitude: 50.83044, longitude: 7.06252),
                .init(latitude: 50.83077, longitude: 7.07932),
                .init(latitude: 50.84211, longitude: 7.11136),
                .init(latitude: 50.84566, longitude: 7.11349),
                .init(latitude: 50.86939, longitude: 7.16188),
                .init(latitude: 50.87385, longitude: 7.15881),
                .init(latitude: 50.87368, longitude: 7.15210),
                .init(latitude: 50.88126, longitude: 7.13759),
                .init(latitude: 50.88740, longitude: 7.14094),
                .init(latitude: 50.89690, longitude: 7.13980),
                .init(latitude: 50.90348, longitude: 7.13353),
                .init(latitude: 50.90590, longitude: 7.13673),
                .init(latitude: 50.91990, longitude: 7.13979),
                .init(latitude: 50.92761, longitude: 7.13667),
                .init(latitude: 50.94639, longitude: 7.14467),
                .init(latitude: 50.94359, longitude: 7.13173),
                .init(latitude: 50.94472, longitude: 7.11706),
                .init(latitude: 50.94084, longitude: 7.11478),
                .init(latitude: 50.94912, longitude: 7.09790),
                .init(latitude: 50.95459, longitude: 7.09595),
                .init(latitude: 50.95733, longitude: 7.08660),
                .init(latitude: 50.96796, longitude: 7.10113),
                .init(latitude: 50.97620, longitude: 7.09582),
                .init(latitude: 50.98098, longitude: 7.10006),
                .init(latitude: 50.98253, longitude: 7.09379),
                .init(latitude: 50.98553, longitude: 7.09624),
                .init(latitude: 50.98565, longitude: 7.08793),
                .init(latitude: 50.98793, longitude: 7.08802),
                .init(latitude: 50.98948, longitude: 7.06904),
                .init(latitude: 50.99359, longitude: 7.06677),
                .init(latitude: 51.00199, longitude: 7.07606),
                .init(latitude: 51.01333, longitude: 7.06179),
                .init(latitude: 51.01835, longitude: 7.06838),
                .init(latitude: 51.02112, longitude: 7.04141),
                .init(latitude: 51.01600, longitude: 7.02168),
                .init(latitude: 51.02261, longitude: 7.00926),
                .init(latitude: 51.01642, longitude: 6.99536),
                .init(latitude: 51.01180, longitude: 6.99636),
                .init(latitude: 51.01112, longitude: 6.97552),
                .init(latitude: 51.01417, longitude: 6.97187),
                .init(latitude: 51.02415, longitude: 6.97268),
                .init(latitude: 51.03304, longitude: 6.96239),
                .init(latitude: 51.06596, longitude: 6.89506),
                .init(latitude: 51.07392, longitude: 6.85993),
                .init(latitude: 51.07846, longitude: 6.85413),
                .init(latitude: 51.08418, longitude: 6.85326),
                .init(latitude: 51.08497, longitude: 6.84857),
                .init(latitude: 51.08007, longitude: 6.83661),
                .init(latitude: 51.07774, longitude: 6.83790),
                .init(latitude: 51.07440, longitude: 6.82453),
                .init(latitude: 51.05979, longitude: 6.83373),
                .init(latitude: 51.05383, longitude: 6.81646),
                .init(latitude: 51.04589, longitude: 6.81380),
                .init(latitude: 51.04694, longitude: 6.80627),
                .init(latitude: 51.05958, longitude: 6.80072),
                .init(latitude: 51.06741, longitude: 6.79129),
                .init(latitude: 51.06874, longitude: 6.78682),
                .init(latitude: 51.06162, longitude: 6.77253),
            ]
        ),
        ServiceCity(
            id: "frankfurt", name: "Frankfurt",
            center: .init(latitude: 50.1109, longitude: 8.6821),
            polygon: [
                .init(latitude: 50.09982, longitude: 8.47276),
                .init(latitude: 50.08830, longitude: 8.48792),
                .init(latitude: 50.08492, longitude: 8.48753),
                .init(latitude: 50.08592, longitude: 8.49508),
                .init(latitude: 50.08134, longitude: 8.50189),
                .init(latitude: 50.07542, longitude: 8.50137),
                .init(latitude: 50.06177, longitude: 8.52039),
                .init(latitude: 50.06625, longitude: 8.52700),
                .init(latitude: 50.07769, longitude: 8.52212),
                .init(latitude: 50.08386, longitude: 8.52568),
                .init(latitude: 50.07877, longitude: 8.53241),
                .init(latitude: 50.07529, longitude: 8.54284),
                .init(latitude: 50.07120, longitude: 8.54360),
                .init(latitude: 50.06685, longitude: 8.54976),
                .init(latitude: 50.05507, longitude: 8.54987),
                .init(latitude: 50.04893, longitude: 8.55328),
                .init(latitude: 50.03685, longitude: 8.51980),
                .init(latitude: 50.03403, longitude: 8.52160),
                .init(latitude: 50.03282, longitude: 8.51665),
                .init(latitude: 50.02787, longitude: 8.51951),
                .init(latitude: 50.02711, longitude: 8.51633),
                .init(latitude: 50.02078, longitude: 8.51999),
                .init(latitude: 50.02663, longitude: 8.56301),
                .init(latitude: 50.02539, longitude: 8.57009),
                .init(latitude: 50.01535, longitude: 8.57615),
                .init(latitude: 50.01770, longitude: 8.59201),
                .init(latitude: 50.02789, longitude: 8.59173),
                .init(latitude: 50.04225, longitude: 8.59848),
                .init(latitude: 50.03911, longitude: 8.60639),
                .init(latitude: 50.04509, longitude: 8.61072),
                .init(latitude: 50.05509, longitude: 8.62462),
                .init(latitude: 50.05537, longitude: 8.66518),
                .init(latitude: 50.06173, longitude: 8.72496),
                .init(latitude: 50.06505, longitude: 8.72245),
                .init(latitude: 50.07050, longitude: 8.73049),
                .init(latitude: 50.07303, longitude: 8.72614),
                .init(latitude: 50.07589, longitude: 8.73433),
                .init(latitude: 50.08222, longitude: 8.73219),
                .init(latitude: 50.09223, longitude: 8.74202),
                .init(latitude: 50.09649, longitude: 8.75021),
                .init(latitude: 50.10429, longitude: 8.74172),
                .init(latitude: 50.10540, longitude: 8.73030),
                .init(latitude: 50.10849, longitude: 8.72552),
                .init(latitude: 50.11565, longitude: 8.74846),
                .init(latitude: 50.10793, longitude: 8.76889),
                .init(latitude: 50.11106, longitude: 8.77981),
                .init(latitude: 50.11719, longitude: 8.77977),
                .init(latitude: 50.12675, longitude: 8.77001),
                .init(latitude: 50.13164, longitude: 8.76918),
                .init(latitude: 50.13575, longitude: 8.77364),
                .init(latitude: 50.13937, longitude: 8.78491),
                .init(latitude: 50.14467, longitude: 8.78225),
                .init(latitude: 50.15846, longitude: 8.78343),
                .init(latitude: 50.15891, longitude: 8.79063),
                .init(latitude: 50.16347, longitude: 8.79047),
                .init(latitude: 50.16306, longitude: 8.79399),
                .init(latitude: 50.16684, longitude: 8.79440),
                .init(latitude: 50.16741, longitude: 8.79782),
                .init(latitude: 50.17124, longitude: 8.80040),
                .init(latitude: 50.17451, longitude: 8.79632),
                .init(latitude: 50.17257, longitude: 8.79398),
                .init(latitude: 50.17618, longitude: 8.78997),
                .init(latitude: 50.17711, longitude: 8.77913),
                .init(latitude: 50.18038, longitude: 8.77869),
                .init(latitude: 50.17979, longitude: 8.76879),
                .init(latitude: 50.17898, longitude: 8.76269),
                .init(latitude: 50.17280, longitude: 8.76297),
                .init(latitude: 50.16409, longitude: 8.74256),
                .init(latitude: 50.16220, longitude: 8.73299),
                .init(latitude: 50.16348, longitude: 8.72301),
                .init(latitude: 50.17260, longitude: 8.71189),
                .init(latitude: 50.17892, longitude: 8.70897),
                .init(latitude: 50.18048, longitude: 8.70199),
                .init(latitude: 50.18472, longitude: 8.70449),
                .init(latitude: 50.18380, longitude: 8.70759),
                .init(latitude: 50.18850, longitude: 8.71103),
                .init(latitude: 50.19176, longitude: 8.70545),
                .init(latitude: 50.20259, longitude: 8.72962),
                .init(latitude: 50.20632, longitude: 8.73174),
                .init(latitude: 50.21080, longitude: 8.73071),
                .init(latitude: 50.21127, longitude: 8.73498),
                .init(latitude: 50.21556, longitude: 8.73495),
                .init(latitude: 50.21975, longitude: 8.72434),
                .init(latitude: 50.22516, longitude: 8.71923),
                .init(latitude: 50.22714, longitude: 8.70928),
                .init(latitude: 50.22222, longitude: 8.71115),
                .init(latitude: 50.21709, longitude: 8.70175),
                .init(latitude: 50.21662, longitude: 8.69151),
                .init(latitude: 50.21244, longitude: 8.68192),
                .init(latitude: 50.21695, longitude: 8.66913),
                .init(latitude: 50.20830, longitude: 8.65959),
                .init(latitude: 50.20690, longitude: 8.65075),
                .init(latitude: 50.20236, longitude: 8.64336),
                .init(latitude: 50.20034, longitude: 8.64449),
                .init(latitude: 50.20174, longitude: 8.63874),
                .init(latitude: 50.19454, longitude: 8.63368),
                .init(latitude: 50.18464, longitude: 8.61862),
                .init(latitude: 50.18096, longitude: 8.60563),
                .init(latitude: 50.17625, longitude: 8.61003),
                .init(latitude: 50.17159, longitude: 8.60235),
                .init(latitude: 50.17324, longitude: 8.59687),
                .init(latitude: 50.16732, longitude: 8.59206),
                .init(latitude: 50.16820, longitude: 8.58794),
                .init(latitude: 50.15921, longitude: 8.58977),
                .init(latitude: 50.15699, longitude: 8.60273),
                .init(latitude: 50.13978, longitude: 8.59333),
                .init(latitude: 50.11530, longitude: 8.53296),
                .init(latitude: 50.12096, longitude: 8.52201),
                .init(latitude: 50.12192, longitude: 8.51354),
                .init(latitude: 50.11751, longitude: 8.51239),
                .init(latitude: 50.11657, longitude: 8.50787),
                .init(latitude: 50.10913, longitude: 8.49964),
                .init(latitude: 50.10775, longitude: 8.50229),
                .init(latitude: 50.10672, longitude: 8.49966),
                .init(latitude: 50.11031, longitude: 8.47781),
                .init(latitude: 50.10871, longitude: 8.47587),
                .init(latitude: 50.10528, longitude: 8.48096),
                .init(latitude: 50.09982, longitude: 8.47276),
            ]
        ),
    ]

    /// Radius um den Stadtmittelpunkt — fängt Vororte ab, die außerhalb
    /// der strengen OSM-Stadtgrenze liegen aber zur Metropolregion gehören.
    /// 40km = deckt S-Bahn-Pendlergürtel (Freising, Potsdam, Wedel, Neuss,
    /// Offenbach etc.) ab.
    static let accessBufferMeters: CLLocationDistance = 40_000

    /// Liefert die Stadt, in der die Koordinate liegt (strenge Stadtgrenze).
    /// Nur für Drop-Erstellung + Radius-Filter — "alle Drops in Berlin"
    /// bedeutet wirklich innerhalb Berlins.
    static func city(for coord: CLLocationCoordinate2D) -> ServiceCity? {
        all.first { $0.contains(coord) }
    }

    /// Liefert die NÄCHSTGELEGENE Stadt im Puffer-Radius — großzügiger
    /// Check für Access-Gate (Vororte bleiben drin).
    static func cityNear(_ coord: CLLocationCoordinate2D) -> ServiceCity? {
        // Exakt in einer Stadt? → sofort zurück
        if let exact = city(for: coord) { return exact }
        // Sonst: nächste Stadt im Buffer-Radius finden
        let userLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        var closest: (city: ServiceCity, distance: CLLocationDistance)? = nil
        for city in all {
            let c = CLLocation(latitude: city.center.latitude, longitude: city.center.longitude)
            let d = userLoc.distance(from: c)
            if d <= accessBufferMeters && (closest == nil || d < closest!.distance) {
                closest = (city, d)
            }
        }
        return closest?.city
    }

    /// Access-Gate-Check — User darf rein wenn er in IRGENDEINER Stadt oder
    /// in deren 40km-Umkreis ist.
    static func isInside(_ coord: CLLocationCoordinate2D) -> Bool {
        cityNear(coord) != nil
    }
}

// ─────────────────────────────────────────────────
// MARK: – Deutschland-Außengrenze (Natural Earth 1:10m,
//         per Ramer-Douglas-Peucker auf ~300 Punkte reduziert)
// ─────────────────────────────────────────────────

/// Echte Deutschland-Grenze, vereinfacht auf 161 Stützpunkte.
/// Quelle: Natural Earth Admin-0-Countries (CC0), reduziert mit
/// Ramer-Douglas-Peucker (ε = 0.06°). Folgt der tatsächlichen Grenze
/// inkl. Nord-/Ostseeküste, Oder-Neiße, Tschechischer Grenze, Alpen,
/// Rhein, NL/BE-Grenze. Für den In/Out-Check und das Map-Overlay.
enum Germany {
    /// Polygon-Punkte für den Canvas-Overlay auf der LiveMap + Inside-Check.
    static let coordinates: [CLLocationCoordinate2D] = [
        .init(latitude: 48.7664, longitude: 13.8157),
        .init(latitude: 48.5217, longitude: 13.7165),
        .init(latitude: 48.5734, longitude: 13.4546),
        .init(latitude: 48.3766, longitude: 13.4056),
        .init(latitude: 48.1134, longitude: 12.7389),
        .init(latitude: 47.8471, longitude: 12.9912),
        .init(latitude: 47.7235, longitude: 12.8920),
        .init(latitude: 47.6595, longitude: 13.0720),
        .init(latitude: 47.4660, longitude: 13.0019),
        .init(latitude: 47.5548, longitude: 12.7789),
        .init(latitude: 47.6669, longitude: 12.7620),
        .init(latitude: 47.6289, longitude: 12.4966),
        .init(latitude: 47.7320, longitude: 12.2422),
        .init(latitude: 47.6051, longitude: 12.1736),
        .init(latitude: 47.5897, longitude: 11.6205),
        .init(latitude: 47.3940, longitude: 11.2370),
        .init(latitude: 47.3905, longitude: 10.9795),
        .init(latitude: 47.5307, longitude: 10.8586),
        .init(latitude: 47.5770, longitude: 10.4292),
        .init(latitude: 47.3960, longitude: 10.4283),
        .init(latitude: 47.2711, longitude: 10.1599),
        .init(latitude: 47.3725, longitude: 10.2093),
        .init(latitude: 47.3591, longitude: 10.0829),
        .init(latitude: 47.5408, longitude: 9.9459),
        .init(latitude: 47.6561, longitude: 8.8817),
        .init(latitude: 47.8012, longitude: 8.5582),
        .init(latitude: 47.6655, longitude: 8.3913),
        .init(latitude: 47.6563, longitude: 8.6073),
        .init(latitude: 47.5924, longitude: 8.5741),
        .init(latitude: 47.5647, longitude: 7.6097),
        .init(latitude: 47.7073, longitude: 7.5119),
        .init(latitude: 47.9714, longitude: 7.6211),
        .init(latitude: 48.1145, longitude: 7.5789),
        .init(latitude: 48.3414, longitude: 7.7507),
        .init(latitude: 48.6150, longitude: 7.8103),
        .init(latitude: 48.9586, longitude: 8.2003),
        .init(latitude: 49.0378, longitude: 7.6350),
        .init(latitude: 49.1689, longitude: 7.4105),
        .init(latitude: 49.1050, longitude: 7.2744),
        .init(latitude: 49.1076, longitude: 7.0425),
        .init(latitude: 49.2067, longitude: 6.9144),
        .init(latitude: 49.1556, longitude: 6.7256),
        .init(latitude: 49.4247, longitude: 6.5117),
        .init(latitude: 49.4553, longitude: 6.3453),
        .init(latitude: 49.7957, longitude: 6.5026),
        .init(latitude: 49.8349, longitude: 6.3026),
        .init(latitude: 50.0486, longitude: 6.0964),
        .init(latitude: 50.2140, longitude: 6.1468),
        .init(latitude: 50.3155, longitude: 6.3745),
        .init(latitude: 50.4810, longitude: 6.3369),
        .init(latitude: 50.5180, longitude: 6.1708),
        .init(latitude: 50.6144, longitude: 6.2491),
        .init(latitude: 50.7818, longitude: 5.9730),
        .init(latitude: 50.9075, longitude: 6.0637),
        .init(latitude: 51.0193, longitude: 5.8582),
        .init(latitude: 51.1523, longitude: 6.1473),
        .init(latitude: 51.2117, longitude: 6.0566),
        .init(latitude: 51.3877, longitude: 6.2078),
        .init(latitude: 51.8156, longitude: 5.9315),
        .init(latitude: 51.9083, longitude: 6.7438),
        .init(latitude: 51.9795, longitude: 6.8092),
        .init(latitude: 52.0605, longitude: 6.6799),
        .init(latitude: 52.2306, longitude: 7.0263),
        .init(latitude: 52.4514, longitude: 6.9733),
        .init(latitude: 52.4616, longitude: 6.7148),
        .init(latitude: 52.5417, longitude: 6.6717),
        .init(latitude: 52.6347, longitude: 6.7370),
        .init(latitude: 52.6260, longitude: 7.0185),
        .init(latitude: 52.9980, longitude: 7.1928),
        .init(latitude: 53.2450, longitude: 7.1946),
        .init(latitude: 53.3028, longitude: 7.3665),
        .init(latitude: 53.3764, longitude: 7.0236),
        .init(latitude: 53.5372, longitude: 7.1418),
        .init(latitude: 53.5869, longitude: 7.0868),
        .init(latitude: 53.6665, longitude: 7.2261),
        .init(latitude: 53.7081, longitude: 8.0314),
        .init(latitude: 53.5532, longitude: 8.1680),
        .init(latitude: 53.4687, longitude: 8.0770),
        .init(latitude: 53.4107, longitude: 8.2053),
        .init(latitude: 53.4749, longitude: 8.3151),
        .init(latitude: 53.5252, longitude: 8.2312),
        .init(latitude: 53.6129, longitude: 8.2707),
        .init(latitude: 53.5436, longitude: 8.5521),
        .init(latitude: 53.3581, longitude: 8.5044),
        .init(latitude: 53.5467, longitude: 8.5658),
        .init(latitude: 53.7004, longitude: 8.4861),
        .init(latitude: 53.8704, longitude: 8.5876),
        .init(latitude: 53.8720, longitude: 9.2107),
        .init(latitude: 53.5913, longitude: 9.5824),
        .init(latitude: 53.5436, longitude: 9.8320),
        .init(latitude: 53.6125, longitude: 9.5837),
        .init(latitude: 53.8310, longitude: 9.3952),
        .init(latitude: 53.9374, longitude: 8.9160),
        .init(latitude: 54.0364, longitude: 8.8333),
        .init(latitude: 54.0979, longitude: 9.0183),
        .init(latitude: 54.1805, longitude: 8.8128),
        .init(latitude: 54.3176, longitude: 8.9631),
        .init(latitude: 54.2692, longitude: 8.6785),
        .init(latitude: 54.3381, longitude: 8.5999),
        .init(latitude: 54.5063, longitude: 9.0116),
        .init(latitude: 54.7353, longitude: 8.6887),
        .init(latitude: 54.8963, longitude: 8.6608),
        .init(latitude: 54.7795, longitude: 9.9475),
        .init(latitude: 54.5600, longitude: 10.0269),
        .init(latitude: 54.4753, longitude: 9.8401),
        .init(latitude: 54.4918, longitude: 10.1434),
        .init(latitude: 54.4610, longitude: 10.2039),
        .init(latitude: 54.3244, longitude: 10.1418),
        .init(latitude: 54.4433, longitude: 10.3184),
        .init(latitude: 54.3102, longitude: 10.7313),
        .init(latitude: 54.3859, longitude: 11.1355),
        .init(latitude: 54.1839, longitude: 11.0666),
        .init(latitude: 54.0501, longitude: 10.7526),
        .init(latitude: 53.9614, longitude: 10.9021),
        .init(latitude: 54.0180, longitude: 11.1751),
        .init(latitude: 53.9062, longitude: 11.4577),
        .init(latitude: 54.1552, longitude: 11.6897),
        .init(latitude: 54.1941, longitude: 12.0881),
        .init(latitude: 54.0979, longitude: 12.1150),
        .init(latitude: 54.1830, longitude: 12.1089),
        .init(latitude: 54.4883, longitude: 12.5339),
        .init(latitude: 54.4335, longitude: 12.9212),
        .init(latitude: 54.3875, longitude: 12.4385),
        .init(latitude: 54.2692, longitude: 12.3688),
        .init(latitude: 54.4381, longitude: 13.0088),
        .init(latitude: 54.2800, longitude: 13.1149),
        .init(latitude: 54.0913, longitude: 13.4836),
        .init(latitude: 54.1737, longitude: 13.7119),
        .init(latitude: 54.1047, longitude: 13.8081),
        .init(latitude: 54.0364, longitude: 13.7461),
        .init(latitude: 53.9431, longitude: 13.9060),
        .init(latitude: 53.8529, longitude: 13.8171),
        .init(latitude: 53.7516, longitude: 14.2645),
        .init(latitude: 53.7081, longitude: 14.2127),
        .init(latitude: 53.2518, longitude: 14.4416),
        .init(latitude: 52.8507, longitude: 14.1239),
        .init(latitude: 52.5769, longitude: 14.6448),
        .init(latitude: 52.3822, longitude: 14.5454),
        .init(latitude: 52.0767, longitude: 14.7614),
        .init(latitude: 51.8039, longitude: 14.5858),
        .init(latitude: 51.6583, longitude: 14.7325),
        .init(latitude: 51.5302, longitude: 14.7100),
        .init(latitude: 51.4354, longitude: 14.9554),
        .init(latitude: 51.2368, longitude: 15.0221),
        .init(latitude: 51.0640, longitude: 14.9553),
        .init(latitude: 50.8102, longitude: 14.7592),
        .init(latitude: 50.8456, longitude: 14.6132),
        .init(latitude: 51.0372, longitude: 14.4821),
        .init(latitude: 51.0368, longitude: 14.2875),
        .init(latitude: 50.9825, longitude: 14.2383),
        .init(latitude: 50.8802, longitude: 14.3465),
        .init(latitude: 50.7067, longitude: 13.5566),
        .init(latitude: 50.4042, longitude: 12.9526),
        .init(latitude: 50.3888, longitude: 12.5102),
        .init(latitude: 50.1608, longitude: 12.3004),
        .init(latitude: 50.3152, longitude: 12.0761),
        .init(latitude: 50.0450, longitude: 12.2469),
        .init(latitude: 49.9050, longitude: 12.5241),
        .init(latitude: 49.7429, longitude: 12.3836),
        .init(latitude: 49.4295, longitude: 12.6435),
        .init(latitude: 48.7664, longitude: 13.8157),
    ]

    /// Ray-Casting-Check: liegt `coord` innerhalb des Polygons?
    static func isInside(_ coord: CLLocationCoordinate2D) -> Bool {
        let pts = coordinates
        let n = pts.count
        var inside = false
        var j = n - 1
        for i in 0..<n {
            let xi = pts[i].longitude, yi = pts[i].latitude
            let xj = pts[j].longitude, yj = pts[j].latitude
            let intersect = ((yi > coord.latitude) != (yj > coord.latitude)) &&
                (coord.longitude < (xj - xi) * (coord.latitude - yi) / (yj - yi) + xi)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }
}

// ─────────────────────────────────────────────────
// MARK: – City Gate Checker
// ─────────────────────────────────────────────────

@MainActor
final class CityGateChecker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isOutsideCity = false
    @Published var isChecking    = true

    private let manager = CLLocationManager()
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func startChecking() {
        guard BetaConfig.cityRestrictionEnabled else {
            isChecking = false
            return
        }

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
            startTimeout()
        case .notDetermined:
            // Kein Permission-Dialog hier — kommt erst nach WelcomeSheet/
            // Walkthrough via MainTabView.requestAllPermissions().
            // Benefit of doubt: App starten, Gate läuft nach Permission-Erteilung.
            isChecking = false
        default:
            // Keine Berechtigung — App trotzdem starten (Benefit of doubt)
            isChecking = false
        }
    }

    private func startTimeout() {
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(BetaConfig.timeoutSecs * 1_000_000_000))
            if isChecking {
                isChecking = false  // Timeout → App öffnen
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.check(location: loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isChecking = false  // Fehler → App öffnen
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                self.isChecking = false
            }
        }
    }

    private func check(location: CLLocation) {
        timeoutTask?.cancel()
        // Access-Gate: User muss in einer der 5 Launch-Städte sein
        // (Berlin, Hamburg, München, Köln, Frankfurt).
        isOutsideCity = !ServiceCities.isInside(location.coordinate)
        isChecking = false
    }
}

// ─────────────────────────────────────────────────
// MARK: – City Gate View
// ─────────────────────────────────────────────────

struct CityGateView: View {
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var animateAurora = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            // ── Aurora Hintergrund ─────────────────────────
            Color.brandCream.ignoresSafeArea()

            // Aurora-Blobs aufs App-Icon abgestimmt: Orange dominant oben,
            // Grün dominant unten, Coral in der Mitte als Übergang.
            // Vorher: 34D36E/A78BFA/2DD4BF/FBBF24 (grün/violet/teal/amber).
            Circle()
                .fill(Color.auroraOrange.opacity(0.32))      // Orange (icon-top)
                .frame(width: 500)
                .offset(x: animateAurora ? -140 : -100, y: animateAurora ? -280 : -240)
                .blur(radius: 90)

            Circle()
                .fill(Color.brandCoral.opacity(0.22))      // Koralle
                .frame(width: 420)
                .offset(x: animateAurora ? 180 : 140, y: animateAurora ? -260 : -220)
                .blur(radius: 80)

            Circle()
                .fill(Color.auroraGreen.opacity(0.22))      // Grün (icon-bottom)
                .frame(width: 360)
                .offset(x: animateAurora ? -160 : -120, y: animateAurora ? 340 : 300)
                .blur(radius: 75)

            Circle()
                .fill(Color.auroraCoral.opacity(0.18))      // Coral-Akzent
                .frame(width: 300)
                .offset(x: animateAurora ? 150 : 110, y: animateAurora ? 320 : 280)
                .blur(radius: 70)

            // ── Inhalt ────────────────────────────────────
            VStack(spacing: 0) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.brand.opacity(0.12))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulse ? 1.12 : 1.0)
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)

                    Circle()
                        .fill(Color.brand.opacity(0.18))
                        .frame(width: 88, height: 88)

                    DazuIcon("mappin.and.ellipse")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundColor(Color.brand)
                }
                .padding(.bottom, 36)

                // Titel
                Text(tr("city.not_in_city"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(Color.brandNight)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 14)

                // Beschreibung
                Text((try? AttributedString(markdown: tr("city.coming_soon"),
                    options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(tr("city.coming_soon")))
                    .font(.system(size: 16))
                    .foregroundColor(Color.brandNight.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 48)

                // Stadt-Badge
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.brand)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle().fill(Color.brand.opacity(0.3))
                                .frame(width: 16, height: 16)
                                .scaleEffect(pulse ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)
                        )
                    Text("Live in \(BetaConfig.cityName)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.brand)
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Color.brand.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(Color.brand.opacity(0.25), lineWidth: 1))
                .padding(.bottom, 56)

                Spacer()

                // Info-Text unten
                Text(tr("city.notification_request"))
                    .font(.system(size: 12))
                    .foregroundColor(Color.brandNight.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 36)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                animateAurora = true
            }
            pulse = true
        }
    }
}
