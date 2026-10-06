import SwiftUI
import CoreLocation
import UserNotifications

struct MainTabView: View {
    /// Verzögerung bevor das WelcomeSheet nach Tab-Mount erscheint — damit erst
    /// das Layout settled ist und das Sheet nicht beim ersten Render hochpoppt.
    private static let welcomeSheetDelay: TimeInterval = 0.5
    /// Mini-Tick bevor das Create-Sheet aus dem Quick-Action öffnet — selectedTab
    /// muss erst zur Map gewechselt sein, sonst überlappt das Sheet die alte Tab-View.
    private static let quickActionSheetDelay: TimeInterval = 0.1
    /// Standort-Permission-Dialog 0.5s nach Push-Dialog — iOS stapelt sonst beide
    /// und der User sieht nur einen.
    private static let locationPermissionStagger: TimeInterval = 0.5
    /// Bluetooth-Warmup 1.1s nach Push — nach Push + Location, damit die drei
    /// System-Dialoge sequenziell kommen.
    private static let bluetoothPermissionStagger: TimeInterval = 1.1

    @EnvironmentObject var store: AppStore
    @State private var showCreateSheet = false
    /// Hält den CLLocationManager am Leben bis der Permission-Dialog bestätigt ist.
    @State private var permLocManager: CLLocationManager? = nil
    @State private var isWalkthroughCreate = false
    @StateObject private var cityGate = CityGateChecker()
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var showWelcomeSheet = false
    /// Wird im WelcomeSheet-CTA gesetzt; CreateDropView öffnet sich erst im
    /// onDismiss-Callback des Sheets — damit ist die Dismiss-Animation
    /// garantiert fertig und kein UIKit-Presentation-Conflict entsteht.
    @State private var pendingWalkthrough = false

