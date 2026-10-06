import SwiftUI
import CoreLocation
import FirebaseAuth
import FirebaseDatabase

// MARK: - Activity Presets

/// Feste Liste von Sport-/Aktivitäts-Kategorien für Communities.
/// Jeder Eintrag hat einen Slug (in Firebase gespeichert), Display-Name + SF-Symbol-Icon.
// MARK: - Community Creator Badge

/// Wiederverwendbares Badge zum Anzeigen "ist Community Creator" in Profilen.
/// Wenn `community` non-nil, zeigt es auch den Activity-Icon + Namen mini.
struct CommunityCreatorBadge: View {
    let community: Community?
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: compact ? 8 : 11, weight: .bold))
            if let c = community, !compact {
                Image(systemName: c.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(c.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            } else {
                Text(tr("community.creator"))
                    .font(.system(size: compact ? 9 : 11, weight: .bold))
                    .kerning(0.4)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, compact ? 6 : 9).padding(.vertical, compact ? 2 : 4)
        .background(
            Capsule().fill(
                LinearGradient(colors: [Color.cleroGreen, Color.brand],
                               startPoint: .leading, endPoint: .trailing)
            )
        )
        .shadow(color: Color.cleroGreen.opacity(0.35), radius: 4, y: 1)
    }
}

extension AppStore {
    /// Gibt die Community zurück die der gegebene User erstellt hat (falls existiert).
    /// Quelle: live observierte `nearbyCommunities` — keine Extra-Firebase-Reads nötig.
    func communityForCreator(uid: String) -> Community? {
        nearbyCommunities.first { $0.creatorUID == uid }
    }

    /// Prüft ob bereits eine Community mit dieser Aktivität in diesem Stadtteil
    /// existiert. Pro Aktivität + Stadtteil ist nur 1 Community erlaubt.
    func duplicateCommunity(activitySlug: String, district: String, city: String) -> Community? {
        let dl = district.trimmingCharacters(in: .whitespaces).lowercased()
        let cl = city.trimmingCharacters(in: .whitespaces).lowercased()
        return nearbyCommunities.first { c in
            c.activitySlug == activitySlug
            && c.district.lowercased() == dl
            && c.city.lowercased() == cl
        }
    }
}

// MARK: - District Suggestions

/// Kuratierte Bezirks-Listen pro Stadt — werden als Scroll-Picker im
/// Antrags-Sheet angezeigt, sodass der User schnell den richtigen
/// Stadtteil auswählen kann ohne tippen zu müssen.
enum CommunityDistrict {
    static func suggestions(for city: String) -> [String] {
        let key = city.lowercased()
        switch key {
        case "münchen", "munich", "muenchen":
            return [
                "Altstadt", "Maxvorstadt", "Schwabing", "Neuhausen", "Pasing",
                "Sendling", "Giesing", "Bogenhausen", "Au-Haidhausen",
                "Schwanthalerhöhe", "Berg am Laim", "Trudering", "Ramersdorf",
                "Obergiesing", "Untergiesing", "Laim", "Moosach", "Milbertshofen"
            ]
        case "berlin":
            return [
                "Mitte", "Friedrichshain", "Kreuzberg", "Prenzlauer Berg",
                "Charlottenburg", "Wilmersdorf", "Schöneberg", "Tempelhof",
                "Neukölln", "Wedding", "Moabit", "Pankow", "Lichtenberg",
                "Steglitz", "Spandau", "Zehlendorf", "Köpenick", "Treptow"
            ]
        case "hamburg":
            return [
                "Altona", "Eimsbüttel", "St. Pauli", "St. Georg", "Eppendorf",
                "Winterhude", "Ottensen", "Schanzenviertel", "HafenCity",
                "Wandsbek", "Harvestehude", "Rotherbaum", "Barmbek", "Uhlenhorst",
                "Hammerbrook", "Bergedorf", "Harburg"
            ]
        case "köln", "cologne", "koeln":
            return [
                "Innenstadt", "Altstadt-Nord", "Altstadt-Süd", "Belgisches Viertel",
                "Ehrenfeld", "Nippes", "Lindenthal", "Sülz", "Klettenberg",
                "Rodenkirchen", "Mülheim", "Deutz", "Kalk", "Porz",
                "Chorweiler", "Bayenthal"
            ]
        case "frankfurt", "frankfurt am main":
            return [
                "Innenstadt", "Bahnhofsviertel", "Westend", "Nordend",
                "Ostend", "Sachsenhausen", "Bornheim", "Bockenheim",
                "Gallus", "Höchst", "Riedberg", "Niederrad", "Eschersheim"
            ]
        default:
            return []
        }
    }
}

enum CommunityActivity: String, CaseIterable, Identifiable {
    case football, basketball, tennis, running, cycling
    case strength, yoga, surfing, martialArts, dance
    case climbing, hiking, swimming, volleyball, skating

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .football:    return tr("activity.football")
        case .basketball:  return tr("activity.basketball")
        case .tennis:      return tr("activity.tennis")
        case .running:     return tr("activity.running")
        case .cycling:     return tr("activity.cycling")
        case .strength:    return tr("activity.strength")
        case .yoga:        return tr("activity.yoga")
        case .surfing:     return tr("activity.surfing")
        case .martialArts: return tr("activity.martialarts")
        case .dance:       return tr("activity.dance")
        case .climbing:    return tr("activity.climbing")
        case .hiking:      return tr("activity.hiking")
        case .swimming:    return tr("activity.swimming")
        case .volleyball:  return tr("activity.volleyball")
        case .skating:     return tr("activity.skating")
        }
    }

    var icon: String {
        switch self {
        case .football:    return "soccerball"
        case .basketball:  return "basketball.fill"
        case .tennis:      return "tennis.racket"
        case .running:     return "figure.run"
        case .cycling:     return "bicycle"
        case .strength:    return "dumbbell.fill"
        case .yoga:        return "figure.mind.and.body"
        case .surfing:     return "water.waves"
        case .martialArts: return "figure.martial.arts"
        case .dance:       return "figure.dance"
        case .climbing:    return "figure.climbing"
        case .hiking:      return "figure.hiking"
        case .swimming:    return "figure.pool.swim"
        case .volleyball:  return "volleyball.fill"
        case .skating:     return "figure.skating"
        }
    }

    /// Emoji für den Drop (im CreateDropView pre-filled). Beim Erstellen eines
    /// Community-Drops wird dieses Emoji als Drop-Aktivitäts-Emoji genutzt.
    var emoji: String {
        switch self {
        case .football:    return "⚽"
        case .basketball:  return "🏀"
        case .tennis:      return "🎾"
        case .running:     return "🏃"
        case .cycling:     return "🚴"
        case .strength:    return "💪"
        case .yoga:        return "🧘"
        case .surfing:     return "🏄"
        case .martialArts: return "🥋"
        case .dance:       return "💃"
        case .climbing:    return "🧗"
        case .hiking:      return "🥾"
        case .swimming:    return "🏊"
        case .volleyball:  return "🏐"
        case .skating:     return "🛹"
        }
    }

    static func from(slug: String) -> CommunityActivity? {
        CommunityActivity(rawValue: slug)
    }
}

// MARK: - Models

/// Eine genehmigte Community — wird auf der Map angezeigt und kann beigetreten werden.
struct Community: Identifiable, Equatable {
    let id: String          // Firebase key = creatorUID (1 Community pro Creator)
    var creatorUID: String
    var creatorName: String
    var activitySlug: String
    var district: String
    var city: String
    var lat: Double
    var lng: Double
    var memberCount: Int
    var createdAt: Double
    /// Optionale Kurzbeschreibung — vom Creator pflegbar.
    var description: String? = nil

    var activity: CommunityActivity? { CommunityActivity(rawValue: activitySlug) }
    var displayName: String { activity?.displayName ?? activitySlug.capitalized }
    var icon: String { activity?.icon ?? "person.3.fill" }
    var emoji: String { activity?.emoji ?? "🏃" }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    static func == (lhs: Community, rhs: Community) -> Bool { lhs.id == rhs.id }
}

/// Mitglied einer Community — für die Dashboard-Anzeige beim Creator.
struct CommunityMember: Identifiable, Equatable {
    let uid: String
    var name: String
    var emoji: String?
    var profileImageURL: String?    // Optionales echtes Profil-Foto
    var age: Int?
    var joinedAt: Double?
    var createdAt: Double?          // Account-Erstellungs-TS — für Beta-Badge
    var isCreator: Bool

