import SwiftUI
import MapKit
import CoreBluetooth
import Combine
@preconcurrency import FirebaseDatabase
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore
import FirebaseCrashlytics
import UserNotifications
import ActivityKit
import WidgetKit

// MARK: - Feature Flags

/// Zentrale Feature-Flags. Auf `false` setzen blendet alle UI-Touchpoints
/// für ein Feature aus, ohne Code zu löschen — so kann das Feature später
/// einfach wieder aktiviert werden.
enum FeatureFlags {
    /// Drops+ (Premium-Tier) ist für den initialen Launch deaktiviert.
    /// Wenn `true`: Settings-Banner, Boost-Option, Paywall-Trigger,
    /// Plus-Avatar-Ring etc. werden angezeigt. Sonst überall hidden.
    static let dropsPlusEnabled: Bool = false

    /// Communities-Feature ist deaktiviert bis zur nächsten Version.
    /// Wenn `true`: Community-Creator-Bereich in Settings, Community-Pins
    /// auf der Karte und Community-Strips im Feed werden angezeigt.
    static let communitiesEnabled: Bool = false
}

// MARK: - Crash Reporter

/// Thin wrapper um FirebaseCrashlytics — zentrale Stelle für Logging, Custom Keys
/// und nicht-fatale Errors. Liegt bewusst hier statt in eigener Datei, damit kein
/// manuelles Xcode-Target-Hinzufügen nötig ist.
enum CrashReporter {

    /// Breadcrumb-Log — taucht im Crashlytics-Report als „Logs"-Zeile auf.
    static func log(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }

    /// Custom-Value pro Session — z.B. Feature-Flags, Drop-Status, Plus-Status.
    static func setValue(_ value: Any, forKey key: String) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }

    /// Nicht-fatale Fehler — App crasht NICHT, aber Firebase trackt Häufigkeit
    /// und Stack-Traces.
    static func record(_ error: Error, file: String = #file, line: Int = #line) {
        let userInfo: [String: Any] = [
            "file": (file as NSString).lastPathComponent,
            "line": line
        ]
        let ns = NSError(domain: (error as NSError).domain,
                         code: (error as NSError).code,
                         userInfo: userInfo.merging((error as NSError).userInfo) { $1 })
        Crashlytics.crashlytics().record(error: ns)
    }

    /// User-ID für Session-Tracking — nach Login / Session-Restore setzen.
    static func setUser(uid: String?) {
        if let uid = uid {
            Crashlytics.crashlytics().setUserID(uid)
            setValue(uid, forKey: "uid")
        } else {
            Crashlytics.crashlytics().setUserID("")
        }
    }

    /// Kontext-Snapshot beim App-Start.
    static func recordSessionContext(isPlus: Bool, hasActiveDrop: Bool) {
        setValue(isPlus, forKey: "is_plus")
        setValue(hasActiveDrop, forKey: "has_active_drop")
        let bundle = Bundle.main.infoDictionary
        if let v = bundle?["CFBundleShortVersionString"] as? String { setValue(v, forKey: "app_version") }
        if let b = bundle?["CFBundleVersion"] as? String { setValue(b, forKey: "build_number") }
        if let uid = FirebaseAuth.Auth.auth().currentUser?.uid { setUser(uid: uid) }
    }
}

// MARK: - Timeout Guard (internal, für deleteAccount)

/// Stellt sicher dass eine Continuation genau einmal resumt wird, egal ob die
/// Operation oder der Timeout-Timer zuerst fertig ist.
final class TimeoutGuard: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()

    func resume(_ block: () -> Void) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        lock.unlock()
        block()
    }
}

// MARK: - User

struct User: Identifiable, Equatable {
    let id: UUID
    var name: String
    var emoji: String
    var isAvailable: Bool
    var statusMessage: String
    var coordinate: CLLocationCoordinate2D
    /// Firebase Storage Download-URL — wird für Avatare in Freundesliste etc. genutzt.
    var profileImageURL: String? = nil
    /// Firebase Auth UID des Users — stabiler Dedup-Key über alle Pfade hinweg
    /// (Contact-Match, Observer-Hydration, Direct-Add).
    var firebaseUID: String? = nil
    /// Reliability-Punkte des Users — Default ist der Start-Score (100).
    /// Wird bei Freunden aus RTDB (`users/{uid}/reliabilityPoints`) hydriert.
    var reliabilityPoints: Int = ReliabilityScore.startingPoints

    init(id: UUID = UUID(), name: String, emoji: String,
         isAvailable: Bool, statusMessage: String,
         coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 48.1371, longitude: 11.5754),
         profileImageURL: String? = nil,
         firebaseUID: String? = nil,
         reliabilityPoints: Int = ReliabilityScore.startingPoints) {
        self.id = id; self.name = name; self.emoji = emoji
        self.isAvailable = isAvailable; self.statusMessage = statusMessage
        self.coordinate = coordinate
        self.profileImageURL = profileImageURL
        self.firebaseUID = firebaseUID
        self.reliabilityPoints = reliabilityPoints
    }
    static func == (lhs: User, rhs: User) -> Bool { lhs.id == rhs.id }
}

// MARK: - Activity

struct Activity: Identifiable {
    let id: UUID
    var name: String
    var emoji: String

    static let presets: [Activity] = [
        Activity(id: UUID(), name: "Kaffee", emoji: "☕️"),
        Activity(id: UUID(), name: "Drink",  emoji: "🍺"),
        Activity(id: UUID(), name: "Sport",  emoji: "🏃"),
        Activity(id: UUID(), name: "Essen",  emoji: "🍕"),
        Activity(id: UUID(), name: "Zocken", emoji: "🎮"),
        Activity(id: UUID(), name: "Eigene", emoji: "✏️")
    ]
}

enum LocationType { case current, searched, pin }

struct DropLocation {
    var title: String
    var subtitle: String
    var coordinate: CLLocationCoordinate2D
    var type: LocationType
}

// MARK: - Drop Event

struct DropEvent: Identifiable {
    let id: UUID
    let host: User
    var activity: Activity
    var location: DropLocation
    var participants: [User]
    let createdAt: Date
    var dropDescription: String
    var scheduledTime: String
    var maxParticipants: Int = 10   // 2–15, default 10
    var durationMinutes: Int = 120  // 0 = kein Limit (12h Fallback)
    /// Falls Community-Drop: ID der Community. Wird in Firebase mitgeschrieben,
    /// auf der Map in Clero-Grün dargestellt und automatisch an Member gepusht.
    var communityID: String? = nil

    /// Verzögerung zwischen `createdAt` und tatsächlichem Drop-Start.
    /// "In 30 Min" → 1800s usw. Wird zu `expiresAt` addiert damit die
    /// Drop-Dauer ERST AB dem geplanten Start läuft, nicht ab dem
    /// Erstellungszeitpunkt. Vorher: Drop erstellt um 18:00 mit
    /// "In 30 Min" + 2h Dauer → expiresAt = 20:00, also 30 Min vor
    /// dem geplanten Ende um 20:30 schon abgelaufen.
    static func scheduledStartOffset(for scheduledTime: String) -> TimeInterval {
        switch scheduledTime {
        case "In 30 Min": return 30 * 60
        case "In 1 Std":  return 60 * 60
        case "In 2 Std":  return 120 * 60
        default:          return 0  // "Jetzt", "Heute Abend", oder unbekannt
        }
    }

    /// Tatsächlicher Drop-Start = createdAt + Scheduled-Offset.
    var startsAt: Date {
        createdAt.addingTimeInterval(Self.scheduledStartOffset(for: scheduledTime))
    }

    /// Ablaufzeitpunkt: durationMinutes == 0 → 12h-Fallback (kein Limit).
    /// Bei geplanten Drops läuft die Dauer ab `startsAt`, nicht ab `createdAt`.
    var expiresAt: Date {
        if durationMinutes > 0 {
            return startsAt.addingTimeInterval(Double(durationMinutes) * 60)
        }
        switch scheduledTime {
        case "Heute Abend":
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: createdAt)
            comps.hour = 23; comps.minute = 59; comps.second = 59
            return Calendar.current.date(from: comps) ?? createdAt.addingTimeInterval(12 * 60 * 60)
        default:
            return createdAt.addingTimeInterval(12 * 60 * 60)
        }
    }

    /// Drop gilt als abgelaufen nur wenn der Host ihn explizit beendet hat
    /// (via cancelDrop) — NICHT automatisch nach Zeit.
    /// Der expiryTimer räumt wirklich alte Drops (>12h) auf.
    var isExpired: Bool { Date() > expiresAt }

    /// Status-Label für eigene Drops — kein Countdown mehr, Drop läuft bis Host beendet
    var timeRemainingLabel: String { "Aktiv" }

    func distance(from userCoord: CLLocationCoordinate2D) -> Double {
        let from = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        let to   = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        return from.distance(from: to)
    }

    func isNearby(from userCoord: CLLocationCoordinate2D, maxMeters: Double = 800) -> Bool {
        distance(from: userCoord) <= maxMeters
    }

    func etaMinutes(from userCoord: CLLocationCoordinate2D) -> Int {
        Int(distance(from: userCoord) / 80)
    }
}

// MARK: - Alert Item

struct AlertItem: Identifiable {
    let id: Int
    let emoji: String
    let name: String
    let activity: String
    let eta: String
    var status: AlertStatus
    enum AlertStatus { case pending, accepted, declined }
}

// MARK: - Drop Join (kein Approval — direkt dabei)

/// Wer bei einem Drop vorbeischaut — wird dem Host als Info angezeigt, kein Accept/Decline.
struct JoinRequest: Identifiable {
    let id: UUID
    let dropID: UUID
    let dropEmoji: String
    let dropActivity: String
    let requesterName: String
    let requesterEmoji: String
    let createdAt: Date
    /// Wo der Drop stattfindet — für Entfernungsanzeige und Karten-Pin
    let dropCoordinate: CLLocationCoordinate2D?

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > 24 * 60 * 60
    }

    /// Simulierter aktueller Standort des Joiners (~500–1500m vom Drop entfernt).
    /// In Produktion: echter GPS-Stream des Joiners.
    var simulatedCoordinate: CLLocationCoordinate2D? {
        guard let base = dropCoordinate else { return nil }
        let h = abs(id.hashValue)
        let latOff = (Double(h % 8 + 5) * 0.0010) * ((h / 20) % 2 == 0 ? 1 : -1)
        let lonOff = (Double((h >> 8) % 8 + 5) * 0.0010) * ((h >> 12) % 2 == 0 ? 1 : -1)
        return CLLocationCoordinate2D(latitude: base.latitude + latOff,
                                      longitude: base.longitude + lonOff)
    }

    var timeAgoLabel: String {
        let mins = Int(Date().timeIntervalSince(createdAt) / 60)
        if mins < 1  { return "Gerade eben" }
        if mins < 60 { return "Vor \(mins) Min" }
        let h = mins / 60
        return h == 1 ? "Vor 1 Std" : "Vor \(h) Std"
    }
}

// MARK: - Incoming Join Request (Host-Perspektive)

struct IncomingJoinRequest: Identifiable {
    let id: String               // joinerID (Firebase key)
    let dropID: String
    let joinerName: String
    let joinerEmoji: String
    let joinerAge: Int?
    let joinerProfileImageURL: String?
    var joinerReliabilityPoints: Int = 100
    var joinerIsPlus: Bool = false
    /// Entfernung in Metern vom Drop-Standort — wird vom Host berechnet
    /// sobald Joiner-Live-Position in Firebase steht.
    var joinerDistanceMeters: Double? = nil
    /// Optionale Begleit-Nachricht des Joiners ("Hi, freu mich!"). Wird
    /// dem Host im IncomingJoinRequestSheet angezeigt damit er Kontext
    /// hat, bevor er Accept/Decline drückt.
    let joinerMessage: String?
    let requestedAt: Date

    /// Nach 5 Min Auto-Accept wenn Host nicht reagiert
    static let autoAcceptDelay: TimeInterval = 5 * 60
    var autoAcceptAt: Date { requestedAt.addingTimeInterval(Self.autoAcceptDelay) }
    var shouldAutoAccept: Bool { Date() >= autoAcceptAt }

    var waitingMinutes: Int { max(0, Int(Date().timeIntervalSince(requestedAt) / 60)) }
}

// MARK: - Drop Participant

struct DropParticipant: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    var selfie: UIImage? = nil
    var reliabilityScore: Int = 100
    /// Anzahl der Commit-Einträge — wird gebraucht, um neue User (totalCommits=0)
    /// als „Drop-Entdecker" statt „Drop-Legende" korrekt zu markieren.
    /// Default 0 = „neuer User / unbekannt" → zeigt Drop-Entdecker-Tier.
    var reliabilityCommits: Int = 0
    var age: Int? = nil
    var statusMessage: String = ""
    /// 8-stelliger BLE-Token (Prefix der User-UUID) — für Bluetooth-Presence-Filter.
    var token: String = ""
    /// Simulierte Distanz in Metern zum Drop-Standort (für "Unterwegs"-Anzeige mit ETA).
    var simulatedDistance: Double? = nil
    /// Aktueller Live-Standort des Teilnehmers (simuliert; in Produktion: echter GPS-Stream).
    var liveCoordinate: CLLocationCoordinate2D? = nil
    var profileImageURL: String? = nil
    /// Firebase Auth UID — für Plus-Badge-Lookup und Report-Funktion.
    var firebaseUID: String? = nil
}

// MARK: - Munich City Boundary

/// Drops-Servicegebiet: München + Umgebung (Unterschleißheim, Ismaning, Unterföhring,
/// Haar, Ottobrunn, Unterhaching, Grünwald, Gauting, Germering, Puchheim, Karlsfeld, Dachau)
/// ~40 Stützpunkte im Uhrzeigersinn, orientiert an den tatsächlichen Gemeindegrenzen
/// (Ortsschild-Positionen auf Haupteinfallstraßen).
enum MunichBoundary {
    static let coordinates: [CLLocationCoordinate2D] = [
        // ── Dachau (NW) ──────────────────────────────────────────────
        // Westgrenze Dachau: Sudetenlandstraße / St2342, Ortsschild ~11.372
        .init(latitude: 48.2200, longitude: 11.3750), // Dachau Süd-West (Amper / Karlsfeld-Grenze)
        .init(latitude: 48.2570, longitude: 11.3720), // Dachau West (Ortsschild Sudetenlandstraße)
        .init(latitude: 48.2850, longitude: 11.3930), // Dachau Nord-West
        .init(latitude: 48.3070, longitude: 11.4300), // Dachau Nord (B304 / Schleißheimer Str., Ortsschild)
        .init(latitude: 48.2970, longitude: 11.4960), // Dachau Nord-Ost (Grenze zu Karlsfeld N)
        // ── Unterschleißheim (N) ─────────────────────────────────────
        .init(latitude: 48.3060, longitude: 11.5000), // Unterschleißheim Nord-West
        .init(latitude: 48.3180, longitude: 11.5520), // Unterschleißheim Nord (Spitze)
        .init(latitude: 48.3090, longitude: 11.5880), // Unterschleißheim Nord-Ost
        // ── Oberschleißheim → Ismaning (NO) ──────────────────────────
        .init(latitude: 48.2820, longitude: 11.6120), // Oberschleißheim Ost
        .init(latitude: 48.2660, longitude: 11.6630), // Ismaning Nord
        .init(latitude: 48.2530, longitude: 11.7100), // Ismaning Nord-Ost
        .init(latitude: 48.2340, longitude: 11.7530), // Ismaning Ost (Spitze)
        // ── Unterföhring (O) ─────────────────────────────────────────
        .init(latitude: 48.2100, longitude: 11.7330), // Unterföhring Nord-Ost
        .init(latitude: 48.1950, longitude: 11.7230), // Unterföhring Ost
        // ── Haar (SO) ────────────────────────────────────────────────
        .init(latitude: 48.1680, longitude: 11.7450), // Haar Nord-Ost
        .init(latitude: 48.1340, longitude: 11.7840), // Haar Ost (Spitze, Ortsschild Wasserburger Landstr.)
        .init(latitude: 48.0980, longitude: 11.7760), // Haar Süd-Ost
        // ── Ottobrunn (S-O) ──────────────────────────────────────────
        // Ostgrenze: Rosenheimer Landstr. Ortsschild ~11.710; Südgrenze: Putzbrunner Str. ~48.047
        .init(latitude: 48.0860, longitude: 11.7110), // Ottobrunn Nord-Ost (Grenze Haar/Neubiberg)
        .init(latitude: 48.0640, longitude: 11.7110), // Ottobrunn Ost (Ortsschild Rosenheimer Landstr.)
        .init(latitude: 48.0450, longitude: 11.6950), // Ottobrunn SO-Ecke (Grenze Hohenbrunn/Brunnthal)
        .init(latitude: 48.0440, longitude: 11.6480), // Ottobrunn Süd (Ortsschild Putzbrunner Str.)
        // ── Unterhaching (S) ─────────────────────────────────────────
        .init(latitude: 48.0390, longitude: 11.6490), // Unterhaching Süd-Ost (Grenze Brunnthal)
        .init(latitude: 48.0230, longitude: 11.6080), // Unterhaching Süd (Spitze)
        .init(latitude: 48.0290, longitude: 11.5640), // Unterhaching Süd-West
        // ── Grünwald (S) ─────────────────────────────────────────────
        // Südgrenze: Grünwald erstreckt sich südlich der Isar bis ~47.997
        .init(latitude: 47.9970, longitude: 11.5300), // Grünwald Süd (Spitze, Ortsschild Tölzer Str.)
        .init(latitude: 48.0290, longitude: 11.4650), // Grünwald West (Ortsschild Würmtal)
        // ── Gauting (SW) ─────────────────────────────────────────────
        // Gauting ist großzügig: Südspitze ~47.991, Westgrenze ~11.329
        .init(latitude: 47.9940, longitude: 11.4560), // Gauting Süd-Ost
        .init(latitude: 47.9910, longitude: 11.3800), // Gauting Süd (Spitze, Ortsschild St2063)
        .init(latitude: 48.0480, longitude: 11.3390), // Gauting Nord-West (Ortsschild Gautinger Str.)
        // ── Germering (W) ────────────────────────────────────────────
        // Westgrenze Germering: ~11.316, Südgrenze: ~48.097
        .init(latitude: 48.0970, longitude: 11.3160), // Germering Süd-West
        .init(latitude: 48.1560, longitude: 11.3130), // Germering West (Spitze)
        // ── Puchheim (W) ─────────────────────────────────────────────
        // Westgrenze Puchheim: ~11.310, Südgrenze: ~48.142
        .init(latitude: 48.1680, longitude: 11.3100), // Puchheim West (Spitze, Ortsschild Friedenstr.)
        .init(latitude: 48.2100, longitude: 11.3450), // Puchheim Nord-West
        .init(latitude: 48.2190, longitude: 11.3820), // Puchheim Nord
        // ── Karlsfeld → Dachau (NW) ──────────────────────────────────
        .init(latitude: 48.2230, longitude: 11.4180), // Karlsfeld West (Ortsschild Münchner Str.)
        // zurück zum Startpunkt
        .init(latitude: 48.2200, longitude: 11.3750),
    ]

    /// Prüft ob eine Koordinate innerhalb der Münchner Stadtgrenze liegt (Ray-Casting).
    static func contains(_ coord: CLLocationCoordinate2D) -> Bool {
        let pts = coordinates
        let n = pts.count
        var inside = false
        var j = n - 1
        for i in 0 ..< n {
            let xi = pts[i].longitude, yi = pts[i].latitude
            let xj = pts[j].longitude, yj = pts[j].latitude
            let intersect = ((yi > coord.latitude) != (yj > coord.latitude))
                && (coord.longitude < (xj - xi) * (coord.latitude - yi) / (yj - yi) + xi)
            if intersect { inside = !inside }
            j = i
        }
        return inside
    }
}

// MARK: - Map Annotation Item

struct MapAnnotationItem: Identifiable {
    let id: UUID
    let name: String
    let emoji: String
    let activity: String
    var coordinate: CLLocationCoordinate2D
    let type: AnnotationType
    var dropDescription: String?
    var scheduledTime: String?
    var participants: [DropParticipant] = []
    var createdAt: Date = Date()
    var maxParticipants: Int = 10
    var durationMinutes: Int = 0       // 0 = kein Limit
    var dropLocationType: LocationType = .current
    var isFuzzy: Bool = false
    var creatorAgeGroup: AgeGroup? = nil
    var creatorAge: Int? = nil
    /// Lesbarer Ort-Titel (z.B. "Odeonsplatz 1, München") — für Live Activity / Karte
    var locationTitle: String = ""
    /// Echter Standort — nur befüllt wenn isFuzzy == true und Join akzeptiert wurde.
    /// Vor Accept immer nil (Joiner sieht nur fuzzy coordinate).
    var realCoordinate: CLLocationCoordinate2D? = nil
    /// Geschlecht des Hosts — für optionalen Geschlechts-Filter ("männlich" | "weiblich" | "divers" | nil)
    var hostGender: String? = nil
    /// Firebase UID des Hosts — für Drop-Invite-Bonus (+5 an Host wenn via Link gejoint).
    var hostUID: String? = nil
    /// Reliability-Score des Hosts — für MiniProfileSheet bei Stranger-Drops.
    var hostReliabilityPoints: Int? = nil
    /// Falls dieser Drop von einem Community-Creator über das Dashboard erstellt
    /// wurde — markiert ihn als Community-Drop, wird auf der Map in Clero-Grün
    /// dargestellt und an alle Mitglieder gepusht.
    var communityID: String? = nil
    /// True wenn der Drop einer Community gehört (für Map-Styling).
    var isCommunityDrop: Bool { communityID != nil }
    var isStranger: Bool { type == .stranger }
    /// Live-Teilnehmerzahl aus `drops/{id}/currentParticipants` (Host + Joiner).
    /// Nur bei Stranger-Drops gesetzt — beim eigenen Drop ist `participants`
    /// ohnehin lokal vollständig. Wenn `nil` → Fallback auf `participants.count`.
    var liveParticipantCount: Int? = nil
    /// Ghost-Drop: bereits beendet/abgelaufen, lebt aber noch ~4h als verblasster
    /// Marker auf der Karte. Tap löst CreateDrop-Sheet mit dieser Activity aus.
    var isGhost: Bool = false
    /// Wann der Drop beendet wurde (nur bei Ghost-Drops gesetzt).
    var endedAt: Date? = nil
    /// Seeder-eingefügter Demo-Drop — verschwindet nach 1h, wird auf der
    /// Map deutlich matter/kleiner gerendert als echte Ghost-Drops.
    var isDemo: Bool = false
    /// Effektive Teilnehmerzahl: Stranger-Drops nutzen den Live-Wert vom
    /// Host, eigene Drops die lokale `participants`-Liste.
    var effectiveParticipantCount: Int {
        liveParticipantCount ?? participants.count
    }
    var isFull: Bool { effectiveParticipantCount >= maxParticipants }
    var spotsLeft: Int { max(0, maxParticipants - effectiveParticipantCount) }

    /// Tatsächlicher Drop-Start = createdAt + Scheduled-Offset
    /// (siehe DropEvent.scheduledStartOffset). Bei „Jetzt" identisch
    /// mit createdAt.
    var startsAt: Date {
        createdAt.addingTimeInterval(
            DropEvent.scheduledStartOffset(for: scheduledTime ?? "Jetzt")
        )
    }

    /// Ablaufzeitpunkt — spiegelt DropEvent.expiresAt. Bei geplanten
    /// Drops ("In 30 Min" usw.) läuft die Dauer erst ab `startsAt`
    /// damit der Timer nicht vor dem geplanten Beginn schon abläuft.
    var expiresAt: Date {
        if durationMinutes > 0 {
            return startsAt.addingTimeInterval(Double(durationMinutes) * 60)
        }
        switch scheduledTime ?? "Jetzt" {
        case "Heute Abend":
            var c = Calendar.current.dateComponents([.year, .month, .day], from: createdAt)
            c.hour = 23; c.minute = 59; c.second = 59
            return Calendar.current.date(from: c) ?? createdAt.addingTimeInterval(12 * 60 * 60)
        default:
            return createdAt.addingTimeInterval(12 * 60 * 60)
        }
    }

    var isTimeExpired: Bool { durationMinutes > 0 && Date() > expiresAt }

    /// Verbleibende Zeit als lesbarer String
    var timeRemainingString: String {
        guard durationMinutes > 0 else { return "" }
        let remaining = expiresAt.timeIntervalSince(Date())
        if remaining <= 0 { return "Abgelaufen" }
        let totalMins = max(1, Int(remaining / 60))
        if totalMins >= 60 {
            let h = totalMins / 60
            let m = totalMins % 60
            return m > 0 ? "noch \(h) Std \(m) Min" : "noch \(h) Std"
        }
        return "noch \(totalMins) Min"
    }
    enum AnnotationType { case friend, myDrop, stranger, joiner, cluster, suggested, community }

    /// Nur gesetzt wenn type == .cluster — enthält alle gruppierten Drops.
    var clusterGroup: [MapAnnotationItem]? = nil
    /// Nur gesetzt wenn type == .suggested — der zugehörige Spot aus History.
    var suggestedSpot: AppStore.SuggestedSpot? = nil
    /// Nur gesetzt wenn type == .community — die zugehörige Community.
    var communityRef: Community? = nil

    /// Für Entfernungsberechnungen immer den echten Standort nutzen.
    /// Der fuzzy Pin auf der Karte ist bewusst versetzt (800-1000m) — Distanz
    /// und ETA sollen aber auf dem echten Treffpunkt basieren. Ohne diesen
    /// Fix würde die Push-Notification nie feuern (Fuzzy-Offset > 500m-Radius)
    /// und das Sheet würde falsche Walk-Times anzeigen.
    var effectiveCoordinate: CLLocationCoordinate2D {
        isFuzzy ? (realCoordinate ?? coordinate) : coordinate
    }

    func distance(from userCoord: CLLocationCoordinate2D) -> Double {
        let from = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        let to   = CLLocation(latitude: effectiveCoordinate.latitude,
                              longitude: effectiveCoordinate.longitude)
        return from.distance(from: to)
    }

    func isNearby(from userCoord: CLLocationCoordinate2D, maxMeters: Double = 800) -> Bool {
        distance(from: userCoord) <= maxMeters
    }
}

// MARK: - Friend Suggestion

struct FriendSuggestion: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let mutualFriend: String
    var dismissed = false
}

// MARK: - Emergency Contact


// MARK: - Past Drop (Verlauf)

struct PastDropParticipant: Identifiable, Codable {
    let id = UUID()
    let name: String
    let emoji: String
    let reliabilityScore: Int
    var wasHost: Bool = false
    var didShowUp: Bool = true
    /// Profilbild-URL des Teilnehmers — wird beim Drop-Ende eingefroren,
    /// damit die "Letzte Drops"-Liste und die Drop-Zusammenfassung das
    /// Foto zeigen statt nur das Emoji-Fallback. Optional, weil ältere
    /// PastDrop-Einträge (vor diesem Feld) noch ohne URL existieren.
    var profileImageURL: String? = nil

    // ID wird beim Decodieren neu erzeugt — sie hat keine semantische
    // Bedeutung über den App-Run hinweg.
    enum CodingKeys: String, CodingKey {
        case name, emoji, reliabilityScore, wasHost, didShowUp, profileImageURL
    }
}

struct PastDrop: Identifiable, Codable {
    let id = UUID()
    let activityEmoji: String
    let activityName: String
    let locationName: String
    let date: Date
    let wasHost: Bool
    let participants: [PastDropParticipant]
    /// Koordinaten des Drops für Map-Suggestions (Map-Layer "wo war letzte Zeit was los").
    /// Optional weil Legacy-Einträge sie nicht haben — Coord-basierte Features
    /// müssen damit umgehen können dass diese nil sind.
    var latitude: Double? = nil
    var longitude: Double? = nil
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    enum CodingKeys: String, CodingKey {
        case activityEmoji, activityName, locationName, date, wasHost, participants, latitude, longitude
    }

    var participantCount: Int { participants.count }
    /// Durchschnittliche Zuverlässigkeit in Prozent. `reliabilityScore` ist
    /// historisch ein Roh-Punktestand (kann > 100 sein) — fürs Anzeigen
    /// als „%" cappen wir auf 100, sonst kommen Werte wie 151%/202% raus.
    var avgReliability: Int {
        guard !participants.isEmpty else { return 0 }
        let total = participants.map { min($0.reliabilityScore, 100) }.reduce(0, +)
        return total / participants.count
    }
    var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Heute" }
        if cal.isDateInYesterday(date) { return "Gestern" }
        let df = DateFormatter(); df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "E, d. MMM"
        return df.string(from: date)
    }
    var timeLabel: String {
        let df = DateFormatter(); df.dateFormat = "HH:mm"
        return df.string(from: date)
    }

    static let demos: [PastDrop] = []
}

// MARK: - Encounter

struct Encounter: Identifiable {
    let id = UUID()
    let friendName: String
    let friendEmoji: String
    let activityEmoji: String
    let activityName: String
    let createdAt: Date
    var confirmed: Bool
    var denied: Bool
    /// Firebase-UID des getroffenen Users — wird gebraucht um nach BLE-
    /// Bestätigung eine Freundschaftsanfrage zu schicken. Optional damit
    /// alte/legacy Encounter ohne UID weiter funktionieren.
    var friendUID: String? = nil
    /// Profilbild-URL — Avatar in der Encounter-Liste statt nur Emoji.
    var friendProfileImageURL: String? = nil
    /// Drop-ID (Firebase-Key, gleich `drop.id.uuidString`) zu dem dieser
    /// Encounter gehört. Wird beim Pre-Erstellen (Accept/Join) gesetzt.
    /// Solange dieser Drop noch in den aktiven Drops/dem aktiven Join
    /// steht, wird der Encounter im UI ausgeblendet — er soll erst in
    /// "Letzte Begegnungen" auftauchen, wenn der Drop vorbei ist. Optional
    /// für Legacy-Einträge ohne dropID (die werden wie bisher angezeigt).
    var dropID: String? = nil
    /// Ob der User diesen Encounter im Alert-Tab gesehen hat.
    /// Nur gesehene Encounters können nach Ablauf als No-Show gewertet werden —
    /// verhindert stille Punkte-Abzüge wenn der Tab nie geöffnet wurde.
    var seenByUser: Bool = false

    static let confirmationWindow: TimeInterval = 12 * 60 * 60

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > Self.confirmationWindow
    }

    var remainingHours: Int {
        max(0, Int((createdAt.addingTimeInterval(Self.confirmationWindow).timeIntervalSince(Date())) / 3600))
    }

    var remainingMinutes: Int {
        let total = max(0, createdAt.addingTimeInterval(Self.confirmationWindow).timeIntervalSince(Date()))
        return Int((total.truncatingRemainder(dividingBy: 3600)) / 60)
    }

    var timeAgoLabel: String {
        let mins = Int(Date().timeIntervalSince(createdAt) / 60)
        if mins < 60 { return "Vor \(mins) Min" }
        let h = mins / 60
        return h == 1 ? "Vor 1 Std" : "Vor \(h) Std"
    }
}

// MARK: - Age Group

enum AgeGroup: String, CaseIterable, Codable, Identifiable {
    case young      = "18–24"
    case twenties   = "25–34"
    case thirties   = "35–44"
    case forties    = "45–59"
    case seniors    = "60–99"

    var id: String { rawValue }
    var label: String { rawValue }

    var systemIcon: String {
        switch self {
        case .young:    return "figure.run"
        case .twenties: return "briefcase.fill"
        case .thirties: return "leaf.fill"
        case .forties:  return "cup.and.saucer.fill"
        case .seniors:  return "star.fill"
        }
    }

    var minAge: Int {
        switch self {
        case .young: return 18; case .twenties: return 25
        case .thirties: return 35; case .forties: return 45; case .seniors: return 60
        }
    }
    var maxAge: Int {
        switch self {
        case .young: return 24; case .twenties: return 34
        case .thirties: return 44; case .forties: return 59; case .seniors: return 99
        }
    }

    /// Feste Farbe pro Altersgruppe — sichtbar auf Karte und in Einstellungen
    var color: Color {
        switch self {
        case .young:    return Color(hex: "22c55e") // grün (brand)
        case .twenties: return Color(hex: "06b6d4") // cyan
        case .thirties: return Color.auroraAmber // amber
        case .forties:  return Color(hex: "8b5cf6") // violet
        case .seniors:  return Color(hex: "ec4899") // pink
        }
    }

    static func group(for age: Int) -> AgeGroup {
        switch age {
        case 18...24: return .young
        case 25...34: return .twenties
        case 35...44: return .thirties
        case 45...59: return .forties
        default:      return .seniors
        }
    }

    static func defaultVisible(for age: Int) -> [AgeGroup] {
        let own = group(for: age)
        let all = AgeGroup.allCases
        guard let idx = all.firstIndex(of: own) else { return [own] }
        var result: [AgeGroup] = [own]
        if idx > 0             { result.append(all[idx - 1]) }
        if idx < all.count - 1 { result.append(all[idx + 1]) }
        return result
    }
}

// MARK: - Persistence Keys

private enum UDKey {
    static let userName             = "ud_userName"
    static let userEmoji            = "ud_userEmoji"
    static let isUnderageBlocked    = "ud_isUnderageBlocked"
    static let userBirthdate        = "ud_userBirthdate"
    static let userGender           = "ud_userGender"
    static let blockedUsers         = "ud_blockedUsers"
    static let selectedAgeGroups    = "ud_ageGroups"
    static let userInterests        = "ud_interests"
    static let radiusFilter         = "ud_radius"
    static let unavailabilityReason = "ud_unavailReason"

    static let wasAgeRestricted     = "ud_wasAgeRestricted"
    static let backgroundedAt       = "ud_backgroundedAt"   // Session-Timeout
    static let reliabilityTotal     = "ud_reliabilityTotal"
    static let reliabilityShows     = "ud_reliabilityShows"
    static let reliabilityNoShows   = "ud_reliabilityNoShows"
    static let reliabilityHostOK    = "ud_reliabilityHostOK"
    static let reliabilityStreakB   = "ud_reliabilityStreakB"
    static let reliabilityFirstB    = "ud_reliabilityFirstB"
    static let reliabilityInviteB   = "ud_reliabilityInviteB"
    static let reliabilityNewcB     = "ud_reliabilityNewcB"
    static let reliabilityAppInvB   = "ud_reliabilityAppInvB"
    static let reliabilityCreateB   = "ud_reliabilityCreateB"   // +5 pro Drop-Erstellung
    static let reliabilityBoostB    = "ud_reliabilityBoostB"    // +5 für Aktion während Boost-Phase
    /// Flag: User hat den einmaligen Erst-Host-Bonus (+10) bereits erhalten.
    /// Wird gesetzt wenn der erste eigene Drop tatsächlich Teilnehmer hatte.
    static let firstHostBonusReceived = "ud_firstHostBonusReceived"
    /// JSON-Array aller PastDrop-Einträge. Persistiert den Drop-Verlauf
    /// zwischen App-Sessions damit die Statistik / Drop-Verlauf-Section
    /// nicht jedes Mal leer ist nach App-Restart.
    static let pastDrops             = "ud_pastDrops"
    static let reliabilityStreak    = "ud_reliabilityStreak"
    static let firebaseUID          = "ud_firebaseUID"   // Stabile UID für Drop-Filter
    static let appleEmail           = "ud_appleEmail"    // Apple relay E-Mail (nur beim 1. Login verfügbar)
    static let isAdmin              = "ud_isAdmin"       // Admin-Flag lokal cachen
    static let homeZoneLat         = "ud_homeZoneLat"
    static let homeZoneLng         = "ud_homeZoneLng"
    static let homeZoneRadius      = "ud_homeZoneRadius"
    static let userPhone           = "ud_userPhone"
    static let joinSessionStartedAt = "ud_joinSessionStartedAt"
    static let genderFilterEnabled = "ud_gender_filter"
    static let activityCategoryFilter = "ud_activity_category_filter"
    static let ageFilterMin        = "ud_ageFilterMin"
    static let ageFilterMax        = "ud_ageFilterMax"
    static let feedDistanceFilter  = "ud_feed_distance_filter"
    static let feedTonightOnly     = "ud_feed_tonight_only"
    static let notificationRadius  = "ud_notificationRadius"  // Benachrichtigungsradius in Metern
    static let presenceShareEnabled = "ud_presenceShareEnabled" // Opt-in: eigene Position mit allen Nutzern teilen
    static let presenceLastWrittenAt = "ud_presenceLastWrittenAt" // Throttle-Timestamp fürs Präsenz-Schreiben
    static let pendingNameChange   = "ud_pendingNameChange"   // Ausstehende Namensänderung
    static let lastNameChangeDate  = "ud_lastNameChangeDate"  // Datum der letzten genehmigten Namensänderung
}

