import UIKit
import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseMessaging
import FirebaseCrashlytics
import UserNotifications

// MARK: - AppDelegate
// Notwendig für Firebase Phone Auth auf echtem Gerät.
// Firebase braucht APNs-Token zur Device-Verifikation (stiller Push).
// FCM-Token wird separat für Push Notifications (SOS, DropIn) verwendet.

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Cold-Start via Home-Screen Quick Action: shortcut steckt in launchOptions.
        // routeQuickAction wartet intern bis Singleton + Scene ready ist.
        print("🚦 [QA] didFinishLaunching — launchOptions keys: \(launchOptions?.keys.map(\.rawValue) ?? [])")
        if let shortcut = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            print("🚦 [QA] COLD-START shortcut: \(shortcut.type)")
            AppDelegate.routeQuickAction(shortcut.type)
        } else {
            print("🚦 [QA] No shortcut in launchOptions (warm start or normal launch)")
        }

        // Firebase so früh wie möglich konfigurieren – vor dem ersten SwiftUI-Frame.
        FirebaseApp.configure()

        // Globales App-Theme — matcht Drops Design-System (Violett + Creme).
        configureGlobalAppearance()

        // Remote Feature Flags aus RTDB ziehen (z.B. cityRestrictionEnabled).
        // Default-Werte in BetaConfig sind so gewählt, dass App-Store-Reviewer
        // die App ohne Geo-Beschränkung testen können.
        Task { @MainActor in
            RealtimeDBManager.shared.bootstrapRemoteFlags()
        }

        // Crashlytics aktivieren (wird automatisch durch FirebaseApp.configure() gestartet).
        // In Debug-Builds unterdrücken wir das Senden von Crashes an Firebase,
        // damit Entwicklungs-Crashes keine Production-Metriken verfälschen.
        #if DEBUG
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        #else
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        #endif

        // Falls beim letzten App-Start ein Crash war, frühzeitig loggen damit wir
        // sehen welcher User betroffen war.
        if Crashlytics.crashlytics().didCrashDuringPreviousExecution() {
            Crashlytics.crashlytics().log("⚠️ Previous session ended with a crash")
        }

        // User-ID zuordnen sobald bekannt — Crashlytics kann dann pro User filtern.
        if let uid = Auth.auth().currentUser?.uid {
            Crashlytics.crashlytics().setUserID(uid)
        }

        // FCM Delegate setzen
        Messaging.messaging().delegate = self

        // Notification Center Delegate
        UNUserNotificationCenter.current().delegate = self

        // Gerät für Remote Notifications registrieren — OHNE User-Dialog.
        // Firebase Phone Auth braucht den APNs-Token für stille Verifikations-Pushes.
        // Der User-sichtbare Notification-Dialog wird am Ende des Onboardings angefragt
        // (AppIntroStep), damit er im richtigen Kontext erscheint.
        DispatchQueue.main.async {
            application.registerForRemoteNotifications()
        }
        return true
    }

    // MARK: - APNs Token → Firebase weiterleiten

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Firebase Phone Auth braucht das für silent push verification
        Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
        // FCM bekommt ebenfalls den APNs Token
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Gerät hat kein APNs (z.B. Simulator) – Firebase fällt auf reCAPTCHA zurück
        print("Drops: APNs nicht verfügbar – \(error.localizedDescription)")
    }

    // MARK: - Remote Notifications (Phone Auth silent push)

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Firebase Phone Auth: stille Pushes abfangen
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        completionHandler(.newData)
    }

    // MARK: - FCM Token (MessagingDelegate)

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("Drops FCM Token: \(token)")
        // Token im UserDefaults speichern → AppStore kann ihn für Notifications nutzen
        UserDefaults.standard.set(token, forKey: "fcmToken")
        // Token nach Firebase schreiben, damit Cloud-Functions (z.B. Friendship-Push)
        // den Empfänger gezielt adressieren können.
        Task { @MainActor in
            RealtimeDBManager.shared.setMyFCMToken(token)
        }
        // Notification aussenden damit AppStore reagieren kann
        NotificationCenter.default.post(
            name: Notification.Name("FCMTokenDidRefresh"),
            object: nil,
            userInfo: ["token": token]
        )
    }

    // MARK: - Vordergrund-Notifications anzeigen (UNUserNotificationCenterDelegate)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Im Vordergrund unterdrücken wir manche Notifications, weil die App
        // sie eh als In-App-Sheet zeigt (sonst kommt Push UND Sheet).
        let userInfo = notification.request.content.userInfo
        let type = userInfo["type"] as? String ?? ""
        let suppressInForeground: Set<String> = [
            "join_request",     // Host bekommt Sheet via activeIncomingRequest
            "join_accepted",    // Joiner sieht's via myJoinRequestStatus-Observer
            "join_declined",
            "dropin",           // Joiner taucht in Vor-Ort-Liste auf, Push wäre doppelt
            "encounter",        // BLE-Confirmation passiert eh in der App
            "powerhour_pre",    // Live-Pille zeigt Countdown
            "powerhour_start",  // Banner ist eh im Map
            "powerhour_endwarn",
            "points_earned",    // Punkte-Toast zeigt's bereits in der App
            "evening_reengagement" // App ist offen → kein Reminder nötig
        ]
        if suppressInForeground.contains(type) {
            // Im Foreground unterdrücken wir das Banner — UND wir clearen
            // das Badge sofort, weil der User die Sache eh ingame mitkriegt.
            AppDelegate.clearBadge()
            completionHandler([])
            return
        }
        // Alle anderen Pushs: statt iOS-Banner spielen wir unseren eigenen
        // In-App-Toast (DynamicToast) — konsistenter mit dem App-Look,
        // dismissable per Swipe/Tap, keine Duplikate mit Lockscreen-Push.
        let title = notification.request.content.title
        let body  = notification.request.content.body
        let (symbol, accent, route) = toastStyleForPushType(type)
        Task { @MainActor in
            ToastCenter.shared.show(ToastItem(
                title: title.isEmpty ? "dazu" : title,
                message: body.isEmpty ? nil : body,
                symbol: symbol,
                accent: accent,
                route: route
            ))
        }
        completionHandler([.sound])
    }

    /// Symbol + Akzent + Tap-Route für einen Push-Typ. Steuert Aussehen UND
    /// wohin der Tap auf den In-App-Toast navigiert.
    private func toastStyleForPushType(_ type: String) -> (String, Color, ToastRoute) {
        switch type {
        case "friend_request",
             "friend_added":      return ("person.fill.badge.plus", .brandViolet, .friends)
        case "drop_nearby",
             "drop_created":      return ("mappin.and.ellipse",     .brandViolet, .nearby)
        case "drop_ended":        return ("flag.checkered",         .brandOrange, .live)
        case "drop_start_reminder": return ("alarm.fill",           .accentOrange, .live)
        case "community_push",
             "community_joined":  return ("person.3.fill",          .cleroGreen,  .map)
        case "sos":               return ("exclamationmark.triangle.fill", .accentRed, .map)
        default:                  return ("bell.fill",              .brandViolet, .none)
        }
    }

    // MARK: - applicationDidBecomeActive: Badge clearen
    //
    // Wenn der User die App öffnet (egal über welchen Weg — Icon-Tap,
    // Notification-Tap, App-Switcher), gibt's keinen Grund das Badge
    // weiter anzuzeigen. Sonst klebt die "1" am Icon bis er manuell
    // alle Notifications aus dem Notification Center wischt.
    func applicationDidBecomeActive(_ application: UIApplication) {
        AppDelegate.clearBadge()
    }

    /// Setzt Badge-Counter auf 0. Nutzt iOS 17+ API wenn verfügbar
    /// (UIApplication.applicationIconBadgeNumber ist deprecated), sonst
    /// Fallback. Räumt auch alle bereits ausgelieferten Notifications
    /// im Notification Center auf, damit das Badge nicht beim nächsten
    /// App-Restart wieder erscheint.
    static func clearBadge() {
        let center = UNUserNotificationCenter.current()
        if #available(iOS 16.0, *) {
            center.setBadgeCount(0) { _ in }
        } else {
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = 0
            }
        }
        // Optional: alte ausgelieferte Notifications wegräumen damit der
        // Notification Center nicht 20 alte "📍 Jemand ist eingeDroppt!"
        // Einträge zeigt. Wir behalten Notifications der letzten Stunde
        // — wenn der User gerade weggeschaut hat soll er sie noch sehen.
        center.getDeliveredNotifications { notifs in
            let oneHour: TimeInterval = 60 * 60
            let stale = notifs.filter {
                Date().timeIntervalSince($0.date) > oneHour
            }
            let staleIDs = stale.map(\.request.identifier)
            if !staleIDs.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: staleIDs)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        // Deep Link: bei SOS-Notification zur Karte navigieren
        if let type = userInfo["type"] as? String {
            NotificationCenter.default.post(
                name: Notification.Name("DropsNotificationTapped"),
                object: nil,
                userInfo: ["type": type, "data": userInfo]
            )
        }
        // User hat die Notification getappt → App geht in den Vordergrund
        // → Badge clearen. applicationDidBecomeActive würde das auch tun,
        // hier explizit damit der Tap-Path schnell ist.
        AppDelegate.clearBadge()
        completionHandler()
    }

    // MARK: - Home Screen Quick Actions
    // Tap auf eine Quick-Action (langer Druck auf App-Icon) → Notification posten,
    // MainTabView reagiert und routet auf den entsprechenden Tab/Sheet.

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        // App war im Hintergrund / inactive — direkt am Singleton-Store routen.
        print("🚦 [QA] performActionFor: \(shortcutItem.type)")
        AppDelegate.routeQuickAction(shortcutItem.type)
        completionHandler(true)
    }

    // MARK: - Scene Configuration (für Quick Actions in iOS 13+)
    // SwiftUI App-Lifecycle braucht eine SceneDelegate damit Quick Actions
    // bei COLD-START ankommen (launchOptions ist sonst leer).

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = DropsSceneDelegate.self
        return config
    }

    /// Routet eine Quick-Action direkt am AppStore-Singleton. Funktioniert sowohl
    /// für Cold-Start (aus SceneDelegate.scene(willConnectTo:)) als auch für
    /// Background→Foreground (aus SceneDelegate.windowScene(performActionFor:)).
    static func routeQuickAction(_ type: String) {
        print("🚦 [QA] routeQuickAction CALLED with: \(type), AppStore.shared = \(AppStore.shared == nil ? "NIL" : "OK")")
        // Cold-Start: warte bis SwiftUI-Scene + Auth ready ist
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🚦 [QA] +0.5s — AppStore.shared = \(AppStore.shared == nil ? "NIL" : "OK")")
            guard AppStore.shared != nil else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    print("🚦 [QA] +1.5s retry — AppStore.shared = \(AppStore.shared == nil ? "NIL" : "OK")")
                    apply(type)
                }
                return
            }
            apply(type)
        }

        @MainActor func apply(_ type: String) {
            guard let store = AppStore.shared else {
                print("🚦 [QA] apply() — STILL NIL, abort")
                return
            }
            print("🚦 [QA] apply() — authenticated=\(store.isAuthenticated)")
            // Wenn nicht authenticated: PARK das Pending-Shortcut am Store —
            // MainTabView konsumiert es sobald sie erscheint (post-Auth).
            // Wenn authenticated: direkt routen + zusätzlich parken (MainTabView
            // re-applied on onAppear für Robustheit).
            store.pendingQuickAction = type
            print("🚦 [QA] → store.pendingQuickAction = \(type)")
        }
    }
}