    var id: String { uid }
    static func == (lhs: CommunityMember, rhs: CommunityMember) -> Bool { lhs.uid == rhs.uid }

    /// Beta-Adopter: User die vor dem 04.05.2026 (Europe/Berlin) erstellt wurden
    /// bekommen einen "BETA"-Badge im Member-Eintrag.
    var qualifiesForBetaBadge: Bool {
        guard let createdAt, createdAt > 0 else { return false }
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 4
        c.timeZone = TimeZone(identifier: "Europe/Berlin")
        let cutoff = Calendar(identifier: .gregorian).date(from: c)?.timeIntervalSince1970 ?? 0
        // createdAt kann als Millisek (ServerValue.timestamp) ODER Sek (Unix) kommen
        let createdSec = createdAt > 10_000_000_000 ? createdAt / 1000 : createdAt
        return createdSec < cutoff
    }
}

/// Bewerbungs-Antrag — wird vom User eingereicht und vom Admin genehmigt/abgelehnt.
struct CommunityRequest: Identifiable {
    let id: String          // = creatorUID
    var creatorUID: String
    var creatorName: String
    var activitySlug: String
    var district: String
    var city: String
    var lat: Double
    var lng: Double
    var submittedAt: Double
    var status: String      // "pending" | "approved" | "denied"

    var activity: CommunityActivity? { CommunityActivity(rawValue: activitySlug) }
    var displayName: String { activity?.displayName ?? activitySlug.capitalized }
    var icon: String { activity?.icon ?? "person.3.fill" }
}

// MARK: - Manager

/// Coordinator für alles rund um Communities. Singleton.
@MainActor
final class CommunityManager: ObservableObject {
    static let shared = CommunityManager()
    private let db = Database.database().reference()
    private var statusHandle: DatabaseHandle?
    private var communityHandle: DatabaseHandle?
    private var nearbyHandle: DatabaseHandle?
    private var membershipsHandle: DatabaseHandle?
    private init() {}

    /// Real-time Observer für die Communities denen der User beigetreten ist —
    /// damit `myCommunityMemberships` auch nach App-Restart oder Login auf einem
    /// neuen Gerät korrekt befüllt ist (sonst denkt die App er sei kein Member).
    func observeMyMemberships(uid: String) {
        if let handle = membershipsHandle {
            db.child("communitiesByMember").child(uid).removeObserver(withHandle: handle)
        }
        membershipsHandle = db.child("communitiesByMember").child(uid).observe(.value) { snap in
            var ids: Set<String> = []
            for child in snap.children {
                if let s = child as? DataSnapshot { ids.insert(s.key) }
            }
            Task { @MainActor in
                AppStore.shared?.myCommunityMemberships = ids
            }
        }
    }

    // MARK: Submit Application

    /// Schreibt einen neuen Antrag nach `communityRequests/$uid` mit `status: pending`.
    /// Die Koordinate wird per Forward-Geocoding aus dem gewählten Stadtteil bestimmt,
    /// damit die Community am Bezirks-Zentrum erscheint und nicht am aktuellen
    /// Standort des Creators. Fallback: übergebene Koordinate.
    func submitApplication(activitySlug: String, district: String, city: String,
                           coordinate: CLLocationCoordinate2D,
                           creatorName: String,
                           completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { completion(false); return }
        // Forward-Geocoding für stabilen Bezirks-Mittelpunkt
        let query = "\(district), \(city), Deutschland"
        CLGeocoder().geocodeAddressString(query) { [weak self] placemarks, _ in
            let center = placemarks?.first?.location?.coordinate ?? coordinate
            self?.writeApplication(uid: uid,
                                   activitySlug: activitySlug,
                                   district: district,
                                   city: city,
                                   coordinate: center,
                                   creatorName: creatorName,
                                   completion: completion)
        }
    }

