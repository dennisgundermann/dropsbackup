import SwiftUI
import CoreLocation
import UserNotifications
import StoreKit
import TipKit
import GoogleSignIn

// MARK: - App-Links Konfiguration

/// Zentraler Ort für die App-Website-URLs. Wenn die Domain wechselt
/// (aktuell dazuapp.com; drops-app.de bleibt für alte Links erlaubt), nur hier ändern.
/// User-facing copy (Legal, Settings, Localization) ist intentional
/// hardcoded und bleibt unverändert — wird in der Migration manuell
/// nachgezogen.
enum AppLinks {
    static let baseURL  = "https://dazuapp.com"
    static let allowedHosts: Set<String> = ["dazuapp.com", "www.dazuapp.com", "drops-app.de", "www.drops-app.de"]
    static func dropShareURL(dropID: String) -> String { "\(baseURL)/drop/\(dropID)" }
    static func inviteShareURL(inviterUID: String) -> String { "\(baseURL)/invite/\(inviterUID)" }
}

@main
struct LinkUpApp: App {

    // AppDelegate übernimmt Firebase.configure() + APNs-Setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        // TipKit konfigurieren — .immediate damit Coach-Marks beim ersten
        // Start des CreateDropView sofort erscheinen (kein täglicher
        // Frequency-Filter). MaxDisplayCount(1) je Tip verhindert Wiederholung.
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])

    }

    @StateObject private var store: AppStore = {
        let s = AppStore()
        AppStore.shared = s
        return s
    }()
    @AppStorage("mapStyleMode") private var mapStyleModeRaw = MapStyleMode.auto.rawValue
    @Environment(\.scenePhase) private var scenePhase

    // Hält den CLLocationManager am Leben bis der Dialog bestätigt ist
    @State private var permLocManager: CLLocationManager? = nil

    /// Fragt Standort- und Push-Berechtigungen an — nur wenn noch nicht bestimmt.
    /// Läuft auf dem Main-Thread, wird nach Login aufgerufen.
    private func requestPermissionsIfNeeded() {
        // Push Notifications
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .badge, .sound]
                ) { granted, _ in
                    if granted {
                        DispatchQueue.main.async {
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    }
                }
            }
        }
        // Standort
        let mgr = CLLocationManager()
        permLocManager = mgr
        if mgr.authorizationStatus == .notDetermined {
            mgr.requestWhenInUseAuthorization()
        }
    }

    // MARK: - Universal Link Handler
    // Erwartet: https://(www.)drops-app.de/drop/{UUID}
    //           https://(www.)drops-app.de/invite/{inviterUID}
    //           drops://drop/{UUID}          ← custom scheme (Web-Fallback)
    //           drops://invite/{inviterUID}
    private func handleUniversalLink(_ url: URL) {
        let section: String
        let param: String

        if url.scheme == "drops" {
            // Widget-Deep-Link ohne Parameter: drops://map → nur auf den
            // Karten-Tab schalten, keine weitere Aktion. Wird vom
            // Radar-Widget beim Tap ausgelöst.
            if url.host == "map" {
                store.selectedTab = .map
                return
            }
            // Custom URL scheme: drops://drop/<UUID> oder drops://invite/<UID>
            // host = "drop"/"invite", pathComponents = ["/", "<param>"]
            guard let host = url.host,
                  url.pathComponents.count >= 2 else { return }
            section = host
            param   = url.pathComponents[1]
        } else {
            // Universal Link: https://www.drops-app.de/drop/<UUID>
            guard let host = url.host, AppLinks.allowedHosts.contains(host),
                  url.pathComponents.count >= 3 else { return }
            section = url.pathComponents[1]
            param   = url.pathComponents[2]
        }

        if section == "drop", let dropID = UUID(uuidString: param) {
            store.selectedTab = .map
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                store.pendingDropID = dropID
            }
        } else if section == "invite" {
            store.selectedTab = .map
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                store.pendingInviteUsername = param
            }
        }
    }

    private var preferredScheme: ColorScheme? {
        switch MapStyleMode(rawValue: mapStyleModeRaw) ?? .auto {
        case .auto:  return nil
        case .light: return .light
        case .dark:  return .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            // Altersschutz beim App-Start erzwingen (Schutz vor manipulierten Daten)
            let _ = store.enforceAgeGuard()

            if store.isAuthenticated {
                MainTabView()
                    .environmentObject(store)
                    .preferredColorScheme(preferredScheme)
                    .reviewPromptHandler(store: store)
                    .onOpenURL { url in handleUniversalLink(url) }
                    .onAppear {
                        // Nur für Bestandsuser (hasSeenWelcome = true) hier anfragen.
                        // Neuuser bekommen die Permission-Dialoge erst nach dem
                        // WelcomeSheet / First-Drop-Walkthrough — dann ist der
                        // Kontext klar und die Akzeptanzrate höher.
                        if UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
                            requestPermissionsIfNeeded()
                        }
                        // Cold-Start: scenePhase = .active feuert kein onChange.
                        // Hier nochmal pollen falls AppDelegate ein Pending hat.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            if let pending = UserDefaults.standard.string(forKey: "ud_pendingQuickAction") {
                                UserDefaults.standard.removeObject(forKey: "ud_pendingQuickAction")
                                handlePendingQuickAction(pending)
                            }
                        }
                    }
            } else {
                OnboardingView()
                    .environmentObject(store)
                    .preferredColorScheme(preferredScheme)
                    .onOpenURL { url in
                        if GIDSignIn.sharedInstance.handle(url) { return }
                        handleUniversalLink(url)
                    }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                store.isAppActive = false
                store.recordBackgrounded()
                // Nur für eingeloggte User — kein Push an Onboarding-Nutzer
                guard store.isAuthenticated else { break }
                Task { @MainActor in PushNotificationManager.shared.scheduleReEngagementIfNeeded() }
            case .active:
                store.isAppActive = true
                store.checkSessionTimeout()
                // Quick-Action vom AppDelegate konsumieren (Cold-Start oder
                // Background→Foreground). Kleine Verzögerung damit MainTabView
                // sicher gerendert ist.
                if store.isAuthenticated,
                   let pending = UserDefaults.standard.string(forKey: "ud_pendingQuickAction") {
                    UserDefaults.standard.removeObject(forKey: "ud_pendingQuickAction")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        handlePendingQuickAction(pending)
                    }
                }
                // Permissions + Session-Reset nur nach Login
                guard store.isAuthenticated else { break }
                Task { @MainActor in
                    PushNotificationManager.shared.cancelReEngagementNotification()
                    PushNotificationManager.shared.resetSession()
                    // Nur für User die bereits den WelcomeSheet gesehen haben —
                    // Neuuser bekommen Permissions erst nach WelcomeSheet/Walkthrough.
                    if UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
                        PushNotificationManager.shared.requestPermissionIfNeeded()
                    }
                    // Power-Hour-Pushs als wiederkehrende lokale Notifications
                    // anlegen / refreshen — iOS feuert sie dann jede Woche zur
                    // konfigurierten Uhrzeit auch wenn die App nicht läuft.
                    PushNotificationManager.shared.schedulePowerHourNotifications()
                    // Daily Evening Re-Engagement — Mo/Di/Do 19:00
                    // (Wochentage ohne Power-Hour, sonst Doppel-Push).
                    PushNotificationManager.shared.scheduleDailyEveningPrompts()
                    // App-Version-Gate beim Foregrounding refreshen — falls
                    // der Server inzwischen Force-Update aktiviert hat, sieht
                    // der User es spätestens beim nächsten App-Open.
                    store.refreshAppVersionStatus()
                    // Eigene createdAt nochmal versuchen — beim ersten
                    // App-Init ist Firebase-Auth möglicherweise noch nicht
                    // bereit, der Beta-Badge bleibt dann ungeladen.
                    store.loadOwnCreatedAtIfNeeded()
                }
                // Online-Heartbeat — schreibt zusätzlich aktuelle Koord
                // ins User-Profil, damit Admin-Panel die Stadt auch für
                // User ableiten kann die noch keinen Drop erstellt /
                // besucht haben. Nutzt store.currentUser.coordinate als
                // Quelle (kommt vom LocationManager der App).
                RealtimeDBManager.shared.markOnlineHeartbeat(
                    coordinate: store.currentUser.coordinate
                )
            default:
                break
            }
        }
    }

    /// Routet eine Home-Screen Quick Action auf den entsprechenden Tab/Sheet.
    /// Setzt selectedTab direkt am Store + postet zusätzlich Notification damit
    /// MainTabView (für Create-Sheet) reagieren kann.
    private func handlePendingQuickAction(_ type: String) {
        switch type {
        case "com.dennis.drops.shortcut.create":
            store.selectedTab = .map
            NotificationCenter.default.post(
                name: Notification.Name("DropsQuickAction"),
                object: nil,
                userInfo: ["type": type]
            )
        case "com.dennis.drops.shortcut.map":
            store.selectedTab = .map
        case "com.dennis.drops.shortcut.feed":
            store.selectedTab = .feed
        case "com.dennis.drops.shortcut.profile":
            store.selectedTab = .profile
        default:
            break
        }
    }
}

// MARK: - In-App Review Prompt
//
// Apple-Limit: max 3 Prompts pro User pro 365 Tage. Beste Trigger sind „positive
// Momente" — wir feuern bei meaningful Show-Up-Counts (3, 10, 25). System-Sheet
// erscheint nur wenn das Limit nicht erreicht ist; sonst ist der Aufruf ein No-Op.
private struct ReviewPromptModifier: ViewModifier {
    @ObservedObject var store: AppStore
    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        content
            .onChange(of: store.shouldShowReviewPrompt) { _, newValue in
                guard newValue else { return }
                requestReview()
                // Persistiere Zeitpunkt damit AppStore das nicht zu schnell wieder triggert
                UserDefaults.standard.set(Date().timeIntervalSince1970,
                                          forKey: "ud_lastReviewRequestedAt")
                store.shouldShowReviewPrompt = false
            }
    }
}

extension View {
    func reviewPromptHandler(store: AppStore) -> some View {
        modifier(ReviewPromptModifier(store: store))
    }
}