/// Distanz-Filter im Umgebungs-Tab — nur noch Stadt-Ansicht.
enum FeedDistanceFilter: String, CaseIterable {
    case city

    var meters: Double { .infinity }
    var label: String { tr("models.range_city_short") }
    var detailLabel: String { tr("models.range_city") }
}

/// Variante des First-Drop-Celebration-Sheets — wird einmal pro Variante
/// pro User getriggert.
enum FirstDropCelebration: String, Identifiable {
    case created   // Erster eigener Drop erstellt
    case joined    // Erstem fremden Drop beigetreten
    var id: String { rawValue }

    var title: String {
        switch self {
        case .created: return tr("models.first_drop_created")
        case .joined:  return tr("models.first_drop_joined")
        }
    }

    var body: String {
        switch self {
        case .created:
            return tr("models.host_running_info")
        case .joined:
            return tr("models.joined_info")
        }
    }
}

// MARK: - Session Timeout Konfiguration

enum SessionTimeout {
    /// Nach wie vielen Sekunden Hintergrund-Pause die Session abläuft.
    /// Standard: 2 Stunden → Nutzer muss sich nach längerer Inaktivität neu einloggen.
    static let duration: TimeInterval = 2 * 60 * 60
}

// MARK: - Drop Notification Manager

enum DropNotificationManager {