    private func writeApplication(uid: String, activitySlug: String,
                                  district: String, city: String,
                                  coordinate: CLLocationCoordinate2D,
                                  creatorName: String,
                                  completion: @escaping (Bool) -> Void) {
        let payload: [String: Any] = [
            "creatorUID":   uid,
            "creatorName":  creatorName,
            "activitySlug": activitySlug,
            "district":     district,
            "city":         city,
            "lat":          coordinate.latitude,
            "lng":          coordinate.longitude,
            "submittedAt":  ServerValue.timestamp(),
            "status":       "pending"
        ]
        db.child("communityRequests").child(uid).setValue(payload) { error, _ in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    // MARK: Observe My Status + Community

    /// Real-time Observer für den eigenen Antrags-Status. Setzt
    /// `AppStore.communityCreatorStatus` automatisch bei jeder Admin-Aktion.
    func observeMyStatus(uid: String) {
        if let handle = statusHandle {
            db.child("communityRequests").child(uid).child("status").removeObserver(withHandle: handle)
        }
        statusHandle = db.child("communityRequests").child(uid).child("status").observe(.value) { snap in
            let status = snap.value as? String
            Task { @MainActor in
                AppStore.shared?.communityCreatorStatus = status
                AppStore.shared?.isCommunityCreator = (status == "approved")
                if status == "approved" {
                    // Bei Approval auch direkt die Community laden
                    CommunityManager.shared.observeMyCommunity(uid: uid)
                }
            }
        }
    }

    /// Real-time Observer für die eigene Community (nach Approval).
    func observeMyCommunity(uid: String) {
        if let handle = communityHandle {
            db.child("communities").child(uid).removeObserver(withHandle: handle)
        }
        communityHandle = db.child("communities").child(uid).observe(.value) { snap in
            Task { @MainActor in
                guard let dict = snap.value as? [String: Any] else {
                    AppStore.shared?.myCommunity = nil
                    return
                }
                AppStore.shared?.myCommunity = CommunityManager.parseCommunity(id: uid, dict: dict)
            }
        }
    }

    // MARK: Load All Communities (Map)

    /// Real-time Observer für alle genehmigten Communities — füllt
    /// `AppStore.nearbyCommunities` für die Map-Pins.
    func observeAllCommunities() {
        if let handle = nearbyHandle {
            db.child("communities").removeObserver(withHandle: handle)
        }
        nearbyHandle = db.child("communities").observe(.value) { snap in
            var result: [Community] = []
            for child in snap.children {
                guard let s = child as? DataSnapshot,
                      let dict = s.value as? [String: Any] else { continue }
                if let c = CommunityManager.parseCommunity(id: s.key, dict: dict) {
                    result.append(c)
                }
            }
            Task { @MainActor in
                AppStore.shared?.nearbyCommunities = result.sorted { $0.createdAt > $1.createdAt }
            }
        }
    }

    // MARK: Join / Leave

    func joinCommunity(_ community: Community, completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { completion(false); return }
        let now = Date().timeIntervalSince1970
        // Check ob schon Mitglied
        db.child("communityMembers").child(community.id).child(uid)
            .observeSingleEvent(of: .value) { [weak self] memberSnap in
                guard let self else { completion(false); return }
                if memberSnap.exists() {
                    DispatchQueue.main.async { completion(true) }
                    return
                }
                let updates: [String: Any] = [
                    "communityMembers/\(community.id)/\(uid)":        now,
                    "communitiesByMember/\(uid)/\(community.id)":     true,
                    "communities/\(community.id)/memberCount":        community.memberCount + 1
                ]
                self.db.updateChildValues(updates) { error, _ in
                    DispatchQueue.main.async { completion(error == nil) }
                }
            }
    }

    func leaveCommunity(_ community: Community, completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { completion(false); return }
        let updates: [String: Any?] = [
            "communityMembers/\(community.id)/\(uid)":        nil,
            "communitiesByMember/\(uid)/\(community.id)":     nil,
            "communities/\(community.id)/memberCount":        max(0, community.memberCount - 1)
        ]
        db.updateChildValues(updates as [String: Any]) { error, _ in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    // MARK: Members List (für Dashboard)

    func fetchMembers(communityID: String, creatorUID: String,
                      completion: @escaping ([CommunityMember]) -> Void) {
        db.child("communityMembers").child(communityID)
            .observeSingleEvent(of: .value) { [weak self] snap in
                guard let self, let dict = snap.value as? [String: Any] else {
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                var members: [CommunityMember] = []
                var remaining = dict.count
                guard remaining > 0 else {
                    DispatchQueue.main.async { completion([]) }; return
                }
                for (uid, value) in dict {
                    let joinedAt = value as? Double ?? (value as? Int).map(Double.init)
                    self.db.child("users").child(uid).observeSingleEvent(of: .value) { userSnap in
                        let userDict = userSnap.value as? [String: Any]
                        let name      = userDict?["name"]            as? String ?? "User"
                        let emoji     = userDict?["emoji"]           as? String
                        let imgURL    = userDict?["profileImageURL"] as? String
                        let createdAt = userDict?["createdAt"]       as? Double
                        var age: Int? = nil
                        if let bd = userDict?["birthdate"] as? Double {
                            let birth = Date(timeIntervalSince1970: bd)
                            age = Calendar.current.dateComponents([.year], from: birth, to: Date()).year
                        }
                        DispatchQueue.main.async {
                            members.append(CommunityMember(
                                uid: uid, name: name, emoji: emoji,
                                profileImageURL: imgURL, age: age,
                                joinedAt: joinedAt, createdAt: createdAt,
                                isCreator: uid == creatorUID
                            ))
                            remaining -= 1
                            if remaining == 0 {
                                let sorted = members.sorted { a, b in
                                    if a.isCreator != b.isCreator { return a.isCreator }
                                    return (a.joinedAt ?? 0) < (b.joinedAt ?? 0)
                                }
                                completion(sorted)
                            }
                        }
                    }
                }
            }
    }

    // MARK: Delete Community (Creator)

    /// Löscht die Community komplett: Members, Index, Push-Queue, Antrag.
    /// Danach kann der Creator einen neuen Antrag stellen.
    func deleteCommunity(_ community: Community, completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid, uid == community.creatorUID else {
            completion(false); return
        }
        // Erst alle Member-UIDs holen — damit wir auch communitiesByMember/$uid/...
        // sauber aufräumen können (sonst hängen Index-Einträge fest).
        db.child("communityMembers").child(community.id).observeSingleEvent(of: .value) { [weak self] snap in
            guard let self else {
                DispatchQueue.main.async { completion(false) }; return
            }
            var memberUIDs: [String] = []
            for child in snap.children {
                if let s = child as? DataSnapshot { memberUIDs.append(s.key) }
            }
            var updates: [String: Any?] = [
                "communities/\(community.id)":                nil,
                "communityRequests/\(community.creatorUID)":  nil,
                "communityPushQueue/\(community.id)":         nil
            ]
            for muid in memberUIDs {
                updates["communityMembers/\(community.id)/\(muid)"]    = nil
                updates["communitiesByMember/\(muid)/\(community.id)"] = nil
            }
            self.db.updateChildValues(updates as [String: Any]) { error, _ in
                if let error {
                    print("[deleteCommunity] ❌ Firebase-Write-Fehler: \(error.localizedDescription)")
                    let pathList = updates.keys.sorted().joined(separator: ", ")
                    print("[deleteCommunity]    Paths: \(pathList)")
                } else {
                    print("[deleteCommunity] ✓ Community \(community.id) gelöscht (members: \(memberUIDs.count))")
                }
                DispatchQueue.main.async {
                    if error == nil {
                        AppStore.shared?.myCommunity = nil
                        AppStore.shared?.isCommunityCreator = false
                        AppStore.shared?.communityCreatorStatus = nil
                        AppStore.shared?.myCommunityMemberships.remove(community.id)
                    }
                    completion(error == nil)
                }
            }
        }
    }

    // MARK: Transfer Ownership (Creator verlässt mit Übergabe)

    /// Übergibt die Community an ein anderes Mitglied. Danach ist der ursprüng-
    /// liche Creator nur noch Mitglied, der neue Creator hat volle Admin-Rechte.
    func transferOwnership(community: Community,
                           to newCreatorUID: String,
                           newCreatorName: String,
                           completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid,
              uid == community.creatorUID,
              uid != newCreatorUID
        else { completion(false); return }

        // 1) creatorUID auf neuen User umschreiben + alten Creator als Member entfernen
        let updates: [String: Any?] = [
            "communities/\(community.id)/creatorUID":            newCreatorUID,
            "communities/\(community.id)/creatorName":           newCreatorName,
            "communityMembers/\(community.id)/\(uid)":           nil,
            "communitiesByMember/\(uid)/\(community.id)":        nil,
            "communities/\(community.id)/memberCount":           max(1, community.memberCount - 1),
            "communityRequests/\(uid)":                          nil  // alter Creator kann neu beantragen
        ]
        db.updateChildValues(updates as [String: Any]) { error, _ in
            if let error {
                print("[transferOwnership] ❌ \(error.localizedDescription)")
            } else {
                print("[transferOwnership] ✓ Community \(community.id) → \(newCreatorUID)")
            }
            DispatchQueue.main.async {
                if error == nil {
                    AppStore.shared?.myCommunity = nil
                    AppStore.shared?.isCommunityCreator = false
                    AppStore.shared?.communityCreatorStatus = nil
                }
                completion(error == nil)
            }
        }
    }

    // MARK: Kick Member

    func kickMember(communityID: String, memberUID: String, currentMemberCount: Int,
                    completion: @escaping (Bool) -> Void) {
        let updates: [String: Any?] = [
            "communityMembers/\(communityID)/\(memberUID)":        nil,
            "communitiesByMember/\(memberUID)/\(communityID)":     nil,
            "communities/\(communityID)/memberCount":              max(0, currentMemberCount - 1)
        ]
        db.updateChildValues(updates as [String: Any]) { error, _ in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    // MARK: Push to Community

    /// Limit: max 3 Pushes pro Creator pro Tag.
    func canSendPush(creatorUID: String, completion: @escaping (Bool, Int) -> Void) {
        let dayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 * 1000
        db.child("communityPushQueue").child(creatorUID)
            .queryOrdered(byChild: "sentAt")
            .queryStarting(atValue: dayStart)
            .observeSingleEvent(of: .value) { snap in
                let count = Int(snap.childrenCount)
                DispatchQueue.main.async { completion(count < 3, count) }
            }
    }

    func sendPush(communityID: String, title: String, body: String,
                  completion: @escaping (Bool) -> Void) {
        let pushID = db.child("communityPushQueue").child(communityID).childByAutoId().key ?? UUID().uuidString
        let payload: [String: Any] = [
            "title":  title,
            "body":   body,
            "sentAt": ServerValue.timestamp()
        ]
        db.child("communityPushQueue").child(communityID).child(pushID)
            .setValue(payload) { error, _ in
                DispatchQueue.main.async { completion(error == nil) }
            }
    }

    // MARK: Admin Operations

    func adminFetchRequests(completion: @escaping ([CommunityRequest]) -> Void) {
        db.child("communityRequests").observeSingleEvent(of: .value) { snap in
            var result: [CommunityRequest] = []
            for child in snap.children {
                guard let s = child as? DataSnapshot,
                      let dict = s.value as? [String: Any] else { continue }
                result.append(CommunityRequest(
                    id:           s.key,
                    creatorUID:   dict["creatorUID"]   as? String ?? s.key,
                    creatorName:  dict["creatorName"]  as? String ?? "–",
                    activitySlug: dict["activitySlug"] as? String ?? "",
                    district:     dict["district"]     as? String ?? "",
                    city:         dict["city"]         as? String ?? "",
                    lat:          dict["lat"]          as? Double ?? 0,
                    lng:          dict["lng"]          as? Double ?? 0,
                    submittedAt:  dict["submittedAt"]  as? Double ?? 0,
                    status:       dict["status"]       as? String ?? "pending"
                ))
            }
            let sorted = result.sorted { $0.submittedAt > $1.submittedAt }
            DispatchQueue.main.async { completion(sorted) }
        }
    }

    /// Admin-Approve: prüft erst auf Duplikat im aktuellen Community-Index.
    /// Wenn duplicate → completion(false). Sonst Community anlegen.
    func adminApprove(_ request: CommunityRequest, completion: @escaping (Bool) -> Void) {
        // Frischer Check direkt aus Firebase (nicht aus dem Cache).
        db.child("communities").observeSingleEvent(of: .value) { [weak self] snap in
            guard let self else { completion(false); return }
            for child in snap.children {
                guard let s = child as? DataSnapshot,
                      let dict = s.value as? [String: Any] else { continue }
                let slug = dict["activitySlug"] as? String ?? ""
                let dst  = (dict["district"] as? String ?? "").lowercased()
                let cty  = (dict["city"] as? String ?? "").lowercased()
                if slug == request.activitySlug
                   && dst == request.district.lowercased()
                   && cty == request.city.lowercased() {
                    print("[adminApprove] ❌ Duplikat: \(slug) in \(dst), \(cty) gehört bereits Creator \(s.key)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }
            }

            let now = Date().timeIntervalSince1970
            let updates: [String: Any] = [
                "communityRequests/\(request.id)/status":          "approved",
                "communities/\(request.id)/creatorUID":            request.creatorUID,
                "communities/\(request.id)/creatorName":           request.creatorName,
                "communities/\(request.id)/activitySlug":          request.activitySlug,
                "communities/\(request.id)/district":              request.district,
                "communities/\(request.id)/city":                  request.city,
                "communities/\(request.id)/lat":                   request.lat,
                "communities/\(request.id)/lng":                   request.lng,
                "communities/\(request.id)/memberCount":           1,
                "communities/\(request.id)/createdAt":             now,
                "communityMembers/\(request.id)/\(request.creatorUID)":        now,
                "communitiesByMember/\(request.creatorUID)/\(request.id)":     true
            ]
            self.db.updateChildValues(updates) { error, _ in
                DispatchQueue.main.async { completion(error == nil) }
            }
        }
    }

    func adminDeny(_ request: CommunityRequest, completion: @escaping (Bool) -> Void) {
        db.child("communityRequests").child(request.id).child("status")
            .setValue("denied") { error, _ in
                DispatchQueue.main.async { completion(error == nil) }
            }
    }

    // MARK: Helpers

    private static func parseCommunity(id: String, dict: [String: Any]) -> Community? {
        guard let lat = dict["lat"] as? Double, let lng = dict["lng"] as? Double else { return nil }
        return Community(
            id:           id,
            creatorUID:   dict["creatorUID"]   as? String ?? id,
            creatorName:  dict["creatorName"]  as? String ?? "–",
            activitySlug: dict["activitySlug"] as? String ?? "",
            district:     dict["district"]     as? String ?? "",
            city:         dict["city"]         as? String ?? "",
            lat:          lat,
            lng:          lng,
            memberCount:  dict["memberCount"]  as? Int ?? 1,
            createdAt:    dict["createdAt"]    as? Double ?? 0,
            description:  dict["description"]  as? String
        )
    }

    // MARK: Update Description

    /// Speichert eine neue Kurzbeschreibung der Community. Leerer String = Feld löschen.
    func updateDescription(communityID: String, description: String,
                           completion: @escaping (Bool) -> Void) {
        let cleaned = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: Any = cleaned.isEmpty ? NSNull() : cleaned
        db.child("communities").child(communityID).child("description")
            .setValue(value) { error, _ in
                DispatchQueue.main.async { completion(error == nil) }
            }
    }

    // MARK: Last Community Drops

    /// Lädt die letzten Drops dieser Community — für die "Drop-Historie"-Section
    /// im Dashboard. Sortiert nach Erstellzeit absteigend, max `limit`.
    func fetchLastCommunityDrops(communityID: String, limit: Int = 5,
                                 completion: @escaping ([CommunityDropEntry]) -> Void) {
        db.child("drops")
            .queryOrdered(byChild: "communityID")
            .queryEqual(toValue: communityID)
            .observeSingleEvent(of: .value) { snap in
                var result: [CommunityDropEntry] = []
                for child in snap.children {
                    guard let s = child as? DataSnapshot,
                          let dict = s.value as? [String: Any] else { continue }
                    let createdMs = dict["timestamp"] as? Double ?? 0
                    let createdSec = createdMs > 10_000_000_000 ? createdMs / 1000 : createdMs
                    result.append(CommunityDropEntry(
                        id:          s.key,
                        emoji:       dict["emoji"]               as? String ?? "✨",
                        activity:    dict["activityName"]        as? String ?? "Plan",
                        scheduled:   dict["scheduledTime"]       as? String ?? "Jetzt",
                        participants: dict["currentParticipants"] as? Int ?? 1,
                        max:         dict["maxParticipants"]     as? Int ?? 10,
                        active:      dict["active"]              as? Bool ?? false,
                        createdAt:   createdSec
                    ))
                }
                let sorted = result.sorted { $0.createdAt > $1.createdAt }
                let limited = Array(sorted.prefix(limit))
                DispatchQueue.main.async { completion(limited) }
            }
    }
}

/// Drop-Eintrag für die Dashboard-Historie.
struct CommunityDropEntry: Identifiable, Equatable {
    let id: String
    let emoji: String
    let activity: String
    let scheduled: String
    let participants: Int
    let max: Int
    let active: Bool
    let createdAt: Double
}

// MARK: - Application Sheet

/// Erstellt einen Community-Antrag. Auto-Geocoding für Stadt + Stadtteil.
struct CommunityCreatorApplicationSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedActivity: CommunityActivity? = nil
    @State private var district: String = ""
    @State private var city: String = ""
    @State private var coordinate: CLLocationCoordinate2D? = nil
    @State private var isGeocoding = false
    @State private var isSubmitting = false
    @State private var errorMsg: String? = nil

    private var existingStatus: String? { store.communityCreatorStatus }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    hero
                    if let status = existingStatus {
                        statusBanner(status)
                    }
                    if existingStatus == nil || existingStatus == "denied" {
                        activityPicker
                        locationBlock
                        if let dup = duplicate {
                            duplicateWarning(dup)
                        }
                        if let errorMsg {
                            Text(errorMsg)
                                .font(.dsCaption)
                                .foregroundColor(.accentRed)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        submitButton
                    }
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle(tr("community.creator_app_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            .onAppear { detectLocation() }
        }
    }

    // MARK: Sub-Views

    private var hero: some View {
        VStack(spacing: 10) {
            partnershipBadge
                .padding(.top, 6)

            VStack(spacing: 4) {
                Text(tr("community.become_creator"))
                    .font(.dsTitle)
                    .foregroundColor(.textPrimary)
                Text(tr("community.creator_intro"))
                    .font(.dsBody)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// "Drops × Clero" Kooperations-Pille — kompakt damit alles auf einen Screen passt.
    private var partnershipBadge: some View {
        HStack(alignment: .center, spacing: 6) {
            partnerPill(logoAsset: "drops_logo",
                        brand:     "DROPS",
                        subtitle:  tr("community.partnership_drops"),
                        accent:    Color.auroraOrange)
            Text("×")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.textTertiary)
            partnerPill(logoAsset: "clero_logo",
                        brand:     "CLERO",
                        subtitle:  tr("community.partnership_clero"),
                        accent:    Color.cleroGreen)
        }
    }

    private func partnerPill(logoAsset: String, brand: String, subtitle: String, accent: Color) -> some View {
        HStack(spacing: 5) {
            Image(logoAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(brand)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundColor(accent)
                Text(subtitle)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            Capsule()
                .fill(accent.opacity(0.10))
                .overlay(
                    Capsule().stroke(accent.opacity(0.22), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func statusBanner(_ status: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: status == "approved" ? "checkmark.seal.fill"
                              : status == "denied"  ? "xmark.circle.fill"
                                                    : "clock.fill")
                .font(.system(size: 22))
                .foregroundColor(status == "approved" ? .brand
                                : status == "denied"  ? .accentRed : .accentOrange)
            VStack(alignment: .leading, spacing: 3) {
                Text(status == "approved" ? tr("community.app_approved")
                     : status == "denied"  ? tr("community.app_denied")
                                           : tr("community.app_pending"))
                    .font(.dsBodySemi)
                    .foregroundColor(.textPrimary)
                Text(status == "approved" ? tr("community.app_approved_sub")
                     : status == "denied"  ? tr("community.app_denied_sub")
                                           : tr("community.app_pending_sub"))
                    .font(.dsCaption)
                    .foregroundColor(.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill((status == "approved" ? Color.cleroGreen : status == "denied" ? Color.accentRed : Color.accentOrange).opacity(0.12))
        )
    }

    private var activityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("community.which_activity"))
                .font(.dsCaption)
                .foregroundColor(.textSecondary)
                .padding(.leading, 4)
            LazyVGrid(
                columns: [.init(.flexible()), .init(.flexible()), .init(.flexible()), .init(.flexible(), spacing: 6), .init(.flexible(), spacing: 6)],
                spacing: 6
            ) {
                ForEach(CommunityActivity.allCases) { activity in
                    activityChip(activity)
                }
            }
        }
    }

    private func activityChip(_ activity: CommunityActivity) -> some View {
        let isSelected = selectedActivity == activity
        return Button { selectedActivity = activity } label: {
            VStack(spacing: 3) {
                Image(systemName: activity.icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                Text(activity.displayName)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(isSelected ? .white : .textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.cleroGreen : Color.bgSecondary)
            )
        }
        .dropsPressable()
    }

    private var locationBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.brand)
                Text(tr("community.your_district"))
                    .font(.dsCaption)
                    .foregroundColor(.textSecondary)
                if isGeocoding {
                    ProgressView().scaleEffect(0.7).tint(.brand)
                }
                Spacer()
                if !city.isEmpty {
                    Text(city)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.brand)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.brand.opacity(0.12)))
                }
            }
            .padding(.leading, 4)

            // Horizontale Scroll-Liste mit Bezirken der erkannten Stadt
            districtScrollPicker
        }
    }

    @ViewBuilder
    private var districtScrollPicker: some View {
        let suggestions = CommunityDistrict.suggestions(for: city)
        if !suggestions.isEmpty {
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 10) {
                ForEach(suggestions, id: \.self) { name in
                    districtChip(name)
                }
            }
        }
    }

    private func districtChip(_ name: String) -> some View {
        let isSelected = district == name
        return Button {
            district = name
        } label: {
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundColor(isSelected ? .white : .textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.cleroGreen : Color.bgSecondary)
                )
        }
        .dropsPressable()
    }

    @ViewBuilder
    private func duplicateWarning(_ dup: Community) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.accentOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("community.duplicate_title"))
                    .font(.dsBodySemi)
                    .foregroundColor(.textPrimary)
                Text(tr("community.duplicate_msg")
                        .replacingOccurrences(of: "{activity}", with: dup.displayName)
                        .replacingOccurrences(of: "{district}", with: dup.district)
                        .replacingOccurrences(of: "{creator}", with: dup.creatorName))
                    .font(.dsCaption)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.accentOrange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Color.accentOrange.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var submitButton: some View {
        Button { submit() } label: {
            Group {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text(existingStatus == "denied" ? tr("community.reapply") : tr("community.send_application"))
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(canSubmit
                          ? LinearGradient(
                                colors: [Color.cleroGreen, Color.cleroGreen.opacity(0.85)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                          : LinearGradient(colors: [Color(UIColor.systemGray3)],
                                           startPoint: .leading, endPoint: .trailing))
            )
            .shadow(color: canSubmit ? Color.cleroGreen.opacity(0.35) : .clear,
                    radius: 10, y: 4)
        }
        .disabled(!canSubmit || isSubmitting)
    }

    // MARK: Logic

    /// Existiert bereits eine Community mit dieser Aktivität in diesem Stadtteil?
    private var duplicate: Community? {
        guard let act = selectedActivity,
              !district.trimmingCharacters(in: .whitespaces).isEmpty,
              !city.isEmpty
        else { return nil }
        return store.duplicateCommunity(
            activitySlug: act.rawValue,
            district: district,
            city: city
        )
    }

    private var canSubmit: Bool {
        selectedActivity != nil
        && !district.trimmingCharacters(in: .whitespaces).isEmpty
        && !city.isEmpty
        && coordinate != nil
        && duplicate == nil
    }

    private func detectLocation() {
        guard coordinate == nil else { return }
        let mgr = CLLocationManager()
        guard let loc = mgr.location else { return }
        coordinate = loc.coordinate
        isGeocoding = true
        CLGeocoder().reverseGeocodeLocation(loc) { placemarks, _ in
            DispatchQueue.main.async {
                isGeocoding = false
                guard let p = placemarks?.first else { return }
                if city.isEmpty {
                    city = p.locality ?? ""
                }
                if district.isEmpty {
                    let detected = (p.subLocality ?? p.thoroughfare ?? "")
                        .trimmingCharacters(in: .whitespaces)
                    let suggestions = CommunityDistrict.suggestions(for: city)
                    // Versuche das erkannte mit unserer kuratierten Liste zu matchen,
                    // damit der richtige Chip vorausgewählt ist.
                    if let exact = suggestions.first(where: { $0.caseInsensitiveCompare(detected) == .orderedSame }) {
                        district = exact
                    } else if let fuzzy = suggestions.first(where: { name in
                        let a = name.lowercased(), b = detected.lowercased()
                        return !b.isEmpty && (a.contains(b) || b.contains(a))
                    }) {
                        district = fuzzy
                    } else {
                        district = detected
                    }
                }
            }
        }
    }

    private func submit() {
        guard let activity = selectedActivity, let coord = coordinate else { return }
        let cleanedDistrict = district.trimmingCharacters(in: .whitespaces)
        guard !cleanedDistrict.isEmpty, !city.isEmpty else { return }
        isSubmitting = true
        errorMsg = nil
        CommunityManager.shared.submitApplication(
            activitySlug: activity.rawValue,
            district:     cleanedDistrict,
            city:         city,
            coordinate:   coord,
            creatorName:  store.currentUser.name
        ) { success in
            isSubmitting = false
            if success {
                store.communityCreatorStatus = "pending"
                dismiss()
            } else {
                errorMsg = "Antrag konnte nicht gesendet werden. Versuch's nochmal."
            }
        }
    }
}

// MARK: - Creator Dashboard Sheet

/// Wird angezeigt nach Genehmigung. Zeigt Mitglieder, ermöglicht Push-Versand + Kick.
struct CommunityCreatorDashboardSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let community: Community

    @State private var members: [CommunityMember] = []
    @State private var isLoading = false
    @State private var showPushCompose = false
    @State private var showCreateDrop = false
    @State private var kickConfirm: CommunityMember? = nil
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showLeavePicker = false
    @State private var transferTarget: CommunityMember? = nil
    @State private var isTransferring = false
    @State private var showDescriptionEdit = false
    @State private var lastDrops: [CommunityDropEntry] = []

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    heroBlock
                    descriptionBlock
                    statsBlock
                    dropBlock
                    pushBlock
                    if !lastDrops.isEmpty {
                        dropHistoryBlock
                    }
                    membersBlock
                    leaveBlock
                    deleteBlock
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle(tr("community.manage_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            .onAppear {
                loadMembers()
                loadLastDrops()
            }
            .sheet(isPresented: $showDescriptionEdit) {
                CommunityDescriptionEditSheet(community: community)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showPushCompose) {
                CommunityPushComposeSheet(community: community)
                    .environmentObject(store)
            }
            .fullScreenCover(isPresented: $showCreateDrop) {
                CreateDropView(
                    communityID: community.id,
                    prefilledActivityName: community.displayName,
                    prefilledActivityEmoji: community.emoji,
                    maxParticipantsLimit: 100
                )
                .environmentObject(store)
            }
            .alert(item: $kickConfirm) { member in
                Alert(
                    title: Text(tr("community.kick_title").replacingOccurrences(of: "{name}", with: member.name)),
                    message: Text(tr("community.kick_msg")),
                    primaryButton: .destructive(Text(tr("community.kick_action"))) { kick(member) },
                    secondaryButton: .cancel()
                )
            }
            .alert(tr("community.delete_confirm_title"), isPresented: $showDeleteConfirm) {
                Button(tr("common.cancel"), role: .cancel) {}
                Button(tr("common.delete"), role: .destructive) { performDelete() }
            } message: {
                Text(tr("community.delete_confirm_msg"))
            }
        }
    }

    /// "Community verlassen" — geht NUR wenn mindestens 1 anderes Mitglied
    /// existiert, an das die Creator-Rolle übergeben werden kann.
    @ViewBuilder
    private var leaveBlock: some View {
        let otherMembers = members.filter { !$0.isCreator }
        if !otherMembers.isEmpty {
            Button { showLeavePicker = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14))
                    Text(tr("community.leave_handover"))
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Color.bgSecondary)
                )
            }
            .dropsPressable()
            .sheet(isPresented: $showLeavePicker) {
                TransferOwnershipSheet(
                    community: community,
                    members: otherMembers,
                    isTransferring: $isTransferring,
                    onTransfer: { newOwner in
                        performTransfer(to: newOwner)
                    }
                )
                .environmentObject(store)
            }
        }
    }

