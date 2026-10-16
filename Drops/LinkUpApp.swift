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
    /// Instagram-Name von dazu, ohne @. Leer = Instagram-Knöpfe ausgeblendet.
    static let instagramHandle = "dazu.app"
    /// Öffnet das Profil; ist Instagram installiert, springt iOS direkt in die App.
    static var instagramURL: URL? {
        instagramHandle.isEmpty ? nil : URL(string: "https://www.instagram.com/\(instagramHandle)/")
    }
}

@main
struct LinkUpApp: App {

    // AppDelegate übernimmt Firebase.configure() + APNs-Setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        // Auto-Detect App-Sprache beim ersten Start: wenn der User die Sprache
        // noch nie manuell gesetzt hat, mappen wir die System-Locale auf eine
        // unserer unterstützten Sprachen (DE/EN/IT/FR/ES). Fallback = EN.
        // Danach überschreibt der User die Wahl in Settings → Sprache.
        if UserDefaults.standard.object(forKey: "appLanguage") == nil {
            let systemLang = Locale.preferredLanguages.first ?? "en"
            let twoChar = String(systemLang.prefix(2)).lowercased()
            let mapped: String = ["de", "en", "it", "fr", "es"].contains(twoChar) ? twoChar : "en"
            UserDefaults.standard.set(mapped, forKey: "appLanguage")
        }

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
    /// Die App selbst (Karte, Tabs) wird erst kurz nach dem ersten Bild
    /// aufgebaut. So erscheint die Start-Animation sofort und dreht sich,
    /// während im Hintergrund noch gebaut wird; sonst bliebe so lange das
    /// stehende Startbild von iOS sichtbar.
    @State private var showContent = false

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
    // Erwartet: https://(www.)dazu-app.de/drop/{UUID}
    //           https://(www.)dazu-app.de/invite/{inviterUID}
    //           dazu://drop/{UUID}          ← custom scheme (Web-Fallback)
    //           dazu://invite/{inviterUID}
    //           dazu://map | dazu://feed | dazu://friends     ← Widget-Taps
    //           drops://…                   ← Legacy-Alias, auf alten Widgets
    private func handleUniversalLink(_ url: URL) {
        let section: String
        let param: String

        if url.scheme == "dazu" || url.scheme == "drops" {
            // Widget-Deep-Link ohne Parameter: dazu://map / feed / friends /
            // create → nur den entsprechenden Tab aktivieren.
            switch url.host {
            case "map":     store.selectedTab = .map; return
            case "feed":    store.selectedTab = .feed; return
            case "friends": store.selectedTab = .alerts; return
            case "create":  store.selectedTab = .create; return
            default: break
            }
            // Custom URL scheme: dazu://drop/<UUID> oder dazu://invite/<UID>
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

            ZStack {
                if !showContent {
                    Color("LaunchBackground").ignoresSafeArea()
                } else if store.isAuthenticated {
                    MainTabView()
                        .environmentObject(store)
                        .preferredColorScheme(preferredScheme)
                        .reviewPromptHandler(store: store)
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
                }
                // Start-Animation: liegt beim Kaltstart kurz über der App.
                // Dreht sich, bis die ersten Runden geladen sind (höchstens 3 s).
                DazuSplashView(dataReady: !store.isAuthenticated || !store.activeDrops.isEmpty)
            }
            // Links hier statt an den Ansichten oben: die gibt es beim
            // Kaltstart im ersten Moment noch nicht.
            .onOpenURL { url in
                if !store.isAuthenticated, GIDSignIn.sharedInstance.handle(url) { return }
                handleUniversalLink(url)
            }
            .task {
                // Ein Bild abwarten, dann die App aufbauen.
                try? await Task.sleep(nanoseconds: 60_000_000)
                showContent = true
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
                    // Power-Hour wurde entfernt — alte Scheduled-Requests
                    // einmal cleanen (iOS behält sie sonst bis zum ersten
                    // Reinstall), danach keine Neu-Planung mehr.
                    PushNotificationManager.shared.cancelAllPowerHourNotifications()
                    // Daily Evening Re-Engagement — jetzt Mo/Di/Mi/Do/Fr 19:00
                    // (ohne Power-Hour-Ausschluss, siehe Scheduler).
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
                // Timer starten damit Freunde den User auch bei länger
                // geöffneter App weiter als online sehen (Heartbeat läuft
                // nach 5min aus).
                store.startOnlineHeartbeatTimer()
            default:
                store.stopOnlineHeartbeatTimer()
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