    var body: some View {
        ZStack(alignment: .top) {
        TabView(selection: $store.selectedTab) {
            LiveMapView()
                .tabItem { Label(tr("tab.map"), systemImage: "map.fill") }
                .badge(store.pendingJoinRequests.count)
                .tag(AppStore.Tab.map)

            FeedView()
                .tabItem { Label(tr("tab.nearby"), systemImage: "person.2.wave.2.fill") }
                .tag(AppStore.Tab.feed)

            Group {
                if store.isInActiveDrop, let item = store.currentActiveAnnotation {
                    ActiveDropTabView(item: item)
                        .environmentObject(store)
                } else {
                    Color.clear
                }
            }
            .tabItem {
                if store.isInActiveDrop {
                    Label(tr("tab.active"), systemImage: "dot.radiowaves.left.and.right")
                } else {
                    Label("", systemImage: "plus.circle.fill")
                }
            }
            .tag(AppStore.Tab.create)

            FreundeView()
                .tabItem { Label(tr("tab.friends"), systemImage: "person.fill") }
                .badge(store.incomingFriendRequests.count + store.pendingEncounters.count)
                .tag(AppStore.Tab.alerts)

            ProfileView()
                .tabItem { Label(tr("tab.settings"), systemImage: "gearshape.fill") }
                .tag(AppStore.Tab.profile)
        }
        .tint(.brand)
        .onChange(of: store.selectedTab) { _, tab in
            if tab == .create && !store.isInActiveDrop {
                showCreateSheet = true
                store.selectedTab = .map
            }
        }
        .onChange(of: store.isInActiveDrop) { _, isActive in
            if !isActive && store.selectedTab == .create {
                store.selectedTab = .map
            }
        }
        .fullScreenCover(isPresented: $showCreateSheet, onDismiss: {
            // Walkthrough abgeschlossen → jetzt Permissions anfragen
            if isWalkthroughCreate { requestAllPermissions() }
            isWalkthroughCreate = false
        }) {
            CreateDropView(isWalkthrough: isWalkthroughCreate)
                .environmentObject(store)
        }
        .onAppear {
            consumePendingQuickAction()
        }
        .onChange(of: store.pendingQuickAction) { _, _ in
            consumePendingQuickAction()
        }
        .fullScreenCover(isPresented: $store.showDropsPlusSuccess) {
            DropsPlusSuccessView()
                .environmentObject(store)
        }

        // ── Offline-Banner ────────────────────────────────────────────────
        OfflineBanner()

        } // ZStack
        // ── App-Version-Gate (Hard-Force) ─────────────────────────────────
        // Liegt ÜBER allem (auch über Tab-Bar, Sheets, Toast). Vollbild-
        // Blocker, wenn `minRequiredVersion` aktiv ist.
        .overlay {
            AppVersionGate()
        }
        // ── Soft-Recommend-Banner ─────────────────────────────────────────
        // Echter Top-Banner via safeAreaInset(.top). Sitzt unmittelbar unter
        // der Status Bar (Uhrzeit), pusht den Tab-Inhalt darunter weg, statt
        // als Overlay irgendwo im View-Tree zu schweben.
        .safeAreaInset(edge: .top, spacing: 0) {
            AppVersionRecommendBanner()
        }
        // ── Globaler Punkte-Toast ─────────────────────────────────────────
        // Liegt über der ganzen Tab-View, damit egal in welchem Tab Punkte
        // vergeben werden, der User die "+X Punkte"-Pille zentral oben
        // sieht. Die Pille selbst dismisst sich nach 2.5s; wir nullen den
        // Store-State im onDismiss-Callback.
        .overlay(alignment: .top) {
            if let toast = store.pointsToast {
                PointsToastView(toast: toast) {
                    store.pointsToast = nil
                }
                .id(toast.id)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8),
                   value: store.pointsToast?.id)
        // ── Info-Toast (Anti-Farm-Feedback) ───────────────────────────────
        // Eigene Pille für Negativ-Feedback wenn KEINE Punkte vergeben werden
        // (Drop zu kurz, Pair-Cooldown). Ohne diesen Toast würde der User
        // denken es wäre ein Bug — er bekommt sonst gar keine Rückmeldung.
        .overlay(alignment: .top) {
            if let info = store.infoToast {
                InfoToastView(toast: info)
                    .id(info.id)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8),
                   value: store.infoToast?.id)
        .safeAreaInset(edge: .top, spacing: 0) {
            OfflineBanner()
        }
        // ── Pending-Join-Request Pill ─────────────────────────────────────
        // Floating-Pill oben mit Countdown wenn der User eine Anfrage gestellt
        // hat und auf Host-Reaktion wartet. Schwebt über allem (Sheets, Tab-Bar)
        // damit der Wartestatus immer sichtbar ist.
        .overlay(alignment: .top) {
            PendingJoinRequestPill()
                .environmentObject(store)
                .padding(.top, 4)
                .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85),
                   value: store.myJoinRequestStatus)
        .animation(.spring(response: 0.45, dampingFraction: 0.85),
                   value: store.pendingJoinDropID)
        // Stadtsperre als Vollbild-Gate ist entfernt: User außerhalb der 5
        // Service-Städte können sich registrieren und die App nutzen, dürfen
        // aber keine Drops erstellen oder joinen (Guards in CreateDropView/AppStore).
        .fullScreenCover(isPresented: $store.needsCorePermissions) {
            PermissionGateView()
        }
        .onAppear {
            cityGate.startChecking()
            if !hasSeenWelcome {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.welcomeSheetDelay) {
                    showWelcomeSheet = true
                }
            }
            // Profilbild ist freiwillig — bereits geplante Erinnerungen aus
            // älteren App-Versionen entfernen.
            PushNotificationManager.shared.cancelProfilePictureReminder()
        }
        .sheet(isPresented: $showWelcomeSheet, onDismiss: {
            if pendingWalkthrough {
                // "Ersten Drop erstellen"-Pfad: Walkthrough öffnen.
                // Permissions kommen nach Walkthrough-Sheet-Dismiss.
                pendingWalkthrough = false
                store.selectedTab = .map
                isWalkthroughCreate = true
                showCreateSheet = true
            } else {
                // Direkt überspringen: Permissions jetzt anfragen.
                requestAllPermissions()
            }
        }) {
            WelcomeSheet(
                onDismiss: {
                    hasSeenWelcome = true
                    showWelcomeSheet = false
                },
                onStartFirstDrop: {
                    hasSeenWelcome = true
                    pendingWalkthrough = true   // Merker setzen
                    showWelcomeSheet = false     // Sheet dismisst → onDismiss öffnet CreateDrop
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $store.showPushReaskSheet) {
            PushReaskSheet()
                .presentationDetents([.fraction(0.55)])
                .presentationDragIndicator(.visible)
        }
        // ── Host: eingehende Beitrittsanfrage ─────────────────────────────
        // Auf MainTabView-Ebene angehängt damit das Pop-up egal in welchem
        // Tab der Host gerade ist erscheint. Vorher war's nur an LiveMapView
        // → keine Pop-up wenn Host im Umgebungstab oder Profil war.
        .sheet(item: $store.activeIncomingRequest) { req in
            IncomingJoinRequestSheet(request: req)
                .environmentObject(store)
                .presentationDetents([.fraction(0.52)])
                .presentationDragIndicator(.visible)
                .sheetBackground()
        }
        // ── Admin-Notice: Drop wurde von einem Admin entfernt ─────────────
        // User MUSS „Verstanden" tippen, damit der Notice in Firebase
        // gelöscht wird — sonst taucht er beim nächsten App-Start wieder
        // auf. Drag-to-dismiss ist deaktiviert.
        .sheet(item: $store.pendingAdminNotice) { notice in
            AdminNoticeSheet(notice: notice) {
                store.acknowledgeAdminNotice()
            }
            .presentationDetents([.fraction(0.55), .large])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
            .sheetBackground()
        }
        // ── Joiner: Drop wurde vom Host beendet ───────────────────────────
        // Sonst verschwindet der Drop einfach aus der UI und der User merkt
        // nicht warum er nicht mehr "dabei" ist. Alert ist global an der
        // MainTabView, sodass es egal ist in welchem Tab er gerade ist.
        .alert(item: $store.hostCancelledDropAlert) { alert in
            Alert(
                title: Text(tr("push.host_cancel_title").replacingOccurrences(of: "{emoji}", with: alert.dropEmoji)),
                message: Text(tr("push.host_cancel_body").replacingOccurrences(of: "{activity}", with: alert.activityName)),
                dismissButton: .default(Text(tr("tab.understood")))
            )
        }
        // ── Eingehende Drop-Einladung von einem Freund ────────────────────
        // Freund hat im MiniProfileSheet auf "Zu meinem Drop einladen" getappt
        // → wir bekommen via Firebase-Observer ein Pop-up. Annehmen routet auf
        // die Karte und fokussiert den Drop (nutzt pendingDropID-Mechanismus).
        .alert(item: $store.incomingDropInvitation) { invite in
            Alert(
                title: Text(tr("push.invite_title").replacingOccurrences(of: "{emoji}", with: invite.hostEmoji).replacingOccurrences(of: "{host}", with: invite.hostName)),
                message: Text(tr("tab.invite_msg").replacingOccurrences(of: "{host}", with: invite.hostName).replacingOccurrences(of: "{emoji}", with: invite.dropEmoji).replacingOccurrences(of: "{activity}", with: invite.dropActivity)),
                primaryButton: .default(Text(tr("tab.view_drop"))) {
                    store.acceptIncomingDropInvitation()
                },
                secondaryButton: .cancel(Text(tr("tab.later"))) {
                    store.dismissIncomingDropInvitation()
                }
            )
        }
        // ── Drop-Feedback Sheet ───────────────────────────────────────────
        // Erscheint nach Drop-Ende (Host: nach cancelDrop mit Joinern;
        // Joiner: nach leaveActiveJoin wenn Session ≥ 5 min). Bewerten
        // ist optional — User kann jederzeit Skip drücken.
        .sheet(item: $store.pendingFeedbackPrompt) { prompt in
            DropFeedbackSheet(prompt: prompt)
                .environmentObject(store)
                .presentationDetents([.fraction(0.55)])
                .presentationDragIndicator(.visible)
                .sheetBackground()
        }
        .fullScreenCover(item: $store.firstDropCelebrationKind) { kind in
            FirstDropCelebrationSheet(kind: kind)
        }
        .sheet(item: $store.dropSuccessShareData) { data in
            DropSuccessShareSheet(data: data)
                .presentationDetents([.height(480)])
                .presentationDragIndicator(.visible)
        }
    }

    /// Routet ein pending Quick-Action vom Store — wird beim onAppear (Cold-
    /// Start nach Auth) und bei Änderung (Warm-Start) aufgerufen.
    private func consumePendingQuickAction() {
        guard let type = store.pendingQuickAction else { return }
        store.pendingQuickAction = nil
        print("🚦 [QA] MainTabView consumes: \(type)")
        switch type {
        case "com.dennis.drops.shortcut.create":
            store.selectedTab = .map
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.quickActionSheetDelay) {
                showCreateSheet = true
            }
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

    // MARK: - Permissions

    /// Push + Standort + Bluetooth anfragen — mit Stagger damit iOS die Dialoge
    /// nicht aufeinanderstapelt. Wird erst nach WelcomeSheet / Walkthrough
    /// aufgerufen, damit der User den Kontext versteht.
    private func requestAllPermissions() {
        // 1. Push Notifications
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
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
        // 2. Standort — Versatz damit Push-Dialog zuerst erscheint
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.locationPermissionStagger) {
            let mgr = CLLocationManager()
            permLocManager = mgr   // ARC-Referenz halten
            if mgr.authorizationStatus == .notDetermined {
                mgr.requestWhenInUseAuthorization()
            }
        }
        // 3. Bluetooth — Versatz nach Push damit Dialoge nicht stapeln
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.bluetoothPermissionStagger) {
            store.bluetoothMeetup.warmUpForPermissionPrompt()
        }
    }

}