    private func performTransfer(to newOwner: CommunityMember) {
        isTransferring = true
        CommunityManager.shared.transferOwnership(
            community: community,
            to: newOwner.uid,
            newCreatorName: newOwner.name
        ) { success in
            isTransferring = false
            if success {
                showLeavePicker = false
                dismiss()
            }
        }
    }

    private var deleteBlock: some View {
        Button { showDeleteConfirm = true } label: {
            HStack(spacing: 10) {
                if isDeleting {
                    ProgressView().tint(.accentRed)
                } else {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14))
                }
                Text(isDeleting ? tr("community.deleting") : tr("community.delete"))
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.accentRed)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.accentRed.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .stroke(Color.accentRed.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .dropsPressable()
        .disabled(isDeleting)
        .padding(.top, 8)
    }

    private func performDelete() {
        isDeleting = true
        CommunityManager.shared.deleteCommunity(community) { success in
            isDeleting = false
            if success { dismiss() }
        }
    }

    private var heroBlock: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.cleroGreen.opacity(0.18))
                    .frame(width: 84, height: 84)
                Image(systemName: community.icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.cleroGreen)
            }
            Text(community.displayName)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
            Text("\(community.district), \(community.city)")
                .font(.dsBody)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    /// Kurzbeschreibung — Creator kann sie pflegen. Wenn leer, zeigt sich
    /// nur ein dezenter "Beschreibung hinzufügen"-Hinweis.
    private var descriptionBlock: some View {
        Button { showDescriptionEdit = true } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 13))
                    .foregroundColor(.brand)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(community.description?.isEmpty == false ? tr("community.about_us") : tr("community.add_description"))
                        .font(.dsBodySemi)
                        .foregroundColor(.textPrimary)
                    if let desc = community.description, !desc.isEmpty {
                        Text(desc)
                            .font(.dsCaption)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(tr("community.description_hint"))
                            .font(.dsCaption)
                            .foregroundColor(.textTertiary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.bgSecondary)
            )
        }
        .dropsPressable()
    }

    private var statsBlock: some View {
        HStack(spacing: 12) {
            statTile(value: "\(community.memberCount)", label: tr("community.members"))
            statTile(value: createdLabel, label: tr("community.created"))
        }
    }

    /// Drop-Historie — letzte 5 Community-Drops mit Teilnehmer-Zählung.
    /// Aktive Drops bekommen einen "LIVE"-Indikator, beendete sind ausgegraut.
    private var dropHistoryBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(tr("community.last_drops"), systemImage: "clock.arrow.circlepath")
                    .font(.dsBodySemi)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(lastDrops.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.textTertiary)
            }
            VStack(spacing: 6) {
                ForEach(lastDrops) { drop in
                    dropHistoryRow(drop)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.bgSecondary)
        )
    }

    private func dropHistoryRow(_ drop: CommunityDropEntry) -> some View {
        HStack(spacing: 12) {
            Text(drop.emoji)
                .font(.system(size: 22))
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(drop.active ? Color.cleroGreen.opacity(0.15) : Color.bgTertiary)
                )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(drop.activity)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(drop.active ? .textPrimary : .textSecondary)
                        .lineLimit(1)
                    if drop.active {
                        HStack(spacing: 3) {
                            Circle().fill(Color.cleroGreen).frame(width: 5, height: 5)
                            Text(tr("community.live"))
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .tracking(0.5)
                        }
                        .foregroundColor(.cleroGreen)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.cleroGreen.opacity(0.12)))
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 9))
                    Text("\(drop.participants)/\(drop.max) · \(dropTimeLabel(drop.createdAt))")
                        .font(.system(size: 11))
                }
                .foregroundColor(.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.bgPrimary.opacity(0.5))
        )
    }

    private func dropTimeLabel(_ ts: Double) -> String {
        guard ts > 0 else { return "" }
        let date = Date(timeIntervalSince1970: ts)
        let mins = Int(Date().timeIntervalSince(date) / 60)
        if mins < 60 { return "vor \(max(1, mins)) Min" }
        if mins < 60 * 24 { return "vor \(mins / 60) Std" }
        let days = mins / (60 * 24)
        if days < 7 { return "vor \(days) Tag\(days == 1 ? "" : "en")" }
        let f = DateFormatter(); f.dateFormat = "d. MMM"; f.locale = Locale(identifier: "de_DE")
        return f.string(from: date)
    }

    private func loadLastDrops() {
        CommunityManager.shared.fetchLastCommunityDrops(communityID: community.id) { drops in
            lastDrops = drops
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.brand)
            Text(label)
                .font(.dsCaption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.bgSecondary)
        )
    }

    private var createdLabel: String {
        let date = Date(timeIntervalSince1970: community.createdAt)
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days == 0 { return tr("community.today") }
        if days == 1 { return tr("community.created_yesterday") }
        if days < 30 { return tr("community.created_days_ago").replacingOccurrences(of: "{days}", with: "\(days)") }
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "de"
        let f = DateFormatter(); f.dateFormat = "MMM yy"
        f.locale = Locale(identifier: lang == "en" ? "en_US" : "de_DE")
        return f.string(from: date)
    }

    private var dropBlock: some View {
        Button { showCreateDrop = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("community.create_drop"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(tr("community.create_drop_sub")
                            .replacingOccurrences(of: "{activity}", with: community.displayName))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.92))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.cleroGreen, Color.cleroGreen.opacity(0.85)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            )
            .shadow(color: Color.cleroGreen.opacity(0.35), radius: 10, y: 4)
        }
        .dropsPressable()
    }

    private var pushBlock: some View {
        Button { showPushCompose = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("community.push_all"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(tr("community.push_all_sub"))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(LinearGradient.aurora)
            )
            .shadowMd(color: .auroraGreen)
        }
        .dropsPressable()
    }

    private var membersBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(tr("community.members")) (\(max(community.memberCount, members.count)))",
                      systemImage: "person.fill")
                    .font(.dsBodySemi)
                    .foregroundColor(.textPrimary)
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.8).tint(.brand)
                }
            }
            if members.isEmpty && !isLoading {
                Text(tr("community.no_members_yet"))
                    .font(.dsCaption)
                    .foregroundColor(.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 6) {
                    ForEach(members) { member in
                        memberRow(member)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.bgSecondary)
        )
    }

    @ViewBuilder
    private func memberRow(_ member: CommunityMember) -> some View {
        HStack(spacing: 12) {
            memberAvatar(member)
            memberInfo(member)
            Spacer()
            if !member.isCreator {
                Button { kickConfirm = member } label: {
                    Image(systemName: "person.fill.xmark")
                        .font(.system(size: 14))
                        .foregroundColor(.accentRed)
                        .padding(8)
                        .background(Color.accentRed.opacity(0.10), in: Circle())
                }
                .dropsPressable()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.bgPrimary.opacity(0.5))
        )
    }

    @ViewBuilder
    private func memberAvatar(_ member: CommunityMember) -> some View {
        ZStack {
            Circle()
                .fill(member.isCreator ? Color.brand.opacity(0.18) : Color.bgTertiary)
                .frame(width: 44, height: 44)
            if let urlStr = member.profileImageURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure, .empty:
                        avatarFallback(member)
                    @unknown default:
                        avatarFallback(member)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                avatarFallback(member)
            }
        }
    }

    @ViewBuilder
    private func avatarFallback(_ member: CommunityMember) -> some View {
        if let e = member.emoji, !e.isEmpty {
            Text(e).font(.system(size: 20))
        } else {
            Text(String(member.name.prefix(1).uppercased()))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(member.isCreator ? .brand : .textSecondary)
        }
    }

    @ViewBuilder
    private func memberInfo(_ member: CommunityMember) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(member.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                if member.isCreator {
                    Text(tr("community.creator"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.cleroGreen, in: Capsule())
                }
                if member.qualifiesForBetaBadge {
                    Text(tr("shared.beta"))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                LinearGradient(colors: [Color.auroraOrange, Color.auroraGoldLight],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                        )
                }
            }
            memberSubtitle(member)
        }
    }

    @ViewBuilder
    private func memberSubtitle(_ member: CommunityMember) -> some View {
        HStack(spacing: 8) {
            if let age = member.age {
                Text(tr("community.years_abbrev").replacingOccurrences(of: "{age}", with: "\(age)"))
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }
            if let joined = joinedLabel(member.joinedAt) {
                Text("· \(joined)")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }
        }
    }

    private func joinedLabel(_ ts: Double?) -> String? {
        guard let ts, ts > 0 else { return nil }
        let date = Date(timeIntervalSince1970: ts)
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days == 0 { return tr("community.created_today") }
        if days == 1 { return tr("community.created_yesterday") }
        if days < 7  { return tr("community.created_days_ago").replacingOccurrences(of: "{days}", with: "\(days)") }
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "de"
        let f = DateFormatter(); f.dateFormat = "d. MMM"
        f.locale = Locale(identifier: lang == "en" ? "en_US" : "de_DE")
        return tr("community.created_since").replacingOccurrences(of: "{date}", with: f.string(from: date))
    }

    private func loadMembers() {
        isLoading = true
        CommunityManager.shared.fetchMembers(communityID: community.id,
                                             creatorUID: community.creatorUID) { list in
            members = list
            isLoading = false
        }
    }

    private func kick(_ member: CommunityMember) {
        CommunityManager.shared.kickMember(
            communityID: community.id,
            memberUID:   member.uid,
            currentMemberCount: community.memberCount
        ) { success in
            if success { members.removeAll { $0.uid == member.uid } }
        }
    }
}