    /// Benachrichtigungs-Berechtigung anfragen
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Plant 3 Erinnerungen vor Ablauf eines Drops (1h, 30min, 10min) + eine bei Ablauf
    static func scheduleExpiryReminders(for drop: MapAnnotationItem) {
        let center = UNUserNotificationCenter.current()
        let dropIDStr = drop.id.uuidString
        let expiresAt = drop.expiresAt

        // Erinnerungen vor Ablauf
        let reminders: [(TimeInterval, String)] = [
            (60 * 60, tr("models.expire_1h").replacingOccurrences(of: "{activity}", with: drop.activity)),
            (30 * 60, tr("models.expire_30min").replacingOccurrences(of: "{activity}", with: drop.activity)),
            (10 * 60, tr("models.expire_10min").replacingOccurrences(of: "{activity}", with: drop.activity))
        ]

        for (offset, body) in reminders {
            let fireDate = expiresAt.addingTimeInterval(-offset)
            guard fireDate > Date() else { continue }   // Vergangenheit überspringen

            let content = UNMutableNotificationContent()
            content.title = tr("models.drop_expiring")
            content.body  = body
            content.sound = .default

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id = "\(dropIDStr)_\(Int(offset))"
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }

        // Benachrichtigung bei Ablauf (nur wenn in der Zukunft)
        guard expiresAt > Date() else { return }
        let expiredContent = UNMutableNotificationContent()
        expiredContent.title = tr("models.drop_expired")
        expiredContent.body  = tr("models.drop_expired_body").replacingOccurrences(of: "{activity}", with: drop.activity)
        expiredContent.sound = .default
        let expComps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: expiresAt)
        let expTrigger = UNCalendarNotificationTrigger(dateMatching: expComps, repeats: false)
        center.add(UNNotificationRequest(identifier: "\(dropIDStr)_0", content: expiredContent, trigger: expTrigger))
    }

    /// Überladung für DropEvent (beim Erstellen eines eigenen Drops)
    static func scheduleExpiryReminders(for drop: DropEvent) {
        let center = UNUserNotificationCenter.current()
        let dropIDStr = drop.id.uuidString
        let expiresAt = drop.expiresAt

        // Erinnerungen vor Ablauf
        let reminders: [(TimeInterval, String)] = [
            (60 * 60, tr("models.expire_1h").replacingOccurrences(of: "{activity}", with: drop.activity.name)),
            (30 * 60, tr("models.expire_30min").replacingOccurrences(of: "{activity}", with: drop.activity.name)),
            (10 * 60, tr("models.expire_10min").replacingOccurrences(of: "{activity}", with: drop.activity.name))
        ]

        for (offset, body) in reminders {
            let fireDate = expiresAt.addingTimeInterval(-offset)
            guard fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = tr("models.drop_expiring")
            content.body  = body
            content.sound = .default

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id = "\(dropIDStr)_\(Int(offset))"
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }

        // Benachrichtigung bei Ablauf — Host: kurze Erinnerung, den Drop zu beenden
        guard expiresAt > Date() else { return }
        let expiredContent = UNMutableNotificationContent()
        expiredContent.title = tr("models.drop_expired")
        expiredContent.body  = tr("models.drop_expired_host").replacingOccurrences(of: "{activity}", with: drop.activity.name)
        expiredContent.sound = .default
        let expComps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: expiresAt)
        let expTrigger = UNCalendarNotificationTrigger(dateMatching: expComps, repeats: false)
        center.add(UNNotificationRequest(identifier: "\(dropIDStr)_0", content: expiredContent, trigger: expTrigger))
    }

    /// Entfernt alle geplanten Benachrichtigungen für einen Drop (inkl. Ablauf-Benachrichtigung)
    static func cancelReminders(for dropID: UUID) {
        let idStr = dropID.uuidString
        let ids = [3600, 1800, 600, 0].map { "\(idStr)_\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

// MARK: - App Store

@MainActor
class AppStore: ObservableObject {
    /// Schwache Referenz für AppDelegate-Hooks (z.B. Quick Actions die VOR der
    /// SwiftUI-Scene laufen). Wird in LinkUpApp init gesetzt.
    nonisolated(unsafe) static weak var shared: AppStore?

    @Published var isAuthenticated = false {
        didSet {
            // Drop-Einladungs-Observer beim Login starten — egal ob frisch
            // signed-in oder warm-restart. Idempotent: Re-Aufruf entfernt
            // den alten Handle und registriert neu.
            if isAuthenticated, !oldValue {
                startObservingDropInvitations()
            }
        }
    }
    /// true = App ist gesperrt nach Timeout → Face ID erforderlich, kein Logout
    @Published var isSessionLocked = false
    /// Pending Quick-Action — gesetzt von AppDelegate.routeQuickAction wenn
    /// bei Cold-Start noch keine MainTabView da ist (Auth restoration läuft).
    /// MainTabView konsumiert es beim onAppear.
    @Published var pendingQuickAction: String? = nil

    @Published var currentUser = User(
        name: "Alex", emoji: "😊", isAvailable: false,
        statusMessage: "Tippe um verfügbar zu sein",
        coordinate: CLLocationCoordinate2D(latitude: 48.1371, longitude: 11.5754)
    )

    // MARK: - Bluetooth Auto-Confirmation
    /// Erkennt andere Drop-Teilnehmer automatisch via BLE-Proximity.
    /// Treffen werden bestätigt, sobald beide ≥ 20 Sek. in Reichweite waren.
    /// Lazy, damit der BLE-Permission-Dialog NICHT beim App-Start erscheint —
    /// erst beim ersten Drop (create/join) wird CBCentralManager instanziert.
    lazy var bluetoothMeetup: BluetoothMeetupManager = BluetoothMeetupManager()

    @Published var radiusFilter: Double = 2000   // Free-Default: 2km
    @Published var notificationRadius: Double = 2000  // Benachrichtigungsradius: 500m–10km
    @Published var pendingNameChange: String? = nil   // Ausstehende Namensänderung (wartet auf Admin)
    @Published var lastNameChangeDate: Date? = nil    // Datum der letzten genehmigten Namensänderung

    /// true wenn seit der letzten Genehmigung mehr als 14 Tage vergangen sind
    var canRequestNameChange: Bool {
        guard let last = lastNameChangeDate else { return true }
        return Date().timeIntervalSince(last) >= 14 * 86_400
    }
    /// Verbleibende Tage bis zur nächsten erlaubten Änderung (0 wenn erlaubt)
    var daysUntilNextNameChange: Int {
        guard let last = lastNameChangeDate else { return 0 }
        let elapsed = Date().timeIntervalSince(last)
        let remaining = (14 * 86_400) - elapsed
        return remaining > 0 ? Int(ceil(remaining / 86_400)) : 0
    }
    @Published var userGender: String = ""   // "männlich" | "weiblich" | "divers"
    @Published var genderFilterEnabled: Bool = false
    /// Aktuelle Aktivitäts-Kategorie im Umgebungs-Tab-Filter. Leer = "Alle".
    /// Gültige Werte: "Kaffee", "Drink", "Sport", "Essen", "Zocken"
    @Published var activityCategoryFilter: String = ""
    /// Distanz-Filter im Umgebungs-Tab (Nähe/Viertel/Stadt).
    @Published var feedDistanceFilter: FeedDistanceFilter = .city
    /// „Heute Abend"-Filter im Umgebungs-Tab — zeigt nur Drops mit
    /// scheduledTime == "Heute Abend" oder solche die heute nach 17 Uhr starten.
    @Published var feedTonightOnly: Bool = false

    // MARK: - Heimzone
    @Published var homeZoneCoordinate: CLLocationCoordinate2D? = nil
    @Published var homeZoneRadius: Double = 150   // Meter: 50–500
    @Published var focusedDropCoordinate: CLLocationCoordinate2D? = nil
    @Published var liveStrangerDrops: [StrangerDropData] = []
    /// Alle Presence-Einträge (nach 20-Min-Delay, 4h-Cutoff, DE-BoundingBox
    /// gefiltert). Wird von der Map genutzt um Freunde-Avatare + Fremd-Dots
    /// darzustellen. Immer den ganzen Filter durch getVisiblePresences().
    @Published var allPresences: [PresenceEntry] = []
    private var dbDropsHandle: DatabaseHandle?

    private let strangerTemplates: [(emoji: String, activity: String, name: String,
                                     participantEmojis: [String], ageGroup: AgeGroup, age: Int)] = [
        // 🎉 Young (18–24) — grün
        ("🎒", "Lernen",       "Lea",    ["📚","🎨"],        .young,    18),
        ("🎮", "Zocken",       "Nico",   ["🎮","😎","🎧"],   .young,    19),
        ("🛹", "Skaten",       "Hanna",  ["🛹","🎵"],        .young,    21),
        ("🧋", "Bubble Tea",   "Finn",   ["🧋","😊"],        .young,    20),

        // 💼 Twenties (25–34) — cyan
        ("☕️", "Kaffee",       "Mia",    ["😊","🎵"],        .twenties, 27),
        ("🍺", "Feierabend",   "Jonas",  ["🎮","🏃"],        .twenties, 27),
        ("🧘", "Yoga",         "Sophie", ["🌿","☕️"],        .twenties, 23),
        ("🏃", "Laufen",       "Lukas",  ["🎧","🌍"],        .twenties, 26),
        ("🎸", "Jam Session",  "Emma",   ["🎵","🎶"],        .twenties, 25),
        ("🍕", "Pizza-Abend",  "Noah",   ["🎮","🍕","😊"],   .twenties, 22),

        // 💼 Thirties (30–39) — amber
        ("🍷", "After Work",   "Anna",   ["🍷","💼"],        .thirties, 33),
        ("🏋️", "Gym",          "Ben",    ["💪","🏃"],        .thirties, 36),
        ("🌿", "Spazieren",    "Julia",  ["🌸","🐕"],        .thirties, 31),
        ("🍜", "Mittagessen",  "Paul",   ["🍜","😊"],        .thirties, 34),

        // 🌿 Forties (40–54) — violet
        ("🧗", "Klettern",     "Stefan", ["🧗","💪"],        .forties,  44),
        ("🎨", "Kunst",        "Petra",  ["🖌️","☕️"],       .forties,  48),
        ("🚴", "Radtour",      "Klaus",  ["🌿","🚴"],        .forties,  51),

        // ☕️ Seniors (55+) — pink
        ("♟️", "Schach",       "Werner", ["♟️","🎯"],        .seniors,  62),
        ("🎭", "Theater",      "Ingrid", ["🎭","🎵"],        .seniors,  58),
        ("🌳", "Spaziergang",  "Horst",  ["🌳","☕️"],       .seniors,  67),
    ]
    private var strangerDropsCache: [MapAnnotationItem] = []
    private var strangerDropsPlaced = false
    private var expiryTimer: Timer?

    @Published var friends: [User] = []

    @Published var activeDrops: [DropEvent] = []
    @Published var selectedTab: Tab = .map
    @Published var pendingDropID: UUID? = nil           // Universal Link → Drop direkt öffnen
    @Published var pendingInviteUsername: String? = nil // Universal Link → Freund hinzufügen
    @Published var selfieImage: UIImage? = nil
    @Published var profileImageURL: String? = nil
    /// Cached Live-Activity-Filename des Host-Profilbilds (von Firebase vorab gedownloaded).
    /// Wird beim App-Start asynchron befüllt damit der Drop-Start nicht auf einen Download wartet.
    @Published var cachedLAProfileImageFilename: String = ""
    /// Optionale Handynummer für Kontakt-Suche (z.B. "+4915712345678")
    @Published var userPhone: String = ""
    @Published var activeJoinedDropID: UUID? = nil
    /// DB-Observer-Handle für „Drop-active=false / Drop-gelöscht"-Detection.
    /// Wird beim `setActiveJoin` gestartet, beim `leaveActiveJoin` entfernt.
    /// Garantiert dass der Joiner „Host hat Drop beendet"-Alert auch im
    /// Live-Tab bekommt (observeNearbyDrops läuft dort nicht).
    private var joinedDropEndHandle: DatabaseHandle? = nil
    /// dropID → Zeitpunkt des Verlassens. Schützt vor Missbrauch durch Re-Join.
    @Published var dropLeaveTimes: [UUID: Date] = [:]
    static let joinCooldown: TimeInterval = 10 * 60   // 10 Minuten
    @Published var activeDropAnnotation: MapAnnotationItem? = nil
    @Published var unavailabilityReason: String = ""
    @Published var userBirthdate: Date? = nil
    @Published var isUnderageBlocked: Bool = false
    @Published var isAdmin: Bool = false

    // MARK: - Community Creator
    /// Status des Community-Antrags: nil | "pending" | "approved" | "denied"
    @Published var communityCreatorStatus: String? = nil
    /// True wenn der User Community Creator ist (Antrag genehmigt).
    @Published var isCommunityCreator: Bool = false
    /// Die vom User erstellte Community (falls Antrag genehmigt + Community existiert).
    @Published var myCommunity: Community? = nil
    /// Alle genehmigten Communities — werden als Pins auf der Karte gezeigt.
    @Published var nearbyCommunities: [Community] = []
    /// IDs der Communities denen der User beigetreten ist. Wird lokal gepflegt
    /// damit die Join-Sheet sofort den "Mitglied"-Status zeigt.
    @Published var myCommunityMemberships: Set<String> = []

    // MARK: - Drops+
    /// Ground truth kommt von DropsStoreManager — wird beim Start und nach Kauf synchronisiert.
    @Published var isPlusUser: Bool = false
    @Published var showDropsPlusPaywall: Bool = false
    /// Wird auf true gesetzt nach Kauf oder Admin-Freischaltung → MainTabView zeigt Success-Popup
    @Published var showDropsPlusSuccess: Bool = false

    /// Immer aktueller Plus-Status (direkt aus StoreKit — kein Caching-Lag).
    var isDropsPlusActive: Bool {
        isPlusUser || DropsStoreManager.shared.isPlusUser
    }
    @Published var selectedAgeGroups: [AgeGroup] = AgeGroup.allCases
    @Published var ageFilterMin: Int = 18
    @Published var ageFilterMax: Int = 99

    /// Interessen des Nutzers — nur intern für Feed-Priorisierung, nie öffentlich sichtbar.
    @Published var userInterests: [String] = []

    // Drop-Verlauf
    @Published var pastDrops: [PastDrop] = []

    // Wer kommt zu meinen Drops — reine Info für den Host, kein Approval
    @Published var joinRequests: [JoinRequest] = []

    /// Gibt an ob die App gerade im Vordergrund ist (wird von LinkUpApp.swift gesetzt)
    var isAppActive: Bool = true

    // MARK: - Beta-Badge (Early-Adopter)
    //
    // Eigenes Erstell-Datum aus RTDB. Wird einmalig beim ersten Settings-/
    // Profil-Open via fetchUserMeta nachgezogen und in der App gehalten,
    // damit alle UI-Touchpoints (Settings-Header, ParticipantDetailRow,
    // ProfileSheet) konsistent denselben Beta-Badge zeigen.
    @Published var ownCreatedAt: Date? = nil

    /// Stichtag: Nutzer ab 04.05.2026 00:00 Europe/Berlin bekommen kein
    /// Beta-Badge mehr. Frühere Nutzer (Early Adopter) behalten den Badge
    /// dauerhaft. Wenn `createdAt` nil ist (Datum noch nicht geladen oder
    /// fremder User ohne propagierten Wert) → false (kein Badge).
    static func qualifiesForBetaBadge(createdAt: Date?) -> Bool {
        guard let created = createdAt else { return false }
        // Sanity-Floor: Drops gibt's erst seit Anfang 2026. Werte vor
        // 01.01.2025 sind Datums-Bugs (z.B. createdAt=0 → 1970) und
        // dürfen den Badge NICHT auslösen.
        var minC = DateComponents(); minC.year = 2025; minC.month = 1; minC.day = 1
        minC.timeZone = TimeZone(identifier: "Europe/Berlin")
        let minPlausible = Calendar(identifier: .gregorian).date(from: minC) ?? Date(timeIntervalSince1970: 0)
        guard created >= minPlausible else { return false }

        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 4
        c.hour = 0; c.minute = 0; c.second = 0
        c.timeZone = TimeZone(identifier: "Europe/Berlin")
        let cutoff = Calendar(identifier: .gregorian).date(from: c) ?? Date()
        return created < cutoff
    }

    /// Convenience: Eigenes Beta-Badge-Recht.
    var qualifiesForBetaBadge: Bool {
        Self.qualifiesForBetaBadge(createdAt: ownCreatedAt)
    }

    // MARK: - App Version Gate
    //
    // Steuert Force-Update (Hard) und Soft-Recommend-Banner. Config kommt
    // aus Firebase RTDB unter /config:
    //   - minRequiredVersion: Hard-Force, blockierender Vollbild
    //   - recommendedVersion: dezenter Banner, dismissibel
    enum AppVersionStatus: Equatable {
        case unknown                  // noch nicht geladen oder offline
        case ok                       // aktuelle Version >= recommended
        case updateRecommended(String)// recommended-Version-String
        case updateRequired(String)   // minRequired-Version-String
    }
    @Published var appVersionStatus: AppVersionStatus = .unknown

    /// App-Store-ID für den Update-Link. Wird aus dem Sheet als `itms-apps://`
    /// URL geöffnet → springt direkt in den App-Store.
    /// Drops – Triff Leute (https://apps.apple.com/de/app/drops-triff-leute/id6762097493)
    static let appStoreID: String = "6762097493"

    /// User hat den Soft-Recommend-Banner für diese Version weggewischt.
    /// Persistiert in UserDefaults damit er nicht nach jedem App-Start
    /// erneut aufpoppt. Der Banner kommt nur wieder wenn eine NEUE
    /// recommendedVersion als die zuletzt dismissed höher ist.
    @AppStorage("ud_dismissedRecommendVersion") private var dismissedRecommendVersion: String = ""

    /// Gibt die installierte App-Version zurück (z.B. "1.0.2").
    var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Live-Observer-Handle für `config/`. Wird einmalig in `init`
    /// registriert. Solange der Listener läuft, reagiert die App
    /// sofort wenn du in Firebase `minRequiredVersion` änderst —
    /// kein Cold-Start nötig.
    private var appVersionConfigHandle: DatabaseHandle? = nil

    /// Lädt Version-Config + setzt appVersionStatus. Erstaufruf
    /// registriert einen Live-Observer, alle weiteren Aufrufe sind
    /// no-ops (Observer feuert ohnehin bei jedem Config-Change).
    /// `refreshAppVersionStatus()` beim Foregrounding bleibt safe —
    /// der Observer würde dort auch ein Initial-Snapshot liefern.
    func refreshAppVersionStatus() {
        let current = currentAppVersion
        let apply: (String?, String?) -> Void = { [weak self] minReq, rec in
            guard let self = self else { return }
            // Min-Required hat Vorrang
            if let minReq = minReq, !minReq.isEmpty,
               Self.compareVersions(current, minReq) < 0 {
                self.appVersionStatus = .updateRequired(minReq)
                return
            }
            // Recommended (nur wenn der User nicht schon dismisst hat)
            if let rec = rec, !rec.isEmpty,
               Self.compareVersions(current, rec) < 0,
               Self.compareVersions(self.dismissedRecommendVersion, rec) < 0 {
                self.appVersionStatus = .updateRecommended(rec)
                return
            }
            self.appVersionStatus = .ok
        }

        if appVersionConfigHandle == nil {
            // Erstaufruf → Live-Observer registrieren. Feuert sofort
            // mit Initial-Snapshot + bei jedem späteren Update.
            appVersionConfigHandle = RealtimeDBManager.shared
                .observeAppVersionConfig(onUpdate: apply)
        } else {
            // Re-Trigger (z.B. Foregrounding) → einmal lesen, falls
            // der Observer aus irgendeinem Grund stehen geblieben ist.
            RealtimeDBManager.shared.fetchAppVersionConfig(completion: apply)
        }
    }

    /// User hat den Soft-Recommend-Banner für diese Version weggewischt.
    func dismissRecommendBanner(forVersion version: String) {
        dismissedRecommendVersion = version
        if case .updateRecommended = appVersionStatus {
            appVersionStatus = .ok
        }
    }

    /// Vergleicht zwei Versions-Strings im "1.2.3"-Format. Liefert -1 / 0 / 1.
    /// Robuster als String-Compare: "1.10.0" > "1.9.0".
    static func compareVersions(_ a: String, _ b: String) -> Int {
        let parts1 = a.split(separator: ".").map { Int($0) ?? 0 }
        let parts2 = b.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(parts1.count, parts2.count)
        for i in 0 ..< count {
            let v1 = i < parts1.count ? parts1[i] : 0
            let v2 = i < parts2.count ? parts2[i] : 0
            if v1 != v2 { return v1 < v2 ? -1 : 1 }
        }
        return 0
    }

    /// Lädt das eigene createdAt einmalig aus RTDB. Idempotent — mehrfache
    /// Aufrufe haben keine zusätzliche Wirkung wenn schon geladen.
    func loadOwnCreatedAtIfNeeded() {
        guard ownCreatedAt == nil,
              let uid = FirebaseAuth.Auth.auth().currentUser?.uid else { return }
        print("[BetaBadge] loadOwnCreatedAt für UID=\(uid)")
        RealtimeDBManager.shared.fetchUserMeta(uid: uid) { [weak self] created, _ in
            DispatchQueue.main.async {
                self?.ownCreatedAt = created
                let qualifies = AppStore.qualifiesForBetaBadge(createdAt: created)
                print("[BetaBadge] createdAt=\(created.map { String(describing: $0) } ?? "nil") → qualifiesForBeta=\(qualifies)")
            }
        }
    }

    // MARK: - Points-Toast
    //
    // Zeigt eine kleine animierte Pille mit "+X Punkte" wann immer der
    // ReliabilityScore steigt. Die Pille wird per Combine-Observer auf
    // `reliabilityScore.points` angefangen — so erfasst er ALLE Punkte-
    // Events (Show-Up, Streak, Boost, Power-Hour, Invite, etc.) ohne
    // dass jede einzelne Score-Update-Stelle den Toast manuell triggern
    // muss.
    struct PointsToast: Identifiable, Equatable {
        let id = UUID()
        let delta: Int
        /// Nur wahr wenn der Punkt-Push aus einer aktiven Power-Hour kam.
        /// Steuert eine kleine Bolt-Variation in der Toast-UI.
        let isPowerHour: Bool
        /// Optionaler Begründungs-Text — z.B. "Drop bestätigt", "Streak-Bonus",
        /// "Host-Erfolg". Wird im Toast als kleine Subline angezeigt damit
        /// der User nicht im Dunkeln tappt warum gerade Punkte kamen.
        var reason: String? = nil
    }
    @Published var pointsToast: PointsToast? = nil
    /// Letzter Punkte-Award-Grund, gesetzt von den verschiedenen Award-
    /// Funktionen vor dem Score-Inkrement. Der Toast-Observer liest ihn
    /// und resettet danach. Verwendet als „Annotation" für den nächsten
    /// Toast — sonst müssten wir jede Score-Mutation manuell touchen.
    fileprivate var nextPointsReason: String? = nil

    /// Eindeutiger BLE-Token für den aktuellen User: erste 8 Zeichen der
    /// Firebase-UID. Wird sowohl beim Werben (BLE-Advertise) als auch
    /// beim Matchen (drop.participants[].token) verwendet — nur so
    /// können Host und Joiner sich gegenseitig identifizieren.
    /// VORHER nutzte der Code `currentUser.id.uuidString.prefix(8)`
    /// (lokale UUID), aber `acceptJoinRequest` setzt den Token-Wert vom
    /// JOINER aus dessen firebaseUID — dadurch hatte der Host einen
    /// firebaseUID-basierten Token im participant.token, aber der Joiner
    /// advertisierte mit local-UUID-Token → keine Match → BLE-Bestätigung
    /// erreichte die UI nie, Joiner blieb ewig auf "Unterwegs".
    var myBLEToken: String {
        let uid = FirebaseAuth.Auth.auth().currentUser?.uid
            ?? UserDefaults.standard.string(forKey: UDKey.firebaseUID)
            ?? ""
        guard !uid.isEmpty else {
            // Fallback (vor Auth/Hydration) — sollte selten passieren.
            return String(currentUser.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
        }
        return String(uid.prefix(8))
    }

    /// Letzter beobachteter Punktestand. Initial bei loadAll() gesetzt,
    /// damit die Hydration aus UserDefaults/Firebase keinen Toast triggert.
    private var lastObservedPoints: Int = ReliabilityScore.startingPoints
    /// Toast-Observer ist erst aktiv NACH initialer Score-Hydration.
    private var pointsToastReady: Bool = false
    private var pointsToastCancellable: AnyCancellable? = nil

    /// Eingehende Beitrittsanfragen für den eigenen Drop (Host-Ansicht)
    @Published var pendingJoinRequests: [IncomingJoinRequest] = []

    /// Wahr wenn WEDER Standort NOCH Bluetooth autorisiert sind — dann blockt die App,
    /// weil ohne beides kein Drop-Matching/-Erkennen funktioniert. MainTabView
    /// rendert dann einen Permission-Gate-Sheet mit Settings-Link.
    @Published var needsCorePermissions: Bool = false


    /// Viewers des eigenen aktiven Drops (Drops+ „wer hat geschaut"-Feature).
    /// Key = dropID.uuidString → Liste aller Viewer sortiert nach viewedAt (neueste zuerst).
    @Published var dropViewersByDropID: [String: [RealtimeDBManager.DropViewerSnapshot]] = [:]
    /// Handles der Firebase-Observer (pro Drop) — zum sauberen Abmelden.
    private var dropViewsObserverHandles: [String: DatabaseHandle] = [:]
    /// Drop-IDs die in der aktuellen App-Session bereits „gezählt" wurden —
    /// verhindert dass mehrfaches Öffnen des Sheets mehrfach feuert.
    private var viewedDropIDsThisSession: Set<String> = []

    /// Live-Observer-Handle für `friends/{myUID}`.
    private var friendsObserverHandle: DatabaseHandle?
    private var friendsObservedUID: String?
    /// UIDs der Freunde, die wir bei der letzten Observer-Feuerung schon hatten.
    /// Damit können wir NEUE Freundschafts-Adds erkennen und Push auslösen.
    private var knownFriendUIDs: Set<String> = []
    /// Erste Observer-Feuerung initialisiert nur die Baseline — ohne Push.
    private var friendsObserverInitialized = false

    // MARK: - Friend Requests
    /// Eingehende Freundschaftsanfragen — werden im Freunde-Tab als Section
    /// ganz oben mit Annehmen/Ablehnen-Buttons angezeigt.
    @Published var incomingFriendRequests: [FriendRequestSnapshot] = []
    private var friendRequestsObserverHandle: DatabaseHandle?
    private var friendRequestsObserverInitialized = false

    /// Sheet: aktuell angezeigte Anfrage
    @Published var activeIncomingRequest: IncomingJoinRequest? = nil

    /// Status der eigenen Anfrage als Joiner: "pending" | "accepted" | "declined"
    @Published var myJoinRequestStatus: String = ""
    /// Drop-ID der aktuell ausstehenden Beitrittsanfrage. Wird gesetzt sobald
    /// `sendJoinRequest` rausgeht und gecleart wenn Host akzeptiert/ablehnt
    /// oder der Joiner zurückzieht. Verwendet von FeedView/LiveMapView um
    /// "Ausstehend" statt "Bin dabei!" anzuzeigen — sonst wirkt's so als
    /// hätte der Host schon bestätigt, was zu Verwirrung führt.
    @Published var pendingJoinDropID: UUID? = nil
    /// Zeitpunkt der pending Beitrittsanfrage — Source-of-Truth für den
    /// Countdown in der Pending-Pill oben in der App. Wird beim
    /// `sendJoinRequest` gesetzt und beim Status-Change geleert.
    @Published var pendingJoinRequestedAt: Date? = nil
    /// Emoji + Activity-Name des pending Drops — cached beim sendJoinRequest
    /// damit die Pending-Pill auch dann den richtigen Emoji zeigt wenn der
    /// Drop aus `allMapAnnotations` rausfällt (z.B. außerhalb Radius oder
    /// vom Host beendet). Vorher fiel der Emoji auf 📍 zurück.
    @Published var pendingJoinDropEmoji: String = ""
    @Published var pendingJoinDropActivity: String = ""
    /// Timer-Task für den 5-Min-Auto-Accept-Watcher auf Joiner-Seite. Wenn
    /// der Host nach 5 min nicht reagiert hat, gehen wir auf die DB und
    /// kicken Auto-Accept selbst (Host-App könnte ja closed sein). Push
    /// folgt automatisch über den Status-Observer.
    private var pendingAutoAcceptTask: DispatchWorkItem? = nil

    private var joinRequestObserverHandle: DatabaseHandle?
    private var myJoinStatusObserverHandle: DatabaseHandle?
    private var nameChangeResultHandle: UInt? = nil
    /// Direkter Observer auf den Drop-Pfad während eine Beitrittsanfrage
    /// pending ist. Wenn der Host den Drop beendet (active=false) ODER der
    /// Drop ganz aus Firebase verschwindet (Cleanup), feuert dieser
    /// Observer und räumt den Pending-State sofort auf. Sonst hing die
    /// Pending-Pill bis zum 5-Min-Auto-Cleanup hängen.
    private var pendingDropEndHandle: DatabaseHandle?
    private var pendingDropEndDropID: String?
    private var autoAcceptTimer: Timer?

    // MARK: - Init

    init() {
        // DIAGNOSTIC: wenn du diese Zeile in der Console siehst, läuft init().
        print("🚀🚀🚀 [AppStore.init] START — args=\(CommandLine.arguments)")

        // Singleton-Referenz IMMEDIATELY setzen — vor jedem AppDelegate-Hook.
        // AppDelegate.routeQuickAction prüft AppStore.shared, daher muss die
        // Referenz vor `application(_:didFinishLaunchingWithOptions:)` da sein.
        Self.shared = self

        // ── Firebase-Session beim App-Start wiederherstellen ──────────────
        // isAuthenticated startet als false. Wenn Firebase einen gültigen User
        // hat UND das Onboarding abgeschlossen wurde, direkt in die App.
        let hasOnboarded = UserDefaults.standard.bool(forKey: "hasOnboarded")

        // Safety: iCloud-Backup kann bei Neuinstallation oder Account-Wechsel
        // ein altes hasSeenWelcome=true zurückspielen, obwohl kein Firebase-User
        // mehr da ist. Ohne diesen Reset würde der WelcomeSheet nie erscheinen
        // und Permissions würden sofort gefeuert — vor dem Onboarding-Kontext.
        if FirebaseAuth.Auth.auth().currentUser == nil {
            UserDefaults.standard.removeObject(forKey: "hasSeenWelcome")
        }

        // Nach Deinstallation persistiert die Firebase-Session im Keychain.
        // UserDefaults ist normalerweise leer → hasOnboarded=false → Logout.
        // ABER: iCloud-Backup restauriert manchmal UserDefaults → hasOnboarded
        // wäre irreführend true. Deshalb zusätzlich prüfen ob der Name wirklich
        // gesetzt ist — wenn nicht, ist der State korrupt, wir loggen aus.
        //
        // AUSNAHME: nach normalem In-App-Logout ist `userName` leer aber
        // `ud_lastLoginName` gesetzt — das ist KEIN korrupter State, sondern
        // eine bewusste Logout-Situation, in der wir die Firebase-Session
        // **erhalten** wollen damit Quick-Login ohne Apple-Sheet funktioniert.
        var hasNameStored = !(UserDefaults.standard.string(forKey: UDKey.userName) ?? "").isEmpty
        let hasLastLoginName = !(UserDefaults.standard.string(forKey: "ud_lastLoginName") ?? "").isEmpty

        // Self-heal: Wenn Firebase-Session da ist und wir einen ud_lastLoginName
        // haben, aber ud_userName leer ist, ist das ein Bug-Fall aus einem
        // früheren Login (OnboardingView schrieb userName nicht in UD). Wir
        // stellen ihn aus ud_lastLoginName wieder her, damit die App nicht
        // fälschlich im Post-Logout-Screen klemmt.
        if FirebaseAuth.Auth.auth().currentUser != nil, !hasNameStored, hasLastLoginName,
           let lastName = UserDefaults.standard.string(forKey: "ud_lastLoginName"), !lastName.isEmpty {
            UserDefaults.standard.set(lastName.capitalizedFirst, forKey: UDKey.userName)
            hasNameStored = true
        }

        let isPostLogoutState = hasOnboarded && !hasNameStored && hasLastLoginName
        if FirebaseAuth.Auth.auth().currentUser != nil
            && (!hasOnboarded || !hasNameStored)
            && !isPostLogoutState {
            try? FirebaseAuth.Auth.auth().signOut()
            UserDefaults.standard.set(false, forKey: "hasOnboarded")
            UserDefaults.standard.removeObject(forKey: "hasSeenWelcome")
        }

        if FirebaseAuth.Auth.auth().currentUser != nil && hasOnboarded && hasNameStored {
            isAuthenticated = true
            // hasSeenWelcome wird NICHT mehr hier gesetzt — der WelcomeSheet
            // soll auch nach Neuinstallation erscheinen (Dynamic Island Demo +
            // First-Drop-Walkthrough). hasSeenWelcome wird erst in MainTabView
            // gesetzt, wenn der User den Sheet wirklich gesehen und dismissed hat.
            // Ohne Neuinstallation ist hasSeenWelcome durch den früheren Dismiss
            // bereits true und der Sheet erscheint ohnehin nicht nochmals.
            // Firebase UID persistent speichern damit der Drop-Filter auch beim Start funktioniert
            if let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
                UserDefaults.standard.set(uid, forKey: UDKey.firebaseUID)

                // Im Discovery-Index registrieren (phoneIndex + emailIndex) damit andere uns finden.
                // Bei Apple Sign-In ist FirebaseAuth.phoneNumber = nil — daher Fallback auf die
                // optional hinterlegte Nummer aus UserDefaults (wird beim Onboarding/Settings gespeichert).
                let authPhone  = FirebaseAuth.Auth.auth().currentUser?.phoneNumber
                let savedPhone = UserDefaults.standard.string(forKey: UDKey.userPhone)
                let idxPhone   = (authPhone?.isEmpty == false) ? authPhone : savedPhone
                let idxEmail   = FirebaseAuth.Auth.auth().currentUser?.email
                let savedName  = UserDefaults.standard.string(forKey: UDKey.userName) ?? ""
                let idxName    = savedName.isEmpty ? "Dazu-Nutzer" : savedName
                RealtimeDBManager.shared.registerInDiscoveryIndex(
                    uid: uid, name: idxName,
                    phone: idxPhone, email: idxEmail
                )
                // Eingehende Drop-Einladungen beobachten (Freund klickt
                // "Zu meinem Drop einladen" → wir bekommen ein Sheet).
                startObservingDropInvitations()
            }

            // Sofort-Check per Telefon/E-Mail — kein Firebase-Roundtrip nötig
            let authPhone = FirebaseAuth.Auth.auth().currentUser?.phoneNumber ?? ""
            let authEmail = (FirebaseAuth.Auth.auth().currentUser?.email ?? "").lowercased()
            // Apple Relay-Email wird nur beim ersten Login gesendet → aus UserDefaults laden
            let storedAppleEmail = (UserDefaults.standard.string(forKey: UDKey.appleEmail) ?? "").lowercased()
            if AdminConfig.isBootstrapAdmin(authEmail: authEmail, authPhone: authPhone, storedAppleEmail: storedAppleEmail) {
                isAdmin = true
            }

            // Verwaiste eigene Drops in Firebase aufräumen (z.B. nach App-Crash)
            let cleanupUID = FirebaseAuth.Auth.auth().currentUser?.uid
                ?? UserDefaults.standard.string(forKey: UDKey.firebaseUID) ?? ""
            if !cleanupUID.isEmpty {
                let activeIDs = Set(activeDrops.map { $0.id.uuidString })
                RealtimeDBManager.shared.cleanupOrphanedDrops(ownerUID: cleanupUID, activeDropIDs: activeIDs)
            }

            // FCM-Token sicherstellen — damit Cloud-Function-Pushes den User erreichen.
            // AppDelegate schreibt bereits bei Token-Refresh, aber wenn der Token aus einer
            // früheren Session gecacht ist und kein Refresh in dieser Session feuert, bleibt
            // Firebase sonst ohne Token-Zuordnung.
            if let uid = FirebaseAuth.Auth.auth().currentUser?.uid,
               let token = UserDefaults.standard.string(forKey: "fcmToken"),
               !token.isEmpty {
                RealtimeDBManager.shared.setMyFCMToken(token, uid: uid)
            }

            // Zusätzlich Firebase-Profil laden (Fallback + übrige Felder)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                // Einmalig isAdmin in Firebase schreiben falls Credentials passen aber Flag fehlt
                // (passiert wenn Account vor der Admin-Whitelist-Ergänzung registriert wurde)
                if self.isAdmin, let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
                    RealtimeDBManager.shared.ensureAdminFlagInFirebase(uid: uid)
                }
                RealtimeDBManager.shared.loadUserProfile { [weak self] profile in
                    guard let self = self, let p = profile else { return }
                    DispatchQueue.main.async {
                        if p.isAdmin           { self.isAdmin           = true }
                        if p.isPlusUser        { self.isPlusUser        = true }   // Admin-gewährtes Plus

                        // Community-Creator-Status real-time observieren — reagiert
                        // sofort auf Admin-Genehmigung/Ablehnung ohne App-Neustart.
                        // Nur wenn das Feature aktiv ist (FeatureFlags.communitiesEnabled).
                        if FeatureFlags.communitiesEnabled {
                            if let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
                                CommunityManager.shared.observeMyStatus(uid: uid)
                                CommunityManager.shared.observeMyCommunity(uid: uid)
                                CommunityManager.shared.observeMyMemberships(uid: uid)
                            }
                            // Alle Communities für die Map laden.
                            CommunityManager.shared.observeAllCommunities()
                        }

                        if let name = p.name, !name.isEmpty {
                            self.currentUser.name = name.capitalizedFirst
                        }
                        // Geburtsdatum + Geschlecht auch aus Firebase zurückholen —
                        // sonst fehlen sie nach Reinstall / Session-Restore, obwohl sie
                        // beim Onboarding einmal gesetzt wurden.
                        if let bd = p.birthdate {
                            self.userBirthdate = bd
                            UserDefaults.standard.set(bd.timeIntervalSinceReferenceDate,
                                                       forKey: UDKey.userBirthdate)
                        }
                        if let gender = p.gender, !gender.isEmpty {
                            self.userGender = gender
                            UserDefaults.standard.set(gender, forKey: UDKey.userGender)
                        }
                        // Benutzer-Einstellungen aus Firebase wiederherstellen
                        // (Radius, Altersfilter, Interests, Blocklist etc.)
                        self.applyRemoteUserSettings(p.settings)
                        // profileImageURL kommt aus Firestore (loadProfileImageURL)
                        self.loadProfileImageURL()
                    }
                }
            }
        }

        loadAll()

        // Score aus Firestore wiederherstellen — überschreibt lokalen UserDefaults-Stand
        // nur wenn Firestore-Wert größer ist (verhindert Datenverlust bei Race-Conditions).
        // Notwendig nach Konto-Wechsel oder Neuinstallation, wo UserDefaults leer sind.
        syncReliabilityFromFirestore()

        // Points-Toast-Observer NACH Hydration starten — sonst triggert
        // die Score-Initialisierung aus UserDefaults selbst einen Toast.
        startPointsToastObserver()

        // Eigenes createdAt für Beta-Badge laden (idempotent)
        loadOwnCreatedAtIfNeeded()

        // App-Version-Status laden (Force-Update / Recommend-Banner)
        refreshAppVersionStatus()

        // ── Eigene aktive Drops aus Firebase rehydrieren ─────────────────
        // activeDrops und joinRequests werden lokal nicht persistiert, aber nach
        // App-Neustart soll ein noch laufender Drop weiter im „Aktiv"-Tab erscheinen.
        // → Firebase ist die Single Source of Truth, wir laden die eigenen
        // aktiven Drops des Users einmalig zurück in den In-Memory-State.
        if let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
            Task { @MainActor in
                let snapshots = await RealtimeDBManager.shared.loadMyActiveDrops(ownerUID: uid)
                for snap in snapshots where !self.activeDrops.contains(where: { $0.id.uuidString == snap.dropID }) {
                    guard let dropUUID = UUID(uuidString: snap.dropID) else { continue }
                    let activity = Activity(id: UUID(), name: snap.activityName, emoji: snap.emoji)
                    let location = DropLocation(
                        title: "Dein aktiver Plan",
                        subtitle: "",
                        coordinate: snap.coordinate,
                        type: .current
                    )
                    let duration = max(0, Int(snap.expiresAt.timeIntervalSince(snap.createdAt) / 60))
                    let drop = DropEvent(
                        id: dropUUID, host: self.currentUser,
                        activity: activity, location: location,
                        participants: [self.currentUser],
                        createdAt: snap.createdAt,
                        dropDescription: "",
                        scheduledTime: snap.scheduledTime,
                        maxParticipants: snap.maxParticipants,
                        durationMinutes: duration
                    )
                    self.activeDrops.append(drop)
                    DropNotificationManager.scheduleExpiryReminders(for: drop)
                    self.startObservingDropIns(forDropID: snap.dropID)
                    self.startObservingJoinRequests(forDropID: snap.dropID)
                    self.startObservingDropViews(forDropID: snap.dropID)
                }
            }
        }

        // ── Freundesliste live aus Firebase observieren ───────────────────
        // friends/{myUID} wird beobachtet: Adds auf anderen Geräten,
        // Re-Hydrates nach App-Neustart etc. feuern alle über denselben Weg.
        // Avatare kommen aus users/{theirUID}/profileImageURL (RTDB-Cache).
        if let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
            startObservingFriends(ownerUID: uid)
            // Presence-Observer — läuft für alle eingeloggten User (nicht nur
            // die mit opt-in), damit auch Ghost-Mode-Nutzer die anderen sehen.
            startObservingPresence()
            // Admin-Notices live mitlesen — wenn ein Admin den Drop des
            // Users entfernt hat (auch offline geschehen), wird das Sheet
            // beim nächsten App-Start sofort präsentiert.
            startObservingAdminNotices()
        }

        // ── Veraltete Drop-Benachrichtigungen aus vorherigen Sessions löschen ─
        // Alte UNCalendarNotificationTrigger würden sonst feuern; neue werden nach
        // der Rehydration oben bzw. bei createDrop/joinDrop neu eingeplant.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        // ── Live Activities aus früheren Sessions behandeln ───────────────
        // ActivityKit hält Activities über App-Neustarts hinweg am Leben.
        // Strategie:
        //  1. Pending-End-Marker: Activities die der User in der letzten Session
        //     beenden wollte, bei denen der Network-Call aber nicht durchkam
        //     → garantiert jetzt beenden.
        //  2. Noch nicht abgelaufene Activities BEHALTEN und als currentLiveActivity
        //     referenzieren — Drop-Rehydration erfolgt ggf. noch async,
        //     aber die User-sichtbare Activity bleibt durchgängig.
        //  3. Wirklich abgelaufene (expiresAt < jetzt) werden beendet.
        let pendingEndIDs = Set(UserDefaults.standard.stringArray(forKey: "ud_liveActivitiesPendingEnd") ?? [])
        Task { [weak self] in
            guard let self = self else { return }
            let now = Date()
            for activity in ActivityKit.Activity<DropLiveActivityAttributes>.activities {
                // Priorität 1: Pending-End aus letzter Session durchziehen
                if pendingEndIDs.contains(activity.id) {
                    await activity.end(nil, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
                    continue
                }
                let expiresAt = activity.content.state.expiresAt
                if expiresAt > now {
                    // Noch laufend — Referenz übernehmen (erste nehmen, falls mehrere)
                    await MainActor.run {
                        if self.currentLiveActivity == nil {
                            self.currentLiveActivity = activity
                        }
                    }
                } else {
                    // Wirklich abgelaufen → Zombie beenden
                    await activity.end(nil, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
                }
            }
            // Pending-End-Marker sauber räumen — alle bekannten Zombies sind durch
            await MainActor.run {
                UserDefaults.standard.removeObject(forKey: "ud_liveActivitiesPendingEnd")
            }
        }

        startExpiryTimer()

        // Stale Demo-UserDefaults aus früheren Builds aufräumen — falls jemand
        // diese Keys noch von der Beta-Phase im UserDefaults stehen hat.
        UserDefaults.standard.removeObject(forKey: "dropsDemoSeed")
        UserDefaults.standard.removeObject(forKey: "dropsDemoOff")

        // ── Drops+ Entitlements prüfen ────────────────────────────────────
        Task {
            await DropsStoreManager.shared.refreshEntitlements()
            // NUR auf true hochsetzen — nie überschreiben.
            // Sonst würde der Admin-gewährte Plus-Status (aus Firebase, ohne StoreKit-Purchase)
            // vom refreshEntitlements()-Callback auf false zurückgesetzt.
            if DropsStoreManager.shared.isPlusUser {
                self.isPlusUser = true
            }
        }

        // ── Drops+ Status live synchronisieren (nach Kauf / Widerruf / Restore) ──
        NotificationCenter.default.addObserver(
            forName: .dropsPlusStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let isPlus = notification.userInfo?["isPlus"] as? Bool
            else { return }
            // Trotz queue: .main verlangt Swift 6 explizites MainActor-Hopping.
            Task { @MainActor in self.isPlusUser = isPlus }
        }

        // Benachrichtigungs-, Standort- und Bluetooth-Berechtigungen werden NICHT
        // beim App-Start angefragt — das passiert im Onboarding (AppIntroStep /
        // Permission-Schritte) im richtigen Kontext, damit der User versteht wofür.
        // Nach Login triggert requestPermissionsIfNeeded() in LinkUpApp.swift
        // ggf. Nachfragen falls der User im Onboarding abgelehnt hat.
        // Abgelaufene Begegnungen ohne Bestätigung → No-Show werten
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.processExpiredEncounters()
        }

        // Auth-Listener: reagiert auf Logout/Token-Ablauf zur Laufzeit
        _ = FirebaseAuth.Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                let onboarded = UserDefaults.standard.bool(forKey: "hasOnboarded")
                if user == nil && onboarded && self?.isAuthenticated == true {
                    // User wurde extern ausgeloggt oder Token ungültig
                    print("[auth] stateDidChange: user=nil while onboarded — setting isAuthenticated=false")
                    self?.isAuthenticated = false
                }
                // Einloggen (user != nil) wird nur über den Onboarding-Flow
                // getriggert — kein automatisches isAuthenticated = true hier,
                // da sonst ein anonymer Firebase-User die App öffnet.
            }
        }
    }

    // MARK: - Session Timeout

    /// Wird beim App-Wechsel in den Hintergrund aufgerufen — speichert den Zeitstempel.
    func recordBackgrounded() {
        UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate,
                                  forKey: UDKey.backgroundedAt)
    }

    /// Wird beim App-Rückkehr in den Vordergrund aufgerufen.
    /// Prüft Permissions + ob der Firebase-Account noch existiert.
    /// Session-Lock mit Face ID wurde entfernt — zu unterbrechend für die UX.
    func checkSessionTimeout() {
        let ud = UserDefaults.standard
        evaluateCorePermissions()
        // Auch ohne Timeout: Firebase-Konto prüfen (z.B. extern gelöscht)
        validateFirebaseAccount()
        // Alten Timestamp räumen falls vorhanden (Legacy-Daten aus früheren Versionen)
        ud.removeObject(forKey: UDKey.backgroundedAt)
    }

    /// Prüft ob Standort- UND Bluetooth-Berechtigung verweigert sind.
    /// Setzt `needsCorePermissions = true` wenn beide weg sind; sonst false.
    /// MainTabView reagiert darauf mit einem blockierenden Settings-Sheet.
    func evaluateCorePermissions() {
        let locStatus = CLLocationManager().authorizationStatus
        let locDenied = (locStatus == .denied || locStatus == .restricted)

        // Bluetooth: .notDetermined → noch nicht gefragt (nicht blocken), .denied → blockieren
        let btAuth = CBCentralManager.authorization
        let btDenied = (btAuth == .denied || btAuth == .restricted)

        let bothDenied = locDenied && btDenied
        if needsCorePermissions != bothDenied {
            needsCorePermissions = bothDenied
        }
    }

    /// Prüft ob der Firebase-Account noch existiert (z.B. nach externer Löschung).
    /// Falls nicht → lokal ausloggen.
    private func validateFirebaseAccount() {
        guard let user = FirebaseAuth.Auth.auth().currentUser else { return }
        user.reload { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let nsError = error as? NSError {
                    let code = FirebaseAuth.AuthErrorCode(rawValue: nsError.code)
                    // Nur bei eindeutiger Konto-Löschung/-Sperrung ausloggen.
                    // userTokenExpired: Firebase erneuert Token selbst — kein Logout bei Netzwerkproblemen.
                    if code == .userNotFound || code == .userDisabled {
                        print("[auth] validateFirebaseAccount: account gone (code=\(code?.rawValue ?? -1)) → clearLocalData")
                        self.clearLocalData()
                    } else {
                        print("[auth] validateFirebaseAccount: non-fatal error \(nsError.code) — keeping session")
                    }
                }
            }
        }
    }

    // MARK: - Persistence

    private var selfieURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("drops_selfie.jpg")
    }

    /// Löscht das Konto: alle persönlichen Daten aus RTDB/Firestore/Storage + Indizes
    /// werden entfernt, der User wird ausgeloggt. Der Firebase-Auth-Account bleibt als
    /// technische Hülle bestehen (enthält keine PII) und wird mit einem `deletedAt`-
    /// Marker versehen. Meldet sich der User erneut mit derselben Apple-ID an, erkennt
    /// `handlePostLoginResurrection()` den Marker und startet das Onboarding von vorn
    /// — aus User-Sicht wie ein komplett neues Konto.
    ///
    /// Dieser Ansatz vermeidet den Apple-Reauth-Sheet (den Firebase bei `user.delete()`
    /// für Apple-Sign-In-User erzwingen würde) und ist DSGVO-konform: alle PII sind
    /// aus allen Stores weg.
    func deleteAccount(completion: @escaping (String?) -> Void = { _ in }) {
        guard let user = FirebaseAuth.Auth.auth().currentUser else {
            print("[deleteAccount] Kein currentUser — nur lokaler Cleanup")
            clearLocalData()
            completion(nil)
            return
        }

        let uid = user.uid
        print("[deleteAccount] Start uid=\(uid)")

        Task { @MainActor in
            // 1. Alle persönlichen Daten aus Firebase entfernen (Direktpfade, 10s Timeout)
            print("[deleteAccount] Schritt 1: Firebase-Daten löschen…")
            await Self.withTimeout(seconds: 10) {
                await RealtimeDBManager.shared.deleteUserData(uid: uid)
            }
            print("[deleteAccount] Schritt 1 ✓")

            // 2. Tombstone setzen, damit ein Wiederlogin mit derselben Apple-ID
            //    als Neuregistrierung behandelt wird (siehe handlePostLoginResurrection).
            print("[deleteAccount] Schritt 2: Tombstone setzen…")
            await Self.withTimeout(seconds: 5) {
                await RealtimeDBManager.shared.markAccountDeleted(uid: uid)
            }
            print("[deleteAccount] Schritt 2 ✓")

            // 3. Lokale Daten + Logout
            print("[deleteAccount] Schritt 3: Lokale Daten + Logout…")
            UserDefaults.standard.removeObject(forKey: "hasOnboarded")
            UserDefaults.standard.removeObject(forKey: "hasSeenWelcome")
            // Quick-Login-Daten weg — sonst würde der Name nach Löschung
            // im Welcome-Screen noch auftauchen.
            UserDefaults.standard.removeObject(forKey: "ud_lastLoginName")
            UserDefaults.standard.removeObject(forKey: "ud_lastProfileImageURL")
            // Apple-Given-Name + Relay-Email auch entfernen — sonst wird der
            // alte Apple-Vorname beim Re-Register vorgeblendet im Namensfeld.
            // Apple sendet beides nur beim ALLERERSTEN Sign-In, also haben
            // wir nach Re-Register beide nicht mehr — User gibt frischen
            // Namen ein, ohne alte Defaults.
            UserDefaults.standard.removeObject(forKey: "ud_appleGivenName")
            UserDefaults.standard.removeObject(forKey: "ud_appleEmail")
            // Heimzone (persönliche Standort-Präferenz) wird beim normalen
            // Logout absichtlich behalten — nur bei Account-Löschung weg.
            self.homeZoneCoordinate = nil
            self.homeZoneRadius     = 150
            UserDefaults.standard.removeObject(forKey: UDKey.homeZoneLat)
            UserDefaults.standard.removeObject(forKey: UDKey.homeZoneLng)
            UserDefaults.standard.removeObject(forKey: UDKey.homeZoneRadius)
            // Erst-Host-Bonus-Flag zurücksetzen, damit ein wiederkehrender
            // User (Re-Register nach Account-Löschung) den +10-Bonus
            // erneut beim ersten erfolgreichen Hosten bekommen kann.
            UserDefaults.standard.removeObject(forKey: UDKey.firstHostBonusReceived)
            self.clearLocalData()
            print("[deleteAccount] Fertig — isAuthenticated=\(self.isAuthenticated)")

            completion(nil)
        }
    }

    /// Führt eine Void-async-Operation aus und bricht nach `seconds` ab.
    /// WICHTIG: Nutzt Task.detached + NSLock statt withTaskGroup, weil
    /// withTaskGroup auf ALLE Child-Tasks wartet (auch gecancelte). Firebase-
    /// Async-APIs reagieren nicht auf Cancellation → würden sonst ewig hängen.
    /// Mit diesem Pattern geht's weiter sobald Timer ODER Operation fertig ist.
    private static func withTimeout(seconds: Int, operation: @escaping @Sendable () async -> Void) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let state = TimeoutGuard()
            Task.detached {
                await operation()
                state.resume { cont.resume() }
            }
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                state.resume { cont.resume() }
            }
        }
    }

    /// Wie `withTimeout`, aber gibt das Operation-Ergebnis zurück (oder Fallback bei Timeout).
    private static func withTimeoutReturning<T: Sendable>(
        seconds: Int, fallback: T,
        operation: @escaping @Sendable () async -> T
    ) async -> T {
        await withCheckedContinuation { (cont: CheckedContinuation<T, Never>) in
            let state = TimeoutGuard()
            Task.detached {
                let result = await operation()
                state.resume { cont.resume(returning: result) }
            }
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                state.resume { cont.resume(returning: fallback) }
            }
        }
    }

    /// Meldet den User ab — clears alle lokalen Daten, **behält aber die
    /// Firebase-Auth-Session**. So kann der Quick-Login-Button beim nächsten
    /// Start direkt re-authentifizieren ohne das Apple-System-Sheet zu öffnen.
    func logout() {
        clearLocalData(signOutFirebase: false)
    }

    /// Löscht alle lokalen Daten. Firebase-Logout ist optional — wird beim
    /// `deleteAccount`-Pfad gebraucht (true), beim normalen Logout NICHT (false),
    /// damit Quick-Login schnell und ohne Apple-Sheet funktioniert.
    func clearLocalData(signOutFirebase: Bool = true) {
        // Friends-Observer abmelden, damit er beim nächsten User nicht auf der
        // alten UID hängen bleibt
        stopObservingFriends()
        friends = []
        knownFriendUIDs = []

        // ── 1. UserDefaults leeren ────────────────────────────────────────
        let ud = UserDefaults.standard
        let allKeys = [
            UDKey.userName, UDKey.userEmoji,
            UDKey.isUnderageBlocked, UDKey.userBirthdate,
            UDKey.userGender, UDKey.blockedUsers,
            UDKey.selectedAgeGroups, UDKey.userInterests, UDKey.radiusFilter,
            UDKey.unavailabilityReason, UDKey.wasAgeRestricted,
            UDKey.reliabilityTotal, UDKey.reliabilityShows, UDKey.reliabilityNoShows,
            UDKey.firebaseUID, UDKey.appleEmail, UDKey.isAdmin
        ]
        allKeys.forEach { ud.removeObject(forKey: $0) }
        // WICHTIG: hasOnboarded und Quick-Login-Daten NICHT löschen.
        // So sieht der User nach Session-Timeout den Login-Screen (nicht das Voll-Onboarding).
        // mapStyleMode und prefersDarkOnboarding sind harmlose UI-Präferenzen → auch behalten.
        // Nur wirklich sensitives löschen:
        ud.removeObject(forKey: "savedPhoneNumber")
        ud.removeObject(forKey: "savedPhoneDialCode")
        // WelcomeSheet nach Logout immer zurücksetzen — beim nächsten Login
        // (auch Account-Wechsel auf demselben Gerät) soll der Sheet erscheinen
        // damit Permissions erst danach angefragt werden.
        ud.removeObject(forKey: "hasSeenWelcome")

        // ── 2. Selfie-Datei löschen + Image-Cache räumen ──────────────────
        try? FileManager.default.removeItem(at: selfieURL)
        // ProfileImageCache cached Bilder per URL — sonst kommt beim Re-Login
        // mit demselben UID das alte Profilbild zurück (Cache-Hit).
        ProfileImageCache.shared.clear()
        // Live-Activity-Cache (App-Group-Container) auch räumen, damit der
        // Drop-Widget kein altes Profilbild zeigt.
        cachedLAProfileImageFilename = ""

        // ── 3. In-Memory-State zurücksetzen ───────────────────────────────
        // Wichtig: AppStore-Instanz bleibt beim Account-Wechsel dieselbe,
        // daher müssen alle @Published-Werte explizit zurückgesetzt werden.
        currentUser.name          = ""
        currentUser.emoji         = "😊"
        currentUser.isAvailable   = false
        currentUser.statusMessage = tr("models.status_tap_available")
        selfieImage               = nil
        userBirthdate             = nil
        isAdmin                   = false
        isUnderageBlocked         = false
        userGender                = ""
        blockedUserNames          = []
        selectedAgeGroups         = AgeGroup.allCases
        ageFilterMin              = 18
        ageFilterMax              = 99
        userInterests             = []
        radiusFilter              = 2000
        unavailabilityReason      = ""
        reliabilityScore          = ReliabilityScore(totalCommits: 0, showUps: 0, noShows: 0)
        activeDrops               = []
        // Heimzone bleibt erhalten — sie ist eine persönliche Standort-
        // Präferenz, kein Session-Datum. Beim normalen Logout (Re-Login auf
        // demselben Gerät) soll der User seinen Heim-Anker behalten. Erst
        // bei Account-Löschung entfernt deleteAccount() sie explizit.
        profileImageURL           = nil
        geocodedDropLocationTitle = ""

        // ── 4. Dynamic Island beenden ─────────────────────────────────────
        endDropLiveActivity()

        // ── 5. Firebase ausloggen (optional) + Session beenden ────────────
        // Quick-Login soll ohne Apple-Sheet funktionieren — dafür muss
        // Firebase-Auth aktiv bleiben. Nur bei echter Account-Löschung
        // wirklich aus Firebase ausloggen.
        print("[auth] clearLocalData → signOutFirebase=\(signOutFirebase), isAuthenticated=false (caller: \(Thread.callStackSymbols.dropFirst(1).first ?? ""))")
        if signOutFirebase {
            try? FirebaseAuth.Auth.auth().signOut()
        }
        isAuthenticated = false
    }

    func saveAll() {
        let ud = UserDefaults.standard
        ud.set(currentUser.name,  forKey: UDKey.userName)
        ud.set(currentUser.emoji, forKey: UDKey.userEmoji)
        if isAdmin { ud.set(true, forKey: UDKey.isAdmin) }  // Admin-Flag cachen
        ud.set(isUnderageBlocked, forKey: UDKey.isUnderageBlocked)
        if let bd = userBirthdate {
            ud.set(bd.timeIntervalSinceReferenceDate, forKey: UDKey.userBirthdate)
        } else {
            ud.removeObject(forKey: UDKey.userBirthdate)
        }
        ud.set(userGender,           forKey: UDKey.userGender)
        ud.set(userPhone,            forKey: UDKey.userPhone)
        ud.set(genderFilterEnabled,  forKey: UDKey.genderFilterEnabled)
        ud.set(activityCategoryFilter, forKey: UDKey.activityCategoryFilter)
        ud.set(feedDistanceFilter.rawValue, forKey: UDKey.feedDistanceFilter)
        ud.set(feedTonightOnly,      forKey: UDKey.feedTonightOnly)
        ud.set(Array(blockedUserNames),                       forKey: UDKey.blockedUsers)
        ud.set(selectedAgeGroups.map { $0.rawValue },         forKey: UDKey.selectedAgeGroups)
        ud.set(ageFilterMin, forKey: UDKey.ageFilterMin)
        ud.set(ageFilterMax, forKey: UDKey.ageFilterMax)
        ud.set(userInterests,                                  forKey: UDKey.userInterests)
        ud.set(radiusFilter,                                  forKey: UDKey.radiusFilter)
        ud.set(notificationRadius,                            forKey: UDKey.notificationRadius)
        if let pnc = pendingNameChange {
            ud.set(pnc, forKey: UDKey.pendingNameChange)
        } else {
            ud.removeObject(forKey: UDKey.pendingNameChange)
        }
        if let lncd = lastNameChangeDate {
            ud.set(lncd.timeIntervalSinceReferenceDate, forKey: UDKey.lastNameChangeDate)
        } else {
            ud.removeObject(forKey: UDKey.lastNameChangeDate)
        }
        ud.set(unavailabilityReason,                          forKey: UDKey.unavailabilityReason)
        if let hz = homeZoneCoordinate {
            ud.set(hz.latitude,  forKey: UDKey.homeZoneLat)
            ud.set(hz.longitude, forKey: UDKey.homeZoneLng)
        } else {
            ud.removeObject(forKey: UDKey.homeZoneLat)
            ud.removeObject(forKey: UDKey.homeZoneLng)
        }
        ud.set(homeZoneRadius, forKey: UDKey.homeZoneRadius)
        ud.set(isAgeRestricted, forKey: UDKey.wasAgeRestricted)
        ud.set(reliabilityScore.totalCommits,      forKey: UDKey.reliabilityTotal)
        ud.set(reliabilityScore.showUps,           forKey: UDKey.reliabilityShows)
        ud.set(reliabilityScore.noShows,           forKey: UDKey.reliabilityNoShows)
        ud.set(reliabilityScore.hostSuccesses,     forKey: UDKey.reliabilityHostOK)
        ud.set(reliabilityScore.streakBonusPoints, forKey: UDKey.reliabilityStreakB)
        ud.set(reliabilityScore.firstArrivalPoints, forKey: UDKey.reliabilityFirstB)
        ud.set(reliabilityScore.dropInvitesPoints, forKey: UDKey.reliabilityInviteB)
        ud.set(reliabilityScore.newcomerHostPoints, forKey: UDKey.reliabilityNewcB)
        ud.set(reliabilityScore.appInvitesPoints,  forKey: UDKey.reliabilityAppInvB)
        ud.set(reliabilityScore.creationBonusPoints, forKey: UDKey.reliabilityCreateB)
        ud.set(reliabilityScore.boostBonusPoints, forKey: UDKey.reliabilityBoostB)
        ud.set(reliabilityScore.currentStreak,     forKey: UDKey.reliabilityStreak)
        // Drop-Verlauf persistieren — damit beendete Drops und die
        // Statistik einen App-Restart überleben.
        if let pastData = try? JSONEncoder().encode(pastDrops) {
            ud.set(pastData, forKey: UDKey.pastDrops)
        }
        saveSelfie()

        // Benutzer-Settings zusätzlich nach Firebase spiegeln — so überleben Radius,
        // Altersfilter, Interests etc. einen Logout/Re-Login oder Gerätewechsel.
        // (UserDefaults wird beim Logout bewusst geleert → Firebase ist die Truth-Source.)
        if FirebaseAuth.Auth.auth().currentUser != nil {
            RealtimeDBManager.shared.saveUserSettings(
                radiusFilter:           radiusFilter,
                ageFilterMin:           ageFilterMin,
                ageFilterMax:           ageFilterMax,
                selectedAgeGroups:      selectedAgeGroups.map { $0.rawValue },
                userInterests:          userInterests,
                blockedUsers:           Array(blockedUserNames),
                unavailabilityReason:   unavailabilityReason,
                genderFilterEnabled:    genderFilterEnabled,
                activityCategoryFilter: activityCategoryFilter
            )
        }
    }

    /// Wendet ein `UserSettingsSnapshot` aus Firebase auf den Store an.
    /// Nil-Felder werden ignoriert (lokaler Default bleibt stehen).
    /// Persistiert die Werte anschließend auch in UserDefaults, damit ein
    /// Offline-Start nicht wieder auf Default fällt.
    func applyRemoteUserSettings(_ s: UserSettingsSnapshot) {
        let ud = UserDefaults.standard
        if let r = s.radiusFilter, r > 0 {
            // Free-User dürfen max. 2 km — aber nur wenn Drops+ überhaupt
            // als Feature aktiv ist. Im Launch ohne Plus → kein Cap.
            let needsCap = FeatureFlags.dropsPlusEnabled && !isPlusUser
            let clamped = (needsCap && r > 2000) ? 2000 : r
            radiusFilter = clamped
            ud.set(clamped, forKey: UDKey.radiusFilter)
        }
        if let minA = s.ageFilterMin {
            ageFilterMin = minA
            ud.set(minA, forKey: UDKey.ageFilterMin)
        }
        if let maxA = s.ageFilterMax, maxA > 0 {
            ageFilterMax = maxA
            ud.set(maxA, forKey: UDKey.ageFilterMax)
        }
        if let groups = s.selectedAgeGroups, !groups.isEmpty {
            let parsed = groups.compactMap { AgeGroup(rawValue: $0) }
            if !parsed.isEmpty {
                selectedAgeGroups = parsed
                ud.set(groups, forKey: UDKey.selectedAgeGroups)
            }
        }
        if let interests = s.userInterests {
            userInterests = interests
            ud.set(interests, forKey: UDKey.userInterests)
        }
        if let blocked = s.blockedUsers {
            blockedUserNames = Set(blocked)
            ud.set(blocked, forKey: UDKey.blockedUsers)
        }
        if let reason = s.unavailabilityReason {
            unavailabilityReason = reason
            ud.set(reason, forKey: UDKey.unavailabilityReason)
        }
        if let g = s.genderFilterEnabled {
            genderFilterEnabled = g
            ud.set(g, forKey: UDKey.genderFilterEnabled)
        }
        if let cat = s.activityCategoryFilter {
            activityCategoryFilter = cat
            ud.set(cat, forKey: UDKey.activityCategoryFilter)
        }
    }

    /// Schreibt den aktuellen Zuverlässigkeits-Score in Firestore,
    /// damit andere User den echten Wert sehen können.
    /// Zusätzlich wird die kompakte `reliabilityPoints`-Zahl in die RTDB
    /// unter `users/{uid}/reliabilityPoints` gespiegelt — so können
    /// Freunde-Observer + Drop-Pins den echten Score ohne Firestore-Call lesen.
    private func pushReliabilityScoreToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let points = reliabilityScore.points
        Firestore.firestore()
            .collection("users").document(uid)
            .setData([
                "reliabilityTotal":        reliabilityScore.totalCommits,
                "reliabilityShows":        reliabilityScore.showUps,
                "reliabilityNoShows":      reliabilityScore.noShows,
                "reliabilityHostOK":       reliabilityScore.hostSuccesses,
                "reliabilityStreakBonus":  reliabilityScore.streakBonusPoints,
                "reliabilityFirstBonus":   reliabilityScore.firstArrivalPoints,
                "reliabilityInviteBonus":  reliabilityScore.dropInvitesPoints,
                "reliabilityNewcomerBonus": reliabilityScore.newcomerHostPoints,
                "reliabilityAppInviteBonus": reliabilityScore.appInvitesPoints,
                "reliabilityCreationBonus": reliabilityScore.creationBonusPoints,
                "reliabilityBoostBonus":   reliabilityScore.boostBonusPoints,
                "reliabilityCurrentStreak": reliabilityScore.currentStreak,
                "reliabilityPoints":       points
            ], merge: true)
        // Mirror in RTDB (read-path für Freundes-Observer + Drop-Pin-Badges)
        RealtimeDBManager.shared.setMyReliabilityPoints(points)
    }

    /// Stellt den Reliability-Score aus Firestore wieder her — wichtig nach
    /// Account-Wechsel oder Neuinstallation, wenn UserDefaults leer sind.
    /// Wird beim Login aufgerufen. Überschreibt lokale Daten nur wenn Firestore
    /// einen höheren oder gleichwertigen Score hat (verhindert Downgrade).
    func syncReliabilityFromFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("users").document(uid).getDocument { [weak self] snap, _ in
            guard let self, let data = snap?.data() else { return }
            let remoteTotal = data["reliabilityTotal"] as? Int ?? 0
            // Kein Firestore-Eintrag vorhanden → nichts tun
            guard remoteTotal > 0 || (data["reliabilityPoints"] as? Int ?? 0) > 0 else { return }
            // Nur überschreiben wenn Firestore-Wert größer als lokaler (verhindert Datenverlust)
            let localPoints = self.reliabilityScore.points
            let remotePoints = data["reliabilityPoints"] as? Int ?? 0
            guard remotePoints > localPoints else { return }
            let ud = UserDefaults.standard
            let score = ReliabilityScore(
                totalCommits:        data["reliabilityTotal"]          as? Int ?? 0,
                showUps:             data["reliabilityShows"]          as? Int ?? 0,
                noShows:             data["reliabilityNoShows"]        as? Int ?? 0,
                hostSuccesses:       data["reliabilityHostOK"]         as? Int ?? 0,
                streakBonusPoints:   data["reliabilityStreakBonus"]    as? Int ?? 0,
                firstArrivalPoints:  data["reliabilityFirstBonus"]     as? Int ?? 0,
                dropInvitesPoints:   data["reliabilityInviteBonus"]    as? Int ?? 0,
                newcomerHostPoints:  data["reliabilityNewcomerBonus"]  as? Int ?? 0,
                appInvitesPoints:    data["reliabilityAppInviteBonus"] as? Int ?? 0,
                creationBonusPoints: data["reliabilityCreationBonus"]  as? Int ?? 0,
                boostBonusPoints:    data["reliabilityBoostBonus"]     as? Int ?? 0,
                currentStreak:       data["reliabilityCurrentStreak"]  as? Int ?? 0
            )
            DispatchQueue.main.async {
                self.reliabilityScore = score
                ud.set(score.totalCommits,        forKey: UDKey.reliabilityTotal)
                ud.set(score.showUps,             forKey: UDKey.reliabilityShows)
                ud.set(score.noShows,             forKey: UDKey.reliabilityNoShows)
                ud.set(score.hostSuccesses,       forKey: UDKey.reliabilityHostOK)
                ud.set(score.streakBonusPoints,   forKey: UDKey.reliabilityStreakB)
                ud.set(score.firstArrivalPoints,  forKey: UDKey.reliabilityFirstB)
                ud.set(score.dropInvitesPoints,   forKey: UDKey.reliabilityInviteB)
                ud.set(score.newcomerHostPoints,  forKey: UDKey.reliabilityNewcB)
                ud.set(score.appInvitesPoints,    forKey: UDKey.reliabilityAppInvB)
                ud.set(score.creationBonusPoints, forKey: UDKey.reliabilityCreateB)
                ud.set(score.boostBonusPoints,    forKey: UDKey.reliabilityBoostB)
                ud.set(score.currentStreak,       forKey: UDKey.reliabilityStreak)
                // RTDB-Mirror aktualisieren
                RealtimeDBManager.shared.setMyReliabilityPoints(score.points)
            }
        }
    }

    func saveSelfie() {
        guard let img = selfieImage,
              let data = img.jpegData(compressionQuality: 0.75) else {
            print("[selfie] saveSelfie: selfieImage ist nil oder JPEG-Encoding fehlgeschlagen")
            return
        }
        print("[selfie] saveSelfie: \(data.count) bytes, lokal speichern…")
        // 1. Lokal speichern
        let localURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("drops_selfie.jpg")
        try? data.write(to: localURL)
        // 2. Firebase Storage Upload → URL in Firestore speichern
        guard let uid = Auth.auth().currentUser?.uid else {
            print("[selfie] saveSelfie: kein Auth-User → Upload übersprungen")
            return
        }
        let ref = Storage.storage().reference().child("profileImages/\(uid).jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        ref.putData(data, metadata: meta) { [weak self] _, error in
            if let error = error {
                print("[selfie] Storage putData ✗: \(error.localizedDescription)")
                return
            }
            print("[selfie] Storage putData ✓ — hole downloadURL…")
            ref.downloadURL { url, error in
                guard let self = self, let url = url, error == nil else {
                    print("[selfie] downloadURL ✗: \(error?.localizedDescription ?? "kein URL")")
                    return
                }
                let urlString = url.absoluteString
                print("[selfie] Upload ✓ → \(urlString)")
                // Firestore: users/{uid} → profileImageURL (für den eigenen Profil-Load)
                Firestore.firestore()
                    .collection("users").document(uid)
                    .setData(["profileImageURL": urlString], merge: true)
                // Realtime DB: users/{uid}/profileImageURL — damit Freunde-Avatare
                // mit einem einzigen Query gleich den URL mitbekommen.
                RealtimeDBManager.shared.setMyProfileImageURL(urlString)
                DispatchQueue.main.async {
                    self.profileImageURL = urlString
                }
                // Persistiert für den Quick-Login-Button auf Welcome-Screen
                UserDefaults.standard.set(urlString, forKey: "ud_lastProfileImageURL")
            }
        }
    }

    func loadProfileImageURL(retriesLeft: Int = 4) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("[selfie] loadProfileImageURL: kein Auth-User")
            // Direkt nach einem signOut/re-signIn kann currentUser kurz nil sein —
            // einmal kurz warten und erneut versuchen.
            if retriesLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.loadProfileImageURL(retriesLeft: retriesLeft - 1)
                }
            }
            return
        }
        Firestore.firestore()
            .collection("users").document(uid)
            .getDocument { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    let ns = error as NSError
                    // Bei ALLEN transienten Firestore-Fehlern retryen, nicht nur "offline".
                    // Direkt nach Re-Auth kann der Token noch nicht propagiert sein
                    // → permission-denied (7) oder unauthenticated (16). Ein kurzer
                    // Backoff löst das fast immer.
                    let transientCodes: Set<Int> = [
                        4,   // deadline-exceeded
                        7,   // permission-denied (oft direkt nach re-auth)
                        8,   // unavailable / offline
                        13,  // internal
                        14,  // unavailable (alt)
                        16   // unauthenticated
                    ]
                    let isTransient = ns.domain == "FIRFirestoreErrorDomain"
                        && transientCodes.contains(ns.code)
                    if isTransient && retriesLeft > 0 {
                        let delay = 2.0 + Double(4 - retriesLeft) * 1.0   // 2s, 3s, 4s, 5s
                        print("[selfie] loadProfileImageURL transient (\(ns.code)) — retry in \(delay)s (noch \(retriesLeft) Versuche)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self.loadProfileImageURL(retriesLeft: retriesLeft - 1)
                        }
                    } else {
                        print("[selfie] loadProfileImageURL Firestore-Fehler (\(ns.code)): \(error.localizedDescription)")
                        // Harter Fehler → RTDB als Fallback (dort liegt die URL auch)
                        DispatchQueue.main.async { self.loadProfileImageURLFromRTDBFallback() }
                    }
                    return
                }
                let data = snapshot?.data()
                if let url = data?["profileImageURL"] as? String, !url.isEmpty {
                    print("[selfie] loadProfileImageURL ✓ URL: \(url.prefix(80))")
                    DispatchQueue.main.async { self.profileImageURL = url }
                    // Persistiert für den Quick-Login-Button — überlebt Logout
                    UserDefaults.standard.set(url, forKey: "ud_lastProfileImageURL")
                    // Sofort für Live Activity vorbereiten — Download in den
                    // App-Group-Container, damit das Widget beim nächsten Drop
                    // das Profilbild synchron hat (kein Race mehr).
                    Task {
                        let filename = await LiveActivityImageCache.shared.cacheImage(urlString: url)
                        if !filename.isEmpty {
                            await MainActor.run { self.cachedLAProfileImageFilename = filename }
                        }
                    }
                } else {
                    print("[selfie] loadProfileImageURL: keine profileImageURL im Firestore-Dokument — RTDB-Fallback")
                    DispatchQueue.main.async { self.loadProfileImageURLFromRTDBFallback() }
                }
                if let phone = data?["phoneNumber"] as? String, !phone.isEmpty {
                    DispatchQueue.main.async {
                        self.userPhone = phone
                        UserDefaults.standard.set(phone, forKey: UDKey.userPhone)
                    }
                }
            }
    }

    /// Holt die Profilbild-URL aus der Realtime DB als Fallback, wenn Firestore
    /// leer/unzugänglich ist. Beim `saveSelfie` schreiben wir beide Stores parallel,
    /// hier lesen wir daher mit hoher Wahrscheinlichkeit einen Treffer.
    private func loadProfileImageURLFromRTDBFallback() {
        RealtimeDBManager.shared.loadMyProfileImageURL { [weak self] url in
            guard let self = self, let url = url, !url.isEmpty else {
                print("[selfie] RTDB-Fallback: keine profileImageURL gefunden")
                return
            }
            print("[selfie] RTDB-Fallback ✓ URL: \(url.prefix(80))")
            self.profileImageURL = url
            Task {
                let filename = await LiveActivityImageCache.shared.cacheImage(urlString: url)
                if !filename.isEmpty {
                    await MainActor.run { self.cachedLAProfileImageFilename = filename }
                }
            }
        }
    }

    /// Speichert die optionale Handynummer in Firestore (Persistenz) UND aktualisiert
    /// den phoneIndex in Realtime DB (für Kontakt-Matching durch andere User).
    /// Bei leerer Nummer wird der Index-Eintrag entfernt.
    func saveUserPhone(_ phone: String) {
        let oldPhone = userPhone
        userPhone = phone
        UserDefaults.standard.set(phone, forKey: UDKey.userPhone)

        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Firestore: Persistenz fürs Profil
        let value: Any = phone.isEmpty ? NSNull() : phone
        Firestore.firestore()
            .collection("users").document(uid)
            .setData(["phoneNumber": value], merge: true)

        // Realtime DB: phoneIndex für Discovery — alte Nummer räumen, neue eintragen
        let indexName = currentUser.name.isEmpty ? "Dazu-Nutzer" : currentUser.name
        RealtimeDBManager.shared.updatePhoneDiscoveryIndex(
            uid: uid, name: indexName, oldPhone: oldPhone, newPhone: phone
        )
    }

    private func loadAll() {
        let ud = UserDefaults.standard
        // Joiner-Session-Startzeit wiederherstellen (falls App mid-session gekillt)
        if let ts = ud.object(forKey: UDKey.joinSessionStartedAt) as? Double {
            joinSessionStartedAt = Date(timeIntervalSince1970: ts)
        }
        // Pair-Cooldowns aus Firebase laden — überlebt App-Reinstall
        if let myUID = FirebaseAuth.Auth.auth().currentUser?.uid {
            RealtimeDBManager.shared.loadPairCooldowns(myUID: myUID) { [weak self] dict in
                guard let self else { return }
                for (uid, ts) in dict {
                    let date = Date(timeIntervalSince1970: ts)
                    guard Date().timeIntervalSince(date) < AppStore.pairCooldownSeconds else { continue }
                    UserDefaults.standard.set(date, forKey: self.pairCooldownKey(for: uid))
                }
            }
        }
        if let name = ud.string(forKey: UDKey.userName), !name.isEmpty  {
            currentUser.name  = name.capitalizedFirst
        }
        if let emoji = ud.string(forKey: UDKey.userEmoji), !emoji.isEmpty { currentUser.emoji = emoji }
        isUnderageBlocked = ud.bool(forKey: UDKey.isUnderageBlocked)
        if ud.bool(forKey: UDKey.isAdmin) { isAdmin = true }  // gecachtes Admin-Flag laden
        if let ti = ud.object(forKey: UDKey.userBirthdate) as? Double {
            userBirthdate = Date(timeIntervalSinceReferenceDate: ti)
        }
        userGender          = ud.string(forKey: UDKey.userGender) ?? ""
        userPhone           = ud.string(forKey: UDKey.userPhone)  ?? ""
        genderFilterEnabled = ud.bool(forKey: UDKey.genderFilterEnabled)
        activityCategoryFilter = ud.string(forKey: UDKey.activityCategoryFilter) ?? ""
        if let raw = ud.string(forKey: UDKey.feedDistanceFilter),
           let v = FeedDistanceFilter(rawValue: raw) {
            feedDistanceFilter = v
        }
        feedTonightOnly = ud.bool(forKey: UDKey.feedTonightOnly)
        if let blocked = ud.stringArray(forKey: UDKey.blockedUsers) {
            blockedUserNames = Set(blocked)
        }
        if let groups = ud.stringArray(forKey: UDKey.selectedAgeGroups), !groups.isEmpty {
            let parsed = groups.compactMap { AgeGroup(rawValue: $0) }
            selectedAgeGroups = parsed.isEmpty ? AgeGroup.allCases : parsed
        }
        if let interests = ud.stringArray(forKey: UDKey.userInterests) {
            userInterests = interests
        }
        if ud.object(forKey: UDKey.ageFilterMin) != nil {
            ageFilterMin = ud.integer(forKey: UDKey.ageFilterMin)
        }
        if ud.object(forKey: UDKey.ageFilterMax) != nil {
            let saved = ud.integer(forKey: UDKey.ageFilterMax)
            ageFilterMax = saved > 0 ? saved : 99
        }
        // Auto-Unlock: War vorher unter 18, ist jetzt 18+ → Altersgruppen freischalten
        let wasRestricted = ud.bool(forKey: UDKey.wasAgeRestricted)
        if wasRestricted && !isAgeRestricted, let age = userAge {
            selectedAgeGroups = AgeGroup.defaultVisible(for: age)
        }
        // Mindestalter 18 — keine Einschränkung mehr nötig
        let radius = ud.double(forKey: UDKey.radiusFilter)
        if radius > 0 { radiusFilter = radius }
        let notifRadius = ud.double(forKey: UDKey.notificationRadius)
        if notifRadius > 0 { notificationRadius = notifRadius }
        pendingNameChange = ud.string(forKey: UDKey.pendingNameChange)
        let lncdInterval = ud.double(forKey: UDKey.lastNameChangeDate)
        if lncdInterval > 0 { lastNameChangeDate = Date(timeIntervalSinceReferenceDate: lncdInterval) }
        // Observer reaktivieren wenn nach App-Neustart noch eine Anfrage offen ist
        if pendingNameChange != nil,
           let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
            startNameChangeResultObserver(uid: uid)
        }
        unavailabilityReason = ud.string(forKey: UDKey.unavailabilityReason) ?? ""
        let hzLat = ud.double(forKey: UDKey.homeZoneLat)
        let hzLng = ud.double(forKey: UDKey.homeZoneLng)
        if hzLat != 0 || hzLng != 0 {
            homeZoneCoordinate = CLLocationCoordinate2D(latitude: hzLat, longitude: hzLng)
        }
        let hzRadius = ud.double(forKey: UDKey.homeZoneRadius)
        if hzRadius > 0 { homeZoneRadius = hzRadius }
        // Zuverlässigkeitsscore laden — nur wenn schon Daten gespeichert sind
        let savedTotal = ud.integer(forKey: UDKey.reliabilityTotal)
        let savedShows = ud.integer(forKey: UDKey.reliabilityShows)
        let savedNoShows = ud.integer(forKey: UDKey.reliabilityNoShows)
        // integer(forKey:) gibt 0 zurück wenn der Key nicht existiert —
        // das ist korrekt: neue User starten bei 0/0/0
        if ud.object(forKey: UDKey.reliabilityTotal) != nil {
            reliabilityScore = ReliabilityScore(
                totalCommits: savedTotal,
                showUps:      savedShows,
                noShows:      savedNoShows,
                hostSuccesses:      ud.integer(forKey: UDKey.reliabilityHostOK),
                streakBonusPoints:  ud.integer(forKey: UDKey.reliabilityStreakB),
                firstArrivalPoints: ud.integer(forKey: UDKey.reliabilityFirstB),
                dropInvitesPoints:  ud.integer(forKey: UDKey.reliabilityInviteB),
                newcomerHostPoints: ud.integer(forKey: UDKey.reliabilityNewcB),
                appInvitesPoints:   ud.integer(forKey: UDKey.reliabilityAppInvB),
                creationBonusPoints:ud.integer(forKey: UDKey.reliabilityCreateB),
                boostBonusPoints:   ud.integer(forKey: UDKey.reliabilityBoostB),
                currentStreak:      ud.integer(forKey: UDKey.reliabilityStreak)
            )
        }
        // Selfie vom Disk laden
        if let data = try? Data(contentsOf: selfieURL),
           let img = UIImage(data: data) {
            selfieImage = img
        }
        // Drop-Verlauf laden — JSON aus UserDefaults
        if let data = ud.data(forKey: UDKey.pastDrops),
           let decoded = try? JSONDecoder().decode([PastDrop].self, from: data) {
            pastDrops = decoded
        }
    }

    // MARK: - Drop Expiry Timer

    private func startExpiryTimer() {
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanExpiredDrops()
            }
        }
    }

    private func cleanExpiredDrops() {
        let expired = activeDrops.filter { $0.isExpired }
        guard !expired.isEmpty else { return }

        for drop in expired {
            DropNotificationManager.cancelReminders(for: drop.id)
            // Drop aus Firebase entfernen → für neue User unsichtbar.
            // Der Drop bleibt in activeDrops und die Live Activity läuft weiter —
            // der Host sieht noch wer vor Ort ist und beendet manuell.
            RealtimeDBManager.shared.unpublishDrop(dropID: drop.id.uuidString)
        }
        // Drops bleiben in activeDrops (isExpired == true), werden im UI als
        // "abgelaufen" markiert. cancelDrop() entfernt sie dann sauber.
        saveAll()
    }

    // MARK: - Drop Join (sofort, kein Approval)

    /// Wer bei einem Drop vorbeischaut (für Host-Anzeige)
    var activeJoinNotifications: [JoinRequest] {
        joinRequests.filter { !$0.isExpired }
    }

    /// Direkt beitreten — kein Warten auf Bestätigung.
    /// Gibt `false` zurück wenn Cooldown noch aktiv oder User bereits in einem anderen Drop ist.
    @discardableResult
    func joinDrop(_ drop: MapAnnotationItem) -> Bool {
        // Kein Beitritt wenn eigener Drop aktiv oder bereits einem anderen beigetreten
        guard !isInActiveDrop else { return false }
        guard !hasJoinedDrop(dropID: drop.id) else { return false }
        // Service-Zone-Gate: User muss in einer der 5 Launch-Städte sein um zu joinen.
        guard !BetaConfig.cityRestrictionEnabled
                || ServiceCities.isInside(currentUser.coordinate)
        else { return false }
        // Cooldown prüfen: nach Verlassen 10 Min sperren
        if let leftAt = dropLeaveTimes[drop.id],
           Date().timeIntervalSince(leftAt) < AppStore.joinCooldown {
            return false
        }
        // Drop-Invite-Tracking: wenn der User via Universal Link hierher kam
        // und genau diesen Drop öffnet, wird's als Invite-Join markiert.
        // Der Host kriegt +5 sobald der ShowUp bestätigt ist.
        if pendingDropID == drop.id {
            markJoinAsInviteBased(dropID: drop.id, hostUID: drop.hostUID)
            pendingDropID = nil
        }
        let note = JoinRequest(
            id: UUID(), dropID: drop.id,
            dropEmoji: drop.emoji, dropActivity: drop.activity,
            requesterName: currentUser.name, requesterEmoji: currentUser.emoji,
            createdAt: Date(),
            dropCoordinate: drop.coordinate
        )
        joinRequests.append(note)
        activeDropAnnotation = drop
        setActiveJoin(drop.id)
        DropNotificationManager.scheduleExpiryReminders(for: drop)
        startDropLiveActivity(annotation: drop, isHost: false)
        Task { @MainActor in PushNotificationManager.shared.trackAction() }

        // ── Firebase: DropIn schreiben + Host benachrichtigen ──────────
        // Nur GPS schreiben wenn wirklich Fix vorhanden — nicht der
        // Default-München-Center. Sonst Joiner-Pin landet auf falschem
        // Standort beim Host. Updates kommen via updateJoinerLiveLocation.
        let uid = FirebaseAuth.Auth.auth().currentUser?.uid ?? currentUser.id.uuidString
        let isDefaultMunichLegacy = abs(currentUser.coordinate.latitude  - 48.1371) < 0.0005
                                  && abs(currentUser.coordinate.longitude - 11.5754) < 0.0005
        let legacyValidGPS = !isDefaultMunichLegacy
        RealtimeDBManager.shared.joinDrop(
            dropID: drop.id.uuidString,
            joinerID: uid,
            joinerName: currentUser.name,
            joinerEmoji: currentUser.emoji,
            joinerAge: userAge,
            joinerLat: legacyValidGPS ? currentUser.coordinate.latitude : nil,
            joinerLng: legacyValidGPS ? currentUser.coordinate.longitude : nil
        )
        // Auf DropIns des Hosts hören (falls der Host derselbe User auf anderem Gerät ist – Schutz)
        startObservingDropIns(forDropID: drop.id.uuidString)

        // First-Drop-Celebration: nur beim allerersten Join.
        maybeCelebrateFirstDrop(.joined)
        return true
    }

    func hasJoinedDrop(dropID: UUID) -> Bool {
        // Sowohl bereits accepted (in joinRequests) als auch noch pending
        // (myJoinRequestStatus == "pending" für genau diesen Drop) zählen
        // als "dabei". Vorher: nur accepted → User klickte "Bin dabei!"
        // bei Pending-Status, aber UI zeigte's nicht und nach Verlassen
        // hing der Pending-State weiter.
        if joinRequests.contains(where: { $0.dropID == dropID && !$0.isExpired }) {
            return true
        }
        if myJoinRequestStatus == "pending",
           activeDropAnnotation?.id == dropID {
            return true
        }
        return false
    }

    /// Verbleibende Cooldown-Sekunden für einen Drop (0 wenn frei).
    func joinCooldownRemaining(dropID: UUID) -> TimeInterval {
        guard let leftAt = dropLeaveTimes[dropID] else { return 0 }
        let remaining = AppStore.joinCooldown - Date().timeIntervalSince(leftAt)
        return max(0, remaining)
    }

    func leaveDropJoin(dropID: UUID) {
        // Score-Abzug nur im kritischen Fenster: 12–30 Min.
        // < 12 Min → noch schnell umentschieden, bevor jemand wirklich unterwegs ist → kein Abzug
        // 12–30 Min → die andere Person ist wahrscheinlich schon auf dem Weg → No-Show
        // > 30 Min → ausreichend teilgenommen → kein Abzug
        if let req = joinRequests.first(where: { $0.dropID == dropID }) {
            let elapsed = Date().timeIntervalSince(req.createdAt)
            if elapsed >= 12 * 60 && elapsed < 30 * 60 {
                reliabilityScore.totalCommits += 1
                // Score-Schutz für Drops+ ist als Feature angekündigt aber noch nicht aktiv
                reliabilityScore.noShows += 1   // Mitten drin abgebrochen = No-Show
                breakStreak()
                saveAll()                           // Score lokal persistieren
                pushReliabilityScoreToFirestore()   // Score für andere sichtbar machen
            }
        }
        joinRequests.removeAll { $0.dropID == dropID }

        // Pending Join-Request canceln: Firebase-Eintrag löschen, Observer
        // abmelden, lokalen Status reseten. Vorher blieb das Pending-Flag
        // hängen → "Bin dabei!" im Umgebungstab obwohl der User verlassen
        // hat, plus der Host bekam keine Cancel-Notification.
        let uid = FirebaseAuth.Auth.auth().currentUser?.uid ?? currentUser.id.uuidString
        RealtimeDBManager.shared.cancelJoinRequest(
            dropID: dropID.uuidString, joinerID: uid
        )
        if let handle = myJoinStatusObserverHandle {
            RealtimeDBManager.shared.removeJoinRequestObserver(handle, dropID: dropID.uuidString)
            myJoinStatusObserverHandle = nil
        }
        if activeDropAnnotation?.id == dropID {
            activeDropAnnotation = nil
        }
        myJoinRequestStatus = ""
        // Pending-State + Auto-Accept-Watcher canceln — sonst feuert der
        // 5-Min-Timer auf einen Drop den der User gerade verlassen hat.
        if pendingJoinDropID == dropID {
            pendingJoinDropID = nil
            pendingAutoAcceptTask?.cancel()
            pendingAutoAcceptTask = nil
            removePendingDropEndObserver()
        }

        if activeJoinedDropID == dropID { leaveActiveJoin() }
        DropNotificationManager.cancelReminders(for: dropID)
        endDropLiveActivity()
        // Cooldown starten
        dropLeaveTimes[dropID] = Date()
    }

    // MARK: - Age Groups

    var userAgeGroup: AgeGroup? {
        guard let age = userAge else { return nil }
        return AgeGroup.group(for: age)
    }

    /// Mindestalter 18 — keine Alterseinschränkung mehr
    var isAgeRestricted: Bool { false }

    func applyDefaultAgeGroups() {
        guard let age = userAge else { return }
        selectedAgeGroups = AgeGroup.defaultVisible(for: age)
        saveAll()
    }

    @Published var friendSuggestions: [FriendSuggestion] = []

    var userAge: Int? {
        guard let bd = userBirthdate else { return nil }
        return Calendar.current.dateComponents([.year], from: bd, to: Date()).year
    }

    func enforceAgeGuard() {
        if let age = userAge, age < 18 {
            isUnderageBlocked = true
            saveAll()
        }
    }

    // MARK: - Block

    @Published var blockedUserNames: Set<String> = []

    func blockUser(name: String) {
        guard name != currentUser.name else { return }
        blockedUserNames.insert(name)
        strangerDropsCache.removeAll { $0.name == name }
        saveAll()
    }

    // MARK: - Freunde entfernen

    /// Entfernt die Freundschaft mit dem User `theirUID` — beidseitig in Firebase.
    /// Lokal wird der Freund sofort aus `friends` genommen, damit die UI nicht auf
    /// die Observer-Aktualisierung warten muss.
    func removeFriend(theirUID: String) {
        guard !theirUID.isEmpty else { return }
        friends.removeAll { $0.firebaseUID == theirUID }
        knownFriendUIDs.remove(theirUID)
        RealtimeDBManager.shared.removeFriend(theirUID: theirUID)
    }

    // MARK: - Encounters

    @Published var encounters: [Encounter] = []

    var pendingEncounters: [Encounter] {
        // Live-Drops rausfiltern: ein Encounter zu einem laufenden Drop ist
        // noch nicht „pending zur Bestätigung" — der Drop läuft ja noch. Das
        // Profil-Tab-Badge soll erst nach Drop-Ende erscheinen.
        let live = liveDropIDsForEncounterFilter
        return encounters.filter { enc in
            guard !enc.confirmed && !enc.denied && !enc.isExpired else { return false }
            if let did = enc.dropID, live.contains(did) { return false }
            return true
        }
    }

    /// IDs der Drops, die gerade noch laufen (eigener oder beigetretener).
    /// Encounter mit einer dieser dropIDs werden im Profil ausgeblendet —
    /// sie sollen erst auftauchen, wenn der Drop wirklich vorbei ist.
    private var liveDropIDsForEncounterFilter: Set<String> {
        var ids = Set<String>()
        for d in activeDrops where !d.isExpired { ids.insert(d.id.uuidString) }
        if let joined = activeJoinedDropID { ids.insert(joined.uuidString) }
        return ids
    }

    /// Encounters, die in „Letzte Begegnungen" angezeigt werden sollen.
    /// Pre-erstellte Encounter (Accept/Join) werden ausgeblendet, solange
    /// ihr zugehöriger Drop noch läuft — sonst stünde der Treffende im
    /// Profil schon als Begegnung, obwohl man sich noch gar nicht
    /// getroffen hat. Legacy-Encounter ohne dropID bleiben sichtbar.
    var visibleEncounters: [Encounter] {
        let live = liveDropIDsForEncounterFilter
        return encounters.filter { enc in
            guard let did = enc.dropID else { return true }
            return !live.contains(did)
        }
    }

    func confirmEncounter(id: UUID) {
        if let i = encounters.firstIndex(where: { $0.id == id }) {
            encounters[i].confirmed = true
            generateFriendSuggestions(from: encounters[i])
            // Bestätigung → ShowUp zählt positiv
            reliabilityScore.totalCommits += 1
            reliabilityScore.showUps += 1
            applyStreakBonus()
            // Boost: +5 wenn die Umgebung gerade leer ist
            applyBoostBonusIfActive(reason: tr("models.reason_meeting"))
            saveAll()                           // Score lokal persistieren
            pushReliabilityScoreToFirestore()   // Score für andere sichtbar machen
            maybeAskForReview()                 // Review nach guten Show-Up-Meilensteinen
        }
    }

    /// Erhöht den Streak-Counter und vergibt +20 bei jedem 5er-Block.
    /// Aufrufen wenn ein ShowUp gezählt wird (confirmEncounter / BLE-Arrival / Host-Success).
    private func applyStreakBonus() {
        reliabilityScore.currentStreak += 1
        if reliabilityScore.currentStreak % 5 == 0 {
            reliabilityScore.streakBonusPoints += 30
        }
    }

    /// Bricht den Streak bei einem No-Show.
    private func breakStreak() {
        reliabilityScore.currentStreak = 0
    }

    // MARK: - Points-Toast Observer

    /// Startet den Combine-Observer, der bei jedem Anstieg des ReliabilityScores
    /// einen Toast emittiert. Wird einmalig nach `loadAll()` in `init` aufgerufen.
    private func startPointsToastObserver() {
        guard pointsToastCancellable == nil else { return }
        lastObservedPoints = reliabilityScore.points
        pointsToastReady = true

        pointsToastCancellable = $reliabilityScore
            .map(\.points)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPoints in
                guard let self = self, self.pointsToastReady else { return }
                let delta = newPoints - self.lastObservedPoints
                self.lastObservedPoints = newPoints
                guard delta > 0 else { return }
                // Letzter Toast wird durch neuen ersetzt — neue ID damit
                // SwiftUI ein .transition triggert. Reason wird vom letzten
                // Award-Pfad mitgegeben (z.B. "Drop besucht", "Host-Erfolg").
                let reason = self.nextPointsReason
                self.nextPointsReason = nil
                Haptic.pointsEarned()
                self.pointsToast = PointsToast(
                    delta: delta,
                    isPowerHour: self.isPowerHourActive,
                    reason: reason
                )
            }
    }

    // MARK: - Boost-Phase (Umgebungs-Tab leer → +Bonus)
    //
    // Wenn weniger als 5 Drops in der näheren Umgebung des Users sind, ist
    // die App "leer" — wir incentivieren in dem Moment Aktionen mit einem
    // Punkte-Bonus: einmal beim Erstellen, einmal beim Bestätigen eines
    // Treffens (entweder als Joiner via confirmEncounter oder als Host via
    // recordHostSuccess).
    //
    // Power-Hour: zu festgelegten Stoßzeiten verdoppelt sich der Boost-Bonus
    // (von +15 auf +25). Die Logik bleibt: BOOST-Bedingung muss erfüllt sein
    // (leere Umgebung). Power-Hour ist nur ein höherer Multiplikator on-top.
    static let boostThreshold = 5
    static let boostBonus     = 15
    static let powerHourBonus = 25

    // MARK: - Suggested Spots (Map "wo war zuletzt was los")
    //
    // Aggregiert die eigenen pastDrops nach ~150m-Grid und gibt die
    // Top 5 wiederkehrenden Spots zurück. Auf der Karte als subtile
    // Marker dargestellt — Hinweis "hier hast du schon X mal gedroppt".
    // Für Empty-State / neue User → leeres Array (kein Schaden).
    struct SuggestedSpot: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let activityEmoji: String
        let activityName: String
        let occurrences: Int
        let lastSeen: Date
    }

    var suggestedSpots: [SuggestedSpot] {
        guard !pastDrops.isEmpty else { return [] }
        // Grid-Bucket: 1° lat ≈ 111 km → 150 m ≈ 0.00135°
        let gridSize: Double = 0.00135
        struct Bucket {
            var coords: [CLLocationCoordinate2D] = []
            var emoji: String = ""
            var activity: String = ""
            var count: Int = 0
            var lastSeen: Date = .distantPast
        }
        var buckets: [String: Bucket] = [:]
        // pastDrops ist neueste zuerst → erste Iteration setzt emoji/activity
        // auf den jüngsten Wert (gut, falls Activity sich am Spot geändert hat).
        for past in pastDrops {
            guard let coord = past.coordinate else { continue }
            let bLat = (coord.latitude / gridSize).rounded() * gridSize
            let bLng = (coord.longitude / gridSize).rounded() * gridSize
            let key = "\(bLat),\(bLng)"
            var b = buckets[key] ?? Bucket()
            b.coords.append(coord)
            b.count += 1
            if b.lastSeen < past.date {
                b.lastSeen = past.date
                b.emoji    = past.activityEmoji
                b.activity = past.activityName
            }
            buckets[key] = b
        }
        return buckets.values
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { b in
                let n = Double(b.coords.count)
                let avgLat = b.coords.map(\.latitude).reduce(0, +)  / n
                let avgLng = b.coords.map(\.longitude).reduce(0, +) / n
                return SuggestedSpot(
                    id: "\(avgLat),\(avgLng)",
                    coordinate: CLLocationCoordinate2D(latitude: avgLat, longitude: avgLng),
                    activityEmoji: b.emoji,
                    activityName: b.activity,
                    occurrences: b.count,
                    lastSeen: b.lastSeen
                )
            }
    }

    // MARK: - Anti-Farm: Mindestdauer & Pair-Cooldown
    //
    // Schutz gegen Punkte-Farming mit zwei Accounts in einem Raum:
    //   1) Drop muss ≥ 15 min aktiv gewesen sein, sonst keine Punkte.
    //   2) Zwei UIDs können sich nur 1× alle 12h gegenseitig Punkte
    //      einbringen (Encounter-Bonus + Host-Newcomer-Bonus).
    // Beide Schichten kombiniert verhindern die häufigsten Farm-Setups
    // ohne ehrliche User zu treffen (15 min ist die Schwelle für ein
    // "echtes" Treffen, 12h trifft fast nie zwei reale Drops/Tag mit
    // derselben Person).
    static let minPaidDropDuration: TimeInterval = 15 * 60
    static let pairCooldownSeconds: TimeInterval = 12 * 60 * 60

    // MARK: - Presence Sharing (Opt-in)

    /// Wie oft schreibt der Client die eigene Position nach RTDB.
    /// 10 Min ist der Sweet Spot: aktuell genug damit „vor 22 min" stimmt,
    /// selten genug für Battery + RTDB-Kosten.
    static let presenceThrottleSeconds: TimeInterval = 10 * 60

    /// Schreibt die eigene Position nach RTDB `presence/{uid}`, sofern der User
    /// per Settings-Toggle eingewilligt hat, in DE ist und der letzte Write
    /// mind. `presenceThrottleSeconds` alt ist. Wird bei jedem relevanten
    /// Location-Update aufgerufen.
    func maybeWriteMyPresence(coord: CLLocationCoordinate2D) {
        let ud = UserDefaults.standard
        guard ud.bool(forKey: UDKey.presenceShareEnabled) else { return }
        guard GermanyBoundingBox.contains(coord) else { return }
        guard let uid = FirebaseAuth.Auth.auth().currentUser?.uid else { return }

        let lastTS = ud.double(forKey: UDKey.presenceLastWrittenAt)
        let now = Date().timeIntervalSince1970
        if lastTS > 0, now - lastTS < Self.presenceThrottleSeconds { return }

        RealtimeDBManager.shared.writeMyPresence(
            uid: uid, coord: coord,
            emoji: currentUser.emoji,
            name: currentUser.name,
            profileImageURL: currentUser.profileImageURL
        )
        ud.set(now, forKey: UDKey.presenceLastWrittenAt)
    }

    // GPS-Fallback-Bestätigung (falls BLE nicht greift, z. B. weil Nutzer
    // BLE deaktiviert hat / iOS den Background-Scan zwischendurch killt):
    //
    //   • Joiner muss innerhalb 20 m vom Drop-Standort sein
    //     (bewusst eng — GPS in der Stadt ist 5–15 m genau,
    //     20 m fängt das Rauschen ab ohne falsch-positive Treffer
    //     vom Nachbartisch / anderen Hauseingang).
    //   • UND er muss diese Position für mindestens 60 s gehalten
    //     haben (kurzes Vorbeilaufen zählt nicht als "anwesend").
    //
    // Vorher war es einfach < 100 m beim Drop-Ende — das hat zwei reale
    // Probleme erzeugt: (a) Joiner, die nur kurz an der Adresse vorbei-
    // gefahren sind, wurden als "vor Ort" gewertet; (b) der Schwellen-
    // wert war so locker, dass auch GPS-Drift quer durch den Häuser-
    // block reichte. Mit 20 m + 1 min Verweildauer fällt beides weg.
    static let gpsArrivalThresholdMeters: Double = 20
    static let gpsArrivalDwellSeconds: TimeInterval = 60
    /// GPS-Radius beim Verlassen — Fallback wenn BLE nicht verfügbar war.
    /// Bewusst großzügiger als gpsArrivalThresholdMeters (Live-Indikator):
    /// beim Verlassen zählt 50 m als "war vor Ort".
    static let gpsConfirmThresholdMeters: Double = 50

    /// UD-Key für den letzten Pair-Award-Zeitpunkt zwischen mir und
    /// otherUID. Sortiert die UIDs damit (A,B) und (B,A) denselben Key
    /// ergeben — sonst würde jede Seite ihren eigenen Cooldown-Eintrag
    /// schreiben und die Logik wäre asymmetrisch.
    private func pairCooldownKey(for otherUID: String) -> String {
        let myUID = UserDefaults.standard.string(forKey: UDKey.firebaseUID) ?? ""
        let pair = [myUID, otherUID].sorted().joined(separator: "_")
        return "ud_pairAwardAt_\(pair)"
    }

    /// True wenn dieser User-Pair innerhalb der letzten 12 h schon
    /// einmal Punkte für ein gemeinsames Treffen vergeben wurden.
    /// Bei fehlender UID (z.B. unbekannter Joiner) → false (großzügig).
    func isPairOnCooldown(otherUID: String?) -> Bool {
        guard let otherUID = otherUID, !otherUID.isEmpty else { return false }
        let ud = UserDefaults.standard
        guard let lastTS = ud.object(forKey: pairCooldownKey(for: otherUID)) as? Date else {
            return false
        }
        return Date().timeIntervalSince(lastTS) < Self.pairCooldownSeconds
    }

    /// Markiert einen Pair-Award als jetzt erfolgt — sperrt den Pair
    /// für die nächsten 12 h gegen weitere Punkte.
    func markPairAwarded(otherUID: String?) {
        guard let otherUID = otherUID, !otherUID.isEmpty else { return }
        UserDefaults.standard.set(Date(), forKey: pairCooldownKey(for: otherUID))
        // Firebase-Backup — überlebt App-Reinstall und Geräte-Wechsel
        if let myUID = FirebaseAuth.Auth.auth().currentUser?.uid {
            RealtimeDBManager.shared.savePairCooldown(
                myUID: myUID, otherUID: otherUID,
                timestamp: Date().timeIntervalSince1970
            )
        }
    }

    // MARK: - Info-Toast (Anti-Farm-Feedback)
    //
    // Eigener Kanal getrennt vom positiven `pointsToast` — wir nutzen ihn
    // wenn KEINE Punkte vergeben werden (Drop zu kurz, Pair auf Cooldown),
    // damit der User nicht denkt es wäre ein Bug.
    struct InfoToast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let icon: String           // SF Symbol
    }
    @Published var infoToast: InfoToast? = nil

    func showInfoToast(_ message: String, icon: String = "hourglass") {
        let toast = InfoToast(message: message, icon: icon)
        infoToast = toast
        // Auto-dismiss nach 3.5 s — neue Toast überschreibt vorherigen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            if self?.infoToast?.id == toast.id { self?.infoToast = nil }
        }
    }

    /// Definition eines Power-Hour-Zeitfensters: Wochentage + Uhrzeit-Spanne.
    /// `weekdays` nutzt die Apple-Convention (1 = Sonntag … 7 = Samstag).
    /// `endHour` ist exklusiv (z.B. 18..<20 = 18:00 bis 19:59).
    /// `labelKey` und `daysKey` sind Localization-Keys (siehe Localization.swift).
    struct PowerHourWindow {
        let weekdays: Set<Int>
        let startHour: Int
        let endHour: Int
        let labelKey: String
        let daysKey: String
        var label: String { tr(labelKey) }
        var daysLabel: String { tr(daysKey) }
        /// Lokalisierte Zeitspanne, z.B. "18–20 Uhr" / "18–20".
        var timeRangeLabel: String {
            tr("ph.time_range")
                .replacingOccurrences(of: "{from}", with: "\(startHour)")
                .replacingOccurrences(of: "{to}",   with: "\(endHour)")
        }
    }

    static let powerHourWindows: [PowerHourWindow] = [
        // Werktag-Abend: Mo–Do 18–20 Uhr
        PowerHourWindow(weekdays: [2, 3, 4, 5], startHour: 18, endHour: 20,
                        labelKey: "ph.label.weekday_evening", daysKey: "ph.days.mon_thu"),
        // Weekend Prime: Fr–Sa 19–23 Uhr
        PowerHourWindow(weekdays: [6, 7], startHour: 19, endHour: 23,
                        labelKey: "ph.label.weekend_prime", daysKey: "ph.days.fri_sat"),
        // Sonntag-Brunch: So 11–14 Uhr
        PowerHourWindow(weekdays: [1], startHour: 11, endHour: 14,
                        labelKey: "ph.label.sunday_brunch", daysKey: "ph.days.sun"),
    ]

    /// True wenn aktuell weniger als `boostThreshold` Drops in Reichweite des
    /// Users sind. Quelle: `allMapAnnotations` gefiltert auf den Radius-Filter
    /// — gleiche Logik wie die Karte/Feed sieht. Eigene Drops zählen mit (Host
    /// macht für die Region trotzdem Aktivität sichtbar).
    var isBoostPhaseActive: Bool {
        // Ghosts zählen nicht — sie sind vorbei, Bereich kann trotzdem "leer" sein.
        let visible = allMapAnnotations.filter { !$0.isGhost && isWithinRadius($0.coordinate) }
        return visible.count < Self.boostThreshold
    }

    /// Admin-Debug-Override: zwingt Power-Hour permanent an, unabhängig von
    /// Wochentag/Uhrzeit. Wird im Admin-Panel umgeschaltet (debugSection)
    /// damit Tests nicht erst auf 18 Uhr warten müssen. Persistiert
    /// in UserDefaults, damit der Modus über App-Restarts hält.
    @Published var debugForcePowerHour: Bool = UserDefaults.standard.bool(forKey: "ud_debugForcePowerHour") {
        didSet {
            UserDefaults.standard.set(debugForcePowerHour, forKey: "ud_debugForcePowerHour")
        }
    }

    /// True wenn gerade ein Power-Hour-Zeitfenster läuft. Unabhängig von der
    /// Boost-Bedingung — die UI kann beide Flags kombinieren um den richtigen
    /// Banner-Text und Bonus-Wert anzuzeigen. Admin-Debug-Override gewinnt.
    var isPowerHourActive: Bool {
        if debugForcePowerHour { return true }
        let now = Date()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        let hour = cal.component(.hour, from: now)
        return Self.powerHourWindows.contains { window in
            window.weekdays.contains(weekday)
                && hour >= window.startHour
                && hour < window.endHour
        }
    }

    /// Aktueller Bonus-Wert (15 oder 25). UI nutzt das, der Code unten auch.
    var currentBoostBonus: Int {
        isPowerHourActive ? Self.powerHourBonus : Self.boostBonus
    }

    /// Countdown-Info für die Map-UI. Drei Phasen:
    ///   - .startingSoon: ≤60 Min vor Start des nächsten Slots heute
    ///   - .running:      mittendrin im Slot, noch >60 Min Zeit
    ///   - .endingSoon:   in den letzten 60 Min eines aktiven Slots
    /// Außerhalb aller Slots (oder >60 Min vor Start): nil.
    struct PowerHourCountdown {
        enum Phase { case startingSoon, running, endingSoon }
        let phase: Phase
        let minutesRemaining: Int
        let windowLabel: String
    }

    static func powerHourCountdown(at date: Date) -> PowerHourCountdown? {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let nowMin = hour * 60 + minute

        // 1) Aktiver Slot? → immer Countdown zeigen (running oder endingSoon)
        for w in powerHourWindows where w.weekdays.contains(weekday) {
            if hour >= w.startHour && hour < w.endHour {
                let endMin = w.endHour * 60
                let remaining = endMin - nowMin
                guard remaining > 0 else { return nil }
                let phase: PowerHourCountdown.Phase = remaining <= 60 ? .endingSoon : .running
                return PowerHourCountdown(
                    phase: phase,
                    minutesRemaining: remaining,
                    windowLabel: w.label
                )
            }
        }

        // 2) Heutiger upcoming Slot in den nächsten 60 Min?
        for w in powerHourWindows where w.weekdays.contains(weekday) {
            if hour < w.startHour {
                let startMin = w.startHour * 60
                let untilStart = startMin - nowMin
                if untilStart > 0 && untilStart <= 60 {
                    return PowerHourCountdown(
                        phase: .startingSoon,
                        minutesRemaining: untilStart,
                        windowLabel: w.label
                    )
                }
            }
        }

        return nil
    }

    /// Vergibt den Boost-Bonus. Zwei unabhängige Trigger:
    ///   1. Boost-Phase: Umgebung gerade leer (<5 Drops) → +15
    ///   2. Power-Hour: konfiguriertes Zeitfenster läuft → +25
    /// Wenn beide zutreffen gewinnt Power-Hour (höherer Wert).
    /// Außerhalb beider Bedingungen: kein Bonus.
    /// Wird von createDrop / confirmEncounter / recordHostSuccess aufgerufen.
    /// Persistierung + Firestore-Push übernimmt der Aufrufer (saveAll).
    fileprivate func applyBoostBonusIfActive(reason: String) {
        let powerHour = isPowerHourActive
        let boost     = isBoostPhaseActive
        guard powerHour || boost else { return }

        let bonus  = powerHour ? Self.powerHourBonus : Self.boostBonus
        let prefix = powerHour ? "Power-Hour: " : "Boost: "
        reliabilityScore.boostBonusPoints += bonus
        Task { @MainActor in
            PushNotificationManager.shared.notifyPointsEarned(
                delta: bonus,
                totalPoints: reliabilityScore.points,
                reason: prefix + reason
            )
        }
    }

    // MARK: - Drop-Invite-Bonus-Tracking
    // Set von Drop-IDs (UUID-Strings) die via Invite-Link gejoint wurden.
    // Beim ShowUp wird der Eintrag verbraucht und der Host bekommt +5 Punkte.
    // Persistiert in UserDefaults damit's App-Restart überlebt.
    private static let invitedDropJoinsKey = "ud_invitedDropJoins"

    private func markJoinAsInviteBased(dropID: UUID, hostUID: String?) {
        let ud = UserDefaults.standard
        var set = Set(ud.stringArray(forKey: Self.invitedDropJoinsKey) ?? [])
        set.insert(dropID.uuidString)
        ud.set(Array(set), forKey: Self.invitedDropJoinsKey)
        // Host-UID separat merken (pro Drop), damit wir beim ShowUp korrekt crediten können
        if let host = hostUID, !host.isEmpty {
            ud.set(host, forKey: "ud_inviteDropHost_\(dropID.uuidString)")
        }
    }

    /// Löst den Drop-Invite-Bonus aus wenn der ShowUp für einen invite-gejointen Drop war.
    /// Aufrufen direkt nach applyStreakBonus/maybeAwardFirstArrivalBonus im Arrival-Flow.
    private func maybeAwardDropInviteBonusToHost() {
        guard let dropID = activeJoinedDropID else { return }
        let ud = UserDefaults.standard
        var set = Set(ud.stringArray(forKey: Self.invitedDropJoinsKey) ?? [])
        guard set.remove(dropID.uuidString) != nil else { return }
        ud.set(Array(set), forKey: Self.invitedDropJoinsKey)
        // Host-UID laden und Bonus schreiben
        let key = "ud_inviteDropHost_\(dropID.uuidString)"
        let hostUID = ud.string(forKey: key) ?? ""
        ud.removeObject(forKey: key)
        guard !hostUID.isEmpty else { return }
        RealtimeDBManager.shared.creditDropInviteBonus(hostUID: hostUID)
    }

    /// Vergibt +5 Bonus wenn der User als Erster Joiner vor Ort ist — außer er ist Host.
    /// Heuristik: wenn BLE noch keine anderen Teilnehmer bestätigt hat, sind wir der Erste.
    private func maybeAwardFirstArrivalBonus() {
        guard activeJoinedDropID != nil else { return }           // Nur bei gejointem Drop
        guard bluetoothMeetup.confirmedTokens.isEmpty else { return } // Schon jemand anderes da
        reliabilityScore.firstArrivalPoints += 10
    }

    /// Wird aufgerufen wenn ein eigener Drop zustande gekommen ist (min. 1 weiterer Teilnehmer
    /// war vor Ort). +12 Host-Bonus + Prüfung Neuling-Host-Bonus (+5 pro Drop-Entdecker).
    func recordHostSuccess(arrivedParticipants: [DropParticipant]) {
        nextPointsReason = tr("models.reason_host_success")
        // Anti-Farm: Joiner mit aktivem 12h-Cooldown rausfiltern.
        // Wenn KEIN Joiner mehr "frisch" ist (alle schon heute getroffen)
        // → kein Host-Bonus, keine Newcomer-Punkte. Drop wandert trotzdem
        // in den Verlauf (das passiert in cancelDrop), aber ohne Punkte-
        // Belohnung. Sonst könnte man Multi-Drop-Farming mit denselben
        // Alt-Accounts betreiben.
        let freshJoiners = arrivedParticipants.filter { p in
            !isPairOnCooldown(otherUID: p.firebaseUID)
        }
        guard !freshJoiners.isEmpty else {
            // Alle Pairs auf Cooldown → Drop zählt für Statistik, keine Punkte.
            showInfoToast("Heute schon mit allen getroffen — keine Punkte (12 h Cooldown)",
                          icon: "clock.arrow.circlepath")
            saveAll()
            return
        }

        reliabilityScore.hostSuccesses += 1
        reliabilityScore.totalCommits += 1
        reliabilityScore.showUps += 1
        applyStreakBonus()
        // Neuling-Bonus: für jeden noch nicht trusted gejointen User (<200 Pkt) +5
        // — aber nur wenn der Pair NICHT auf Cooldown ist (freshJoiners).
        let newcomers = freshJoiners.filter {
            !ReliabilityScore.isTrusted(forPoints: $0.reliabilityScore)
        }
        reliabilityScore.newcomerHostPoints += newcomers.count * 5
        // Erst-Host-Bonus: einmaliger +10 wenn der erste eigene Drop
        // tatsächlich Teilnehmer hatte. Belohnt erfolgreiches Hosten ohne
        // farmbar zu sein — kann genau einmal pro User vergeben werden.
        let ud = UserDefaults.standard
        if !freshJoiners.isEmpty,
           !ud.bool(forKey: UDKey.firstHostBonusReceived) {
            reliabilityScore.creationBonusPoints += 10
            ud.set(true, forKey: UDKey.firstHostBonusReceived)
        }
        // Boost: +5 wenn die Umgebung gerade leer ist
        applyBoostBonusIfActive(reason: "Plan gehostet")

        // Pair-Cooldown markieren — alle Fresh-Joiner sind jetzt für 12 h
        // gegen weitere Host-/Encounter-Punkte gesperrt.
        for p in freshJoiners { markPairAwarded(otherUID: p.firebaseUID) }

        saveAll()
        pushReliabilityScoreToFirestore()
        maybeAskForReview()
    }

    /// Wird aufgerufen wenn jemand den Drop via deiner Einladung gejoint hat.
    /// Aufrufer muss sicherstellen, dass der Joiner via Link vom aktuellen User kam.
    func recordDropInviteJoined() {
        reliabilityScore.dropInvitesPoints += 10
        saveAll()
        pushReliabilityScoreToFirestore()
    }

    /// Wird aufgerufen wenn ein von diesem User eingeladener Freund Drops neu installiert
    /// und das Onboarding abgeschlossen hat (via deeplink-Zuordnung).
    func recordAppInviteCompleted() {
        reliabilityScore.appInvitesPoints += 25
        saveAll()
        pushReliabilityScoreToFirestore()
    }

    func denyEncounter(id: UUID) {
        if let i = encounters.firstIndex(where: { $0.id == id }) {
            encounters[i].denied = true
            // Ablehnung des anderen → kein Score-Einfluss auf eigenen Score
        }
    }

    /// Abgelaufene Encounters ohne Bestätigung als No-Show werten.
    /// Sollte beim App-Start und beim Tab-Wechsel aufgerufen werden.
    func processExpiredEncounters() {
        var changed = false
        for i in encounters.indices {
            let e = encounters[i]
            guard !e.confirmed && !e.denied && e.isExpired && e.seenByUser else { continue }
            // Als nicht erschienen markieren
            encounters[i].denied = true
            reliabilityScore.totalCommits += 1
            // Score-Schutz für Drops+ ist als Feature angekündigt aber noch nicht aktiv
            reliabilityScore.noShows += 1
            breakStreak()
            changed = true
        }
        if changed {
            saveAll()                           // Score lokal persistieren
            pushReliabilityScoreToFirestore()   // Score für andere sichtbar machen
        }
    }

    /// Markiert alle unbestätigten Encounters als vom User gesehen.
    /// Nur gesehene Encounters werden nach Ablauf als No-Show gewertet.
    func markEncountersSeen() {
        var changed = false
        for i in encounters.indices where !encounters[i].seenByUser {
            encounters[i].seenByUser = true
            changed = true
        }
        if changed { saveAll() }
    }

    var isInActiveDrop: Bool {
        // Eigener Drop aktiv ODER direkt beigetreten (kein Approval nötig)
        !activeDrops.isEmpty || activeJoinedDropID != nil
    }

    /// Annotation für den aktuell aktiven Drop (eigener oder beigetretener).
    var currentActiveAnnotation: MapAnnotationItem? {
        if !activeDrops.isEmpty {
            return allMapAnnotations.first { $0.type == .myDrop }
        }
        return activeDropAnnotation
    }

    /// Ob BLE in der aktuellen Drop-Session eine Begegnung bestätigt hat.
    private var bleConfirmedInCurrentSession = false
    /// Zeitpunkt des Beitritts für Mindestzeit-Prüfung beim No-Show.
    private var joinSessionStartedAt: Date? = nil
    /// Drop-Standort der aktuellen Session (für GPS-Fallback).
    private var joinSessionDropCoord: CLLocationCoordinate2D? = nil
    /// Host-UID der aktuellen Session (für GPS-Fallback Encounter-Bestätigung).
    private var joinSessionHostUID: String? = nil

    /// Firebase-Handle für den DropIn-Observer (Host-Seite).
    private var dropInObserverHandle: DatabaseHandle? = nil
    private var dropInObservedDropID: String? = nil

    // MARK: - DropIn Observer

    /// Startet den Firebase-Observer für eingehende DropIns (Host-Seite).
    /// Feuert eine lokale Push-Benachrichtigung wenn jemand beitritt.
    func startObservingDropIns(forDropID dropID: String) {
        // Alten Observer sauber abmelden
        stopObservingDropIns()
        dropInObservedDropID = dropID
        // Kleines Delay damit der eigene joinDrop-Write nicht sofort als "neuer" DropIn gewertet wird
        let activityName = activeDrops.first?.activity.name
            ?? activeDropAnnotation?.activity
            ?? "Plan"
        dropInObserverHandle = RealtimeDBManager.shared.observeDropIns(dropID: dropID) { [weak self] name, emoji, _ in
            guard let self = self else { return }
            // Nur den Host benachrichtigen — Joiner sollen keine eigene Notification bekommen
            guard !self.activeDrops.isEmpty else { return }
            PushNotificationManager.shared.notifyDropIn(joinerName: "\(emoji) \(name)".trimmingCharacters(in: .whitespaces),
                                                         activityName: activityName)
            // Live-Activity aktualisieren damit der neue Teilnehmer erscheint
            self.refreshLiveActivityParticipants()
        }
        // Zusätzlich: Live-Positions-Updates der Joiner beobachten → Pins auf der Karte
        joinerLocationObserverHandle = RealtimeDBManager.shared.observeJoinerLocations(
            dropID: dropID,
            onUpdate: { [weak self] joinerID, info in
                guard let self = self else { return }
                self.joinerLiveInfos[joinerID] = info

                // GPS-Verweilzeit-Tracking (für anyGPSNear-Gate beim
                // Drop-Ende). Ist der Joiner innerhalb der Schwelle, setzen
                // wir den Eintritts-Zeitpunkt einmal — verlässt er sie,
                // löschen wir ihn, damit er die Verweilzeit von vorn
                // sammeln muss.
                if let myDropID = self.dropInObservedDropID,
                   let drop = self.activeDrops.first(where: { $0.id.uuidString == myDropID }) {
                    let dropLoc = CLLocation(
                        latitude: drop.location.coordinate.latitude,
                        longitude: drop.location.coordinate.longitude
                    )
                    let joinerLoc = CLLocation(latitude: info.lat, longitude: info.lng)
                    let dist = joinerLoc.distance(from: dropLoc)
                    if dist <= AppStore.gpsArrivalThresholdMeters {
                        if self.joinerNearSinceUTC[joinerID] == nil {
                            self.joinerNearSinceUTC[joinerID] = Date()
                        }
                    } else {
                        self.joinerNearSinceUTC.removeValue(forKey: joinerID)
                    }
                }

                // SAFETY-NET: Wenn der Joiner in dropins/ steht aber NICHT
                // in drop.participants ist (z.B. weil Host die Anfrage
                // verpasst hat oder Auto-Accept ohne Sheet lief), ihn
                // jetzt nachträglich anhand der dropins-Daten anhängen.
                // Sonst zeigt das Drop-Sheet ihn nicht in Unterwegs/Vor Ort,
                // und der Map-Pin fällt auf den "Joiner"-Default-Namen.
                if let dropIdx = self.activeDrops.firstIndex(where: { $0.id.uuidString == dropID }),
                   !self.activeDrops[dropIdx].participants.contains(where: { $0.firebaseUID == joinerID }) {
                    // Name ggf. aus Firebase-Profil nachladen wenn dropins-Entry keinen hat
                    // (passiert wenn Joiner disconnect + reconnect + nur Location-Update schreibt).
                    let addParticipant = { [weak self] (name: String, emoji: String) in
                        guard let self else { return }
                        guard let idx = self.activeDrops.firstIndex(where: { $0.id.uuidString == dropID }),
                              !self.activeDrops[idx].participants.contains(where: { $0.firebaseUID == joinerID })
                        else { return }
                        let joinerUser = User(
                            id: UUID(),
                            name: name,
                            emoji: emoji,
                            isAvailable: true,
                            statusMessage: "Unterwegs",
                            coordinate: info.coordinate,
                            profileImageURL: info.profileImageURL,
                            firebaseUID: joinerID,
                            reliabilityPoints: info.reliabilityPoints ?? 100
                        )
                        self.activeDrops[idx].participants.append(joinerUser)
                        self.refreshLiveActivityParticipants()
                        print("[joiners] safety-net added \(name) to drop.participants (was missing)")
                    }

                    if let name = info.name, !name.isEmpty {
                        addParticipant(name, info.emoji ?? "👤")
                    } else {
                        // Profil aus Firebase nachladen (db ist private → Helper)
                        RealtimeDBManager.shared.fetchUserBasicProfile(uid: joinerID) { name, emoji in
                            DispatchQueue.main.async { addParticipant(name, emoji) }
                        }
                    }
                }

                // Live-Teilnehmerzahl auf Firebase pushen, damit andere
                // Clients (Karte / Umgebungstab) den Drop als „Voll"
                // markieren bzw. ausblenden können. Host zählt mit (+1).
                let count = self.joinerLiveInfos.count + 1
                RealtimeDBManager.shared.updateCurrentParticipants(dropID: dropID, count: count)
            },
            onRemove: { [weak self] joinerID in
                guard let self = self else { return }
                // 1) Live-Pin-Daten weg — Karte rendert den Joiner nicht mehr
                self.joinerLiveInfos.removeValue(forKey: joinerID)
                // 1a) GPS-Verweilzeit-Tracker zurücksetzen, sonst würde
                //     ein abgemeldeter Joiner später beim Drop-Ende fälsch-
                //     licherweise als "anwesend" zählen, falls der Stempel
                //     im Dict bliebe.
                self.joinerNearSinceUTC.removeValue(forKey: joinerID)
                // 2) Aus drop.participants entfernen — sonst bleibt der Joiner
                //    in der "Unterwegs"-/"Vor Ort"-Liste des Drop-Sheets.
                //    activeDrops[idx] wird neu gesetzt, damit SwiftUI re-rendert.
                if let dropIdx = self.activeDrops.firstIndex(where: { $0.id.uuidString == dropID }) {
                    let before = self.activeDrops[dropIdx].participants.count
                    self.activeDrops[dropIdx].participants.removeAll {
                        $0.firebaseUID == joinerID
                    }
                    if self.activeDrops[dropIdx].participants.count != before {
                        self.refreshLiveActivityParticipants()
                    }
                }
                // Live-Teilnehmerzahl runter — sobald wieder Platz ist,
                // sehen andere Clients den Drop sofort wieder als „nicht
                // voll" und können beitreten.
                let count = self.joinerLiveInfos.count + 1
                RealtimeDBManager.shared.updateCurrentParticipants(dropID: dropID, count: count)
            }
        )
    }

    /// Live-Daten der Joiner pro UID (Coord + Name + Emoji + Age + Profilbild +
    /// Reliability). Wird durch observeJoinerLocations befüllt aus
    /// `dropins/{dropID}/{joinerID}` — daher kennt der Host den richtigen
    /// Joiner-Namen direkt (statt "Joiner"-Fallback) und kann den Pin sauber
    /// rendern. Wird beim Drop-Ende gecleart.
    @Published var joinerLiveInfos: [String: JoinerLiveInfo] = [:]
    /// Backwards-compat Computed: Map auf coords, falls anderer Code das
    /// noch erwartet.
    var joinerLiveCoordinates: [String: CLLocationCoordinate2D] {
        Dictionary(uniqueKeysWithValues: joinerLiveInfos.map { ($0.key, $0.value.coordinate) })
    }
    private var joinerLocationObserverHandle: DatabaseHandle? = nil

    /// Zeitpunkt, ab dem ein Joiner per GPS innerhalb der
    /// `gpsArrivalThresholdMeters` vom Drop-Standort liegt. Wird beim
    /// ersten Eintreten des Radius gesetzt und bei Verlassen wieder
    /// gelöscht. Beim Drop-Ende muss `now - nearSince ≥ gpsArrivalDwellSeconds`
    /// gelten, damit der Joiner als "anwesend" zählt.
    /// Key: firebaseUID des Joiners.
    private var joinerNearSinceUTC: [String: Date] = [:]

    // MARK: - Drop Views („wer hat geschaut")

    /// Wird aufgerufen wenn der User ein öffentliches Drop-Detail öffnet.
    /// Eigener Drop wird nicht als View gezählt (item.type .stranger filtert bereits).
    func viewDrop(_ item: MapAnnotationItem) {
        guard item.type == .stranger else { return }
        // Safety: nicht zweimal in derselben Session für denselben Drop schreiben
        let dropKey = item.id.uuidString
        guard viewedDropIDsThisSession.insert(dropKey).inserted else { return }
        RealtimeDBManager.shared.recordDropView(
            dropID: dropKey,
            viewerName: currentUser.name,
            viewerEmoji: currentUser.emoji,
            viewerAge: userAge,
            viewerProfileImageURL: profileImageURL
        )
    }

    /// Startet den Live-Observer für die Viewer eines eigenen Drops.
    func startObservingDropViews(forDropID dropID: String) {
        stopObservingDropViews(forDropID: dropID)
        let handle = RealtimeDBManager.shared.observeDropViews(dropID: dropID) { [weak self] viewers in
            self?.dropViewersByDropID[dropID] = viewers
        }
        dropViewsObserverHandles[dropID] = handle
    }

    func stopObservingDropViews(forDropID dropID: String) {
        if let handle = dropViewsObserverHandles[dropID] {
            RealtimeDBManager.shared.removeDropViewsObserver(handle, dropID: dropID)
            dropViewsObserverHandles.removeValue(forKey: dropID)
        }
    }

    // MARK: - Freunde live synchronisieren

    /// Startet den Live-Observer auf `friends/{uid}` — adds auf anderen Geräten
    /// landen automatisch in store.friends. Neue Adds lösen einen Notification-
    /// Push aus (Freundschafts-Event). Gleichzeitig startet der Observer auf
    /// `friendRequests/{uid}` für eingehende Anfragen.
    func startObservingPresence() {
        RealtimeDBManager.shared.observeAllPresence { [weak self] entries in
            self?.allPresences = entries
        }
    }

    func stopObservingPresence() {
        RealtimeDBManager.shared.stopObservingPresence()
    }

    /// Filtert `allPresences` für die Map-Ansicht:
    /// - nur DE-BoundingBox
    /// - nur mind. 20 min alt (Delay)
    /// - nur max 4h alt (Cutoff)
    /// - trennt in Freunde (mit Name+Emoji) und Fremde (anonyme Dots)
    func filteredPresences() -> (friends: [PresenceEntry], strangers: [PresenceEntry]) {
        let myUID = currentUser.firebaseUID ?? FirebaseAuth.Auth.auth().currentUser?.uid ?? ""
        let friendUIDs = Set(friends.compactMap { $0.firebaseUID })
        var f: [PresenceEntry] = []
        var s: [PresenceEntry] = []
        for e in allPresences {
            guard !e.isExpired, e.isDelayReached else { continue }
            guard GermanyBoundingBox.contains(e.coordinate) else { continue }
            // Eigenen User nicht als Ghost rendern — er sieht sich bereits
            // entweder als SelfCharacterOverlay (echte Position) oder als
            // blauer System-Punkt. Doppel-Marker wäre verwirrend.
            if e.uid == myUID { continue }
            if friendUIDs.contains(e.uid) { f.append(e) }
            else                         { s.append(e) }
        }
        return (f, s)
    }

    func startObservingFriends(ownerUID: String) {
        stopObservingFriends()
        friendsObservedUID = ownerUID
        friendsObserverInitialized = false
        friendsObserverHandle = RealtimeDBManager.shared.observeMyFriends(ownerUID: ownerUID) { [weak self] snapshots in
            guard let self = self else { return }
            self.applyFriendSnapshots(snapshots)
        }
        // Eingehende Freundschaftsanfragen — separater Observer
        friendRequestsObserverHandle = RealtimeDBManager.shared.observeIncomingFriendRequests { [weak self] requests in
            guard let self = self else { return }
            // Neue Requests (UID war vorher nicht in der Liste) → lokaler Push
            let oldUIDs = Set(self.incomingFriendRequests.map { $0.fromUID })
            let newRequests = requests.filter { !oldUIDs.contains($0.fromUID) }
            self.incomingFriendRequests = requests
            for req in newRequests where self.friendRequestsObserverInitialized {
                self.notifyFriendRequestReceived(from: req.fromName)
            }
            self.friendRequestsObserverInitialized = true
        }
    }

    func stopObservingFriends() {
        if let handle = friendsObserverHandle, let uid = friendsObservedUID {
            RealtimeDBManager.shared.removeFriendsObserver(handle, ownerUID: uid)
        }
        friendsObserverHandle = nil
        friendsObservedUID = nil
        friendsObserverInitialized = false
        if let handle = friendRequestsObserverHandle {
            RealtimeDBManager.shared.removeFriendRequestsObserver(handle)
        }
        friendRequestsObserverHandle = nil
        friendRequestsObserverInitialized = false
        incomingFriendRequests = []
    }

    /// Lokale Push-Notification bei neuer Freundschaftsanfrage.
    /// (Cloud Function schickt separat die Remote-Push — aber falls sie
    /// nicht deployed ist oder der User gerade die App offen hat, zeigen
    /// wir auch lokal einen Hinweis als Banner.)
    private func notifyFriendRequestReceived(from name: String) {
        let content = UNMutableNotificationContent()
        content.title = tr("models.new_friend_request")
        content.body  = tr("models.friend_wants_to_be").replacingOccurrences(of: "{name}", with: name)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "friendRequest_\(name)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Name Change Request

    /// Stellt eine Namensänderungsanfrage. Wird im Admin-Panel sichtbar,
    /// der Name ändert sich erst nach Genehmigung.
    func requestNameChange(to newName: String) {
        guard let uid = FirebaseAuth.Auth.auth().currentUser?.uid else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines).capitalizedFirst
        guard !trimmed.isEmpty, trimmed != currentUser.name else { return }
        pendingNameChange = trimmed
        saveAll()
        RealtimeDBManager.shared.submitNameChangeRequest(
            uid: uid, oldName: currentUser.name, newName: trimmed
        )
        startNameChangeResultObserver(uid: uid)
    }

    /// Zieht eine ausstehende Namensänderungsanfrage zurück (ohne "denied"-Notification).
    func cancelNameChangeRequest() {
        guard let uid = FirebaseAuth.Auth.auth().currentUser?.uid else { return }
        stopNameChangeResultObserver(uid: uid)
        pendingNameChange = nil
        saveAll()
        // Nur den Request löschen — kein nameChangeResult schreiben,
        // damit der Observer keine fälschliche Ablehnungs-Notification auslöst.
        RealtimeDBManager.shared.withdrawNameChangeRequest(uid: uid)
    }

    /// Startet den Firebase-Observer auf `users/{uid}/nameChangeResult`.
    /// Feuert wenn Admin die Anfrage genehmigt oder ablehnt.
    func startNameChangeResultObserver(uid: String) {
        stopNameChangeResultObserver(uid: uid)
        let handle = RealtimeDBManager.shared.observeNameChangeResult(uid: uid) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case "approved":
                    // Name wurde in Firebase gesetzt — aus Profil neu laden
                    RealtimeDBManager.shared.fetchUserBasicProfile(uid: uid) { name, _ in
                        DispatchQueue.main.async {
                            self.currentUser.name = name.capitalizedFirst
                            self.pendingNameChange = nil
                            self.lastNameChangeDate = Date()  // 14-Tage-Cooldown startet
                            self.saveAll()
                            Haptic.nameChangeApproved()
                            self.showInfoToast(tr("models.name_changed").replacingOccurrences(of: "{name}", with: name.capitalizedFirst), icon: "checkmark.circle.fill")
                            RealtimeDBManager.shared.clearNameChangeResult(uid: uid)
                            self.stopNameChangeResultObserver(uid: uid)
                        }
                    }
                case "denied":
                    self.pendingNameChange = nil
                    self.saveAll()
                    Haptic.nameChangeDenied()
                    self.showInfoToast(tr("models.name_change_rejected"), icon: "xmark.circle.fill")
                    RealtimeDBManager.shared.clearNameChangeResult(uid: uid)
                    self.stopNameChangeResultObserver(uid: uid)
                default:
                    break
                }
            }
        }
        nameChangeResultHandle = handle
    }

    /// Stoppt den nameChangeResult-Observer.
    private func stopNameChangeResultObserver(uid: String) {
        if let h = nameChangeResultHandle {
            RealtimeDBManager.shared.removeNameChangeObserver(h, uid: uid)
            nameChangeResultHandle = nil
        }
    }

    // MARK: - Friend Request Actions

    /// Schickt eine Freundschaftsanfrage an `theirUID`.
    /// Clientseitig kein Auto-Add mehr — der Empfänger muss annehmen.
    func sendFriendRequest(to theirUID: String) {
        guard !theirUID.isEmpty else { return }
        Haptic.friendRequestSent()
        RealtimeDBManager.shared.sendFriendRequest(
            theirUID: theirUID,
            myName: currentUser.name,
            myProfileImageURL: profileImageURL
        )
    }

    func acceptFriendRequest(fromUID: String) {
        RealtimeDBManager.shared.acceptFriendRequest(fromUID: fromUID)
        Haptic.friendAdded()
        // Observer updated incomingFriendRequests automatisch
    }

    func rejectFriendRequest(fromUID: String) {
        RealtimeDBManager.shared.rejectFriendRequest(fromUID: fromUID)
    }

    /// Merged eine frische Snapshot-Liste in store.friends. Dedup per Name
    /// (wie bisher), ergänzt fehlende Einträge, entfernt nicht mehr vorhandene
    /// (nur wenn sie via Friend-Snapshot-Liste ursprünglich kamen).
    /// Bei neuen UIDs (echte Freundschafts-Adds) wird ein lokaler Push ausgelöst.
    private func applyFriendSnapshots(_ snapshots: [RealtimeDBManager.FriendSnapshot]) {
        let currentUIDs = Set(snapshots.map { $0.uid })

        // Adds erkennen
        if friendsObserverInitialized {
            let newUIDs = currentUIDs.subtracting(knownFriendUIDs)
            for newUID in newUIDs {
                if let snap = snapshots.first(where: { $0.uid == newUID }) {
                    notifyFriendshipAdded(name: snap.name)
                }
            }
        }

        // Online-Status: ein Freund gilt als online wenn sein letzter Heartbeat
        // weniger als 5 Minuten her ist. Daraus ableiten wir `isAvailable`.
        let now = Date().timeIntervalSince1970
        let onlineWindow: TimeInterval = 5 * 60
        func isOnline(_ last: TimeInterval?) -> Bool {
            guard let last = last else { return false }
            return (now - last) < onlineWindow
        }

        // Vorhandene Einträge aktualisieren / fehlende hinzufügen — Dedup primär
        // per Firebase-UID (stabil), Name-Fallback für Legacy-Einträge.
        for snap in snapshots {
            let existingIdx: Int?
            if let byUID = friends.firstIndex(where: { $0.firebaseUID == snap.uid }) {
                existingIdx = byUID
            } else if let byName = friends.firstIndex(where: { $0.firebaseUID == nil && $0.name == snap.name }) {
                existingIdx = byName
            } else {
                existingIdx = nil
            }

            let online = isOnline(snap.lastActiveAt)

            if let idx = existingIdx {
                // Legacy-Eintrag mit UID/Name/Avatar/Online-Status/Score auffrischen
                if friends[idx].firebaseUID != snap.uid    { friends[idx].firebaseUID = snap.uid }
                if friends[idx].name != snap.name          { friends[idx].name = snap.name }
                if friends[idx].profileImageURL != snap.profileImageURL {
                    friends[idx].profileImageURL = snap.profileImageURL
                }
                if friends[idx].isAvailable != online {
                    friends[idx].isAvailable = online
                }
                if friends[idx].reliabilityPoints != snap.reliabilityPoints {
                    friends[idx].reliabilityPoints = snap.reliabilityPoints
                }
            } else {
                Haptic.friendAdded()   // Neuer Freund via Firebase-Observer
                friends.append(User(
                    name: snap.name,
                    emoji: "👋",
                    isAvailable: online,
                    statusMessage: "",
                    profileImageURL: snap.profileImageURL,
                    firebaseUID: snap.uid,
                    reliabilityPoints: snap.reliabilityPoints
                ))
            }
        }

        // Lokale Einträge entfernen, deren UID nicht mehr in der Snapshot-Liste ist
        // (Freund wurde gelöscht, auf anderem Gerät entfreundet etc.). Legacy-Einträge
        // ohne UID lassen wir in Ruhe — Server ist nicht authoritativ über sie.
        friends.removeAll { user in
            guard let uid = user.firebaseUID else { return false }
            return !currentUIDs.contains(uid)
        }

        knownFriendUIDs = currentUIDs
        friendsObserverInitialized = true
    }

    /// Die eigentliche Push-Benachrichtigung kommt vom Cloud-Function-Trigger
    /// `onFriendshipAdded` — lokal machen wir nichts mehr, um Doppel-Pushes zu
    /// vermeiden. Wenn die Cloud Function noch nicht deployed ist, sieht der User
    /// den neuen Kontakt trotzdem sofort in der Liste (Live-Observer).
    private func notifyFriendshipAdded(name: String) {
        // Intentionally left blank — siehe functions/src/index.ts onFriendshipAdded
        _ = name
    }

    func stopObservingDropIns() {
        if let handle = joinerLocationObserverHandle, let dropID = dropInObservedDropID {
            RealtimeDBManager.shared.removeJoinerLocationObserver(handle, dropID: dropID)
        }
        joinerLocationObserverHandle = nil
        joinerLiveInfos.removeAll()
        joinerNearSinceUTC.removeAll()
        if let handle = dropInObserverHandle, let dropID = dropInObservedDropID {
            RealtimeDBManager.shared.removeDropInObserver(handle, dropID: dropID)
        }
        dropInObserverHandle = nil
        dropInObservedDropID = nil
    }

    // MARK: - Join Request Flow (Host-Seite)

    func startObservingJoinRequests(forDropID dropID: String) {
        stopObservingJoinRequests()
        // Cutoff-Time: Anfragen die ÄLTER sind als das Drop-Erstellungs-
        // Zeitpunkt sollten unmöglich sein (fresh UUID), aber falls doch
        // — Stale-Data ignorieren statt als "Phantom-Joiner" anzuzeigen.
        // Gibt's immer noch Auto-Join-Probleme, wäre das hier zu sehen.
        let cutoff = activeDrops.first(where: { $0.id.uuidString == dropID })?.createdAt
            ?? Date().addingTimeInterval(-60)  // Fallback: max 60s alt
        joinRequestObserverHandle = RealtimeDBManager.shared.observeIncomingJoinRequests(
            dropID: dropID
        ) { [weak self] joinerID, name, emoji, age, imageURL, points, isPlus, requestedAt, message in
            guard let self = self else { return }
            // Stale-Request-Filter: alles vor cutoff = aus einem alten
            // Snapshot oder Force-Quit-Garbage. NICHT als neue Anfrage
            // verarbeiten, sonst landet ein Geist als pendingJoinRequest
            // im Sheet → Auto-Accept würde ihn nach 5 min hineinziehen.
            if requestedAt < cutoff.addingTimeInterval(-5) {
                print("[joinReq] IGNORED stale request from \(name) — requestedAt=\(requestedAt) < cutoff=\(cutoff)")
                return
            }
            // Keine doppelten Einträge
            guard !self.pendingJoinRequests.contains(where: { $0.id == joinerID }) else { return }
            print("[joinReq] new request from \(name) (\(joinerID)) for drop \(dropID)")
            let req = IncomingJoinRequest(
                id: joinerID, dropID: dropID,
                joinerName: name, joinerEmoji: emoji,
                joinerAge: age,
                joinerProfileImageURL: imageURL,
                joinerReliabilityPoints: points,
                joinerIsPlus: isPlus,
                joinerMessage: message,
                requestedAt: requestedAt
            )
            self.pendingJoinRequests.append(req)

            // App aktiv → Sheet zeigen; sonst Push
            if self.isAppActive {
                if self.activeIncomingRequest == nil {
                    self.activeIncomingRequest = req
                    Haptic.incomingRequest()
                }
            } else {
                PushNotificationManager.shared.notifyIncomingJoinRequest(
                    joinerName: "\(emoji) \(name)",
                    activityName: self.activeDrops.first?.activity.name ?? "Plan"
                )
            }

            // Auto-Accept-Timer starten
            self.scheduleAutoAccept(for: req)
        }
    }

    func stopObservingJoinRequests() {
        autoAcceptTimer?.invalidate()
        autoAcceptTimer = nil
        if let handle = joinRequestObserverHandle,
           let dropID = activeDrops.first?.id.uuidString {
            RealtimeDBManager.shared.removeJoinRequestObserver(handle, dropID: dropID)
        }
        joinRequestObserverHandle = nil
        pendingJoinRequests.removeAll()
        activeIncomingRequest = nil
    }

    func acceptJoinRequest(_ req: IncomingJoinRequest) {
        RealtimeDBManager.shared.respondToJoinRequest(
            dropID: req.dropID, joinerID: req.id, accepted: true)
        removePendingRequest(req)

        // Joiner zur participants-Liste des eigenen Drops hinzufügen, damit
        // er im Drop-Sheet (Vor Ort / Unterwegs) und in der Live Activity
        // erscheint. Match per dropID-String — DropEvent.id ist UUID, der
        // joinRequest.dropID ist String (Firebase-Key).
        if let dropIdx = activeDrops.firstIndex(where: { $0.id.uuidString == req.dropID }) {
            // Verhindern dass derselbe Joiner doppelt eingetragen wird.
            if !activeDrops[dropIdx].participants.contains(where: { $0.firebaseUID == req.id }) {
                let joinerUser = User(
                    id: UUID(),
                    name: req.joinerName,
                    emoji: req.joinerEmoji,
                    isAvailable: true,
                    statusMessage: "Unterwegs",
                    coordinate: currentUser.coordinate,
                    profileImageURL: req.joinerProfileImageURL,
                    firebaseUID: req.id,
                    reliabilityPoints: req.joinerReliabilityPoints
                )
                activeDrops[dropIdx].participants.append(joinerUser)
            }

            // Encounter pre-erstellen für die spätere BLE-Bestätigung —
            // sobald BLE-Proximity feuert, wird `confirmed = true` gesetzt
            // und der Joiner taucht im "Letzte Begegnungen"-Block auf.
            // Ohne diesen Schritt blieb die Encounter-Liste leer obwohl
            // BLE bestätigte. Doppel-Encounter werden über UID gefiltert.
            let drop = activeDrops[dropIdx]
            if !encounters.contains(where: { $0.friendUID == req.id && !$0.denied && !$0.isExpired }) {
                let encounter = Encounter(
                    friendName: req.joinerName,
                    friendEmoji: req.joinerEmoji,
                    activityEmoji: drop.activity.emoji,
                    activityName: drop.activity.name,
                    createdAt: Date(),
                    confirmed: false, denied: false,
                    friendUID: req.id,
                    friendProfileImageURL: req.joinerProfileImageURL,
                    dropID: drop.id.uuidString
                )
                encounters.insert(encounter, at: 0)
            }
        }

        refreshLiveActivityParticipants()
    }

    func declineJoinRequest(_ req: IncomingJoinRequest) {
        RealtimeDBManager.shared.respondToJoinRequest(
            dropID: req.dropID, joinerID: req.id, accepted: false)
        removePendingRequest(req)
    }

    private func removePendingRequest(_ req: IncomingJoinRequest) {
        pendingJoinRequests.removeAll { $0.id == req.id }
        // Sheet erst NACH einem kurzen Delay re-präsentieren wenn weitere
        // Requests warten — sonst frisst SwiftUI's `.sheet(item:)`-Binding
        // die schnelle nil → non-nil Transition und zeigt das nächste
        // Sheet nicht. Bei schnell aufeinanderfolgenden Anfragen war das
        // der Grund warum die 2. Anfrage „nicht ankam".
        if activeIncomingRequest?.id == req.id {
            activeIncomingRequest = nil
            if let next = pendingJoinRequests.first {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                    guard let self = self else { return }
                    // Re-Check: zwischenzeitlich könnte der Joiner cancellt
                    // haben oder ein anderer Request hat den Spot belegt.
                    if self.activeIncomingRequest == nil,
                       self.pendingJoinRequests.contains(where: { $0.id == next.id }) {
                        self.activeIncomingRequest = next
                    }
                }
            }
        }
    }

    private func scheduleAutoAccept(for req: IncomingJoinRequest) {
        let delay = req.autoAcceptAt.timeIntervalSinceNow
        let safeDelay = max(1, delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + safeDelay) { [weak self] in
            guard let self = self,
                  self.pendingJoinRequests.contains(where: { $0.id == req.id })
            else { return }
            // Noch nicht beantwortet → Auto-Accept
            self.acceptJoinRequest(req)
            PushNotificationManager.shared.notifyAutoAccepted(
                joinerName: req.joinerName,
                activityName: self.activeDrops.first?.activity.name ?? "Plan"
            )
        }
    }

    // MARK: - Join Request Flow (Joiner-Seite)

    func sendJoinRequest(to drop: MapAnnotationItem, message: String? = nil) {
        guard !isInActiveDrop else { return }
        guard !hasJoinedDrop(dropID: drop.id) else { return }
        Haptic.joinRequestSent()
        // Service-Zone-Gate: User muss in einer der 5 Launch-Städte sein um zu joinen.
        guard !BetaConfig.cityRestrictionEnabled
                || ServiceCities.isInside(currentUser.coordinate)
        else { return }
        if let leftAt = dropLeaveTimes[drop.id],
           Date().timeIntervalSince(leftAt) < AppStore.joinCooldown { return }

        myJoinRequestStatus = "pending"
        pendingJoinDropID = drop.id
        pendingJoinRequestedAt = Date()
        pendingJoinDropEmoji = drop.emoji
        pendingJoinDropActivity = drop.activity
        let uid = FirebaseAuth.Auth.auth().currentUser?.uid ?? currentUser.id.uuidString

        // Anfrage senden — inkl. optionaler Begleit-Nachricht damit der
        // Host weiß was den Joiner bewegt ("Hi, ich liebe Wandern").
        RealtimeDBManager.shared.sendJoinRequest(
            dropID: drop.id.uuidString,
            joinerID: uid,
            joinerName: currentUser.name,
            joinerEmoji: currentUser.emoji,
            joinerAge: userAge,
            profileImageURL: profileImageURL,
            reliabilityPoints: reliabilityScore.points,
            isPlus: isDropsPlusActive,
            message: message
        )

        // Direkter Drop-Observer: feuert wenn der Host den Drop beendet
        // oder Firebase den Pfad cleant, BEVOR der 5-Min-Timer abläuft.
        // Sonst hängt die Pending-Pill bei „0:00" weil die Joiner-Seite
        // gar nicht mitbekommt dass der Drop weg ist.
        if let oldHandle = pendingDropEndHandle, let oldID = pendingDropEndDropID {
            RealtimeDBManager.shared.removeJoinedDropEndObserver(oldHandle, dropID: oldID)
        }
        pendingDropEndDropID = drop.id.uuidString
        pendingDropEndHandle = RealtimeDBManager.shared.observeJoinedDropEnd(
            dropID: drop.id.uuidString
        ) { [weak self] in
            guard let self = self else { return }
            guard self.pendingJoinDropID == drop.id else { return }
            self.handleHostCancelledDrop(
                dropID: drop.id,
                dropEmoji: drop.emoji,
                dropActivity: drop.activity
            )
        }

        // Status beobachten
        myJoinStatusObserverHandle = RealtimeDBManager.shared.observeMyJoinRequestStatus(
            dropID: drop.id.uuidString, joinerID: uid
        ) { [weak self] status in
            guard let self = self else { return }
            self.myJoinRequestStatus = status
            switch status {
            case "accepted":
                Haptic.joinAccepted()
                // Pending-State clearen, Auto-Accept-Watcher canceln,
                // Push an User damit er weiß dass es jetzt läuft.
                self.pendingJoinDropID = nil
                self.pendingJoinRequestedAt = nil
                self.pendingJoinDropEmoji = ""
                self.pendingJoinDropActivity = ""
                self.pendingAutoAcceptTask?.cancel()
                self.pendingAutoAcceptTask = nil
                self.removePendingDropEndObserver()
                if !self.isAppActive {
                    PushNotificationManager.shared.notifyMyJoinAccepted(
                        hostName: drop.name, activityName: drop.activity
                    )
                }
                // Jetzt tatsächlich joinen
                self.completeJoin(drop: drop)
            case "declined":
                Haptic.joinRejected()
                self.pendingJoinDropID = nil
                self.pendingJoinRequestedAt = nil
                self.pendingJoinDropEmoji = ""
                self.pendingJoinDropActivity = ""
                self.pendingAutoAcceptTask?.cancel()
                self.pendingAutoAcceptTask = nil
                self.removePendingDropEndObserver()
                self.myJoinRequestStatus = "declined"
                // Nach 3 Sek zurücksetzen
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.myJoinRequestStatus = ""
                }
            default: break
            }
        }

        // 5-Min-Hinweis (KEIN Auto-Accept!): wenn Host nach 5 min nicht
        // reagiert, feuern wir auf Joiner-Seite nur einen lokalen Push-
        // Hinweis. Der eigentliche Auto-Accept läuft auf HOST-Seite via
        // `scheduleAutoAccept` (existiert seit Anfang) — wenn Host-App zu
        // ist passiert kein Auto-Accept, das ist ok.
        // VORHER: hier wurde respondToJoinRequest(accepted: true) gefeuert,
        // wodurch der Joiner sich SELBST in fremde Drops eintragen konnte
        // — Bug "stehe automatisch drin". Jetzt nur noch passiver Hinweis.
        // Für die UI nutzt FeedView/LiveMapView weiterhin pendingJoinDropID
        // um "Ausstehend" zu zeigen, und der Host-side Status-Observer
        // räumt den Pending-State auf wenn doch noch akzeptiert wird.
        let autoTask = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.myJoinRequestStatus == "pending",
                  self.pendingJoinDropID == drop.id else { return }
            PushNotificationManager.shared.notifyHostDidntRespond(
                hostName: drop.name, activityName: drop.activity
            )
        }
        pendingAutoAcceptTask?.cancel()
        pendingAutoAcceptTask = autoTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 5 * 60, execute: autoTask)

        // Live Activity & Annotation merken
        activeDropAnnotation = drop
        Task { @MainActor in PushNotificationManager.shared.trackAction() }
    }

    /// Räumt den direkten Drop-Observer auf, der während einer pending
    /// Beitrittsanfrage auf dem Drop-Pfad in Firebase lauscht.
    private func removePendingDropEndObserver() {
        if let handle = pendingDropEndHandle, let id = pendingDropEndDropID {
            RealtimeDBManager.shared.removeJoinedDropEndObserver(handle, dropID: id)
        }
        pendingDropEndHandle = nil
        pendingDropEndDropID = nil
    }

    /// Wird aufgerufen wenn Host akzeptiert hat — eigentlicher Join.
    /// Nach Accept: echte Koordinate (realCoordinate) verwenden statt fuzzy.
    private func completeJoin(drop: MapAnnotationItem) {
        if let handle = myJoinStatusObserverHandle {
            RealtimeDBManager.shared.removeJoinRequestObserver(handle, dropID: drop.id.uuidString)
            myJoinStatusObserverHandle = nil
        }
        myJoinRequestStatus = ""
        // Pending → Accepted: State + Auto-Watcher aufräumen.
        pendingJoinDropID = nil
        pendingAutoAcceptTask?.cancel()
        pendingAutoAcceptTask = nil

        // Nach Accept: echten Standort nutzen
        let exactCoord = drop.realCoordinate ?? drop.coordinate
        var resolvedDrop = drop
        resolvedDrop.coordinate = exactCoord
        resolvedDrop.isFuzzy    = false
        resolvedDrop.realCoordinate = nil

        // activeDropAnnotation auf den ENTFUZZTEN Drop updaten — sonst
        // zeigt der ActiveDropTabView die fuzzy Coordinate (oder gar keine,
        // weil currentActiveAnnotation die alte Fuzzy-Version nicht mehr
        // findet). Vorher: blank/weißer Tab nach Accept.
        activeDropAnnotation = resolvedDrop

        // Encounter pre-erstellen für die spätere BLE-Bestätigung — Host
        // ist der erste Eintrag in resolvedDrop.participants. Wenn BLE
        // dann das Treffen bestätigt, wird confirmed = true gesetzt und
        // der Host erscheint im "Letzte Begegnungen"-Block + als
        // Kontakt-Vorschlag.
        // Für Stranger-Drops haben `participants` keine Einträge — direkt
        // aus dem Annotation-Item (resolvedDrop) lesen.
        let hostUID   = resolvedDrop.participants.first?.firebaseUID ?? resolvedDrop.hostUID
        let hostName  = resolvedDrop.participants.first?.name        ?? resolvedDrop.name
        let hostEmoji = resolvedDrop.participants.first?.emoji       ?? resolvedDrop.emoji
        let hostImgURL = resolvedDrop.participants.first?.profileImageURL
        if let hostUID,
           !encounters.contains(where: { $0.friendUID == hostUID && !$0.denied && !$0.isExpired }) {
            let encounter = Encounter(
                friendName: hostName,
                friendEmoji: hostEmoji,
                activityEmoji: resolvedDrop.emoji,
                activityName: resolvedDrop.activity,
                createdAt: Date(),
                confirmed: false, denied: false,
                friendUID: hostUID,
                friendProfileImageURL: hostImgURL,
                dropID: resolvedDrop.id.uuidString
            )
            encounters.insert(encounter, at: 0)
        }

        let note = JoinRequest(
            id: UUID(), dropID: drop.id,
            dropEmoji: drop.emoji, dropActivity: drop.activity,
            requesterName: currentUser.name, requesterEmoji: currentUser.emoji,
            createdAt: Date(), dropCoordinate: exactCoord
        )
        joinRequests.append(note)
        setActiveJoin(drop.id)
        DropNotificationManager.scheduleExpiryReminders(for: resolvedDrop)
        startDropLiveActivity(annotation: resolvedDrop, isHost: false)

        // Nur GPS schreiben wenn wir wirklich einen Fix haben — nicht den
        // Default-München-Center. Sonst landet der Joiner-Pin beim Host
        // mitten in der Stadt, obwohl der Joiner z.B. nebenan steht.
        // Default-Coord aus User-Init: (48.1371, 11.5754) ± Toleranz.
        let isDefaultMunich = abs(currentUser.coordinate.latitude  - 48.1371) < 0.0005
                           && abs(currentUser.coordinate.longitude - 11.5754) < 0.0005
        let validGPS = !isDefaultMunich
        RealtimeDBManager.shared.joinDrop(
            dropID: drop.id.uuidString,
            joinerID: FirebaseAuth.Auth.auth().currentUser?.uid ?? currentUser.id.uuidString,
            joinerName: currentUser.name, joinerEmoji: currentUser.emoji,
            joinerAge: userAge,
            joinerLat: validGPS ? currentUser.coordinate.latitude : nil,
            joinerLng: validGPS ? currentUser.coordinate.longitude : nil
        )

        // Auf den Live-Tab (.create zeigt ActiveDropTabView wenn isInActiveDrop)
        // umschalten — sonst sieht der User die Bestätigungs-Animation
        // aber bleibt auf seinem letzten Tab (Feed/Map) hängen, ohne
        // eindeutiges Signal "du bist jetzt drin". Kleines Delay damit
        // First-Drop-Celebration und aktueller Sheet-Dismiss zuerst durch sind.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.selectedTab = .create
        }

        // First-Drop-Celebration: nur beim allerersten Join.
        maybeCelebrateFirstDrop(.joined)
    }

    func setActiveJoin(_ id: UUID) {
        PushNotificationManager.shared.cancelInactivityReminder()
        activeJoinedDropID = id
        bleConfirmedInCurrentSession = false
        joinSessionStartedAt = Date()
        UserDefaults.standard.set(joinSessionStartedAt!.timeIntervalSince1970,
                                  forKey: UDKey.joinSessionStartedAt)
        // Drop-Koordinate für GPS-Fallback merken
        joinSessionDropCoord = activeDropAnnotation?.coordinate
        joinSessionHostUID   = activeDropAnnotation?.hostUID

        // BLE-Proximity starten — Token aus firebaseUID damit Host und
        // Joiner sich gegenseitig identifizieren können (siehe myBLEToken).
        bluetoothMeetup.start(userToken: myBLEToken, dropID: id, joinedAt: Date())
        bluetoothMeetup.onMeetupConfirmed = { [weak self] partnerToken in
            guard let self else { return }
            // Ankunfts-Push: Partner-Name aus Drop-Teilnehmern nachschlagen
            let partnerName = self.activeDropAnnotation?.participants
                .first(where: { $0.token == partnerToken })?.name
            let activity = self.activeDropAnnotation?.activity ?? ""
            if let name = partnerName, !activity.isEmpty {
                PushNotificationManager.shared.notifyParticipantArrived(name: name, activityName: activity)
            }
            self.autoConfirmBLEMeetup(partnerToken: partnerToken)
        }

        // Direkt-Observer auf drops/{id} — feuert sofort wenn Host
        // cancelDrop ausführt (active: false) oder Drop gelöscht wird.
        // Wichtig fürs UX: ohne diesen Observer kriegt der Joiner den
        // Cancel-Alert erst wenn observeNearbyDrops anschlägt — was im
        // Live-Tab nicht läuft. Annotation: nutze activeDropAnnotation
        // für Emoji/Activity falls vorhanden, sonst Fallback.
        let dropEmoji = activeDropAnnotation?.emoji ?? "📍"
        let dropActivity = activeDropAnnotation?.activity ?? "Plan"
        joinedDropEndHandle = RealtimeDBManager.shared.observeJoinedDropEnd(
            dropID: id.uuidString
        ) { [weak self] in
            guard let self = self else { return }
            // Nur reagieren wenn der Drop hier noch der aktive ist
            // (Race: leaveActiveJoin könnte schon gelaufen sein).
            guard self.activeJoinedDropID == id else { return }
            self.handleHostCancelledDrop(
                dropID: id,
                dropEmoji: dropEmoji,
                dropActivity: dropActivity
            )
        }
    }

    func leaveActiveJoin() {
        // Joiner-Feedback-Prompt — VOR den defer-Cleanups auswerten,
        // sonst sind activeDropAnnotation/joinSessionStartedAt schon weg.
        // Nur wenn die Session lang genug war (≥ 5 min), damit ein 30-
        // Sek.-Try nicht direkt eine Bewertung des Hosts auslöst.
        if let started = joinSessionStartedAt,
           Date().timeIntervalSince(started) >= 5 * 60 {
            presentJoinerFeedbackPrompt()
        }
        defer {
            bluetoothMeetup.stop()
            bleConfirmedInCurrentSession = false
            UserDefaults.standard.removeObject(forKey: UDKey.joinSessionStartedAt)
            joinSessionStartedAt         = nil
            joinSessionDropCoord         = nil
            joinSessionHostUID           = nil
            // Joiner aus dropins/-Node entfernen, sonst sieht der Host weiter
            // unseren Pin auf der Karte UND einen Eintrag im Vor-Ort-/
            // Unterwegs-Block. Beides gilt als "noch dabei".
            if let joinedID = activeJoinedDropID,
               let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
                RealtimeDBManager.shared.removeJoinerFromDrop(
                    dropID: joinedID.uuidString, joinerID: uid
                )
                // Lokalen joinRequest-Eintrag entfernen — sonst zeigt der
                // Umgebungs-Tab (FeedView) weiter "Bin dabei!", weil
                // hasJoinedDrop(dropID:) auch in `joinRequests` schaut.
                joinRequests.removeAll { $0.dropID == joinedID }
                // Pending-Status zurücksetzen — falls wir noch in der
                // "Warte auf Bestätigung"-Phase waren.
                myJoinRequestStatus = ""
                if pendingJoinDropID == joinedID {
                    pendingJoinDropID = nil
                    pendingAutoAcceptTask?.cancel()
                    pendingAutoAcceptTask = nil
                }
                // Cooldown-Timestamp setzen damit der User den Drop nicht
                // sofort wieder joinen kann (existierende Logik in
                // leaveDropJoin macht das gleich für den ID-spezifischen
                // Fall — hier replizieren für den activeJoinedDropID-Pfad).
                dropLeaveTimes[joinedID] = Date()

                // Drop-End-Observer abräumen — sonst läuft er weiter und
                // könnte beim nächsten Join (= neue ID, neuer Observer)
                // duplicate Callbacks erzeugen.
                if let handle = joinedDropEndHandle {
                    RealtimeDBManager.shared.removeJoinedDropEndObserver(
                        handle, dropID: joinedID.uuidString
                    )
                    joinedDropEndHandle = nil
                }
            }
            activeJoinedDropID           = nil
            activeDropAnnotation         = nil
        }

        // Encounter für zu kurze Sessions entfernen — sonst würde manuelles
        // Bestätigen Punkte für einen 2-Min-Drop vergeben. Erst ab 15 Min
        // sind Begegnungen sinnvoll. BLE-confirmed bleiben immer erhalten.
        if let joinedID = activeJoinedDropID,
           let startedAt = joinSessionStartedAt,
           Date().timeIntervalSince(startedAt) < Self.minPaidDropDuration {
            let dropIDStr = joinedID.uuidString
            encounters.removeAll { $0.dropID == dropIDStr && !$0.confirmed }
        }

        // Mindestzeit: erst nach 10 Min ist man "committed" genug für Score-Einfluss
        guard let startedAt = joinSessionStartedAt,
              Date().timeIntervalSince(startedAt) >= 10 * 60 else { return }

        // Joiner-PastDrop erstellen — landet in "Letzte Drops" + Statistik.
        // Nur wenn ≥ 10 min dabei war (gleicher Schwellwert wie Score-Einfluss).
        if let annotation = activeDropAnnotation {
            let hostParticipant = PastDropParticipant(
                name: annotation.name,
                emoji: annotation.emoji,
                reliabilityScore: annotation.hostReliabilityPoints ?? 100,
                wasHost: true,
                didShowUp: true,
                profileImageURL: annotation.participants.first?.profileImageURL
            )
            let selfParticipant = PastDropParticipant(
                name: currentUser.name,
                emoji: currentUser.emoji,
                reliabilityScore: reliabilityScore.points,
                wasHost: false,
                didShowUp: true,
                profileImageURL: profileImageURL
            )
            let past = PastDrop(
                activityEmoji: annotation.emoji,
                activityName: annotation.activity,
                locationName: annotation.locationTitle.isEmpty
                    ? annotation.activity : annotation.locationTitle,
                date: startedAt,
                wasHost: false,
                participants: [hostParticipant, selfParticipant],
                latitude:  annotation.realCoordinate?.latitude  ?? annotation.coordinate.latitude,
                longitude: annotation.realCoordinate?.longitude ?? annotation.coordinate.longitude
            )
            if !pastDrops.contains(where: { $0.date == past.date && $0.activityName == past.activityName }) {
                pastDrops.insert(past, at: 0)
                saveAll()
            }
        }

        // Encounter auto-bestätigen — 10 min Anwesenheit reicht als Nachweis,
        // auch ohne BLE. Damit erscheint "Hinzufügen" in „Letzte Begegnungen".
        if let joinedID = activeJoinedDropID {
            let dropIDStr = joinedID.uuidString
            if let idx = encounters.firstIndex(where: {
                $0.dropID == dropIDStr && !$0.confirmed && !$0.denied
            }) {
                encounters[idx].confirmed = true
                generateFriendSuggestions(from: encounters[idx])
                saveAll()
            }
        }

        // Share-Card + 24h-Inactivity-Push triggern
        if let annotation = activeDropAnnotation {
            let emoji    = annotation.emoji
            let activity = annotation.activity
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.dropSuccessShareData = DropSuccessShareData(
                    activityEmoji: emoji, activityName: activity, wasHost: false
                )
            }
            PushNotificationManager.shared.scheduleInactivityReminder()
        }

        // Bereits per BLE bestätigt → kein No-Show nötig
        if bleConfirmedInCurrentSession { return }

        // GPS-Fallback ENG: User muss < 50 m am Drop-Standort gewesen
        // sein UND die Session ≥ 10 min gelaufen sein. Vorher 150 m war
        // viel zu großzügig — User die nur kurz vorbeigegangen sind
        // bekamen Punkte. Jetzt: nur echte Anwesenheit zählt.
        if let dropCoord = joinSessionDropCoord {
            let userLoc = CLLocation(latitude: currentUser.coordinate.latitude,
                                     longitude: currentUser.coordinate.longitude)
            let dropLoc = CLLocation(latitude: dropCoord.latitude,
                                     longitude: dropCoord.longitude)
            let dist = userLoc.distance(from: dropLoc)

            if dist < Self.gpsConfirmThresholdMeters {
                // GPS bestätigt physische Anwesenheit → Show-up + Encounter bestätigen
                Haptic.gpsArrival()

                // Encounter bestätigen (GPS-Fallback wenn BLE nicht verfügbar war).
                // Gleiche Anti-Farm-Checks wie autoConfirmBLEMeetup:
                //   1) Drop muss ≥ minPaidDropDuration aktiv gewesen sein
                //   2) Pair darf nicht auf 12-h-Cooldown stehen
                let dropAgeOK: Bool = {
                    guard let started = joinSessionStartedAt else { return true }
                    return Date().timeIntervalSince(started) >= Self.minPaidDropDuration
                }()
                let currentDropID = activeJoinedDropID?.uuidString
                if dropAgeOK && !isPairOnCooldown(otherUID: joinSessionHostUID),
                   let idx = encounters.firstIndex(where: {
                       (currentDropID == nil || $0.dropID == currentDropID) && !$0.confirmed && !$0.denied
                   }) {
                    encounters[idx].confirmed = true
                    generateFriendSuggestions(from: encounters[idx])
                    markPairAwarded(otherUID: joinSessionHostUID)
                }

                nextPointsReason = tr("models.reason_gps")
                reliabilityScore.totalCommits += 1
                reliabilityScore.showUps += 1
                applyStreakBonus()
                maybeAwardFirstArrivalBonus()
                maybeAwardDropInviteBonusToHost()
                saveAll()
                pushReliabilityScoreToFirestore()
                return
            }

            // Weiter weg als 50 m → No-Show, kein „GPS-Drive-By"-Bonus
            reliabilityScore.totalCommits += 1
            reliabilityScore.noShows += 1
            breakStreak()
            saveAll()
            pushReliabilityScoreToFirestore()
            return
        }

        // Kein GPS-Standort verfügbar → neutral (kein Score-Einfluss)
    }

    /// Wird aufgerufen wenn BLE-Proximity eine Begegnung automatisch bestätigt hat.
    private func autoConfirmBLEMeetup(partnerToken: String) {
        bleConfirmedInCurrentSession = true   // Verhindert No-Show beim Verlassen
        Haptic.meetupConfirmed()

        // Anti-Farm Layer 1+2 (Joiner-Seite):
        //   1) Drop muss seit Start ≥ 15 min laufen (sonst zu kurz für Punkte)
        //   2) Pair (ich + Host) darf nicht auf 12 h-Cooldown stehen
        // Beide Schichten verhindern Punkte-Farming durch Alt-Account-Setups.
        // Ein BLE-bestätigtes Treffen aus einem Farm-Drop wird also nur
        // als ShowUp markiert (keine Encounter-Belohnung), Streak/Score
        // bleiben unberührt.
        let dropAgeOK: Bool = {
            guard let started = joinSessionStartedAt else { return true }
            return Date().timeIntervalSince(started) >= Self.minPaidDropDuration
        }()
        let hostUID = activeDropAnnotation?.hostUID
        let pairOK = !isPairOnCooldown(otherUID: hostUID)

        guard dropAgeOK && pairOK else {
            // Kein Score-Effekt — aber den Encounter trotzdem als bestätigt
            // markieren, damit kein "Nicht erschienen" hinten dran droht.
            let currentDropID = activeJoinedDropID?.uuidString
            if let idx = encounters.firstIndex(where: {
                (currentDropID == nil || $0.dropID == currentDropID) && !$0.confirmed && !$0.denied
            }) {
                encounters[idx].confirmed = true
                generateFriendSuggestions(from: encounters[idx])
            }
            if !dropAgeOK {
                let neededMins = Int(Self.minPaidDropDuration / 60)
                showInfoToast(tr("models.drop_too_short").replacingOccurrences(of: "{mins}", with: "\(neededMins)"),
                              icon: "hourglass")
            } else {
                showInfoToast("Heute schon getroffen — keine Punkte (12 h Cooldown)",
                              icon: "clock.arrow.circlepath")
            }
            saveAll()
            return
        }

        // Offenen Encounter suchen, der zu diesem Drop passt
        nextPointsReason = tr("models.reason_bluetooth")
        let currentDropID = activeJoinedDropID?.uuidString
        if let idx = encounters.firstIndex(where: {
            (currentDropID == nil || $0.dropID == currentDropID) && !$0.confirmed && !$0.denied
        }) {
            encounters[idx].confirmed = true
            reliabilityScore.totalCommits += 1
            reliabilityScore.showUps += 1
            applyStreakBonus()
            maybeAwardFirstArrivalBonus()
            maybeAwardDropInviteBonusToHost()
            generateFriendSuggestions(from: encounters[idx])
        } else {
            // Kein Encounter-Eintrag vorhanden (z.B. spontaner Stranger-Drop) →
            // Score direkt gutschreiben
            reliabilityScore.totalCommits += 1
            reliabilityScore.showUps += 1
            applyStreakBonus()
            maybeAwardFirstArrivalBonus()
            maybeAwardDropInviteBonusToHost()
        }

        // Pair markieren — nächste 12 h kein Punkte-Boost mit demselben Host.
        markPairAwarded(otherUID: hostUID)

        saveAll()                           // Score lokal persistieren
        pushReliabilityScoreToFirestore()   // Score für andere sichtbar machen
    }

    @Published var reliabilityScore = ReliabilityScore(totalCommits: 0, showUps: 0, noShows: 0) {
        didSet {
            // Erster ShowUp eines Users → höflicher Push-Reask-Sheet falls er
            // im Onboarding abgelehnt hatte. Apple erlaubt keinen zweiten
            // System-Dialog, der Sheet leitet ihn dann zu den Einstellungen.
            if reliabilityScore.showUps == 1 && oldValue.showUps == 0 {
                maybeShowPushReask()
                // Ersten Drop abgeschlossen → Review-Prompt
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.shouldShowReviewPrompt = true
                    UserDefaults.standard.set(Date().timeIntervalSince1970,
                                              forKey: "ud_lastReviewRequestedAt")
                }
            }

            // Notification bei Punkt-Gewinn (Show-Up = +5, etc.).
            // Skip beim allerersten Set (App-Start mit 0:0:0 Default).
            let delta = reliabilityScore.points - oldValue.points
            if delta > 0 && oldValue.totalCommits > 0 {
                let reason: String
                if reliabilityScore.showUps > oldValue.showUps {
                    reason = "Plan besucht"
                } else if reliabilityScore.totalCommits > oldValue.totalCommits {
                    reason = "Plan verbindlich erstellt"
                } else {
                    reason = tr("models.reason_activity")
                }
                PushNotificationManager.shared.notifyPointsEarned(
                    delta: delta,
                    totalPoints: reliabilityScore.points,
                    reason: reason
                )
            }
        }
    }

    /// Steuert das Push-Reask-Sheet (siehe `maybeShowPushReask()`).
    @Published var showPushReaskSheet: Bool = false

    /// Trigger-Flag für das native In-App-Review-Sheet (StoreKit `requestReview`).
    /// Wird gesetzt nach „guten Momenten" (3./10./25. Show-Up). LinkUpApp's
    /// ReviewPromptModifier reagiert darauf und ruft `requestReview()` auf.
    @Published var shouldShowReviewPrompt: Bool = false

    /// Wird intern aufgerufen wenn ein guter Moment vorbei ist (Show-Up bestätigt etc.).
    /// Trigger-Schwelle: showUps ∈ {3, 10, 25} und letzte Anfrage ≥90 Tage her.
    /// Apple's StoreKit limitiert intern auf 3× pro 365 Tage — falls schon erreicht
    /// ist `requestReview()` ein No-Op.
    func maybeAskForReview() {
        let triggerCounts: Set<Int> = [3, 10, 25]
        guard triggerCounts.contains(reliabilityScore.showUps) else { return }

        let last = UserDefaults.standard.double(forKey: "ud_lastReviewRequestedAt")
        if last > 0 {
            let daysAgo = (Date().timeIntervalSince1970 - last) / 86_400
            guard daysAgo >= 90 else { return }
        }
        // 0.8s Delay damit Confetti / Erfolgs-Toast erst zu Ende läuft, dann Sheet
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.shouldShowReviewPrompt = true
        }
    }

    /// Steuert das Drop-Erfolg-Share-Sheet nach einem erfolgreichen Treffen.
    struct DropSuccessShareData: Identifiable {
        let id = UUID()
        let activityEmoji: String
        let activityName: String
        let wasHost: Bool
    }
    @Published var dropSuccessShareData: DropSuccessShareData? = nil

    /// Steuert das First-Drop-Celebration-Sheet — Konfetti + Welcome-Text
    /// wenn der User seinen ersten Drop erstellt oder beigetreten ist.
    /// Wert: nil = nicht zeigen, "created" / "joined" für Variante.
    @Published var firstDropCelebrationKind: FirstDropCelebration? = nil

    /// Triggert das First-Drop-Celebration-Sheet einmalig pro Variante
    /// (created / joined). Wird in UserDefaults persistiert.
    func maybeCelebrateFirstDrop(_ kind: FirstDropCelebration) {
        let ud = UserDefaults.standard
        let key = "ud_firstDrop_\(kind.rawValue)"
        guard !ud.bool(forKey: key) else { return }
        ud.set(true, forKey: key)
        firstDropCelebrationKind = kind
    }

    /// Zeigt den Reask-Sheet einmalig nach dem ersten ShowUp wenn Push nicht
    /// authorisiert ist. Der Trigger wird in UserDefaults persistiert, damit
    /// er pro User nur einmal erscheint — egal wie viele ShowUps folgen.
    private func maybeShowPushReask() {
        guard !UserDefaults.standard.bool(forKey: "ud_pushReaskShown") else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus != .authorized,
                  settings.authorizationStatus != .provisional
            else { return }
            DispatchQueue.main.async {
                self.showPushReaskSheet = true
                UserDefaults.standard.set(true, forKey: "ud_pushReaskShown")
            }
        }
    }

    @Published var alerts: [AlertItem] = []

    enum Tab: Int { case map, feed, create, alerts, profile }

    // MARK: - Computed Map / Feed Properties

    var nearbyFriends: [User] {
        // Freunde sind immer sichtbar — unabhängig vom eingestellten Radius
        friends.filter { $0.isAvailable }
    }

    var allMapAnnotations: [MapAnnotationItem] {
        // Freunde nur sichtbar wenn sie einen aktiven Drop haben
        let friendsWithDrop = nearbyFriends.filter { friend in
            activeDrops.contains { $0.host.id == friend.id && !$0.isExpired }
        }
        var items: [MapAnnotationItem] = friendsWithDrop.map {
            MapAnnotationItem(id: $0.id, name: $0.name, emoji: $0.emoji,
                              activity: $0.statusMessage, coordinate: $0.coordinate, type: .friend)
        }
        for drop in activeDrops where drop.host.id == currentUser.id && !drop.isExpired {
            // Host ist immer als "bestätigt anwesend" markiert
            let myToken = myBLEToken
            let hostAge: Int? = userBirthdate.flatMap {
                Calendar.current.dateComponents([.year], from: $0, to: Date()).year
            }
            var dropParticipants = [DropParticipant(name: currentUser.name, emoji: currentUser.emoji,
                                                     selfie: selfieImage,
                                                     reliabilityScore: reliabilityScore.points,
                                                     reliabilityCommits: reliabilityScore.totalCommits,
                                                     age: hostAge,
                                                     token: myToken,
                                                     profileImageURL: profileImageURL)]
            let dropCLLoc = CLLocation(latitude: drop.location.coordinate.latitude,
                                        longitude: drop.location.coordinate.longitude)

            // Echte akzeptierte Joiner aus drop.participants übernehmen
            // (Host-Index 0 ist currentUser → wird oben schon eingetragen,
            // also dropFirst überspringen). Live-Koordinaten kommen aus
            // joinerLiveCoordinates wenn vorhanden — sonst Drop-Pos als
            // Fallback. Damit erscheinen Joiner-Pins auf der Karte UND in
            // der Vor-Ort-/Unterwegs-Liste sobald der Host annimmt.
            for joinerUser in drop.participants.dropFirst() {
                guard let uid = joinerUser.firebaseUID else { continue }
                let joinerToken = String(uid.replacingOccurrences(of: "-", with: "").prefix(8))
                let liveCoord = joinerLiveCoordinates[uid]
                let dist: Double? = liveCoord.map {
                    CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                        .distance(from: dropCLLoc)
                }
                dropParticipants.append(DropParticipant(
                    name: joinerUser.name,
                    emoji: joinerUser.emoji,
                    reliabilityScore: joinerUser.reliabilityPoints,
                    age: nil,
                    token: joinerToken,
                    simulatedDistance: dist,
                    liveCoordinate: liveCoord,
                    profileImageURL: joinerUser.profileImageURL,
                    firebaseUID: uid
                ))
            }

            // Fallback: nearbyFriends als Demo-Pins NUR wenn echte Joiner
            // (drop.participants.count == 1, also nur der Host) noch leer
            // sind — sonst wirkt der Drop-Sheet leer beim Erstellen.
            if drop.participants.count <= 1 {
                for friend in nearbyFriends.prefix(3) {
                    let friendToken = String(friend.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
                    let friendCLLoc = CLLocation(latitude: friend.coordinate.latitude,
                                                  longitude: friend.coordinate.longitude)
                    let dist = friendCLLoc.distance(from: dropCLLoc)
                    dropParticipants.append(DropParticipant(name: friend.name, emoji: friend.emoji,
                                                             token: friendToken,
                                                             simulatedDistance: dist,
                                                             liveCoordinate: friend.coordinate,
                                                             firebaseUID: friend.firebaseUID))
                }
            }
            var ann = MapAnnotationItem(
                id: drop.id,
                name: "\(drop.activity.emoji) \(drop.activity.name)",
                emoji: drop.activity.emoji,
                activity: drop.activity.name,
                coordinate: drop.location.coordinate,
                type: .myDrop,
                dropDescription: drop.dropDescription.isEmpty ? nil : drop.dropDescription,
                scheduledTime: drop.scheduledTime,
                participants: dropParticipants,
                createdAt: drop.createdAt,
                maxParticipants: drop.maxParticipants,
                durationMinutes: drop.durationMinutes,
                dropLocationType: drop.location.type,
                locationTitle: drop.location.title
            )
            ann.communityID = drop.communityID
            items.append(ann)
        }
        // Wenn keine Live-Drops da sind → lokaler Cache (kann leer sein in Production)
        // Volle Drops bleiben drin — der Umgebungstab markiert sie als „Voll".
        // Die Map filtert sie separat in `LiveMapView.filteredAnnotations`.
        if liveStrangerDrops.isEmpty {
            items += strangerDropsCache.filter {
                !blockedUserNames.contains($0.name)
                    && ($0.creatorAgeGroup.map { $0.minAge <= ageFilterMax && $0.maxAge >= ageFilterMin } ?? true)
            }
        } else {
            let friendUIDs = Set(friends.compactMap { $0.firebaseUID })
            let joinedDropID = activeJoinedDropID?.uuidString
            let myUID = currentUser.firebaseUID ?? ""
            items += liveStrangerDrops
                .filter { !blockedUserNames.contains($0.displayName) }
                // Eigene aktive Drops nicht als Fremd-Pin zeigen — aber Ghost-Version
                // (beendeter eigener Drop) soll auf Karte + im Feed sichtbar bleiben.
                .filter { myUID.isEmpty || $0.ownerID != myUID || $0.isGhost }
                .map { drop in
                    // Stabile UUID aus dem Firebase-Key — damit joinRequests
                    // auch nach Map-Rerendering korrekt matchen.
                    // UUID(uuidString:) schlägt für Firebase-Keys ("-N8Kz...") fehl
                    // → UUID() würde random ID erzeugen → alle Pins blinken bei
                    // jedem Firebase-Update. stableUUID löst das deterministisch.
                    let stableID = UUID(uuidString: drop.id) ?? Self.stableUUID(from: drop.id)
                    let isFriendHost = friendUIDs.contains(drop.ownerID)
                    // Auch akzeptierte Join-Pfade enthüllen den echten Standort:
                    // sobald der User dem Drop beigetreten ist (activeJoinedDropID),
                    // soll der Pin nicht mehr fuzzy / locked angezeigt werden.
                    let isJoined = joinedDropID == drop.id
                    // Ghost-Drops: echter Standort wird IMMER gezeigt — der Drop
                    // ist vorbei, niemand kann mehr stalken/joinen. Bei aktiven
                    // Stranger-Drops bleibt der 800-1000m-Fuzz aktiv.
                    let revealReal = isFriendHost || isJoined || drop.isGhost
                    let displayCoord = revealReal
                        ? drop.coordinate
                        : Self.fuzzyCoordinate(drop.coordinate, minMeters: 800, maxMeters: 1000, seed: drop.id)
                    let ageGroup = drop.hostAge.map { AgeGroup.group(for: $0) }
                    var ann = MapAnnotationItem(id: stableID, name: drop.displayName, emoji: drop.emoji,
                                            activity: drop.activityName, coordinate: displayCoord,
                                            type: .stranger, scheduledTime: drop.scheduledTime,
                                            maxParticipants: drop.maxParticipants,
                                            isFuzzy: !revealReal,
                                            creatorAgeGroup: ageGroup,
                                            creatorAge: drop.hostAge,
                                            realCoordinate: drop.coordinate, hostGender: drop.hostGender,
                                            hostUID: drop.ownerID,
                                            hostReliabilityPoints: drop.hostReliabilityPoints,
                                            liveParticipantCount: drop.currentParticipants)
                    ann.communityID = drop.communityID
                    ann.isGhost = drop.isGhost
                    ann.endedAt = drop.endedAt
                    ann.locationTitle = drop.locationTitle
                    ann.isDemo = drop.isDemo
                    return ann
                }
        }
        // ── Joiner unterwegs (echter GPS-Standort des Users) ───────────
        // NUR für die eigenen Drops rendern. Sonst sieht der User auch
        // sich selber als Joiner-Pin auf seiner Karte, wenn er einem
        // fremden Drop beigetreten ist (joinRequests enthält dann seine
        // eigene ausgehende Anfrage). Eigener Standort wird bereits durch
        // den blauen System-Punkt gerendert.
        let myDropIDs = Set(activeDrops.map(\.id))
        for note in activeJoinNotifications where myDropIDs.contains(note.dropID) {
            items.append(MapAnnotationItem(
                id: note.id,
                name: note.requesterName,
                emoji: note.requesterEmoji,
                activity: "→ \(note.dropEmoji) \(note.dropActivity)",
                coordinate: currentUser.coordinate,   // Echter Standort statt Simulation
                type: .joiner
            ))
        }
        // ── Host-Sicht: Joiner-Pins basierend auf Firebase-Live-Daten ──
        // joinerLiveInfos wird durch observeJoinerLocations befüllt und
        // enthält neben coord auch Name/Emoji/Age direkt aus dem dropins-
        // Eintrag des Joiners. Damit zeigt der Pin den richtigen Namen
        // statt "Joiner"-Fallback. participants-Liste ist nur Sekundär-
        // Source falls dropins-Felder fehlen.
        if let activeDrop = activeDrops.first {
            for (joinerUID, info) in joinerLiveInfos {
                let match = activeDrop.participants.first(where: { $0.firebaseUID == joinerUID })
                let pinName  = info.name  ?? match?.name  ?? "Joiner"
                let pinEmoji = info.emoji ?? match?.emoji ?? "👤"
                let creatorAge = info.age
                // Stable UUID aus Firebase-UID-Hash. Firebase-UIDs haben NICHT
                // das UUID-Format → UUID(uuidString:) gibt nil → vorher
                // generierte das jeden Render eine NEUE UUID → SwiftUI dachte
                // es sei ein neuer Pin → die Karte hat dauerhaft re-rendert
                // (1× pro Sekunde Bug). Jetzt deterministisch via SHA-Hash.
                let id = Self.stableUUID(from: joinerUID)
                items.append(MapAnnotationItem(
                    id: id,
                    name: pinName,
                    emoji: pinEmoji,
                    activity: "→ \(activeDrop.activity.emoji) \(activeDrop.activity.name)",
                    coordinate: info.coordinate,
                    type: .joiner,
                    creatorAge: creatorAge
                ))
            }
        }
        return items
    }

    func placeStrangerDrops(around center: CLLocationCoordinate2D) {
        // Reguläre Logik: Drops kommen live aus Firebase, Cache bleibt leer.
        guard !strangerDropsPlaced else { return }
        strangerDropsPlaced = true
        strangerDropsCache = []
    }

    /// Deterministische UUID aus einem beliebigen String (z.B. Firebase-UID,
    /// die kein UUID-Format hat). FNV-1a Hash → 16 bytes UUID-Layout. Gleicher
    /// Input ergibt immer dieselbe UUID — SwiftUI behält dadurch View-Identity
    /// über Re-Renders, statt jedes Mal neue Items zu erkennen.
    static func stableUUID(from string: String) -> UUID {
        var hashLow: UInt64  = 14_695_981_039_346_656_037
        var hashHigh: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hashLow  ^= UInt64(byte)
            hashLow  &*= 1_099_511_628_211
            hashHigh ^= UInt64(byte) &+ (hashLow << 7)
            hashHigh &*= 1_099_511_628_211
        }
        let bytes: [UInt8] = (0..<16).map { i in
            let src = i < 8 ? hashLow : hashHigh
            return UInt8(truncatingIfNeeded: src >> ((i % 8) * 8))
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Versetzt eine Koordinate um einen zufälligen aber stabilen Betrag (seed-basiert).
    /// Gleicher seed → gleicher Versatz, damit der Pin nicht bei jedem Rerender springt.
    static func fuzzyCoordinate(_ coord: CLLocationCoordinate2D,
                                 minMeters: Double, maxMeters: Double,
                                 seed: String) -> CLLocationCoordinate2D {
        // Deterministischer Hash aus dem Seed → immer gleicher Versatz für denselben Drop
        var hashValue: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hashValue ^= UInt64(byte)
            hashValue &*= 1_099_511_628_211
        }
        // Winkel 0–360 und Distanz minMeters–maxMeters ableiten
        let angle = Double(hashValue % 3600) / 10.0   // 0.0 … 360.0 Grad
        let range = maxMeters - minMeters
        let dist  = minMeters + Double((hashValue >> 12) % UInt64(range))
        // 1 Grad Breitengrad ≈ 111 320 m
        let deltaLat = (dist * cos(angle * .pi / 180)) / 111_320.0
        let deltaLng = (dist * sin(angle * .pi / 180)) / (111_320.0 * cos(coord.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: coord.latitude + deltaLat,
                                      longitude: coord.longitude + deltaLng)
    }

    var nearbyDropsForFeed: [(name: String, emoji: String, status: String,
                               activity: String, place: String, eta: String, dist: String)] {
        // Wird live aus Firebase befüllt — kein Mock-Inhalt
        return []
    }

    var pendingAlertsCount: Int {
        alerts.filter { $0.status == .pending }.count
    }

    func isWithinRadius(_ coordinate: CLLocationCoordinate2D) -> Bool {
        // Spezialfall: wenn User den Max-Radius gewählt hat (≥ 50km),
        // zeigen wir ALLE Drops innerhalb seiner aktuellen Service-Stadt.
        // Das entspricht dem User-Wunsch: "in München bei Max = alle München-Drops".
        if radiusFilter >= 50000 {
            if let myCity = ServiceCities.city(for: currentUser.coordinate) {
                return myCity.contains(coordinate)
            }
        }
        let from = CLLocation(latitude: currentUser.coordinate.latitude, longitude: currentUser.coordinate.longitude)
        let to   = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return from.distance(from: to) <= radiusFilter
    }


    func startObservingLiveDrops(around coord: CLLocationCoordinate2D) {
        if let handle = dbDropsHandle { RealtimeDBManager.shared.removeObserver(handle) }
        dbDropsHandle = RealtimeDBManager.shared.observeNearbyDrops(around: coord, radiusKm: radiusFilter / 1000) { [weak self] drops in
            guard let self = self else { return }

            // 1. Eigene Drops ausfiltern — stabiler Identifier aus UserDefaults
            // Auth.auth().currentUser?.uid kann beim Start kurz nil sein → gespeicherte UID verwenden
            let myID = FirebaseAuth.Auth.auth().currentUser?.uid
                ?? UserDefaults.standard.string(forKey: UDKey.firebaseUID)
                ?? ""
            let myDropIDs = Set(self.activeDrops.map { $0.id.uuidString })
            self.liveStrangerDrops = drops.filter {
                // Eigene aktive Drops (per UID oder aktiver Drop-ID) ausblenden,
                // aber Ghost-Drops des eigenen Users durchlassen — sie sollen auf
                // Karte + Feed-Ghost-Sektion als vergangene Drops sichtbar sein.
                let byUID    = !myID.isEmpty && $0.ownerID == myID && !$0.isGhost
                let byDropID = myDropIDs.contains($0.id) && !$0.isGhost
                return !byUID && !byDropID
            }

            // Nearby-Drop-Notification auch hier triggern — sonst feuert
            // sie nur beim nächsten GPS-Update. Wenn ein neuer Drop in
            // der Nähe gerade live wird, sollte der User direkt einen
            // Push bekommen statt erst auf den nächsten Location-Heartbeat
            // zu warten. Throttle/Radius werden im Manager gehandhabt.
            if self.activeDrops.isEmpty && self.activeJoinedDropID == nil {
                let visible = self.allMapAnnotations.filter {
                    !$0.isGhost && ($0.type == .stranger || $0.type == .friend)
                }
                PushNotificationManager.shared.checkNearbyDrops(
                    visible, userLocation: self.currentUser.coordinate
                )
            }

            // 2. Auto-Leave: joinRequests bereinigen wenn der Drop vom Host gecancelt wurde
            // WICHTIG: Wenn die Drops-Liste komplett leer ist, ist das fast
            // immer ein transienter Firebase-Glitch (Host backgroundet,
            // RTDB reconnected). Auto-Leave würde den Joiner permanent
            // rauskicken. Plus: Drops außerhalb des Radius sind hier auch
            // nicht drin → bei Joiner-Bewegung würden eigene aktive Drops
            // fälschlich als „canceled" gewertet werden. Beide Fälle skippen.
            guard !drops.isEmpty else { return }

            let liveIDs = Set(drops.map { $0.id })
            let cancelledJoins = self.joinRequests.filter { req in
                !req.isExpired && !liveIDs.contains(req.dropID.uuidString)
            }
            // Bei Verdacht (Drop fehlt im Radius-gefilterten Snapshot) NICHT
            // sofort kicken, sondern via Single-Event den DB-Pfad prüfen.
            // Wenn wirklich gelöscht → Auto-Leave. Wenn nur außer Reichweite
            // → ignorieren, der Drop läuft weiter.
            for req in cancelledJoins {
                let dropIDString = req.dropID.uuidString
                let dropEmoji = req.dropEmoji
                let dropActivity = req.dropActivity
                let dropID = req.dropID
                RealtimeDBManager.shared.dropExists(dropID: dropIDString) { [weak self] exists in
                    guard let self = self else { return }
                    if exists {
                        // Drop läuft noch — der ist nur aus dem Radius gerutscht
                        // oder gerade nicht im Snapshot. NICHT auto-leaven.
                        return
                    }
                    // Wirklich gelöscht → User informieren + cleanen.
                    self.handleHostCancelledDrop(
                        dropID: dropID,
                        dropEmoji: dropEmoji,
                        dropActivity: dropActivity
                    )
                }
            }
        }
    }

    /// Cleanup wenn der Host einen Drop wirklich beendet hat (per
    /// Single-Event-Check bestätigt). Refactor aus dem Auto-Leave-Loop —
    /// damit der DB-Existenz-Check sauber strukturiert bleibt.
    private func handleHostCancelledDrop(dropID: UUID, dropEmoji: String, dropActivity: String) {
        // Alert zeigen — auch wenn Joiner nur pending war (nicht voll dabei).
        // Vorher nur bei activeJoinedDropID-Match → Joiner mit pending
        // Anfrage bekam nichts mit.
        let isRelevant = self.activeJoinedDropID == dropID
                         || self.pendingJoinDropID == dropID
        if isRelevant {
            self.hostCancelledDropAlert = HostCancelledAlert(
                dropEmoji: dropEmoji,
                activityName: dropActivity
            )
            if !self.isAppActive {
                PushNotificationManager.shared.notifyHostCancelledDrop(
                    dropEmoji: dropEmoji,
                    activityName: dropActivity
                )
            }
        }
        self.joinRequests.removeAll { $0.dropID == dropID }
        if self.activeJoinedDropID == dropID { self.leaveActiveJoin() }
        if self.pendingJoinDropID == dropID {
            self.pendingJoinDropID = nil
            self.pendingJoinRequestedAt = nil
            self.pendingJoinDropEmoji = ""
            self.pendingJoinDropActivity = ""
            self.pendingAutoAcceptTask?.cancel()
            self.pendingAutoAcceptTask = nil
            self.myJoinStatusObserverHandle = nil
            self.removePendingDropEndObserver()
        }
        self.myJoinRequestStatus = ""
        DropNotificationManager.cancelReminders(for: dropID)
        self.endDropLiveActivity()
    }


    // MARK: - Host-Cancelled-Drop Alert
    //
    // Wird gesetzt wenn der Host einen Drop beendet, dem dieser User
    // beigetreten war. MainTabView bindet ein Sheet/Alert an diesen
    // State und zeigt einen Hinweis, weil der Drop sonst stillschweigend
    // aus der UI verschwinden würde.
    struct HostCancelledAlert: Identifiable, Equatable {
        let id = UUID()
        let dropEmoji: String
        let activityName: String
    }
    @Published var hostCancelledDropAlert: HostCancelledAlert? = nil

    // MARK: - Drop-Feedback (👍/👎 nach Drop-Ende)
    //
    // Nach jedem abgeschlossenen Drop fragt die App den User wie es war —
    // jeweils pro Mit-Teilnehmer ein 👍 oder 👎. Funktioniert für beide
    // Seiten:
    //   - Host: bewertet alle Joiner die wirklich vor Ort waren
    //   - Joiner: bewertet den Host
    // Votes landen unter userFeedback/{ratedUID}/{raterUID}_{dropID} in
    // Firebase. Aggregat-Score für den Bewerteten wird serverseitig
    // berechnet (TODO Cloud Function), Client schreibt nur den Vote.
    struct FeedbackTarget: Identifiable, Equatable {
        let id: String           // ratedUID (Firebase)
        let name: String
        let emoji: String
        let profileImageURL: String?
        let wasHost: Bool        // markiert den Host in der Liste
    }

    struct DropFeedbackPrompt: Identifiable, Equatable {
        let id = UUID()
        let dropID: String
        let dropEmoji: String
        let dropActivity: String
        let targets: [FeedbackTarget]
        /// Welche Rolle hatte ICH bei dem Drop — fürs UI-Wording
        /// ("Wie waren deine Gäste?" vs. "Wie war der Host?").
        let wasHostMyself: Bool
    }
    @Published var pendingFeedbackPrompt: DropFeedbackPrompt? = nil

    /// Schreibt einen Vote zu Firebase. Idempotent über (rater, drop, rated).
    func submitFeedbackVote(ratedUID: String, dropID: String, vote: String) {
        let myUID = FirebaseAuth.Auth.auth().currentUser?.uid
            ?? UserDefaults.standard.string(forKey: UDKey.firebaseUID)
            ?? ""
        guard !myUID.isEmpty else { return }
        RealtimeDBManager.shared.submitDropFeedback(
            raterUID: myUID, ratedUID: ratedUID,
            dropID: dropID, vote: vote
        )
    }

    /// Host-Trigger: nach `cancelDrop` mit echten Joinern. Baut Liste der
    /// Bewertbaren (alle außer ich selber, mit firebaseUID).
    fileprivate func presentHostFeedbackPrompt(drop: DropEvent,
                                               participants: [User]) {
        let targets = participants.compactMap { user -> FeedbackTarget? in
            guard let uid = user.firebaseUID, !uid.isEmpty,
                  user.name != currentUser.name else { return nil }
            return FeedbackTarget(
                id: uid, name: user.name, emoji: user.emoji,
                profileImageURL: user.profileImageURL, wasHost: false
            )
        }
        guard !targets.isEmpty else { return }
        // Mit kleiner Verzögerung damit der Drop-Verlauf-Toast nicht überlappt
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.pendingFeedbackPrompt = DropFeedbackPrompt(
                dropID: drop.id.uuidString,
                dropEmoji: drop.activity.emoji,
                dropActivity: drop.activity.name,
                targets: targets,
                wasHostMyself: true
            )
        }
    }

    /// Joiner-Trigger: beim `leaveActiveJoin` wenn Session ≥ 5 min lief
    /// (sonst zu kurz für ein sinnvolles Feedback).
    fileprivate func presentJoinerFeedbackPrompt() {
        guard let annotation = activeDropAnnotation,
              let host = annotation.participants.first,
              let hostUID = host.firebaseUID ?? annotation.hostUID,
              !hostUID.isEmpty else { return }
        let target = FeedbackTarget(
            id: hostUID,
            name: host.name.isEmpty ? annotation.name : host.name,
            emoji: host.emoji.isEmpty ? annotation.emoji : host.emoji,
            profileImageURL: host.profileImageURL,
            wasHost: true
        )
        let dropEmoji = annotation.emoji
        let dropActivity = annotation.activity
        let dropID = annotation.id.uuidString
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.pendingFeedbackPrompt = DropFeedbackPrompt(
                dropID: dropID,
                dropEmoji: dropEmoji,
                dropActivity: dropActivity,
                targets: [target],
                wasHostMyself: false
            )
        }
    }

    // MARK: - Drop-Einladung von einem Freund (Empfänger-Seite)

    /// Eingehende Drop-Einladung. Wird gesetzt wenn ein Freund mich via
    /// MiniProfileSheet → "Zu meinem Drop einladen" angetippt hat.
    struct IncomingDropInvitation: Identifiable, Equatable {
        let id: String           // = inviteID (Firebase-Key)
        let dropID: String
        let dropEmoji: String
        let dropActivity: String
        let dropLat: Double
        let dropLng: Double
        let hostUID: String
        let hostName: String
        let hostEmoji: String
        let createdAt: Date

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: dropLat, longitude: dropLng)
        }
    }
    @Published var incomingDropInvitation: IncomingDropInvitation? = nil
    private var dropInvitationObserverHandle: DatabaseHandle? = nil

    /// Vom MiniProfileSheet aufgerufen: schreibt eine direkte Einladung
    /// an einen Freund für meinen aktiven Drop. Sichtbar nur wenn ich
    /// gerade hoste — UI muss das vorher prüfen.
    func inviteFriendToDrop(friendUID: String) {
        guard let drop = activeDrops.first else { return }
        let myUID = FirebaseAuth.Auth.auth().currentUser?.uid
            ?? UserDefaults.standard.string(forKey: UDKey.firebaseUID)
            ?? ""
        guard !myUID.isEmpty, !friendUID.isEmpty else { return }
        RealtimeDBManager.shared.sendDropInvitation(
            recipientUID: friendUID,
            dropID:       drop.id.uuidString,
            dropEmoji:    drop.activity.emoji,
            dropActivity: drop.activity.name,
            dropLat:      drop.location.coordinate.latitude,
            dropLng:      drop.location.coordinate.longitude,
            hostUID:      myUID,
            hostName:     currentUser.name,
            hostEmoji:    currentUser.emoji
        )
        showInfoToast("Einladung gesendet", icon: "paperplane.fill")
    }

    /// Wird beim Auth-Login einmalig aufgerufen — registriert den Observer
    /// auf eingehende Drop-Einladungen für meine UID.
    func startObservingDropInvitations() {
        if let handle = dropInvitationObserverHandle, let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
            RealtimeDBManager.shared.removeIncomingDropInvitationsObserver(handle, myUID: uid)
            dropInvitationObserverHandle = nil
        }
        guard let myUID = FirebaseAuth.Auth.auth().currentUser?.uid else {
            print("[invite] startObservingDropInvitations: SKIP — no Firebase Auth UID")
            return
        }
        print("[invite] observing dropInvitations/\(myUID)")
        dropInvitationObserverHandle = RealtimeDBManager.shared.observeIncomingDropInvitations(
            myUID: myUID
        ) { [weak self] inviteID, dropID, dropEmoji, dropActivity,
              lat, lng, hostUID, hostName, hostEmoji, createdAt in
            guard let self = self else { return }
            print("[invite] received: from=\(hostName) (\(hostUID)) drop=\(dropEmoji) \(dropActivity) inviteID=\(inviteID)")
            // Wenn der Empfänger gerade selbst hostet oder bereits in einem
            // Drop drin ist, ignorieren — sonst wäre die Einladung verwirrend.
            // Wir löschen sie aber damit sie nicht ewig im DB bleibt.
            if !self.activeDrops.isEmpty || self.activeJoinedDropID != nil {
                print("[invite] DROPPED — recipient is already hosting or in a drop")
                RealtimeDBManager.shared.dismissDropInvitation(myUID: myUID, inviteID: inviteID)
                return
            }
            // Nur die NEUSTE Einladung anzeigen — überschreibt vorherige.
            self.incomingDropInvitation = IncomingDropInvitation(
                id: inviteID, dropID: dropID,
                dropEmoji: dropEmoji, dropActivity: dropActivity,
                dropLat: lat, dropLng: lng,
                hostUID: hostUID, hostName: hostName,
                hostEmoji: hostEmoji, createdAt: createdAt
            )
            // Lokale Push-Notification falls App im Hintergrund — sonst
            // sieht der User die Einladung erst beim nächsten Foreground.
            if !self.isAppActive {
                PushNotificationManager.shared.notifyIncomingDropInvitation(
                    hostName: hostName, hostEmoji: hostEmoji,
                    activityName: dropActivity, dropEmoji: dropEmoji
                )
            }
        }
    }

    /// Empfänger lehnt ab oder schließt — Einladung aus DB löschen damit
    /// sie nicht beim nächsten App-Start nochmal aufpoppt.
    func dismissIncomingDropInvitation() {
        guard let inv = incomingDropInvitation,
              let myUID = FirebaseAuth.Auth.auth().currentUser?.uid else {
            incomingDropInvitation = nil
            return
        }
        RealtimeDBManager.shared.dismissDropInvitation(myUID: myUID, inviteID: inv.id)
        incomingDropInvitation = nil
    }

    /// Empfänger nimmt Einladung an: Drop wird zentral auf der Karte
    /// angesteuert. UI verzweigt dann auf den normalen Join-Flow.
    func acceptIncomingDropInvitation() {
        guard let inv = incomingDropInvitation else { return }
        // Damit MainTabView/LiveMapView reagieren können: pendingDropID
        // wird gesetzt — bestehender Universal-Link-Handler routet das
        // bereits auf "Map zeigen + Drop fokussieren".
        if let uuid = UUID(uuidString: inv.dropID) {
            pendingDropID = uuid
        }
        selectedTab = .map
        dismissIncomingDropInvitation()
    }

    private var hasRepositionedFriends = false
    /// Ob der User beim letzten Location-Update in der Heimzone war (für Edge-Detection).
    private var wasInHomeZone: Bool = false
    /// Throttle für Joiner-Live-Location-Push: Zeit + Coord des letzten Push.
    /// updateUserLocation pusht nur wenn ≥60s vergangen oder >50m bewegt.
    private var lastJoinerLocPushAt: Date? = nil
    private var lastJoinerLocPushCoord: CLLocationCoordinate2D? = nil

    func updateUserLocation(_ coord: CLLocationCoordinate2D) {
        currentUser.coordinate = coord
        placeStrangerDrops(around: coord)
        startObservingLiveDrops(around: coord)

        // Wenn wir gerade einem fremden Drop beigetreten sind → Live-Position
        // nach Firebase pushen, damit der Host unseren Pin auf der Karte sieht.
        // Throttle: max. 1× pro 60 Sekunden — iOS feuert Location-Updates
        // sonst alle paar Sekunden, was unnötigen Firebase-Traffic + Battery-
        // Verbrauch verursacht. Bei großen Distanz-Sprüngen (>50m) wird
        // sofort gepusht, sonst auf 60s gewartet.
        if let joinedDropID = activeJoinedDropID,
           let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastJoinerLocPushAt ?? .distantPast)
            let movedFar: Bool = {
                guard let last = lastJoinerLocPushCoord else { return true }
                let prev = CLLocation(latitude: last.latitude, longitude: last.longitude)
                let curr = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                return curr.distance(from: prev) > 50
            }()
            if elapsed >= 60 || movedFar {
                RealtimeDBManager.shared.updateJoinerLiveLocation(
                    dropID: joinedDropID.uuidString,
                    joinerID: uid,
                    lat: coord.latitude,
                    lng: coord.longitude,
                    name: currentUser.name,
                    emoji: currentUser.emoji,
                    age: userAge,
                    profileImageURL: currentUser.profileImageURL,
                    reliabilityPoints: reliabilityScore.points
                )
                lastJoinerLocPushAt = now
                lastJoinerLocPushCoord = coord
            }
        }

        // Last-Known-Location für „Drop in der Nähe"-Pushes (Cloud Function).
        // Throttled auf 1× pro 10 Min, gerundet auf ~100m (3 Nachkommastellen) für Privacy.
        RealtimeDBManager.shared.maybeUpdateLastKnownLocation(coord: coord)

        let isNowInHomeZone = isInHomeZone(coord)

        // Ghosts ignorieren — keine Push-Benachrichtigung "Drops in deiner Nähe"
        // für Drops die schon vorbei sind.
        let visible = allMapAnnotations.filter {
            !$0.isGhost && ($0.type == .stranger || $0.type == .friend)
        }

        // Radar-Widget: Anzahl aktiver Drops im Notification-Radius in App Group
        // schreiben, damit das Home-Screen-Widget "Drops in der Nähe" anzeigt.
        // WidgetCenter.reload triggert das Widget zur Neuberechnung.
        let nearbyForWidget = visible.filter { $0.isNearby(from: coord, maxMeters: notificationRadius) }
        SharedRadarStore.write(SharedRadarState(
            nearbyCount: nearbyForWidget.count,
            nextEndsAt: nil,
            updatedAt: Date()
        ))
        WidgetCenter.shared.reloadTimelines(ofKind: "RadarWidget")

        // Presence-Sharing (Opt-in): eigene Position throttled nach RTDB
        // schreiben — nur wenn User zugestimmt hat und in DE ist.
        maybeWriteMyPresence(coord: coord)

        // Nearby-Drop-Notification — nur wenn kein eigener Drop aktiv
        if activeDrops.isEmpty && activeJoinedDropID == nil {
            PushNotificationManager.shared.checkNearbyDrops(
                visible, userLocation: coord, radius: notificationRadius
            )
        }

        // Heimzone-Warnung: immer prüfen — auch wenn eigener Drop aktiv,
        // da andere Nutzer dann den ungefähren Heimstandort sehen könnten.
        if isNowInHomeZone && !wasInHomeZone {
            let nearbyRadius: Double = max(homeZoneRadius * 2, 400)
            let nearby = visible.filter { $0.isNearby(from: coord, maxMeters: nearbyRadius) }
            if !nearby.isEmpty {
                PushNotificationManager.shared.notifyHomeZoneWarning(nearbyDropCount: nearby.count)
            }
        }

        wasInHomeZone = isNowInHomeZone

        // Live Activity mit aktuellem Teilnehmer-Stand aktuell halten
        refreshLiveActivityParticipants()
        guard !hasRepositionedFriends else { return }
        let offsets: [(Double, Double)] = [
            ( 0.0019, -0.0028), (-0.0031,  0.0042), ( 0.0008,  0.0051),
            (-0.0022, -0.0019), ( 0.0065,  0.0009), (-0.0055,  0.0068)
        ]
        for i in 0..<min(friends.count, offsets.count) {
            friends[i].coordinate = CLLocationCoordinate2D(
                latitude:  coord.latitude  + offsets[i].0,
                longitude: coord.longitude + offsets[i].1
            )
        }
        hasRepositionedFriends = true
    }

    func authenticate(code: String) -> Bool {
        isAuthenticated = true
        return true
    }

    func toggleAvailability() {
        currentUser.isAvailable.toggle()
        currentUser.statusMessage = currentUser.isAvailable ? tr("models.status_available") : tr("models.status_unavailable")
    }

    func generateFriendSuggestions(from encounter: Encounter) {
        // Keine Demo-Vorschläge — echte Vorschläge kommen später via Firebase
    }

    // MARK: - Heimzone

    func setHomeZone(coordinate: CLLocationCoordinate2D) {
        homeZoneCoordinate = coordinate
        saveAll()
    }

    func removeHomeZone() {
        homeZoneCoordinate = nil
        saveAll()
    }

    func isInHomeZone(_ coord: CLLocationCoordinate2D) -> Bool {
        guard let hz = homeZoneCoordinate else { return false }
        let from = CLLocation(latitude: hz.latitude, longitude: hz.longitude)
        let to   = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return from.distance(from: to) <= homeZoneRadius
    }

    func dismissSuggestion(id: UUID) {
        friendSuggestions.removeAll { $0.id == id }
    }

    // MARK: - Dynamic Island / Live Activity
    // Hinweis: ActivityKit.Activity<T> wird vollständig qualifiziert, da
    // die lokale `Activity`-Struct (Aktivitäten wie Kaffee, Sport …)
    // sonst den Namen im Compiler auflöst.

    /// Laufende Live Activity (eine pro Nutzer, ActivityKit-Limit).
    private var currentLiveActivity: ActivityKit.Activity<DropLiveActivityAttributes>?

    /// Gecachter, aufgelöster Adress-String (Reverse-Geocode von "Aktueller Standort").
    private var geocodedDropLocationTitle: String = ""

    /// Tokens von Teilnehmern die per BLE als "vor Ort" erkannt wurden.
    private var bleArrivedTokens: Set<String> = []

    /// Wird aufgerufen wenn der Host via BLE einen Teilnehmer-Token in Reichweite erkennt.
    private func handleBLEParticipantArrived(token: String) {
        guard !bleArrivedTokens.contains(token) else { return }  // Bereits verarbeitet
        guard currentLiveActivity != nil else { return }

        // Teilnehmer mit diesem Token in allMapAnnotations suchen
        guard let myAnnotation = allMapAnnotations.first(where: { $0.type == .myDrop }),
              let myDrop = activeDrops.first(where: { !$0.isExpired }) else { return }

        let allParticipants = myAnnotation.participants
        guard let match = allParticipants.first(where: { $0.token == token }) else { return }

        bleArrivedTokens.insert(token)
        PushNotificationManager.shared.notifyParticipantArrived(name: match.name, activityName: myDrop.activity.name)

        // Teilnehmer aus onTheWay entfernen (falls er dort war) und zu arrived hinzufügen
        // Für die Live Activity: alle bekannten Teilnehmer als "vor Ort" behandeln
        let arrivedEmojis = allParticipants.map { $0.emoji }
        let arrivedNames  = allParticipants.map { $0.name }
        let urls          = allParticipants.map { $0.profileImageURL ?? "" }
        let selfies       = allParticipants.map { $0.selfie }
        let keys          = allParticipants.map { $0.token }

        Task {
            var filenames = await LiveActivityImageCache.shared.cacheImages(urlStrings: urls)
            for i in filenames.indices where filenames[i].isEmpty {
                if let selfie = selfies[i] {
                    let key = keys[i].isEmpty ? "p\(i)" : keys[i]
                    filenames[i] = LiveActivityImageCache.shared.cacheSelfie(selfie, key: key)
                }
            }

            let locationTitle = geocodedDropLocationTitle.isEmpty
                ? myDrop.location.title : geocodedDropLocationTitle

            updateDropLiveActivity(
                participantCount: allParticipants.count,
                maxParticipants: myAnnotation.maxParticipants,
                expiresAt: myDrop.expiresAt,
                locationTitle: locationTitle,
                arrivedEmojis: arrivedEmojis,
                arrivedNames: arrivedNames,
                arrivedImageFilenames: filenames,
                onTheWayEmojis: [], onTheWayNames: [], onTheWayETAs: []
            )
        }

        print("BLE: \(match.name) (\(token)) ist angekommen → Live Activity aktualisiert")
    }
    /// Letzter Refresh-Zeitpunkt — verhindert zu häufige Updates bei GPS-Bursts.
    private var lastLiveActivityRefresh: Date = .distantPast

    // MARK: - Reverse Geocode Helper

    /// Wandelt GPS-Koordinate in lesbaren Adress-String um ("Straße Nr, Stadt").
    private func reverseGeocode(_ coord: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        guard let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location),
              let p = placemarks.first else { return nil }
        var parts: [String] = []
        if let name = p.name, !name.isEmpty, name != p.thoroughfare {
            parts.append(name)
        } else {
            if let street = p.thoroughfare { parts.append(street) }
            if let num   = p.subThoroughfare { parts.append(num) }
        }
        if let city = p.locality { parts.append(city) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: - Live Activity refresh (GPS-Updates)

    /// Aktualisiert Adresse + Profilbilder der Live Activity.
    /// Wird bei GPS-Updates aufgerufen; billig wenn alles bereits gecacht ist.
    private func refreshLiveActivityParticipants() {
        guard currentLiveActivity != nil else { return }
        // Max. 1x alle 30 Sekunden refreshen (GPS feuert viel häufiger)
        let now = Date()
        guard now.timeIntervalSince(lastLiveActivityRefresh) > 30 else { return }
        lastLiveActivityRefresh = now
        guard let myAnnotation = allMapAnnotations.first(where: { $0.type == .myDrop }),
              let myDrop = activeDrops.first(where: { !$0.isExpired }) else { return }

        let arrivedEmojis    = myAnnotation.participants.map { $0.emoji }
        let arrivedNames     = myAnnotation.participants.map { $0.name }
        let urls             = myAnnotation.participants.map { $0.profileImageURL ?? "" }
        let selfies          = myAnnotation.participants.map { $0.selfie }
        let participantKeys  = myAnnotation.participants.map { $0.token }
        let cachedTitle      = geocodedDropLocationTitle

        Task {
            // 1. Profilbilder herunterladen — Selfie als Fallback wenn keine URL
            var filenames = await LiveActivityImageCache.shared.cacheImages(urlStrings: urls)
            for i in filenames.indices where filenames[i].isEmpty {
                if let selfie = selfies[i] {
                    let key = participantKeys[i].isEmpty ? "p\(i)" : participantKeys[i]
                    filenames[i] = LiveActivityImageCache.shared.cacheSelfie(selfie, key: key)
                }
            }

            // 2. Adresse auflösen — nur einmal geocoden, dann Cache nutzen
            var locationTitle = cachedTitle
            if locationTitle.isEmpty {
                let raw = myDrop.location.title
                if raw == "Aktueller Standort" || raw.isEmpty {
                    locationTitle = await reverseGeocode(myDrop.location.coordinate) ?? raw
                } else {
                    locationTitle = raw
                }
                geocodedDropLocationTitle = locationTitle
            }

            updateDropLiveActivity(
                participantCount: myAnnotation.participants.count,
                maxParticipants: myAnnotation.maxParticipants,
                expiresAt: myDrop.expiresAt,
                locationTitle: locationTitle,
                arrivedEmojis: arrivedEmojis,
                arrivedNames: arrivedNames,
                arrivedImageFilenames: filenames,
                onTheWayEmojis: [], onTheWayNames: [], onTheWayETAs: []
            )
        }
    }

    // MARK: - Admin-Notice Sheet
    //
    // Wenn ein Admin den Drop des Users entfernt (Live-Drops-Monitor mit
    // Grund-Auswahl), feuert RealtimeDBManager.observeAdminNotices und
    // wir setzen `pendingAdminNotice` — die UI bindet ein Sheet darauf
    // (sheet(item:) auf MainTabView). Der User MUSS „Verstanden" tippen,
    // dann wird der Notice in Firebase gelöscht und das Sheet
    // verschwindet. Drag-to-dismiss ist deaktiviert, damit der User die
    // Nachricht wirklich liest.

    @Published var pendingAdminNotice: RealtimeDBManager.AdminNotice? = nil
    private var adminNoticeObserverHandle: DatabaseHandle? = nil

    /// Startet den Listener auf `users/{uid}/adminNotices`. Wird beim
    /// erfolgreichen Login / App-Start aufgerufen — siehe wireAfterAuth.
    func startObservingAdminNotices() {
        // Bestehenden Observer abmelden, sonst kann der gleiche Notice
        // zweimal feuern beim Reconnect.
        if let h = adminNoticeObserverHandle {
            RealtimeDBManager.shared.removeAdminNoticesObserver(h)
            adminNoticeObserverHandle = nil
        }
        adminNoticeObserverHandle = RealtimeDBManager.shared.observeAdminNotices { [weak self] notice in
            // Nur den nächsten unbehandelten Notice präsentieren — wenn
            // schon einer im Sheet hängt, queued der neue durch das
            // childAdded-Event sowieso, sobald der User „Verstanden"
            // tippt und der vorherige aus Firebase gelöscht wird.
            guard let self = self, self.pendingAdminNotice == nil else { return }
            self.pendingAdminNotice = notice
        }
    }

    func stopObservingAdminNotices() {
        if let h = adminNoticeObserverHandle {
            RealtimeDBManager.shared.removeAdminNoticesObserver(h)
            adminNoticeObserverHandle = nil
        }
    }

    /// Wird vom Sheet-„Verstanden"-Button gerufen — löscht den Notice
    /// in Firebase und gibt das Sheet frei (UI bindet `item:` auf
    /// `pendingAdminNotice`).
    func acknowledgeAdminNotice() {
        guard let notice = pendingAdminNotice else { return }
        RealtimeDBManager.shared.acknowledgeAdminNotice(noticeID: notice.id)
        pendingAdminNotice = nil
    }

    // MARK: - Live Activity permission hint

    /// true = User wurde schon darauf hingewiesen, Live Activities zu aktivieren
    @Published var showLiveActivitySettingsHint = false

    private func checkLiveActivityEnabled() -> Bool {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        if !enabled {
            // Einmal pro App-Session anzeigen
            if !UserDefaults.standard.bool(forKey: "liveActivityHintShown") {
                showLiveActivitySettingsHint = true
                UserDefaults.standard.set(true, forKey: "liveActivityHintShown")
            }
        }
        return enabled
    }

    // MARK: - Start Live Activity

    /// Startet die Dynamic Island Live Activity für einen eigenen Drop.
    func startDropLiveActivity(drop: DropEvent, isHost: Bool) {
        guard checkLiveActivityEnabled() else { return }
        geocodedDropLocationTitle = ""   // Reset für neuen Drop

        let attributes = DropLiveActivityAttributes(
            activityName: drop.activity.name,
            activityEmoji: drop.activity.emoji,
            dropID: drop.id.uuidString,
            isHost: isHost
        )
        let arrivedEmojis = drop.participants.map { $0.emoji }
        let arrivedNames  = drop.participants.map { $0.name }
        // Profilbild SOFORT synchron verfügbar machen.
        // Priorität: 1) vorab gecachtes Firebase-Bild, 2) lokales Selfie.
        // Dadurch zeigt die Live Activity von Anfang an das Host-Profilbild.
        var initialFilenames = Array(repeating: "", count: arrivedEmojis.count)
        if !initialFilenames.isEmpty {
            if !cachedLAProfileImageFilename.isEmpty {
                initialFilenames[0] = cachedLAProfileImageFilename
            } else if let selfie = self.selfieImage {
                let key = self.currentUser.id.uuidString
                initialFilenames[0] = LiveActivityImageCache.shared.cacheSelfie(selfie, key: key)
            }
        }
        let state = DropLiveActivityAttributes.ContentState(
            participantCount: drop.participants.count,
            maxParticipants: drop.maxParticipants,
            expiresAt: drop.expiresAt,
            locationTitle: drop.location.title,   // Wird sofort async überschrieben
            arrivedEmojis: arrivedEmojis,
            arrivedNames: arrivedNames,
            arrivedImageFilenames: initialFilenames,
            onTheWayEmojis: [], onTheWayETAs: [], onTheWayNames: []
        )
        let content = ActivityContent(state: state, staleDate: drop.expiresAt)
        do {
            currentLiveActivity = try ActivityKit.Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            // Sofort Adresse + Profilbild nachladen
            let myImgURL  = self.profileImageURL ?? ""
            let mySelfie  = self.selfieImage
            let myUserKey = self.currentUser.id.uuidString
            let coord     = drop.location.coordinate
            let rawTitle  = drop.location.title
            Task {
                // Profilbild: Firebase-URL bevorzugen, sonst lokales Selfie
                var myFilename = await LiveActivityImageCache.shared.cacheImage(urlString: myImgURL)
                if myFilename.isEmpty, let selfie = mySelfie {
                    myFilename = LiveActivityImageCache.shared.cacheSelfie(selfie, key: myUserKey)
                }
                let filenames = arrivedEmojis.indices.map { i in i == 0 ? myFilename : "" }

                // Adresse geocoden wenn nötig
                var locationTitle = rawTitle
                if rawTitle == "Aktueller Standort" || rawTitle.isEmpty {
                    locationTitle = await reverseGeocode(coord) ?? rawTitle
                }
                geocodedDropLocationTitle = locationTitle

                updateDropLiveActivity(
                    participantCount: drop.participants.count,
                    maxParticipants: drop.maxParticipants,
                    expiresAt: drop.expiresAt,
                    locationTitle: locationTitle,
                    arrivedEmojis: arrivedEmojis,
                    arrivedNames: arrivedNames,
                    arrivedImageFilenames: filenames,
                    onTheWayEmojis: [], onTheWayNames: [], onTheWayETAs: []
                )
            }
        } catch {
            print("Live Activity start error: \(error)")
        }
    }

    /// Überladung für MapAnnotationItem (beim Beitreten über die Karte).
    func startDropLiveActivity(annotation: MapAnnotationItem, isHost: Bool) {
        guard checkLiveActivityEnabled() else { return }
        let attributes = DropLiveActivityAttributes(
            activityName: annotation.activity,
            activityEmoji: annotation.emoji,
            dropID: annotation.id.uuidString,
            isHost: isHost
        )
        let arrivedEmojis = annotation.participants.map { $0.emoji }
        let arrivedNames  = annotation.participants.map { $0.name }
        let state = DropLiveActivityAttributes.ContentState(
            participantCount: annotation.participants.count,
            maxParticipants: annotation.maxParticipants,
            expiresAt: annotation.expiresAt,
            locationTitle: annotation.locationTitle,   // Korrekt: Ort-Adresse, nicht Host-Name
            arrivedEmojis: arrivedEmojis,
            arrivedNames:  arrivedNames,
            arrivedImageFilenames: Array(repeating: "", count: arrivedEmojis.count),
            onTheWayEmojis: [], onTheWayETAs: [], onTheWayNames: []
        )
        let content = ActivityContent(state: state, staleDate: annotation.expiresAt)
        do {
            currentLiveActivity = try ActivityKit.Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            // Profilbilder + Adresse asynchron nachladen
            let urls      = annotation.participants.map { $0.profileImageURL ?? "" }
            let rawTitle  = annotation.locationTitle
            let coord     = annotation.coordinate
            Task {
                let filenames = await LiveActivityImageCache.shared.cacheImages(urlStrings: urls)
                var locationTitle = rawTitle
                if rawTitle.isEmpty || rawTitle == "Aktueller Standort" {
                    locationTitle = await reverseGeocode(coord) ?? rawTitle
                }
                geocodedDropLocationTitle = locationTitle
                updateDropLiveActivity(
                    participantCount: annotation.participants.count,
                    maxParticipants: annotation.maxParticipants,
                    expiresAt: annotation.expiresAt,
                    locationTitle: locationTitle,
                    arrivedEmojis: arrivedEmojis,
                    arrivedNames: arrivedNames,
                    arrivedImageFilenames: filenames,
                    onTheWayEmojis: [], onTheWayNames: [], onTheWayETAs: []
                )
            }
        } catch {
            print("Live Activity start error: \(error)")
        }
    }

    /// Aktualisiert die Live Activity mit aktuellen Teilnehmer- und Unterwegs-Daten.
    /// - arrivedEmojis/Names/ImageFilenames: Parallel-Arrays für vor Ort angekommene Personen
    /// - onTheWayEmojis/Names/ETAs: Parallel-Arrays für Personen unterwegs
    func updateDropLiveActivity(
        participantCount: Int,
        maxParticipants: Int,
        expiresAt: Date,
        locationTitle: String = "",
        arrivedEmojis: [String] = [],
        arrivedNames: [String] = [],
        arrivedImageFilenames: [String] = [],
        onTheWayEmojis: [String] = [],
        onTheWayNames: [String] = [],
        onTheWayETAs: [Int] = []
    ) {
        guard let liveActivity = currentLiveActivity else { return }
        let state = DropLiveActivityAttributes.ContentState(
            participantCount: participantCount,
            maxParticipants: maxParticipants,
            expiresAt: expiresAt,
            locationTitle: locationTitle,
            arrivedEmojis: arrivedEmojis,
            arrivedNames: arrivedNames,
            arrivedImageFilenames: arrivedImageFilenames,
            onTheWayEmojis: onTheWayEmojis,
            onTheWayETAs: onTheWayETAs,
            onTheWayNames: onTheWayNames
        )
        let content = ActivityContent(state: state, staleDate: expiresAt)
        Task { await liveActivity.update(content) }
    }

    /// Beendet die Live Activity sofort (Drop beendet / verlassen).
    /// Beendet ALLE laufenden Activities dieses Typs — auch Reste aus früheren App-Sessions,
    /// bei denen currentLiveActivity nil ist (z.B. nach Account-Wechsel oder App-Neustart).
    ///
    /// **Persistence-Marker:** `await activity.end(...)` ist ein Netzwerk-Call an Apple.
    /// Wenn die App nach dem User-Tap auf "Drop beenden" schnell suspendiert
    /// (Apple Watch-Szenario), kann der Task unterbrochen werden und die Activity
    /// bleibt zombiehaft aktiv. Deshalb merken wir die pending Activity-IDs in
    /// UserDefaults — beim nächsten App-Start werden sie garantiert beendet.
    func endDropLiveActivity() {
        let pendingIDs = ActivityKit.Activity<DropLiveActivityAttributes>.activities.map { $0.id }
        if !pendingIDs.isEmpty {
            UserDefaults.standard.set(pendingIDs, forKey: "ud_liveActivitiesPendingEnd")
        }
        currentLiveActivity = nil

        Task {
            for activity in ActivityKit.Activity<DropLiveActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
            }
            // Alle durch → Marker räumen
            await MainActor.run {
                UserDefaults.standard.removeObject(forKey: "ud_liveActivitiesPendingEnd")
            }
        }
    }

    func createDrop(activity: Activity, location: DropLocation,
                    description: String = "", scheduledTime: String = "Jetzt",
                    maxParticipants: Int = 10, durationMinutes: Int = 120,
                    communityID: String? = nil) {
        PushNotificationManager.shared.cancelInactivityReminder()
        // Community-Drops dürfen bis zu 100 Teilnehmer haben (Laufgruppen etc).
        // Normale Drops bleiben auf 2-15 begrenzt.
        let cap = communityID != nil ? 100 : 15
        var drop = DropEvent(
            id: UUID(), host: currentUser, activity: activity, location: location,
            participants: [currentUser], createdAt: Date(),
            dropDescription: description, scheduledTime: scheduledTime,
            maxParticipants: max(2, min(cap, maxParticipants)),
            durationMinutes: durationMinutes
        )
        drop.communityID = communityID
        activeDrops.append(drop)
        // Defensives Cleanup gegen Auto-Join-Bug: falls aus irgendeinem
        // Grund Stale-Data unter joinRequests/{newID} oder dropins/{newID}
        // existiert (sehr unwahrscheinlich mit fresh UUID, aber kostet nix
        // und verhindert Phantom-Joiner), aufräumen vor dem Observer-Setup.
        RealtimeDBManager.shared.cleanupJoinRequests(dropID: drop.id.uuidString)
        RealtimeDBManager.shared.cleanupDropIns(dropID: drop.id.uuidString)
        print("[createDrop] new dropID=\(drop.id.uuidString) — cleared any stale join/dropin data")
        let firebaseUID = FirebaseAuth.Auth.auth().currentUser?.uid ?? currentUser.id.uuidString
        RealtimeDBManager.shared.publishDrop(
            dropID: drop.id.uuidString, userID: firebaseUID,
            displayName: currentUser.name, emoji: activity.emoji,
            activityName: activity.name, coordinate: location.coordinate, radius: radiusFilter,
            expiresAt: drop.expiresAt, scheduledTime: scheduledTime, hostGender: userGender,
            hostAge: userAge, hostReliabilityPoints: reliabilityScore.points,
            maxParticipants: drop.maxParticipants,
            communityID: communityID
        )
        // Community-Drop → automatischer Push an alle Mitglieder via
        // communityPushQueue. Die Cloud Function fan-out'et das an die FCM-Tokens.
        if let cid = communityID {
            CommunityManager.shared.sendPush(
                communityID: cid,
                title: "\(activity.emoji) Neuer \(activity.name)-Plan",
                body:  tr("models.community_drop_created").replacingOccurrences(of: "{name}", with: currentUser.name)
            ) { _ in /* fire-and-forget */ }
        }
        // KEINE Punkte mehr fürs reine Erstellen — alle Boni (creation,
        // boost, power-hour) müssen erarbeitet werden:
        //   - jemand kommt zu meinem Drop → recordHostSuccess
        //   - ich treffe jemanden bei fremdem Drop → confirmEncounter
        // Sonst wäre Punkte-Farming durch Erstellen + sofortiges Beenden
        // möglich. `creationBonusPoints` bleibt als Feld erhalten damit
        // alte gespeicherte Werte nicht verloren gehen, wird aber nicht
        // mehr inkrementiert.
        saveAll()
        pushReliabilityScoreToFirestore()
        DropNotificationManager.requestPermission()   // Lazy: erst beim ersten Drop fragen
        DropNotificationManager.scheduleExpiryReminders(for: drop)
        startDropLiveActivity(drop: drop, isHost: true)
        Task { @MainActor in PushNotificationManager.shared.trackAction() }

        // First-Drop-Celebration: nur beim allerersten eigenen Drop.
        maybeCelebrateFirstDrop(.created)
        Haptic.dropCreated()

        // Host beobachtet eingehende DropIns (nach Accept) und neue Join-Requests
        startObservingDropIns(forDropID: drop.id.uuidString)
        startObservingJoinRequests(forDropID: drop.id.uuidString)
        startObservingDropViews(forDropID: drop.id.uuidString)

        // BLE: Host scannt nach Teilnehmer-Tokens desselben Drops.
        // Token aus firebaseUID — matched mit dem was acceptJoinRequest
        // für Joiner-Participant.token setzt, sodass die UI-Filter
        // (`participants.filter { confirmedTokens.contains($0.token) }`)
        // korrekt greifen können.
        bluetoothMeetup.start(userToken: myBLEToken, dropID: drop.id, joinedAt: Date())
        bluetoothMeetup.onParticipantNearby = { [weak self] token in
            self?.handleBLEParticipantArrived(token: token)
        }
        // WICHTIG: Auch Host-Seite muss `onMeetupConfirmed` setzen — sonst
        // wird die Encounter (in `acceptJoinRequest` pre-erstellt) niemals
        // auf confirmed=true geflippt obwohl BLE den Joiner ≥20s gesehen
        // hat. Genau das war der „BLE bestätigt nicht nach 15 min"-Bug.
        bluetoothMeetup.onMeetupConfirmed = { [weak self] partnerToken in
            self?.autoConfirmBLEMeetup(partnerToken: partnerToken)
        }

        saveAll()
    }

    func extendDrop(id: UUID, byMinutes: Int) {
        guard let idx = activeDrops.firstIndex(where: { $0.id == id }) else { return }
        // Verlängerung ab jetzt oder ab dem bisherigen Ablauf (je nachdem was später ist)
        let base = max(activeDrops[idx].expiresAt, Date())
        let newExpiry = base.addingTimeInterval(Double(byMinutes) * 60)
        // durationMinutes so anpassen dass expiresAt = newExpiry
        activeDrops[idx].durationMinutes = Int(newExpiry.timeIntervalSince(activeDrops[idx].createdAt) / 60)
        RealtimeDBManager.shared.extendDropExpiry(dropID: id.uuidString, newExpiry: newExpiry)
        // Neue Ablauf-Erinnerungen planen
        DropNotificationManager.cancelReminders(for: id)
        DropNotificationManager.scheduleExpiryReminders(for: activeDrops[idx])
        saveAll()
    }

    func cancelDrop(id: UUID) {
        stopObservingDropIns()
        stopObservingJoinRequests()
        RealtimeDBManager.shared.cleanupJoinRequests(dropID: id.uuidString)
        RealtimeDBManager.shared.cleanupDropIns(dropID: id.uuidString)
        // Drei Fälle bei Host-Cancel:
        //   1) ≥2 Teilnehmer da → Host-Erfolg (+8) + Neuling-Bonus
        //   2) Pending Joiner wartet ≥12 min → Host-No-Show (-25)
        //   3) Sonst (kein Joiner, oder noch frische Anfrage <12 min) → KEINE Buchung
        //
        // Launch-Phase-Toleranz: solange kein Joiner unterwegs war, wird ein Cancel
        // gar nicht in der Quote sichtbar. Verhindert dass User in Städten mit wenig
        // Aktivität durch reines Trying „bestraft" werden.
        if let drop = activeDrops.first(where: { $0.id == id }) {
            let pendingForThisDrop = pendingJoinRequests.filter { $0.dropID == id.uuidString }
            let hasOldPending = pendingForThisDrop.contains {
                Date().timeIntervalSince($0.requestedAt) >= 12 * 60
            }

            if drop.participants.count >= 2 {
                // (1) Erfolg — Drop hatte mindestens einen Joiner.
                let others = Array(drop.participants.dropFirst())
                let asDropParts = others.map { user in
                    // firebaseUID durchreichen — recordHostSuccess braucht
                    // sie für den Pair-Cooldown-Filter. Vorher wurde die UID
                    // hier verschluckt → kein Cooldown möglich.
                    var dp = DropParticipant(
                        name: user.name, emoji: user.emoji,
                        reliabilityScore: user.reliabilityPoints,
                        reliabilityCommits: 0
                    )
                    dp.firebaseUID = user.firebaseUID
                    dp.profileImageURL = user.profileImageURL
                    return dp
                }

                // Anti-Farm Layer 1: Drop muss ≥ 15 min aktiv gewesen sein.
                // Anti-Farm Layer 2: mindestens EIN Joiner muss wirklich
                // vor Ort gewesen sein — entweder BLE-bestätigt oder per
                // GPS-Fallback (innerhalb 20 m vom Drop-Standort UND
                // mindestens 60 s zusammenhängende Verweildauer dort).
                // Sonst gibt's keine Punkte, auch wenn jemand bloß den
                // Beitritt-Button gedrückt hat oder kurz vorbeigefahren
                // ist (= Punkte-Farming via Anfrage ohne echtes Treffen).
                let dropDuration = Date().timeIntervalSince(drop.createdAt)
                let dropLoc = CLLocation(
                    latitude: drop.location.coordinate.latitude,
                    longitude: drop.location.coordinate.longitude
                )
                let bleConfirmed = !bluetoothMeetup.confirmedTokens.isEmpty
                let now = Date()
                let anyGPSNear = drop.participants.contains { user in
                    guard let uid = user.firebaseUID,
                          let info = joinerLiveInfos[uid] else { return false }
                    let userLoc = CLLocation(latitude: info.lat, longitude: info.lng)
                    let inRadius = userLoc.distance(from: dropLoc) <= Self.gpsArrivalThresholdMeters
                    guard inRadius, let since = joinerNearSinceUTC[uid] else { return false }
                    return now.timeIntervalSince(since) >= Self.gpsArrivalDwellSeconds
                }

                if dropDuration >= Self.minPaidDropDuration && (bleConfirmed || anyGPSNear) {
                    // Unbestätigte Encounters für diesen Drop bestätigen.
                    // BLE markiert sie ggf. schon in Echtzeit; dieser Block
                    // schließt die Lücke wenn der Host kein Bluetooth hatte.
                    let dropIDStr = drop.id.uuidString
                    for idx in encounters.indices {
                        guard encounters[idx].dropID == dropIDStr,
                              !encounters[idx].confirmed,
                              !encounters[idx].denied else { continue }
                        encounters[idx].confirmed = true
                        generateFriendSuggestions(from: encounters[idx])
                    }
                    recordHostSuccess(arrivedParticipants: asDropParts)
                } else if dropDuration < Self.minPaidDropDuration {
                    let neededMins = Int(Self.minPaidDropDuration / 60)
                    showInfoToast(tr("models.drop_too_short").replacingOccurrences(of: "{mins}", with: "\(neededMins)"),
                                  icon: "hourglass")
                    // Unbestätigte Encounters für diesen Drop entfernen —
                    // sonst tauchen sie in „Letzte Begegnungen" auf und
                    // manuelles Bestätigen würde Punkte für einen 2-Min-
                    // Drop vergeben. Confirmed (BLE) bleiben erhalten.
                    let dropIDStr = drop.id.uuidString
                    encounters.removeAll { $0.dropID == dropIDStr && !$0.confirmed }
                } else {
                    // Drop war lang genug, aber keiner war wirklich da
                    showInfoToast(tr("models.no_presence_no_points"),
                                  icon: "person.fill.questionmark")
                }

                // Nur ECHTE Drops landen im Verlauf — Drops ohne Joiner
                // (Clean Cancel oder No-Show) sind nur "Versuche" und
                // sollen weder die Statistik aufblähen noch den Drop-
                // Verlauf füllen. Sonst Punkte-/Aktivitäts-Inflation.
                //
                // Filter: Host bleibt immer drin. Joiner nur wenn beim Cancel
                // noch in dropins/ — sprich seine UID ist im joinerLiveInfos-
                // Dict. Hat er verlassen, hat .childRemoved den Eintrag schon
                // rausgekickt → wird hier ausgeschlossen, taucht nicht im
                // Verlauf auf. Konservativ: ohne firebaseUID → ausgeschlossen,
                // sonst könnten alte/buggy Einträge ins pastDrops rutschen.
                let pastParticipants: [PastDropParticipant] = drop.participants.compactMap { p in
                    let isHost = p.name == currentUser.name
                    if !isHost {
                        guard let uid = p.firebaseUID,
                              joinerLiveInfos[uid] != nil else { return nil }
                    }
                    let url = isHost ? profileImageURL : p.profileImageURL
                    return PastDropParticipant(
                        name: p.name,
                        emoji: p.emoji,
                        reliabilityScore: p.reliabilityPoints,
                        wasHost: isHost,
                        didShowUp: true,
                        profileImageURL: url
                    )
                }
                // Nur dann in den Verlauf, wenn nach Filterung mindestens
                // ein Joiner übrig ist (d.h. Host war nicht alleine). Sonst
                // war der Drop effektiv ein Cancel ohne Treffen.
                if pastParticipants.contains(where: { !$0.wasHost }) {
                    let past = PastDrop(
                        activityEmoji: drop.activity.emoji,
                        activityName: drop.activity.name,
                        locationName: drop.location.title,
                        date: drop.createdAt,
                        wasHost: true,
                        participants: pastParticipants,
                        latitude:  drop.location.coordinate.latitude,
                        longitude: drop.location.coordinate.longitude
                    )
                    pastDrops.insert(past, at: 0)
                    // Host-Feedback-Prompt: nur Joiner mit firebaseUID, die
                    // beim Cancel noch in dropins/ waren (= echte Anwesende).
                    let stillThere = drop.participants.filter { user in
                        guard user.name != currentUser.name else { return false }
                        guard let uid = user.firebaseUID else { return false }
                        return joinerLiveInfos[uid] != nil
                    }
                    presentHostFeedbackPrompt(drop: drop, participants: stillThere)
                    // Share-Card nach erfolgreichem Host-Drop (1.5s Delay damit
                    // Feedback-Sheet zuerst erscheint)
                    let emoji = drop.activity.emoji
                    let name  = drop.activity.name
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.dropSuccessShareData = DropSuccessShareData(
                            activityEmoji: emoji, activityName: name, wasHost: true
                        )
                    }
                    PushNotificationManager.shared.scheduleInactivityReminder()
                }
            } else if hasOldPending {
                // (2) Host-No-Show: jemand wartet schon ≥12 min, Host bricht ab
                reliabilityScore.totalCommits += 1
                reliabilityScore.noShows += 1
                breakStreak()
                saveAll()
                pushReliabilityScoreToFirestore()
            }
            // (3) Sonst: clean cancel, keine Buchung — egal wie lange der Drop offen war.
        }
        activeDrops.removeAll { $0.id == id }
        currentUser.isAvailable = false
        currentUser.statusMessage = tr("models.status_unavailable")
        RealtimeDBManager.shared.cancelDrop(dropID: id.uuidString)
        DropNotificationManager.cancelReminders(for: id)
        endDropLiveActivity()
        Haptic.dropEnded()
        bluetoothMeetup.stop()
        bleArrivedTokens.removeAll()
        saveAll()
    }

    // MARK: - Drops+ Boost

    func respondToAlert(id: Int, accept: Bool) {
        if let i = alerts.firstIndex(where: { $0.id == id }) {
            alerts[i].status = accept ? .accepted : .declined
        }
    }

    func etaString(to coordinate: CLLocationCoordinate2D) -> String {
        let from = CLLocation(latitude: currentUser.coordinate.latitude, longitude: currentUser.coordinate.longitude)
        let to   = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let mins = Int(from.distance(from: to) / 80)
        return mins < 1 ? "< 1 Min" : "\(mins) Min"
    }

    func distanceString(to coordinate: CLLocationCoordinate2D) -> String {
        let from = CLLocation(latitude: currentUser.coordinate.latitude, longitude: currentUser.coordinate.longitude)
        let to   = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let m = from.distance(from: to)
        return m < 1000 ? "\(Int(m))m" : String(format: "%.1fkm", m / 1000)
    }
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

