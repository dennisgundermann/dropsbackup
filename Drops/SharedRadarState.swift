import Foundation

/// Wird von der App geschrieben und vom Radar-Widget (in DropLiveActivity)
/// gelesen. Datenaustausch läuft über die App Group `group.com.dennis.drops`.
///
/// Design-Ziel: klein und JSON-serialisierbar, damit sich die Struktur später
/// erweitern lässt ohne Widget-Binary-Kompatibilität zu brechen.
struct SharedRadarState: Codable {
    /// Anzahl aktiver Drops in der Suchradius-Zone rund um den User.
    let nearbyCount: Int

    /// Ende-Zeitstempel des nächsten Drops (falls einer existiert),
    /// damit das Widget einen Countdown anzeigen kann ("noch 4 min").
    let nextEndsAt: Date?

    /// Wann die App den State zuletzt geschrieben hat.
    /// Widget zeigt "veraltet"-Hinweis wenn > 15 min alt.
    let updatedAt: Date

    static let empty = SharedRadarState(nearbyCount: 0, nextEndsAt: nil, updatedAt: .distantPast)
}

enum SharedRadarStore {
    private static let appGroupID = "group.com.dennis.drops"
    private static let key = "sharedRadarState.v1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func write(_ state: SharedRadarState) {
        guard let ud = defaults,
              let data = try? JSONEncoder().encode(state) else { return }
        ud.set(data, forKey: key)
    }

    static func read() -> SharedRadarState {
        guard let ud = defaults,
              let data = ud.data(forKey: key),
              let state = try? JSONDecoder().decode(SharedRadarState.self, from: data)
        else { return .empty }
        return state
    }
}