// MARK: - Push Compose Sheet

struct CommunityPushComposeSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let community: Community

    @State private var title: String = ""
    @State private var body_: String = ""
    @State private var isSending = false
    @State private var errorMsg: String? = nil
    @State private var sentToday: Int? = nil
    @State private var canSend: Bool = true
    @FocusState private var focused: Field?
    private enum Field { case title, body }

    private var remaining: Int? { sentToday.map { max(0, 3 - $0) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    if let remaining {
                        limitBadge(remaining: remaining)
                    }
                    titleField
                    bodyField
                    if let errorMsg {
                        Text(errorMsg)
                            .font(.dsCaption)
                            .foregroundColor(.accentRed)
                    }
                    sendButton
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { focused = nil }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle(tr("community.push_send_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.textTertiary)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { focused = nil }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.brand)
                }
            }
            .onAppear { checkLimit() }
        }
    }

    private var hero: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(LinearGradient.aurora.opacity(0.18))
                    .frame(width: 70, height: 70)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.brand)
            }
            Text(tr("community.push_to_members").replacingOccurrences(of: "{count}", with: "\(community.memberCount)"))
                .font(.dsBodySemi)
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func limitBadge(remaining: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: remaining > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(remaining > 0 ? .brand : .accentOrange)
            Text(remaining > 0
                 ? tr("community.push_remaining")
                    .replacingOccurrences(of: "{count}", with: "\(remaining)")
                    .replacingOccurrences(of: "{plural}", with: remaining == 1 ? "" : "es")
                 : tr("community.push_limit_reached"))
                .font(.dsCaption)
                .foregroundColor(.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill((remaining > 0 ? Color.brand : Color.accentOrange).opacity(0.10))
        )
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("community.push_title"))
                .font(.dsCaption)
                .foregroundColor(.textSecondary)
                .padding(.leading, 4)
            TextField("", text: $title)
                .focused($focused, equals: .title)
                .font(.dsBodySemi)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Color.bgSecondary)
                )
        }
    }

    private var bodyField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("community.push_message"))
                .font(.dsCaption)
                .foregroundColor(.textSecondary)
                .padding(.leading, 4)
            TextEditor(text: $body_)
                .focused($focused, equals: .body)
                .font(.system(size: 15))
                .frame(minHeight: 100)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Color.bgSecondary)
                )
        }
    }

    private var sendButton: some View {
        Button { send() } label: {
            Group {
                if isSending { ProgressView().tint(.white) }
                else { Text(tr("community.push_send")).font(.system(size: 16, weight: .semibold)) }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(canSubmit ? LinearGradient.aurora
                          : LinearGradient(colors: [Color(UIColor.systemGray3)],
                                           startPoint: .leading, endPoint: .trailing))
            )
        }
        .disabled(!canSubmit || isSending)
    }

    private var canSubmit: Bool {
        canSend
        && !title.trimmingCharacters(in: .whitespaces).isEmpty
        && !body_.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func checkLimit() {
        CommunityManager.shared.canSendPush(creatorUID: community.creatorUID) { allowed, count in
            sentToday = count
            canSend = allowed
        }
    }

    private func send() {
        guard canSubmit else { return }
        focused = nil
        isSending = true
        errorMsg = nil
        CommunityManager.shared.sendPush(
            communityID: community.id,
            title: title.trimmingCharacters(in: .whitespaces),
            body:  body_.trimmingCharacters(in: .whitespaces)
        ) { success in
            isSending = false
            if success { dismiss() }
            else { errorMsg = tr("community.push_send_failed") }
        }
    }
}