// MARK: - First Drop Celebration

/// Vollbild-Celebration mit Konfetti-Explosion vom Emoji-Punkt aus.
/// Läuft im fullScreenCover damit das Konfetti den ganzen Screen einnimmt.
struct FirstDropCelebrationSheet: View {
    let kind: FirstDropCelebration
    @Environment(\.dismiss) private var dismiss
    @State private var emojiAppeared = false

    private var hero: String { kind == .created ? "🎉" : "🙌" }

    /// Marketing-Copy — kürzer, punchier, hook-driven.
    private var headline: String {
        switch kind {
        case .created: return tr("tab.drop_live")
        case .joined:  return tr("tab.you_in")
        }
    }

    private var subline: String {
        switch kind {
        case .created:
            return tr("tab.created_subline")
        case .joined:
            return tr("tab.bluetooth_explainer")
        }
    }

    private var cta: String {
        kind == .created ? tr("tab.lets_start") : tr("tab.to_the_drop")
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Hintergrund mit weichem Aurora-Gradient
                LinearGradient(
                    colors: [
                        Color.brand.opacity(0.18),
                        Color.bgPrimary,
                        Color.accentOrange.opacity(0.10)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Konfetti-Explosion ausgehend vom Emoji-Zentrum
                ConfettiBurstView(
                    origin: CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.32),
                    screenSize: geo.size
                )
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Spacer().frame(height: geo.size.height * 0.20)

                    // Hero-Emoji mit Spring-Pop-In
                    Text(hero)
                        .font(.system(size: 96))
                        .scaleEffect(emojiAppeared ? 1.0 : 0.4)
                        .opacity(emojiAppeared ? 1.0 : 0.0)
                        .shadow(color: Color.brand.opacity(0.35), radius: 30, y: 8)

                    Spacer().frame(height: 28)

                    VStack(spacing: 12) {
                        Text(headline)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)

                        Text(subline)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 32)
                    }
                    .opacity(emojiAppeared ? 1.0 : 0.0)
                    .offset(y: emojiAppeared ? 0 : 20)