// MARK: - Live Activity Image Cache
// Downloads profile photos and stores them in the shared App Group container
// (group.com.dennis.drops / la_avatars/) so the Widget Extension can read them.

final class LiveActivityImageCache {

    static let shared = LiveActivityImageCache()
    private init() {}

    private let groupID    = "group.com.dennis.drops"
    private let folderName = "la_avatars"

    var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    private var avatarsFolderURL: URL? {
        guard let base = containerURL else { return nil }
        let folder = base.appendingPathComponent(folderName)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: nil)
        }
        return folder
    }

    /// Downloads `urlString`, saves to App Group container, returns filename or "".
    /// Bilder werden auf 256x256 runterskaliert — das Widget hat nur ~30MB Speicher,
    /// original hochauflösende Profilbilder würden den Extension-Prozess crashen.
    func cacheImage(urlString: String) async -> String {
        guard !urlString.isEmpty else { return "" }
        let filename = stableFilename(for: urlString)
        guard let folder = avatarsFolderURL else { return "" }
        let fileURL = folder.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: fileURL.path) { return filename }
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return "" }
        let resized = Self.downscale(image, maxDim: 256)
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { return "" }
        try? jpeg.write(to: fileURL, options: .atomic)
        return filename
    }

    /// Skaliert ein UIImage proportional runter, sodass die längere Kante ≤ maxDim ist.
    /// Wichtig für Widget-Speicherlimit — Original-Fotos sind oft 4000x4000.
    static func downscale(_ image: UIImage, maxDim: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        guard max(w, h) > maxDim else { return image }
        let scale = maxDim / max(w, h)
        let newSize = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize, format: {
            let f = UIGraphicsImageRendererFormat.default()
            f.scale = 1   // 1x statt Screen-Scale — Widget braucht kein @3x
            f.opaque = true
            return f
        }())
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Caches all URLs concurrently, returns filenames in the same order.
    func cacheImages(urlStrings: [String]) async -> [String] {
        await withTaskGroup(of: (Int, String).self) { group in
            for (i, url) in urlStrings.enumerated() {
                group.addTask { (i, await self.cacheImage(urlString: url)) }
            }
            var results = Array(repeating: "", count: urlStrings.count)
            for await (index, filename) in group { results[index] = filename }
            return results
        }
    }

    func loadImage(filename: String) -> UIImage? {
        guard !filename.isEmpty, let folder = avatarsFolderURL else { return nil }
        return (try? Data(contentsOf: folder.appendingPathComponent(filename))).flatMap { UIImage(data: $0) }
    }

    /// Speichert ein lokales UIImage (z.B. Selfie) direkt in den App-Group-Container.
    /// Gibt den Dateinamen zurück, oder "" bei Fehler.
    /// Bild wird auf 256px runterskaliert für Widget-Speichersicherheit.
    @discardableResult
    func cacheSelfie(_ image: UIImage, key: String) -> String {
        let filename = stableFilename(for: "selfie_\(key)") // deterministisch pro User
        guard let folder = avatarsFolderURL else { return "" }
        let resized = Self.downscale(image, maxDim: 256)
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { return "" }
        let fileURL = folder.appendingPathComponent(filename)
        try? jpeg.write(to: fileURL, options: .atomic)
        return filename
    }

    func cleanupOldImages() {
        guard let folder = avatarsFolderURL,
              let files  = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { return }
        let now = Date()
        for file in files {
            let url = folder.appendingPathComponent(file)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let mod = attrs[.modificationDate] as? Date,
               now.timeIntervalSince(mod) > 24 * 3600 {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func stableFilename(for s: String) -> String {
        var h: UInt64 = 14_695_981_039_346_656_037
        for b in s.utf8 { h ^= UInt64(b); h = h &* 1_099_511_628_211 }
        return String(h, radix: 16) + ".jpg"
    }
}