// MARK: - Map Pin

struct CommunityMapPin: View {
    let community: Community
    let action: () -> Void
    @State private var pulsate = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack {
                    // Subtile Radar-Wellen — zwei zeitversetzt pulsierende Ringe.
                    radarRing(delay: 0)
                    radarRing(delay: 1.0)

                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.cleroGreen, Color.cleroGreen.opacity(0.85)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 38, height: 38)
                        .shadow(color: Color.cleroGreen.opacity(0.45), radius: 6, y: 3)
                    Image(systemName: community.icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                }
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.cleroGreen)
                    .offset(y: -3)
            }
        }
        .dropsPressable()
        .onAppear { pulsate = true }
    }

    @ViewBuilder
    private func radarRing(delay: Double) -> some View {
        Circle()
            .stroke(Color.cleroGreen, lineWidth: 1.5)
            .frame(width: 38, height: 38)
            .scaleEffect(pulsate ? 2.2 : 1.0)
            .opacity(pulsate ? 0 : 0.55)
            .animation(
                .easeOut(duration: 2.0)
                    .repeatForever(autoreverses: false)
                    .delay(delay),
                value: pulsate
            )
            .allowsHitTesting(false)
    }
}

// MARK: - Join Sheet (Map Tap)

struct CommunityJoinSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let community: Community

    @State private var isJoining = false
    @State private var joinedLocally = false

    private var alreadyMember: Bool {
        joinedLocally || (store.myCommunityMemberships.contains(community.id))
    }
    private var isOwnCommunity: Bool {
        store.currentUser.firebaseUID == community.creatorUID
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.cleroGreen.opacity(0.18))
                    .frame(width: 76, height: 76)
                Image(systemName: community.icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.cleroGreen)
            }
            .padding(.top, 18)
            VStack(spacing: 4) {
                Text(community.displayName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("\(community.district), \(community.city)")
                    .font(.dsBody)
                    .foregroundColor(.textSecondary)
                Text("\(community.memberCount) Mitglied\(community.memberCount == 1 ? "" : "er") · Creator: \(community.creatorName)")
                    .font(.dsCaption)
                    .foregroundColor(.textTertiary)
            }

            // Kurzbeschreibung — nur wenn der Creator was geschrieben hat.
            if let desc = community.description, !desc.isEmpty {
                Text(desc)
                    .font(.dsBody)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.bgSecondary)
                    )
            }

            if isOwnCommunity {
                Label(tr("community.your_community"), systemImage: "checkmark.seal.fill")
                    .font(.dsBodySemi)
                    .foregroundColor(.cleroGreen)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Capsule().fill(Color.cleroGreen.opacity(0.16)))
            } else if alreadyMember {
                Label(tr("community.you_are_member"), systemImage: "checkmark.circle.fill")
                    .font(.dsBodySemi)
                    .foregroundColor(.cleroGreen)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Capsule().fill(Color.cleroGreen.opacity(0.16)))
            } else {
                Button { join() } label: {
                    Group {
                        if isJoining { ProgressView().tint(.white) }
                        else { Text(tr("community.join")).font(.system(size: 16, weight: .semibold)) }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.cleroGreen, Color.cleroGreen.opacity(0.85)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                    )
                    .shadow(color: Color.cleroGreen.opacity(0.35), radius: 10, y: 4)
                }
                .disabled(isJoining)
            }

            // Minimale Partnership-Footer: nur Logos + "×" — kein Subtitle.
            HStack(spacing: 6) {
                Image("drops_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                Text("DROPS")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundColor(.auroraOrange)
                Text("×")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
                Image("clero_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                Text("CLERO")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundColor(.brand)
            }
            .opacity(0.75)
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(Color.bgPrimary.ignoresSafeArea())
    }

    private func join() {
        isJoining = true
        CommunityManager.shared.joinCommunity(community) { success in
            isJoining = false
            if success {
                joinedLocally = true
                store.myCommunityMemberships.insert(community.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismiss() }
            }
        }
    }
}