                    Spacer()

                    Button { dismiss() } label: {
                        HStack(spacing: 8) {
                            Text(cta)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color.brand, Color.brand.opacity(0.85)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                        )
                        .shadow(color: Color.brand.opacity(0.45), radius: 16, y: 8)
                    }
                    .dropsPressable()
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
                    .opacity(emojiAppeared ? 1.0 : 0.0)
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) {
                    emojiAppeared = true
                }
            }
        }
    }
}

/// Konfetti-Explosion mit echter Physik: Partikel starten am Origin mit
/// initialer Geschwindigkeit in zufällige Richtung, dann zieht Gravitation
/// sie kontinuierlich nach unten. Luftwiderstand bremst horizontal.
/// Läuft EINMAL ~7s, danach komplett stille Canvas (kein Loop).
struct ConfettiBurstView: View {
    let origin: CGPoint
    let screenSize: CGSize
    /// `@State` damit pieces & startDate über View-Updates hinweg stabil bleiben.
    /// Sonst würde die Animation bei jedem Re-Render der Parent-View neu starten
    /// (z.B. wenn GeometryReader die Größe meldet).
    @State private var pieces: [ConfettiPiece] = (0..<55).map { _ in ConfettiPiece.random() }
    @State private var startDate: Date = Date()

    private let totalLifetime: Double = 7.0