// MARK: - SceneDelegate für Quick Actions

/// Empfängt Home-Screen Quick Actions in iOS 13+.
/// AppDelegate's `application(_:performActionFor:)` wird in Scene-basierten
/// Apps nicht mehr aufgerufen — Apple routet zur SceneDelegate.
class DropsSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        // Cold-Start: Quick Action steckt in den connectionOptions.
        if let shortcut = connectionOptions.shortcutItem {
            print("🚦 [QA] SceneDelegate willConnectTo with shortcut: \(shortcut.type)")
            AppDelegate.routeQuickAction(shortcut.type)
        } else {
            print("🚦 [QA] SceneDelegate willConnectTo (no shortcut)")
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        // Warm-Start: Quick Action während App im Hintergrund.
        print("🚦 [QA] SceneDelegate performActionFor: \(shortcutItem.type)")
        AppDelegate.routeQuickAction(shortcutItem.type)
        completionHandler(true)
    }

    /// Scene wird aktiv (App im Vordergrund) — Badge zurücksetzen damit
    /// die "1" am Icon verschwindet. SwiftUI App-Lifecycle hat keinen
    /// applicationDidBecomeActive-Hook auf View-Ebene — die Scene-API
    /// ist der zuverlässige Weg.
    func sceneDidBecomeActive(_ scene: UIScene) {
        AppDelegate.clearBadge()
    }
}