// MARK: - Admin Sheet (Community Requests)

struct AdminCommunityRequestsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var requests: [CommunityRequest] = []
    @State private var isLoading = true
    @State private var filter: String = "pending"
    @State private var duplicateAlert = false
    @State private var duplicateMsg: String = ""

    private var filtered: [CommunityRequest] {
        requests.filter { $0.status == filter }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter
                Picker("", selection: $filter) {
                    Text(tr("community.filter_pending").replacingOccurrences(of: "{count}", with: "\(requests.filter { $0.status == "pending" }.count)")).tag("pending")
                    Text(tr("community.filter_approved")).tag("approved")
                    Text(tr("community.filter_denied")).tag("denied")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 12)

                if isLoading {
                    Spacer()
                    ProgressView().tint(.brand)
                    Spacer()
                } else if filtered.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 36))
                            .foregroundColor(.textTertiary)
                        Text(filter == "pending" ? tr("community.no_pending_requests")
                             : filter == "approved" ? tr("community.no_approved_yet")
                             : tr("community.no_denied_yet"))
                            .font(.dsBody)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(filtered) { req in
                                requestCard(req)
                            }
                        }
                        .padding(.horizontal, 16).padding(.top, 12)
                    }
                }
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle(tr("community.admin_requests_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            .onAppear { load() }
            .alert("Nicht genehmigt", isPresented: $duplicateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(duplicateMsg)
            }
        }
    }

    private func requestCard(_ req: CommunityRequest) -> some View {
        let isDuplicate = store.duplicateCommunity(
            activitySlug: req.activitySlug,
            district: req.district,
            city: req.city
        ) != nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.aurora.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: req.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.brand)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(req.displayName)
                            .font(.dsBodySemi)
                            .foregroundColor(.textPrimary)
                        if isDuplicate && req.status == "pending" {
                            Text(tr("community.duplicate_badge"))
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(0.8)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentOrange))
                        }
                    }
                    Text("\(req.district), \(req.city)")
                        .font(.dsCaption)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("community.creator_label").replacingOccurrences(of: "{name}", with: req.creatorName))
                    .font(.dsCaption)
                    .foregroundColor(.textSecondary)
                Text(tr("community.uid_label").replacingOccurrences(of: "{uid}", with: req.creatorUID))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textTertiary)
                Text(tr("community.submitted_label").replacingOccurrences(of: "{date}", with: submittedLabel(req.submittedAt)))
                    .font(.dsCaption)
                    .foregroundColor(.textTertiary)
            }
            if req.status == "pending" {
                HStack(spacing: 10) {
                    Button { deny(req) } label: {
                        Text(tr("community.deny"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.accentRed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.accentRed.opacity(0.12))
                            )
                    }
                    Button { approve(req) } label: {
                        Text(tr("community.approve"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.brand)
                            )
                    }
                }
                .dropsPressable()
            } else {
                HStack(spacing: 6) {
                    Image(systemName: req.status == "approved" ? "checkmark.seal.fill" : "xmark.circle.fill")
                        .foregroundColor(req.status == "approved" ? .brand : .accentRed)
                    Text(req.status == "approved" ? tr("community.status_approved") : tr("community.status_denied"))
                        .font(.dsCaption)
                        .foregroundColor(req.status == "approved" ? .brand : .accentRed)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.bgSecondary)
        )
    }

    private func submittedLabel(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts / 1000)
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        f.locale = Locale(identifier: "de_DE")
        return f.string(from: date)
    }

    private func load() {
        isLoading = true
        CommunityManager.shared.adminFetchRequests { result in
            requests = result
            isLoading = false
        }
    }

    private func approve(_ req: CommunityRequest) {
        CommunityManager.shared.adminApprove(req) { success in
            if !success {
                duplicateMsg = "\(req.displayName) in \(req.district), \(req.city) wurde nicht genehmigt — es gibt bereits eine Community mit dieser Aktivität in diesem Stadtteil."
                duplicateAlert = true
            }
            load()
        }
    }

    private func deny(_ req: CommunityRequest) {
        CommunityManager.shared.adminDeny(req) { _ in load() }
    }
}