    var body: some View {
        TimelineView(.animation(paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            // Komplett stoppen sobald alle Partikel ausgeblendet sind — sonst
            // würde TimelineView ewig weiter ticken (auch wenn nichts gezeichnet).
            if elapsed > totalLifetime + 1.0 {
                Color.clear
            } else {
                Canvas { ctx, size in
                    for piece in pieces {
                        drawPiece(piece, elapsed: elapsed, in: &ctx, size: size)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    /// Berechnet Position + Rotation + Opacity zu Zeit `t` und zeichnet
    /// den Partikel als Text-Symbol auf den Canvas.
    private func drawPiece(_ piece: ConfettiPiece, elapsed: Double, in ctx: inout GraphicsContext, size: CGSize) {
        let t = max(0, elapsed - piece.delay)
        guard t > 0 else { return }
        let lifetime = 7.0   // Gesamtanimationsdauer

        // Initial-Geschwindigkeit aus Winkel + Speed (relative zur Diagonale)
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        let v0: CGFloat = piece.speed * diagonal * 0.7
        let vx0: CGFloat = CGFloat(cos(piece.angle)) * v0
        let vy0: CGFloat = CGFloat(sin(piece.angle)) * v0
        // Bias nach oben für Explosion-Feel: -10% y für mehr Aufwärtsbewegung
        let vyBias: CGFloat = -diagonal * 0.08

        // Luftwiderstand: x-Bewegung dämpft mit e^(-k·t)
        let drag: CGFloat = 0.55       // pro Sekunde
        let dragFactor = (1.0 - exp(-drag * CGFloat(t))) / drag
        let x = origin.x + vx0 * dragFactor

        // Gravitation: y-Bewegung = v0_y + 0.5 g t² (mit leichter y-Dämpfung)
        let g: CGFloat = diagonal * 0.55   // Schwerkraft
        let yDrag: CGFloat = 0.4
        let yDragFactor = (1.0 - exp(-yDrag * CGFloat(t))) / yDrag
        let y = origin.y + (vy0 + vyBias) * yDragFactor + 0.5 * g * CGFloat(t * t) * 0.6

        // Rotation skaliert linear mit t
        let rotation = piece.rotationStart + (piece.rotationEnd - piece.rotationStart) * (t / lifetime)

        // Fade-Out: erste 5s voll sichtbar, dann linear ausblenden
        let fadeStart = 5.0
        let opacity: Double = t < fadeStart
            ? 1.0
            : max(0.0, 1.0 - (t - fadeStart) / (lifetime - fadeStart))

        // Sobald Partikel weit aus dem Bild → nicht mehr zeichnen (Performance)
        if y > size.height + 80 || opacity <= 0.0 { return }

        // Text-Resolve mit Rotation
        let resolved = ctx.resolve(Text(piece.emoji).font(.system(size: piece.size)))
        var transformed = ctx
        transformed.opacity = opacity
        transformed.translateBy(x: x, y: y)
        transformed.rotate(by: .degrees(rotation))
        transformed.draw(resolved, at: .zero, anchor: .center)
    }
}

struct ConfettiPiece: Identifiable {
    let id = UUID()
    let emoji: String
    /// Winkel in Radiant — bestimmt Richtung der Explosion. 0 = rechts, π/2 = unten.
    let angle: Double
    /// Initiale Geschwindigkeit (relativ zur Bildschirm-Diagonale).
    let speed: CGFloat
    let delay: Double
    let rotationStart: Double
    let rotationEnd: Double
    let size: CGFloat

    static func random() -> ConfettiPiece {
        let emojis = ["🎉", "✨", "💫", "🎊", "⭐️", "🟠", "🟣", "🔵"]
        return ConfettiPiece(
            emoji: emojis.randomElement() ?? "🎉",
            // Vollkreis 360° gleichmäßig verteilt
            angle: Double.random(in: -Double.pi ... Double.pi),
            // Speed: variabel, einige fliegen weiter, andere nah am Origin
            speed: CGFloat.random(in: 0.45...1.25),
            delay: Double.random(in: 0...0.15),
            rotationStart: Double.random(in: -45...45),
            // Volle Drehungen je nach „Gewicht" — kleinere Partikel drehen mehr
            rotationEnd: Double.random(in: 540...1440),
            size: CGFloat.random(in: 18...30)
        )
    }
}

// MARK: - Push Re-Ask Sheet

/// Wird einmalig nach dem ersten ShowUp eines Users angezeigt wenn er
/// im Onboarding Push-Berechtigung abgelehnt hatte. iOS erlaubt keinen
/// zweiten System-Dialog — der Sheet leitet daher zu den App-Einstellungen.
struct PushReaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.brandCream.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.brandLavender.opacity(0.9))
                        .frame(width: 96, height: 96)
                        .scaleEffect(pulse ? 1.05 : 0.98)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 42, weight: .heavy))
                        .foregroundColor(.brandOrange)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: -2) {
                    Text(tr("tab.push_on_title"))
                        .foregroundColor(.brandNight)
                }
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .padding(.horizontal, 28)

                Text(tr("tab.push_on_body"))
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)