// MARK: - Global Appearance (UIKit tint-through für SwiftUI)

private func configureGlobalAppearance() {
    // Brand-Farben als UIColors (für UIKit-Appearance)
    let violet = UIColor(red: 0.357, green: 0.239, blue: 0.961, alpha: 1.0)   // #5B3DF5
    let cream  = UIColor(red: 1.000, green: 0.965, blue: 0.918, alpha: 1.0)   // #FFF6EA
    let night  = UIColor(red: 0.090, green: 0.067, blue: 0.180, alpha: 1.0)   // #17112E
    // Adaptive Tab-Bar-Fläche: cream in Light-Mode, dunkles Nacht-Violett in
    // Dark-Mode, damit die Tab Bar in beiden Modi lesbar bleibt.
    let tabSurface = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.098, green: 0.078, blue: 0.165, alpha: 1.0)      // #19142A
            : cream
    }
    let tabIdleIcon = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.55)
            : night.withAlphaComponent(0.4)
    }
    let tabIdleText = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.65)
            : night.withAlphaComponent(0.5)
    }

    // ── Tab Bar ──────────────────────────────────────────────
    // Opak Cream, damit die Tab Bar in Dark Mode / iOS 26 Liquid-Glass nicht
    // schwarz wird. Material-Blur bringt wenig, weil die App ohnehin ein helles
    // Cream-Design fährt.
    let tabAppearance = UITabBarAppearance()
    tabAppearance.configureWithOpaqueBackground()
    tabAppearance.backgroundColor = tabSurface
    tabAppearance.backgroundEffect = nil
    tabAppearance.shadowColor = .clear
    // Selected-iconColor nicht setzen: die Aktiv-Icons sind original-rendered
    // (Markenfarben inkl. Dark-Mode-Variante). Würde Appearance hier einfärben,
    // würde Violett das Original übermalen.
    tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
        .foregroundColor: violet,
        .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
    ]
    tabAppearance.stackedLayoutAppearance.normal.iconColor = tabIdleIcon
    tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
        .foregroundColor: tabIdleText,
        .font: UIFont.systemFont(ofSize: 10, weight: .medium)
    ]
    UITabBar.appearance().standardAppearance = tabAppearance
    UITabBar.appearance().scrollEdgeAppearance = tabAppearance

    // ── Navigation Bar ───────────────────────────────────────
    let navAppearance = UINavigationBarAppearance()
    navAppearance.configureWithTransparentBackground()
    navAppearance.titleTextAttributes = [
        .foregroundColor: night,
        .font: UIFont.systemFont(ofSize: 17, weight: .bold)
    ]
    navAppearance.largeTitleTextAttributes = [
        .foregroundColor: night,
        .font: UIFont.systemFont(ofSize: 34, weight: .bold)
    ]
    UINavigationBar.appearance().standardAppearance = navAppearance
    UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    UINavigationBar.appearance().tintColor = violet
}