// MARK: - Transfer Ownership Sheet

/// Wird gezeigt wenn ein Creator die Community verlassen will. Listet alle
/// anderen Mitglieder auf, der Creator wählt einen neuen Owner. Nach Bestätigung
/// wird transferOwnership() aufgerufen.
struct TransferOwnershipSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let community: Community
    let members: [CommunityMember]
    @Binding var isTransferring: Bool
    let onTransfer: (CommunityMember) -> Void

    @State private var selected: CommunityMember? = nil
    @State private var showConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    hero
                    membersList
                    if let s = selected {
                        confirmButton(s)
                    }
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle(tr("community.handover_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            .alert(tr("community.transfer_confirm_title"), isPresented: $showConfirm, presenting: selected) { member in
                Button(tr("common.cancel"), role: .cancel) {}
                Button(tr("community.transfer_confirm").replacingOccurrences(of: "{name}", with: member.name), role: .destructive) {
                    onTransfer(member)
                }
            } message: { member in
                Text(tr("community.transfer_confirm_msg").replacingOccurrences(of: "{name}", with: member.name))
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient.aurora.opacity(0.18))
                    .frame(width: 70, height: 70)
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.brand)
            }
            Text(tr("community.transfer_creator"))
                .font(.dsTitle)
                .foregroundColor(.textPrimary)
            Text(tr("community.transfer_intro"))
                .font(.dsCaption)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }

    private var membersList: some View {
        VStack(spacing: 6) {
            ForEach(members) { member in
                memberRow(member)
            }
        }
    }

    private func memberRow(_ member: CommunityMember) -> some View {
        let isSelected = selected?.uid == member.uid
        return Button { selected = member } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.brand.opacity(0.18) : Color.bgTertiary)
                        .frame(width: 40, height: 40)
                    if let urlStr = member.profileImageURL, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                            } else if let e = member.emoji, !e.isEmpty {
                                Text(e).font(.system(size: 18))
                            } else {
                                Text(String(member.name.prefix(1).uppercased()))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    } else if let e = member.emoji, !e.isEmpty {
                        Text(e).font(.system(size: 18))
                    } else {
                        Text(String(member.name.prefix(1).uppercased()))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.textSecondary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    if let age = member.age {
                        Text("\(age) J.")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .brand : .textTertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.brand.opacity(0.08) : Color.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.brand.opacity(0.30) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .dropsPressable()
    }

    private func confirmButton(_ member: CommunityMember) -> some View {
        Button { showConfirm = true } label: {
            Group {
                if isTransferring {
                    ProgressView().tint(.white)
                } else {
                    Text(tr("community.transfer_confirm").replacingOccurrences(of: "{name}", with: member.name))
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient.aurora)
            )
            .shadowMd(color: .auroraGreen)
        }
        .disabled(isTransferring)
    }
}

// MARK: - Description Edit Sheet

struct CommunityDescriptionEditSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let community: Community

    @State private var text: String = ""
    @State private var isSaving = false
    @State private var errorMsg: String? = nil
    @FocusState private var focused: Bool

    private let limit = 240

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    textField
                    if let errorMsg {
                        Text(errorMsg)
                            .font(.dsCaption)
                            .foregroundColor(.accentRed)
                    }
                    saveButton
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { focused = false }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle(tr("community.description_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.textTertiary)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { focused = false }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.brand)
                }
            }
            .onAppear { text = community.description ?? "" }
            .onChange(of: text) { _, new in
                if new.count > limit { text = String(new.prefix(limit)) }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(LinearGradient.aurora.opacity(0.18))
                    .frame(width: 64, height: 64)
                Image(systemName: "text.alignleft")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.brand)
            }
            Text(tr("community.about_us"))
                .font(.dsTitle)
                .foregroundColor(.textPrimary)
            Text(tr("community.description_intro"))
                .font(.dsCaption)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
        .padding(.vertical, 4)
    }

    private var textField: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextEditor(text: $text)
                .focused($focused)
                .font(.system(size: 15))
                .frame(minHeight: 120)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Color.bgSecondary)
                )
            Text("\(text.count) / \(limit)")
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
        }
    }

    private var saveButton: some View {
        Button { save() } label: {
            Group {
                if isSaving { ProgressView().tint(.white) }
                else { Text(tr("community.save")).font(.system(size: 16, weight: .semibold)) }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient.aurora)
            )
        }
        .disabled(isSaving)
    }

    private func save() {
        focused = false
        isSaving = true
        errorMsg = nil
        CommunityManager.shared.updateDescription(
            communityID: community.id,
            description: text
        ) { success in
            isSaving = false
            if success { dismiss() }
            else { errorMsg = tr("community.save_failed") }
        }
    }
}