                Spacer()

                VStack(spacing: 8) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                        dismiss()
                    } label: {
                        Text(tr("tab.enable_push"))
                            .dropsPrimaryButton()
                    }
                    .dropsPressable()
                    .padding(.horizontal, 20)

                    Button(tr("tab.maybe_later")) { dismiss() }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.55))
                        .padding(.vertical, 10)
                        .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Welcome Sheet

struct WelcomeSheet: View {
    let onDismiss: () -> Void
    /// Wird statt `onDismiss` aufgerufen wenn der User direkt seinen ersten
    /// Drop erstellen will (Primary-CTA „Mach deinen ersten Drop"). Aktivierungs-
    /// Hack: User landet nicht auf leerer Map sondern direkt im Drop-Erstellungs-
    /// Sheet — sieht sofort den Wert der App.
    var onStartFirstDrop: (() -> Void)? = nil
    @AppStorage("appLanguage") private var appLanguage = "de"

    // Feature-Farben — erste zwei aus der App-Icon-Palette (Orange-Top
    // + Grün-Bottom), letzte zwei behalten Diversität (Amber für
    // "Menschen", Violet für "Privatsphäre" — semantisch etabliert).
    private var features: [(icon: String, color: Color, titleKey: String, subtitleKey: String)] {[
        ("dot.radiowaves.left.and.right", Color.auroraOrange,  "welcome.feature1_title", "welcome.feature1_sub"),
        ("map.fill",                      Color.auroraGreen,  "welcome.feature2_title", "welcome.feature2_sub"),
        ("person.2.fill",                 Color.auroraAmber,  "welcome.feature3_title", "welcome.feature3_sub"),
        ("lock.shield.fill",              Color.brandViolet,     "welcome.feature4_title", "welcome.feature4_sub"),
    ]}

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 12)

            // App-Icon + Titel — Radar-Hero matched die Sprache des
            // App-Icons (Drop-Center + pulsierende Wellen) statt eines
            // generischen SF-Symbols auf farbigem Rechteck.
            VStack(spacing: 8) {
                // Dazu Wortmarke als Hero (echter SVG-Pfad)
                DazuWordmark(color: .brandNight, dotColor: .brandOrange)
                    .frame(height: 80)
                    .padding(.top, 20)
                    .padding(.bottom, 32)

                // Rondesignlab-Style Riesen-Statement
                VStack(spacing: -4) {
                    Text("Hingehen")
                        .foregroundColor(.brandNight)
                    Text("statt ")
                        .foregroundColor(.brandNight) +
                    Text("schreiben.")
                        .foregroundColor(.brandViolet)
                }
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 36)

            // Feature-Liste
            VStack(spacing: 0) {
                ForEach(features.indices, id: \.self) { i in
                    let f = features[i]
                    HStack(alignment: .top, spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(f.color.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: f.icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(f.color)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr(f.titleKey))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text(tr(f.subtitleKey))
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)

                    if i < features.count - 1 {
                        Divider().padding(.leading, 84)
                    }
                }
            }

            Spacer()

            // Primary CTA: direkt zum First-Drop, nicht zur leeren Karte.
            // Activation-Hack: User sieht sofort den Drop-Erstellungs-Sheet
            // statt einer leeren Map die Verwirrung stiftet.
            VStack(spacing: 10) {
                Button(action: { onStartFirstDrop?() ?? onDismiss() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                        Text(tr("tab.make_first_drop"))
                    }
                    .dropsPrimaryButton()
                }
                .dropsPressable()

                // Secondary: nur zur Karte, kein Drop erstellt.
                Button(action: onDismiss) {
                    Text(tr("tab.just_look_around"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .background(Color.bgGrouped.ignoresSafeArea())
    }
}


// MARK: - Permission Gate

/// Blockierender Sheet, wenn WEDER Standort NOCH Bluetooth verfügbar sind.
/// Ohne mindestens eines davon kann Drops keine echten Begegnungen erkennen,
/// daher werden die Haupt-Features gesperrt bis der User mindestens eine
/// Berechtigung freigibt.
struct PermissionGateView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack {
            Color.bgGrouped.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()
                RadarPulseHero(icon: "location.slash.fill")

                VStack(spacing: 10) {
                    Text(tr("tab.no_access"))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)

                    Text(tr("tab.no_access_body"))
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                }

                Spacer()

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(tr("tab.open_settings"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                        .background(Capsule().fill(Color.brand))
                }
                .padding(.horizontal, 24)

                Button {
                    // Manuell nochmal prüfen (falls der User die Berechtigung im
                    // anderen Tab bereits gegeben hat und zurückkommt).
                    store.evaluateCorePermissions()
                } label: {
                    Text(tr("tab.check_again"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                .padding(.bottom, 36)
            }
        }
    }
}

