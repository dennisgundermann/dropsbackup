import SwiftUI

// MARK: - Profile Image Cache

final class ProfileImageCache {
    static let shared = ProfileImageCache()
    private var cache: [String: UIImage] = [:]
    private let lock = NSLock()

    func get(_ url: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return cache[url]
    }
    func set(_ url: String, image: UIImage) {
        lock.lock(); defer { lock.unlock() }
        cache[url] = image
    }
    /// Komplett leeren — wird beim Logout/Account-Löschen aufgerufen,
    /// damit altes Profilbild nicht beim Re-Login wieder auftaucht.
    func clear() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll()
    }
}

// MARK: - Remote Profile Image View

struct RemoteProfileImage: View {
    let url: String?
    let fallbackEmoji: String
    let size: CGFloat
    var strokeColor: Color = Color.white.opacity(0.25)

    @State private var image: UIImage? = nil

    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(strokeColor, lineWidth: 1.5))
            } else {
                Circle()
                    .fill(Color.brand.opacity(0.12))
                    .frame(width: size, height: size)
                    .overlay(Text(fallbackEmoji).font(.system(size: size * 0.48)))
                    .overlay(Circle().stroke(strokeColor, lineWidth: 1.5))
            }
        }
        .onAppear { loadImage() }
        .onChange(of: url) { _, _ in loadImage() }
    }

    private func loadImage() {
        guard let urlString = url, let remoteURL = URL(string: urlString) else { return }
        if let cached = ProfileImageCache.shared.get(urlString) {
            image = cached; return
        }
        URLSession.shared.dataTask(with: remoteURL) { data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            ProfileImageCache.shared.set(urlString, image: img)
            DispatchQueue.main.async { image = img }
        }.resume()
    }
}

// MARK: – Gemeinsamer Aurora-Hintergrund (Login, Welcome, Registrierung)

struct AppAuroraBackground: View {
    var isLight: Bool? = nil
    @Environment(\.colorScheme) var cs
    private var light: Bool { isLight ?? (cs == .light) }

    var body: some View {
        ZStack {
            // Base: Creme (Light) oder Nacht (Dark)
            (light ? Color.brandCream : Color.brandNightFixed)
                .ignoresSafeArea()

            // Statische farbige Akzente — subtil, keine Animation.
            // Links oben: Violett-Hauch (Logo-Farbe).
            // Rechts unten: Orange-Hauch (Dot-Farbe).
            // Beide sehr weich und mit viel Blur → Hintergrund wirkt lebendig
            // ohne zu bewegen oder abzulenken.
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(Color.brandViolet.opacity(light ? 0.14 : 0.22))
                        .frame(width: 420, height: 420)
                        .blur(radius: 120)
                        .offset(x: -geo.size.width * 0.25,
                                y: -geo.size.height * 0.20)

                    Circle()
                        .fill(Color.brandOrange.opacity(light ? 0.12 : 0.18))
                        .frame(width: 360, height: 360)
                        .blur(radius: 110)
                        .offset(x: geo.size.width * 0.30,
                                y: geo.size.height * 0.35)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Push Permission Banner
//
// Persistenter Inline-Banner für User die Push abgelehnt haben oder den
// Reask-Sheet weggedismissed haben. Wichtig weil ohne Push die ganze App-
// Reaktivität wegfällt: Drop-Anfragen, Drop-beendet, Pair-Auto-Accept
// sind alle silently broken. Banner ist klar dismissable damit User der
// bewusst kein Push will nicht genervt wird (ud_pushBannerDismissed).
struct PushPermissionBanner: View {
    @AppStorage("ud_pushBannerDismissed") private var dismissed = false
    @State private var isAuthorized: Bool? = nil
    @State private var checkedOnce = false

    var body: some View {
        Group {
            if !dismissed,
               let auth = isAuthorized,
               !auth {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                EmptyView()
            }
        }
        .task(id: checkedOnce) {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            let auth = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            await MainActor.run { self.isAuthorized = auth }
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.auroraOrange, Color.auroraPink],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tr("shared.push_missing"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(tr("shared.push_missing_body"))
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeOut(duration: 0.25)) { dismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .dropsPressable()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Color.auroraOrange.opacity(0.3), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture {
            // iOS-Einstellungen für die App öffnen — Apple erlaubt keinen
            // zweiten Permission-Dialog programmatisch nach „Denied".
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - Radar Pulse Hero

/// Zentrales Visual: konzentrische pulsierende Aurora-Ringe um ein
/// SF-Symbol im Zentrum. Matched die Sprache des App-Icons (Radar-Wellen
/// aus dem Drop-Center). Wird in EmptyStates, Onboarding-Sheets und
/// Permission-Gates wiederverwendet — eine Quelle, ein Look.
struct RadarPulseHero: View {
    let icon: String
    /// Skaliert die gesamte Komposition. 1.0 = Original-Größe (180×180
    /// Frame, 72pt Core, 28pt Icon, Ringe 116/160/204).
    var scale: CGFloat = 1.0
    /// 3 Ringe = volle EmptyState-Version, 2 = kompakte (ohne äußersten
    /// grünen Ring) für engere Layouts wie FreundeEmptyState.
    var ringCount: Int = 3

    @AppStorage("ud_profileHeroTemplate") private var templateRaw = ProfileHeroTemplate.aurora.rawValue
    private var template: ProfileHeroTemplate {
        ProfileHeroTemplate(rawValue: templateRaw) ?? .aurora
    }
    private var c0: Color { template.colors.first ?? .auroraOrange }
    private var c1: Color { template.colors.last  ?? .auroraGreen  }

    @State private var pulse0 = false
    @State private var pulse1 = false
    @State private var pulse2 = false

    var body: some View {
        ZStack {
            // Innerster Ring
            Circle()
                .stroke(c0.opacity(0.30), lineWidth: 1.2)
                .frame(width: 116 * scale, height: 116 * scale)
                .scaleEffect(pulse0 ? 1.06 : 0.96)
            // Mittlerer Ring
            Circle()
                .stroke(c0.opacity(0.18), lineWidth: 1)
                .frame(width: 160 * scale, height: 160 * scale)
                .scaleEffect(pulse1 ? 1.05 : 0.97)
            // Äußerer Ring
            if ringCount >= 3 {
                Circle()
                    .stroke(c1.opacity(0.16), lineWidth: 1)
                    .frame(width: 204 * scale, height: 204 * scale)
                    .scaleEffect(pulse2 ? 1.04 : 0.97)
            }
            // Center: Material-Basis + Template-Gradient + Icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 72 * scale, height: 72 * scale)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [c0.opacity(0.30), c1.opacity(0.22)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72 * scale, height: 72 * scale)
                Image(systemName: icon)
                    .font(.system(size: 28 * scale, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [c0, c1],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            }
        }
        .frame(width: 180 * scale, height: 180 * scale)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulse0 = true
            }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true).delay(0.3)) {
                pulse1 = true
            }
            if ringCount >= 3 {
                withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true).delay(0.6)) {
                    pulse2 = true
                }
            }
        }
    }
}

// MARK: - Dynamic Island Mock (WelcomeSheet Hero)

/// Animierte Nachbildung der Dynamic Island — zeigt wie ein laufender Drop
/// oben auf dem Sperrbildschirm / in der Live Activity aussieht.
/// Loopt: kompakt → expandiert (Aktivität + Count + Live) → kompakt.
struct DynamicIslandMock: View {
    @State private var expanded = false
    @State private var showContent = false

    var body: some View {
        // Single morphing shape — no if/else view destruction.
        // cornerRadius 17 = capsule (half of height 34), 28 = expanded pill.
        RoundedRectangle(cornerRadius: expanded ? 28 : 17, style: .continuous)
            .fill(Color.black)
            .frame(
                width:  expanded ? 300 : 126,
                height: expanded ? 88  : 34
            )
            .shadow(
                color:  .black.opacity(expanded ? 0.35 : 0.20),
                radius: expanded ? 18 : 8,
                y:      expanded ? 8  : 4
            )
            .overlay {
                ZStack {
                    // Compact content — always in tree, fades out on expand
                    compactContent
                        .frame(width: 126)          // fixed → no layout thrash
                        .opacity(expanded ? 0 : 1)
                    // Expanded content — fades in after shape finishes morphing
                    expandedContent
                        .frame(width: 300)
                        .opacity(showContent ? 1 : 0)
                }
                .clipped()
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.74), value: expanded)
            .frame(height: 140)
            .task {
                do {
                    // Wait for sheet presentation to finish before starting loop.
                    try await Task.sleep(for: .seconds(0.7))
                    while true {
                        try await Task.sleep(for: .seconds(1.0))
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) { expanded = true }
                        try await Task.sleep(for: .seconds(0.3))
                        withAnimation(.easeIn(duration: 0.18)) { showContent = true }
                        try await Task.sleep(for: .seconds(2.8))
                        withAnimation(.easeOut(duration: 0.12)) { showContent = false }
                        try await Task.sleep(for: .seconds(0.2))
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { expanded = false }
                        try await Task.sleep(for: .seconds(1.5))
                    }
                } catch {}
            }
    }

    // Compact: links emoji + "2/4", rechts grüner Dot
    private var compactContent: some View {
        HStack {
            HStack(spacing: 3) {
                Text("☕️").font(.system(size: 14))
                Text("2/4")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.leading, 10)
            Spacer()
            Circle()
                .fill(Color(hex: "22c55e"))
                .frame(width: 6, height: 6)
                .padding(.trailing, 10)
        }
    }

    // Expanded: Leading = emoji-Box + Name + Ort, Trailing = Personen-Capsule
    private var expandedContent: some View {
        HStack(alignment: .center, spacing: 0) {
            // Leading
            HStack(spacing: 8) {
                Text("☕️")
                    .font(.system(size: 28))
                    .frame(width: 46, height: 46)
                    .background(Color.white.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kaffee")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text("Schwabing")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .padding(.leading, 14)

            Spacer()

            // Trailing — Personen-Capsule
            HStack(spacing: 3) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11))
                Text("2/4")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.12), in: Capsule())
            .padding(.trailing, 14)
        }
    }
}

// MARK: - Empty State: Keine Drops in der Nähe

struct DropsEmptyState: View {
    var onCreateTap: (() -> Void)? = nil
    /// Wenn true → kleine Boost-Bonus-Zeile unter der Beschreibung
    /// ("+15 / +25 Punkte als Bonus für deinen Drop"). Triggert wenn weniger
    /// als `AppStore.boostThreshold` Drops in der Umgebung sind — die
    /// gleiche Bedingung, unter der dieser Empty-State sichtbar ist.
    /// Der frühere separate `BoostBanner` weiter unten im Feed entfällt
    /// damit, weil sonst zwei UI-Elemente die gleiche Info doppelt zeigen.
    var boostActive: Bool = false
    /// Während Power-Hour-Slots ist `boostBonus` 25 statt 15 — wird vom
    /// Aufrufer durchgereicht, damit der Empty-State den richtigen Wert
    /// + ein "Power-Hour"-Label statt "Bonus" zeigen kann.
    var boostBonus: Int = 15
    var isPowerHour: Bool = false
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        VStack(spacing: 28) {
            // Rotierendes Drops-Mark (echtes App-Icon-Zeichen, ohne „du"-Dot
            // — niemand ist da, der Ring dreht sich und wartet).
            RotatingDropsMark(size: 92)
                .padding(.top, 8)

            VStack(spacing: 12) {
                Text(tr("shared.feed_empty_title"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.brandNight)
                    .multilineTextAlignment(.center)
                Text(tr("shared.feed_empty_body"))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 40)

                // Boost-Bonus-Zeile — sichtbar wenn Boost-Phase aktiv ist.
                // Schmale Capsule mit Bolt-Icon + Hinweis auf die +15
                // Punkte. Belohnung statt eigener Werbe-Banner — die
                // Botschaft "sei der erste" oben bleibt der primäre CTA,
                // der Bonus untermauert ihn nur.
                if boostActive {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.accentOrange)
                        Text(isPowerHour
                             ? tr("shared.power_hour_bonus_amount").replacingOccurrences(of: "{bonus}", with: "\(boostBonus)")
                             : tr("shared.boost_bonus_amount").replacingOccurrences(of: "{bonus}", with: "\(boostBonus)"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.accentOrange)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.accentOrange.opacity(0.12))
                    )
                    .overlay(
                        Capsule().stroke(Color.accentOrange.opacity(0.30), lineWidth: 1)
                    )
                    .padding(.top, 8)
                }
            }

            if let action = onCreateTap {
                Button(action: action) {
                    HStack(spacing: 10) {
                        // „du"-Dot aus dem Logo — Orange Signal links.
                        Circle()
                            .fill(Color.brandOrange)
                            .frame(width: 10, height: 10)
                            .shadow(color: Color.brandOrange.opacity(0.6), radius: 4)
                        Text("Starte eine Runde")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 22).padding(.vertical, 15)
                    .background(Capsule().fill(Color.brandViolet))
                }
                .dropsPressable()
                .padding(.top, 6)
            }
        }
    }
}

// MARK: - Orbiting Dot Mark
//
// MARK: - Swipe-to-Confirm (Komm dazu)
//
// Große Swipe-Capsule mit Violett→Orange-Gradient. Links sitzt ein weißes
// Handle mit der JoinMorphMark — während der User nach rechts zieht, läuft
// der progress 0→1 und der offene Ring schließt sich live mit der Geste.
// Bei ≥85% schnappt der Handle ans Ende, der Ring ist komplett geschlossen,
// und `onConfirm` feuert. Loslassen vorher = federt zurück.
struct SwipeToConfirm: View {
    var label: String = "Komm dazu"
    /// Steuert ob das Swipen überhaupt möglich ist. True auch dann, wenn
    /// `canConfirm` false ist — der User kann die Morph-Animation auslösen,
    /// aber am Ende rastet der Handle nicht ein (federt zurück).
    var isEnabled: Bool = true
    /// Darf der onConfirm beim vollständigen Swipe tatsächlich feuern?
    /// Wenn false federt der Handle zurück statt zu rasten.
    var canConfirm: Bool = true
    var onConfirm: () -> Void

    @State private var dragX: CGFloat = 0
    @State private var confirmed: Bool = false
    @State private var pulse: CGFloat = 1.0
    @State private var dotBreathe: CGFloat = 1.0
    private let handleSize: CGFloat = 52
    private let height: CGFloat = 68
    private let horizontalPadding: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let maxDrag = max(geo.size.width - handleSize - horizontalPadding * 2, 1)
            let progress = min(max(dragX / maxDrag, 0), 1)

            ZStack(alignment: .leading) {
                // Track — Violett→Orange Verlauf
                Capsule()
                    .fill(Color.brandViolet)
                    .shadow(color: Color.brandViolet.opacity(0.3), radius: 14, y: 5)

                // Light-Sweep-Overlay (bewegt sich sanft über die Capsule)
                // signalisiert „hier swipen", damit es nicht wie ein Button
                // wirkt. Fadet raus wenn User anfängt zu ziehen.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.0),
                                     Color.white.opacity(0.22),
                                     Color.white.opacity(0.0)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .scaleEffect(x: 0.35, y: 1, anchor: .leading)
                    .offset(x: (geo.size.width + 60) * (pulse - 0.5))
                    .mask(Capsule())
                    .opacity(1.0 - progress)
                    .allowsHitTesting(false)

                // Label (verblasst mit progress)
                Text(label)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(1.0 - progress * 0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.leading, handleSize * 0.6)
                    .allowsHitTesting(false)

                // Hint-Pfeile rechts (zwei, wie bei iOS „slide to unlock")
                HStack(spacing: 2) {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white.opacity(0.55 * (1.0 - progress)))
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white.opacity(0.85 * (1.0 - progress)))
                }
                .font(.system(size: 14, weight: .heavy))
                .padding(.trailing, 22)
                .allowsHitTesting(false)

                // Swipeable Handle = der orangene „du"-Dot aus dem Logo.
                // Metapher: der Dot swiped nach rechts, kommt zur Runde dazu
                // (schließt am Ende den offenen Ring). Pulsiert sanft im
                // Ruhezustand als „komm, drück mich" — Signal.
                ZStack {
                    // Soft outer glow (orange halo)
                    Circle()
                        .fill(Color.brandOrange.opacity(0.35))
                        .frame(width: handleSize + 14, height: handleSize + 14)
                        .blur(radius: 8)
                        .scaleEffect(dotBreathe)

                    // Core Dot
                    Circle()
                        .fill(Color.brandOrange)
                        .frame(width: handleSize, height: handleSize)
                        .shadow(color: Color.brandOrange.opacity(0.55), radius: 10, y: 3)
                        .scaleEffect(dotBreathe * (1.0 + (dragX > 0 ? 0.05 : 0)))
                }
                .offset(x: horizontalPadding + dragX)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragX > 0)
            }
            // Geste auf dem GESAMTEN Track — der User kann irgendwo im Track
            // starten und swipen, nicht nur am Handle. Fühlt sich natürlicher an.
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled, !confirmed else { return }
                        dragX = min(max(value.translation.width, 0), maxDrag)
                    }
                    .onEnded { _ in
                        guard isEnabled, !confirmed else { return }
                        if dragX >= maxDrag * 0.82 && canConfirm {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                                dragX = maxDrag
                            }
                            confirmed = true
                            Haptic.selection()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                onConfirm()
                            }
                        } else {
                            // Zurückfedern — bei Teil-Swipe oder wenn
                            // canConfirm=false (Formular unvollständig).
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                                dragX = 0
                            }
                            if dragX >= maxDrag * 0.82 && !canConfirm {
                                // Kurzer „Nein"-Shake-Impuls als Feedback.
                                Haptic.selection()
                            }
                        }
                    }
            )
        }
        .frame(height: height)
        .onAppear {
            // Light-Sweep-Loop für die „swipebar"-Signalisierung.
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: false)) {
                pulse = 1.5
            }
            // Breath-Pulse auf dem orangen Dot — lebendig, lockt zum Swipen.
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                dotBreathe = 1.08
            }
        }
    }

    /// Reset von außen falls der Submit abbricht (z.B. HomeZoneWarningSheet).
    static let resetNotification = Notification.Name("SwipeToConfirm.reset")
}

// MARK: - Rotating Drops Mark (Empty State)
//
// Für Empty-States: nur der offene violette Kreis (ohne „a"-Stamm) steht
// still, der orangene „du"-Dot kreist drumherum und sucht einen Anschluss.
// Signal: „wir scannen die Umgebung — niemand ist bisher dran".
private struct RotatingDropsMark: View {
    var size: CGFloat = 92
    @State private var spin: Double = 0

    var body: some View {
        ZStack {
            // Offener Ring (gleiche Geometrie wie AppIcon: r=78, Strich 40,
            // Lücke oben rechts), aber OHNE Stamm.
            OpenRingShape()
                .fill(Color.brandViolet)
                .frame(width: size, height: size)

            // Oranger Dot auf Kreisbahn: Dot sitzt rechts vom Zentrum
            // (.offset.x = Radius), der ganze Container rotiert um die
            // Mitte — so wandert der Dot sauber um den Ring.
            ZStack {
                Circle()
                    .fill(Color.brandOrange)
                    .frame(width: size * 0.21, height: size * 0.21)
                    .shadow(color: Color.brandOrange.opacity(0.5), radius: 6, y: 2)
                    .offset(x: size * 0.46)
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin))
        }
        .onAppear {
            // Linear + repeatForever auf rotationEffect = sauberer Dauer-Orbit.
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                spin = 360
            }
        }
    }
}

/// Nur der offene Ring aus dem AppIcon — ohne den „a"-Stamm.
private struct OpenRingShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 256.0
        var arc = Path()
        arc.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                   radius: 78 * s,
                   startAngle: .degrees(-1.16), endAngle: .degrees(265.16),
                   clockwise: false)
        return arc.strokedPath(StrokeStyle(lineWidth: 40 * s, lineCap: .round))
    }
}

// MARK: - Empty State: Noch keine Freunde

struct FreundeEmptyState: View {
    /// Optionaler Tap-Handler für „Aus Kontakten hinzufügen". Wenn gesetzt
    /// wird der Button gerendert. Falls die Parent-View den Flow nicht
    /// braucht (z.B. Settings-Section ohne diesen Aktion), kann sie nil
    /// übergeben und der Button erscheint nicht.
    var onAddFromContacts: (() -> Void)? = nil
    var onShareInvite: (() -> Void)? = nil

    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        VStack(spacing: 28) {
            RadarPulseHero(icon: "person.2.fill", ringCount: 2)

            VStack(spacing: 12) {
                Text(tr("shared.no_friends_title"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.brandNight)
                    .multilineTextAlignment(.center)
                Text(tr("shared.no_friends_body"))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 40)
            }

            // CTA-Buttons — primär „Kontakte" (häufigster Pfad), sekundär
            // „Einladungslink teilen". Vorher: gar nichts klickbar →
            // Sackgassen-Empty-State, Frust statt Action.
            if onAddFromContacts != nil || onShareInvite != nil {
                VStack(spacing: 8) {
                    if let action = onAddFromContacts {
                        Button(action: action) {
                            HStack(spacing: 8) {
                                Text(tr("shared.add_from_contacts"))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 13, weight: .heavy))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 26).padding(.vertical, 14)
                            .background(Capsule().fill(Color.brandViolet))
                        }
                        .dropsPressable()
                    }
                    if let share = onShareInvite {
                        Button(action: share) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(tr("shared.share_invite_link"))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.brand)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(Color.brand.opacity(0.10)))
                        }
                        .dropsPressable()
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Drop teilen (ShareSheet)

struct DropShareButton: View {
    let item: MapAnnotationItem
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        Button {
            shareDrops()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.textSecondary)
                .padding(8)
                .background(Circle().fill(Color.white.opacity(0.78)))
        }
        .dropsPressable()
    }

    private func shareDrops() {
        // www-Subdomain nutzen — Apex 307-redirected zu www, Apple Universal
        // Links akzeptieren keine Redirects (siehe LiveMapView).
        let deepLink = AppLinks.dropShareURL(dropID: item.id.uuidString)
        let location = item.locationTitle.isEmpty ? "" : " · \(item.locationTitle)"
        let text = "\(item.emoji) \(item.activity)\(location) — komm vorbei. Spontan, vor Ort, kein Smalltalk. 👋"
        // Text + URL als EIN String — sonst kopiert iOS „In Zwischenablage"
        // nur den Text und verliert die URL. Apps wie iMessage/WhatsApp
        // parsen die URL eh automatisch raus und zeigen Link-Preview.
        let combined = "\(text)\n\(deepLink)"
        let items: [Any] = [combined]

        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        av.excludedActivityTypes = [.assignToContact, .saveToCameraRoll, .print]

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            var top = root
            while let presented = top.presentedViewController { top = presented }
            top.present(av, animated: true)
        }
    }
}


// MARK: - Profile Hero Background Templates

/// Vordefinierte Hintergrund-Vorlagen für die Profil-Hero-Karte.
/// User kann via Picker zwischen den 6 Varianten wählen — wird in
/// UserDefaults persistiert (`ud_profileHeroTemplate`).
enum ProfileHeroTemplate: String, CaseIterable, Identifiable {
    case tester, aurora, sunset, ocean, forest, neon, midnight
    var id: String { rawValue }

    var label: String {
        switch self {
        case .tester:   return "Beta"
        case .aurora:   return "Dazu"
        case .sunset:   return "Goldstunde"
        case .ocean:    return "Himmel"
        case .forest:   return "Natur"
        case .neon:     return "Abendrot"
        case .midnight: return "Nacht"
        }
    }

    /// Exklusive Tester-Variante — holographisch / iridescent. Symbolisiert
    /// die Beta-Tester-Identität visuell. Default für Beta-User.
    var isExclusive: Bool { self == .tester }

    /// Dunkle Templates brauchen mehr Material-Opazität damit Text lesbar bleibt.
    var isDark: Bool {
        switch self {
        case .midnight, .neon, .forest: return true
        default: return false
        }
    }

    /// Gradient-Opazität die auf Karten verwendet wird — dunkle Templates
    /// erhalten eine niedrigere Deckkraft damit das Material nicht zu sehr eingefärbt wird.
    var cardGradientOpacity: Double { isDark ? 0.20 : 0.38 }

    /// Hauptfarben — auch für Thumbnail-Vorschau im Picker genutzt.
    var colors: [Color] {
        switch self {
        case .tester:
            // Holographic/iridescent — pink → cyan → gold → violet
            return [Color.auroraPink, Color.auroraCyan,
                    Color.auroraAmber, Color.auroraPurple]
        case .aurora:
            // Brand-Gradient: warmes Orange → Pink → frisches Grün (App-Icon-Palette)
            return [Color.auroraOrange, Color.auroraPink, Color.auroraGreen]
        case .sunset:
            // Goldstunde — warmer Amber → Peach → Rose (goldene Stunde, Feierabend-Drops)
            return [Color(hex: "f59e0b"), Color(hex: "fb923c"), Color(hex: "f43f5e")]
        case .ocean:
            // Himmel — Sky Blue → Indigo → Violet (klarer Himmel über der Stadt)
            return [Color(hex: "0ea5e9"), Color(hex: "6366f1"), Color(hex: "8b5cf6")]
        case .forest:
            // Natur — Tiefes Waldgrün → Smaragd → Limette (Parks, Spaziergänge, Natur-Drops)
            return [Color(hex: "166534"), Color(hex: "16a34a"), Color(hex: "65a30d")]
        case .neon:
            // Abendrot — Violet → Hot Pink → Orange (Dusk-Gradient, Bar-Drops, Abende)
            return [Color(hex: "7c3aed"), Color(hex: "db2777"), Color(hex: "f97316")]
        case .midnight:
            // Nacht — Deep Navy → Dunkles Indigo → Blue-Pop (Stadtlichter, Nacht-Drops)
            return [Color(hex: "0f172a"), Color(hex: "1e1b4b"), Color(hex: "2563eb")]
        }
    }

    var gradient: LinearGradient {
        // Tester nutzt steileren Winkel für mehr "Iridescent"-Effekt
        if self == .tester {
            return LinearGradient(colors: colors,
                                  startPoint: UnitPoint(x: 0, y: 0),
                                  endPoint: UnitPoint(x: 1, y: 1))
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Emoji Scatter Background

/// Mehrere kleine Emojis in einem fixen Scatter-Muster — wirkt wie ein
/// dezentes Hintergrundmuster ohne echte Zufälligkeit (deterministisch für SwiftUI).
struct EmojiScatterBackground: View {
    let emoji: String

    // (x%, y%, rotation°, scale, delay, duration)
    private let placements: [(CGFloat, CGFloat, Double, CGFloat, Double, Double)] = [
        (0.10, 0.18, -18, 0.85,  0.0, 2.4),
        (0.78, 0.10,  14, 1.00,  0.9, 2.8),
        (0.42, 0.55,  -7, 0.80,  1.7, 2.2),
        (0.88, 0.55,  22, 0.90,  0.4, 3.0),
        (0.18, 0.82, -22, 0.95,  2.1, 2.6),
        (0.60, 0.22,   6, 0.75,  1.3, 2.0),
        (0.93, 0.82, -12, 1.05,  0.6, 3.2),
        (0.50, 0.88,  17, 0.88,  1.8, 2.4),
    ]

    @State private var visible: [Bool] = Array(repeating: false, count: 8)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(placements.enumerated()), id: \.offset) { i, p in
                    Text(emoji)
                        .font(.system(size: 26))
                        .scaleEffect(p.3)
                        .rotationEffect(.degrees(p.2))
                        .opacity(visible[i] ? 0.40 : 0.0)
                        .position(x: geo.size.width  * p.0,
                                  y: geo.size.height * p.1)
                }
            }
        }
        .allowsHitTesting(false)
        .task {
            // Task wird automatisch gecancelt wenn der View verschwindet —
            // kein DispatchQueue-Stacking bei schnellem Show/Hide.
            await withTaskGroup(of: Void.self) { group in
                for i in 0..<placements.count {
                    let delay    = placements[i].4
                    let duration = placements[i].5
                    group.addTask {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                                visible[i] = true
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Animated Hero Gradient

/// Lebendiger Hero-Gradient — zwei Richtungen kreuzen sich langsam,
/// sodass der Farbverlauf sanft "atmet". Performant (nur Opacity-Animation,
/// kein Layout-Pass nötig).
struct AnimatedHeroGradient: View {
    let template: ProfileHeroTemplate
    var opacity: Double = 1.0

    @State private var shifted = false

    var body: some View {
        ZStack {
            // Primäre Richtung
            LinearGradient(colors: template.colors,
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            // Querrichtung — blendet langsam ein und aus
            LinearGradient(colors: template.colors,
                           startPoint: .bottomLeading,
                           endPoint: .topTrailing)
                .opacity(shifted ? 0.55 : 0.0)
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                shifted = true
            }
        }
    }
}

// MARK: - Gradient Avatar Ring

/// Dünner Gradient-Ring um ein Avatar-Circle. Wird überall in der App
/// verwendet wo Profilbilder erscheinen.
struct GradientAvatarRing: View {
    var template: ProfileHeroTemplate = .aurora
    var size: CGFloat          // Außendurchmesser des Rings
    var lineWidth: CGFloat = 2.2

    @State private var shifted = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(colors: template.colors,
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    lineWidth: lineWidth
                )
                .opacity(shifted ? 0.0 : 1.0)
            Circle()
                .stroke(
                    LinearGradient(colors: template.colors,
                                   startPoint: .bottomLeading,
                                   endPoint: .topTrailing),
                    lineWidth: lineWidth
                )
                .opacity(shifted ? 1.0 : 0.0)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                shifted = true
            }
        }
    }
}

/// Tap-Picker-Sheet zum Wechseln des Hero-Backgrounds.
struct ProfileHeroPickerSheet: View {
    @Binding var selection: ProfileHeroTemplate
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(tr("shared.choose_background"))
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28).padding(.top, 8)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(ProfileHeroTemplate.allCases) { tpl in
                            Button {
                                Haptic.selection()
                                selection = tpl
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dismiss() }
                            } label: {
                                VStack(spacing: 8) {
                                    AnimatedHeroGradient(template: tpl)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                                        .frame(height: 110)
                                        .overlay(alignment: .topTrailing) {
                                            // Exklusiv-Marker für Tester-Variante
                                            if tpl.isExclusive {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "sparkle")
                                                        .font(.system(size: 7, weight: .bold))
                                                    Text(tr("shared.beta"))
                                                        .font(.system(size: 8, weight: .bold))
                                                        .kerning(0.3)
                                                }
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(Capsule().fill(Color.white.opacity(0.75)))
                                                .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 0.6))
                                                .padding(8)
                                            }
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                                .stroke(
                                                    selection == tpl ? Color.brand : Color.white.opacity(0.15),
                                                    lineWidth: selection == tpl ? 3 : 1
                                                )
                                        )
                                        .shadow(color: tpl.colors.first?.opacity(0.35) ?? .clear, radius: 8, y: 4)
                                    HStack(spacing: 5) {
                                        if selection == tpl {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(.brand)
                                        }
                                        Text(tpl.label)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.textPrimary)
                                    }
                                }
                            }
                            .dropsPressable()
                        }
                    }
                    .padding(.horizontal, 16)

                    Spacer(minLength: 24)
                }
            }
            .navigationTitle(tr("shared.background"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("shared.done")) { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - Beta Badge

/// Kleiner Badge für Early-Adopter / Beta-User. Wird neben dem Namen
/// im Profil + auf User-Karten angezeigt.
struct BetaBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkle")
                .font(.system(size: 8, weight: .bold))
            Text(tr("shared.beta"))
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .kerning(0.4)
        }
        .foregroundColor(.brandViolet)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Color.brandLavender))
    }
}


// MARK: - Emoji Picker Sheet

struct EmojiPickerSheet: View {
    let selected: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    // Kategorien: Personen, Tiere, Gesichter/Natur, Essen, Aktivitäten, Objekte
    private let categories: [(name: String, icon: String, emojis: [String])] = [
        ("Personen", "person.fill", [
            "😊","😎","🤩","😇","🥳","🤓","🧐","😏","😌","🥰",
            "😂","🤣","😆","😄","😁","😋","🤤","🤗","🫡","🤭",
            "😤","😅","🤠","🥸","🫠","🤑","😈","👾","🤖","👻",
            "🧑","👦","👧","👨","👩","🧔","👱","🧕","👮","🕵️"
            
        ]),
        ("Tiere", "pawprint.fill", [
            "🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐨","🐯",
            "🦁","🐮","🐷","🐸","🐵","🐔","🐧","🐦","🦅","🦉",
            "🦋","🐢","🦎","🐍","🐬","🐳","🦈","🦑","🐙","🦔",
            "🦄","🐲","🦖","🦕","🦩","🦚","🦜","🐺","🦝","🦛"
        ]),
        ("Natur", "leaf.fill", [
            "🌸","🌺","🌻","🌹","🌷","🌼","💐","🍀","🌿","🌱",
            "🌲","🌴","🌵","🎋","🍁","🍂","🍃","⭐️","🌟","✨",
            "🔥","💧","🌊","❄️","⚡️","🌈","☀️","🌙","🌍","🪐"
        ]),
        ("Essen", "fork.knife", [
            "🍕","🍔","🌮","🌯","🍜","🍣","🍩","🍪","🎂","🍰",
            "🍦","🧃","🥤","☕️","🍺","🍷","🧋","🍭","🍫","🍿",
            "🥑","🍓","🍇","🍉","🍋","🥦","🧀","🥚","🥐","🍞"
        ]),
        ("Sport", "figure.run", [
            "⚽️","🏀","🏈","⚾️","🎾","🏐","🎱","🏓","🏸","🥊",
            "🎿","🏂","🏄","🚴","🧗","🤸","⛹️","🏋️","🤼","🥋",
            "🎯","🎳","🎮","🕹️","🎲","♟️","🎭","🎨","🎵","🎸"
        ]),
        ("Objekte", "star.fill", [
            "🚀","🛸","🏆","🥇","🎖️","👑","💎","🔮","🎁","🎀",
            "📱","💻","🎧","📷","🎤","🎬","🔑","💡","🧲","⚙️",
            "🛡️","⚔️","🪄","🎩","🕶️","💼","🧳","🌂","🪬","🔭"
        ])
    ]

    @State private var selectedCategory = 0
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule().fill(Color(UIColor.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 10).padding(.bottom, 16)

            // Titel
            HStack {
                Text(tr("shared.your_emoji"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                // Vorschau
                Text(selected)
                    .font(.system(size: 28))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            // Kategorien-Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(categories.enumerated()), id: \.offset) { i, cat in
                        Button {
                            withAnimation(.spring(response: 0.25)) { selectedCategory = i }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(cat.name)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(selectedCategory == i ? .white : .textSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(
                                selectedCategory == i
                                    ? Color.brand
                                    : Color(UIColor.systemGray5),
                                in: Capsule()
                            )
                        }
                        .dropsPressable()
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 12)

            // Emoji-Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(categories[selectedCategory].emojis, id: \.self) { emoji in
                        Button {
                            Haptic.selection()
                            onSelect(emoji)
                            dismiss()
                        } label: {
                            Text(emoji)
                                .font(.system(size: 28))
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                                .background(
                                    emoji == selected
                                        ? Color.brand.opacity(0.18)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: Radius.md)
                                )
                                .overlay(
                                    emoji == selected
                                        ? RoundedRectangle(cornerRadius: Radius.md)
                                            .stroke(Color.brand.opacity(0.5), lineWidth: 1.5)
                                        : nil
                                )
                        }
                        .dropsPressable()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Power-Hour Countdown Pill
//
// Wird sowohl im LiveMapView als auch im FeedView angezeigt — extrahiert
// damit beide Tabs konsistent dieselbe Pille rendern. Sichtbar ≤60 Min vor
// einem Window-Start oder ≤60 Min vor Ende eines aktiven Slots; sonst nil.
//
// Hostende Views wickeln den Aufruf in eine TimelineView, damit der
// Countdown jede Minute neu berechnet wird.
struct PowerHourCountdownPill: View {
    let countdown: AppStore.PowerHourCountdown

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(Color.brandOrange))
    }

    private var label: String {
        let mins = formatMinutes(countdown.minutesRemaining)
        switch countdown.phase {
        case .startingSoon: return tr("shared.ph_starting_in").replacingOccurrences(of: "{time}", with: mins)
        case .running:      return tr("shared.power_hour_running").replacingOccurrences(of: "{time}", with: mins)
        case .endingSoon:   return tr("shared.ph_ending_in").replacingOccurrences(of: "{time}", with: mins)
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) Min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)min"
    }
}

// MARK: - App Version Gate (Force-Update + Recommend-Banner)
//
// Liest store.appVersionStatus und rendert je nach Phase:
//   - .updateRequired: blockierender Vollbild (kein Schließen möglich)
//   - .updateRecommended: dezenter dismissibler Banner oben
//   - .ok / .unknown: nichts
/// Force-Update-Vollbild-Overlay. NUR für Hard-Force. Der Soft-Recommend-
/// Banner wird in MainTabView via safeAreaInset(.top) eingehängt, damit er
/// wirklich an den oberen Screen-Rand andockt und nicht von anderen Overlays
/// verdrängt wird.
struct AppVersionGate: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if case .updateRequired(let v) = store.appVersionStatus {
                ForceUpdateSheet(requiredVersion: v)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85),
                   value: store.appVersionStatus)
    }
}

/// Recommend-Banner als eigene Top-Inset-View, damit er als wirklicher
/// Top-Banner direkt unter der Status Bar sitzt und nicht im View-Mittelteil
/// verschwindet.
struct AppVersionRecommendBanner: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if case .updateRecommended(let v) = store.appVersionStatus {
                RecommendUpdateBanner(recVersion: v) {
                    store.dismissRecommendBanner(forVersion: v)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85),
                   value: store.appVersionStatus)
    }
}

/// Vollbild-Blocker: kein "X", kein Drag-Dismiss. Einziger Ausweg ist
/// "App Store öffnen". Genutzt nur für Notfälle (kritische Bugs).
///
/// Design: vollflächiger `AppAuroraBackground` (matched zum Rest der App)
/// + Hero-Icon-Stack mit drei pulsierenden Radar-Wellen + Sunset-Gradient-
/// Glow drumherum. Visuell parallel zum `EndDropSheet`/`HomeZoneWarningSheet`,
/// nur „aufwärts" statt „beenden" konnotiert.
private struct ForceUpdateSheet: View {
    let requiredVersion: String
    @EnvironmentObject var store: AppStore

    @State private var iconBeat = false

    var body: some View {
        ZStack {
            Color.brandCream.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.brandLavender.opacity(0.9))
                        .frame(width: 96, height: 96)
                        .scaleEffect(iconBeat ? 1.05 : 0.98)
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 46, weight: .heavy))
                        .foregroundColor(.brandOrange)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: -2) {
                    Text("Update")
                        .foregroundColor(.brandNight)
                    Text("ist nötig.")
                        .foregroundColor(.brandViolet)
                }
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .padding(.horizontal, 28)

                Text(tr("shared.version_required").replacingOccurrences(of: "{ver}", with: requiredVersion))
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)

                HStack(spacing: 6) {
                    Image(systemName: "iphone")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.brandViolet)
                    Text(tr("shared.using_version").replacingOccurrences(of: "{ver}", with: store.currentAppVersion))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandViolet)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.brandLavender))
                .padding(.horizontal, 28)

                Spacer()

                Button(action: openAppStore) {
                    Text(tr("shared.open_app_store"))
                        .dropsPrimaryButton()
                }
                .dropsPressable()
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                iconBeat = true
            }
        }
    }

    private func openAppStore() {
        let id = AppStore.appStoreID
        // itms-apps:// öffnet die App-Store-App direkt; falls die ID
        // mal nicht gesetzt ist (Pre-Release-Branch o.ä.) → https-Fallback
        // auf den echten Drops-Listing-Pfad.
        let urlString = id.isEmpty
            ? "https://apps.apple.com/de/app/drops-triff-leute/id6762097493"
            : "itms-apps://itunes.apple.com/app/id\(id)"
        if let url = URL(string: urlString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}

/// Soft-Recommend: kleiner Banner oben, dismissibel mit X.
private struct RecommendUpdateBanner: View {
    let recVersion: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("shared.new_version"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text(tr("shared.version_in_store").replacingOccurrences(of: "{ver}", with: recVersion))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.85))
            }
            Spacer()
            Button(action: openAppStore) {
                Text(tr("shared.now"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.22)))
            }
            .dropsPressable()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(6)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .dropsPressable()
            .accessibilityLabel(tr("shared.close_banner"))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [Color.brand, Color.accentOrange],
                    startPoint: .leading, endPoint: .trailing
                )
            )
        )
        .shadow(color: Color.accentOrange.opacity(0.25), radius: 8, y: 2)
    }

    private func openAppStore() {
        let id = AppStore.appStoreID
        let urlString = id.isEmpty
            ? "https://apps.apple.com/de/app/drops"
            : "itms-apps://itunes.apple.com/app/id\(id)"
        if let url = URL(string: urlString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Home Zone Warning Sheet
//
// Eigene Warnung statt System-Alert: visuell wärmer, mit Icon und
// strukturierten Hinweisen. Gibt dem User mehr Kontext was passiert
// und ist visuell konsistent mit dem restlichen App-Design (Aurora-
// Hintergrund, Brand-Farben, Liquid-Glass-Card).
struct HomeZoneWarningSheet: View {
    /// User wählt "Trotzdem hier starten".
    let onProceed: () -> Void
    /// User wählt "Abbrechen" oder Drag-to-dismiss.
    let onCancel: () -> Void

    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.brandCream.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        // Großes Haus-Icon in Orange-Lavendel-Kreis (flat).
                        ZStack {
                            Circle()
                                .fill(Color.brandLavender.opacity(0.9))
                                .frame(width: 92, height: 92)
                                .scaleEffect(pulse ? 1.05 : 0.98)
                            Image(systemName: "house.fill")
                                .font(.system(size: 40, weight: .heavy))
                                .foregroundColor(.brandOrange)
                        }
                        .padding(.top, 20)
                        .frame(maxWidth: .infinity, alignment: .center)

                        // Big headline im Rondesignlab-Rhythmus: Nacht + Violett.
                        VStack(alignment: .leading, spacing: -2) {
                            Text("Das ist")
                                .foregroundColor(.brandNight)
                            Text("deine Heimzone.")
                                .foregroundColor(.brandViolet)
                        }
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)

                        Text("Wenn du hier startest, sehen Fremde ungefähr, wo du wohnst.")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.65))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 24)

                        VStack(spacing: 10) {
                            warningRow(icon: "eye.fill",
                                       text: "Dein Standort ist auf 500 m sichtbar")
                            warningRow(icon: "figure.walk",
                                       text: "Wähle lieber einen öffentlichen Ort")
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Aktionen — fester Footer
                VStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("Anderen Ort wählen")
                            .dropsPrimaryButton()
                    }
                    .dropsPressable()

                    Button(action: onProceed) {
                        Text("Trotzdem hier starten")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .dropsPressable()
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 22)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    @ViewBuilder
    private func warningRow(icon: String, text: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.brandViolet)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.brandLavender))
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.brandNight.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .liquidGlass(cornerRadius: 18)
    }
}

// MARK: - Admin Notice Sheet
//
// Pflicht-Sheet wenn ein Admin den Drop des Users via Live-Drops-Monitor
// entfernt hat. Wird auf MainTabView-Ebene gebunden (sheet(item:)
// auf store.pendingAdminNotice). Der User MUSS „Verstanden" tippen,
// das löscht den Notice aus Firebase. Drag-to-dismiss ist deaktiviert
// — die Botschaft soll wirklich gelesen werden.

struct AdminNoticeSheet: View {
    let notice: RealtimeDBManager.AdminNotice
    let onAcknowledge: () -> Void

    private var headline: String {
        switch notice.type {
        case "drop_removed": return "Dein Plan wurde entfernt"
        default:             return "Hinweis"
        }
    }

    private var body1: String {
        switch notice.type {
        case "drop_removed":
            return "Ein Admin hat ihn von der Karte genommen."
        default:
            return "Lies dir das durch."
        }
    }

    var body: some View {
        ZStack {
            Color.brandCream.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color.brandLavender.opacity(0.9))
                                .frame(width: 92, height: 92)
                            Image(systemName: "exclamationmark.shield.fill")
                                .font(.system(size: 40, weight: .heavy))
                                .foregroundColor(.brandOrange)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)

                        VStack(alignment: .leading, spacing: -2) {
                            Text(headline)
                                .foregroundColor(.brandNight)
                        }
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 24)

                        Text(body1)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 24)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(tr("shared.reason").uppercased())
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .tracking(1.2)
                                .foregroundColor(.brandViolet.opacity(0.7))
                            Text(notice.reason)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(.brandNight)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .liquidGlass(cornerRadius: 18)
                        .padding(.horizontal, 20)

                        Text(tr("shared.questions_support"))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                    }
                    .padding(.bottom, 12)
                }

                Button(action: onAcknowledge) {
                    Text(tr("shared.understood"))
                        .dropsPrimaryButton()
                }
                .dropsPressable()
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 22)
            }
        }
    }
}

// MARK: - Power-Hour Intro Sheet
//
// Einmaliger Hinweis nach App-Update, gezeigt beim ersten Map-Open.
// Erklärt Power-Hour kurz mit Bonus-Wert und den drei Slots — danach
// wird der Hinweis via @AppStorage("hasSeenPowerHourIntro") nicht mehr
// angezeigt. Auch ohne nochmal in die Settings zu gehen, weiß der User
// dann was Power-Hour ist und wann.
struct PowerHourIntroSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.brandCream.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color.brandLavender.opacity(0.9))
                                .frame(width: 92, height: 92)
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 40, weight: .heavy))
                                .foregroundColor(.brandOrange)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)

                        VStack(alignment: .leading, spacing: -2) {
                            Text("Power-Hour.")
                                .foregroundColor(.brandNight)
                            Text("Mehr Punkte.")
                                .foregroundColor(.brandViolet)
                        }
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 24)

                        Text(tr("shared.power_hour_explainer")
                            .replacingOccurrences(of: "{bonus}", with: "\(AppStore.powerHourBonus)")
                            .replacingOccurrences(of: "{base}", with: "\(AppStore.boostBonus)"))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 24)

                        VStack(spacing: 8) {
                            ForEach(Array(AppStore.powerHourWindows.enumerated()), id: \.offset) { _, window in
                                HStack {
                                    Text(window.label)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(.brandNight)
                                    Spacer()
                                    Text(formatWindow(window))
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(.brandViolet)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                                .liquidGlass(cornerRadius: 18)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    }
                }

                Button(action: onDismiss) {
                    Text(tr("shared.understood"))
                        .dropsPrimaryButton()
                }
                .dropsPressable()
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
                .padding(.top, 6)
            }
        }
    }

    private func formatWindow(_ w: AppStore.PowerHourWindow) -> String {
        "\(w.daysLabel) · \(w.timeRangeLabel)"
    }
}

// MARK: - Points Toast
//
// Globaler Toast für jeden Punkte-Gewinn. Wird vom AppStore via
// `pointsToast` getriggert — die View hier ist rein visuell und
// auto-dismisst sich nach 2.5 Sekunden via `.task`. Gradient + Bolt
// imitieren die Optik von Boost/Power-Hour-Hinweisen, im Power-Hour-
// Modus mit hellerem Akzent für mehr "pop".
// MARK: - Pending Join Request Pill (Joiner-Seite)

/// Floating-Pill oben in der App während eine Beitrittsanfrage des Users
/// pending ist. Zeigt Drop-Emoji + Aktivität + Live-Countdown bis Auto-
/// Accept (5 Min). Schwebt über Sheets + Tab-Bar damit der Joiner immer
/// sieht dass seine Anfrage läuft, egal wo er gerade ist in der App.
struct PendingJoinRequestPill: View {
    @EnvironmentObject var store: AppStore

    /// Emoji + Activity-Name werden beim sendJoinRequest in `store.pendingJoinDropEmoji`
    /// / `pendingJoinDropActivity` gecached — robuster als allMapAnnotations-
    /// Lookup, der fehlschlägt wenn der Drop aus dem Radius rutscht oder
    /// gerade vom Host gecancelt wird.
    private var dropEmoji: String {
        if !store.pendingJoinDropEmoji.isEmpty { return store.pendingJoinDropEmoji }
        // Fallback für Edge-Cases (Cache leer aus früherer App-Version etc.)
        if let id = store.pendingJoinDropID,
           let match = store.allMapAnnotations.first(where: { $0.id == id }) {
            return match.emoji
        }
        return "📍"
    }
    private var dropActivity: String {
        if !store.pendingJoinDropActivity.isEmpty { return store.pendingJoinDropActivity }
        if let id = store.pendingJoinDropID,
           let match = store.allMapAnnotations.first(where: { $0.id == id }) {
            return match.activity
        }
        return ""
    }

    /// Sekunden bis Auto-Accept (5 Min nach Anfrage). Capped bei 0.
    private func secondsRemaining(now: Date) -> Int {
        guard let requestedAt = store.pendingJoinRequestedAt else { return 0 }
        let elapsed = now.timeIntervalSince(requestedAt)
        return max(0, Int(5 * 60 - elapsed))
    }

    private func timeLabel(now: Date) -> String {
        let s = secondsRemaining(now: now)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Progress 0..1 — wieviel der 5 Min sind verstrichen.
    private func progress(now: Date) -> Double {
        guard let requestedAt = store.pendingJoinRequestedAt else { return 0 }
        let elapsed = now.timeIntervalSince(requestedAt)
        return min(1.0, max(0, elapsed / (5 * 60)))
    }

    /// Räumt den Pending-State lokal auf wenn der Timer 5 Min überschritten
    /// hat OHNE dass eine Antwort kam (Drop weg, Firebase-Path gelöscht,
    /// Host-App offline). Sonst hängt die Pill ewig bei 0:00.
    /// 5s Puffer für die Auto-Accept-Propagation; größere Hänger fängt der
    /// direkte Drop-Observer in AppStore (`observePendingDropEnd`) ab.
    private func cleanupIfStale(now: Date) {
        guard let requestedAt = store.pendingJoinRequestedAt else { return }
        let elapsed = now.timeIntervalSince(requestedAt)
        guard elapsed > 5 * 60 + 5 else { return }
        store.pendingJoinDropID = nil
        store.pendingJoinRequestedAt = nil
        store.pendingJoinDropEmoji = ""
        store.pendingJoinDropActivity = ""
        store.myJoinRequestStatus = ""
    }

    var body: some View {
        if store.myJoinRequestStatus == "pending",
           store.pendingJoinDropID != nil {
            // TimelineView statt Timer.publish — akkurater Tick auch wenn
            // andere Sheets/Animationen den Main-Thread belasten.
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let now = timeline.date
                VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Drop-Emoji-Avatar mit pulsierendem Ring
                    ZStack {
                        Circle()
                            .stroke(Color.auroraOrange.opacity(0.4), lineWidth: 1.5)
                            .frame(width: 38, height: 38)
                            .scaleEffect(1.0 + 0.1 * sin(now.timeIntervalSinceReferenceDate * 2))
                        Circle()
                            .fill(Color.auroraOrange.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Text(dropEmoji)
                            .font(.system(size: 18))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(tr("shared.request_pending"))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.textPrimary)
                            if !dropActivity.isEmpty {
                                Text("· \(dropActivity)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        // Countdown + Progress-Bar
                        HStack(spacing: 6) {
                            Text(timeLabel(now: now))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.textSecondary)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.textTertiary.opacity(0.18))
                                        .frame(height: 3)
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.auroraOrange, Color.auroraGreen],
                                                startPoint: .leading, endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geo.size.width * CGFloat(progress(now: now)), height: 3)
                                }
                            }
                            .frame(height: 3)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.75))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.auroraOrange.opacity(0.30), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(0.10), radius: 12, y: 4)
                .padding(.horizontal, 14)
                .padding(.top, 4)
                }
                .frame(maxWidth: 380)
                .onAppear { cleanupIfStale(now: now) }
                // Jeder Timeline-Tick (1× pro Sekunde) checkt ob die 5min+
                // bereits abgelaufen sind. Vorher: onChange(of: secondsRemaining)
                // feuerte einmal bei 0 — wenn dann die Guard (elapsed > 5*60+X)
                // noch nicht erfüllt war, blieb die Pill ewig bei „0:00" hängen,
                // weil secondsRemaining sich nicht mehr ändert.
                .onChange(of: Int(now.timeIntervalSinceReferenceDate)) { _, _ in
                    cleanupIfStale(now: now)
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct PointsToastView: View {
    let toast: AppStore.PointsToast
    /// Wird beim Auto-Dismiss aufgerufen (setzt store.pointsToast = nil).
    let onDismiss: () -> Void

    @State private var visible = false

    var body: some View {
        // Wenn Reason vorhanden → 2-Zeilen-Layout mit Subline darunter,
        // sonst kompakte 1-Zeile wie vorher. So weiß der User immer wofür
        // die Punkte kommen, ohne dass die Pille überfüllt wirkt.
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: toast.isPowerHour ? "bolt.fill" : "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(tr("shared.points_plus").replacingOccurrences(of: "{delta}", with: "\(toast.delta)"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                if toast.isPowerHour {
                    Text(tr("shared.power_hour"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
            }
            if let reason = toast.reason, !reason.isEmpty {
                Text(reason)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, toast.reason == nil ? 10 : 8)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: toast.isPowerHour
                        ? [Color.accentOrange, Color.brand]
                        : [Color.brand, Color.brand.opacity(0.85)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
        )
        .shadow(color: Color.accentOrange.opacity(0.32), radius: 12, y: 4)
        .scaleEffect(visible ? 1.0 : 0.85)
        .opacity(visible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                visible = true
            }
        }
        .task(id: toast.id) {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                visible = false
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            onDismiss()
        }
    }
}

// MARK: - Info-Toast (Anti-Farm-Feedback)
//
// Negativ-Variante des PointsToast: zeigt KEINE Punkte-Zahl, sondern
// einen kurzen Hinweis warum gerade nichts vergeben wurde
// ("Drop zu kurz", "12 h Cooldown"). Eigenes Styling (neutral grau-blau
// statt Brand-Orange) damit der User es sofort als „kein Gewinn"
// einordnet. Auto-Dismiss erfolgt im Store über asyncAfter — die View
// rendert nur solange `store.infoToast != nil`.
struct InfoToastView: View {
    let toast: AppStore.InfoToast

    @State private var visible = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text(toast.message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.22, blue: 0.28),
                        Color(red: 0.28, green: 0.30, blue: 0.36)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
        )
        .shadow(color: Color.black.opacity(0.20), radius: 10, y: 3)
        .scaleEffect(visible ? 1.0 : 0.9)
        .opacity(visible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                visible = true
            }
        }
    }
}

// MARK: - Leave-Drop Sheet (Joiner verlässt einen Drop)
//
// Visuell und vom Aufbau angelehnt an HomeZoneWarningSheet — wir wollen
// nicht dass der User aus Versehen einen Drop verlässt und seine
// Reliability-Punkte verliert. Klares Wording, primärer Bleiben-Button,
// destruktiver Verlassen-Button als Sekundär-Aktion.
struct LeaveDropSheet: View {
    let activityEmoji: String
    let activityName: String
    /// Sekunden seit Beitritt — entscheidet ob ein No-Show-Risiko besteht
    /// (nach 12 min wird Verlassen als Score-Abzug gewertet).
    let elapsedSeconds: TimeInterval
    let onLeave: () -> Void
    let onCancel: () -> Void

    @State private var pulse = false

    /// 12-Min-Schwelle = "kritischer Bereich" mit Score-Risiko.
    private var hasScoreRisk: Bool { elapsedSeconds >= 12 * 60 }

    var body: some View {
        ZStack {
            Color.brandCream.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        // Flat Icon-Circle (Lavendel).
                        ZStack {
                            Circle()
                                .fill(Color.brandLavender.opacity(0.9))
                                .frame(width: 92, height: 92)
                                .scaleEffect(pulse ? 1.04 : 0.98)
                            Image(systemName: "door.left.hand.open")
                                .font(.system(size: 40, weight: .heavy))
                                .foregroundColor(hasScoreRisk ? .brandOrange : .brandViolet)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)

                        VStack(alignment: .leading, spacing: -2) {
                            Text("Runde")
                                .foregroundColor(.brandNight)
                            Text("wirklich verlassen?")
                                .foregroundColor(.brandViolet)
                        }
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 24)

                        Text("\(activityEmoji) \(activityName)")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.65))
                            .padding(.horizontal, 24)

                        VStack(spacing: 10) {
                            if hasScoreRisk {
                                infoRow(icon: "exclamationmark.triangle.fill",
                                        text: "Nach 12 Min zählt das als No-Show")
                            } else {
                                infoRow(icon: "checkmark.shield.fill",
                                        text: "Innerhalb 12 Min: ohne Punkt-Abzug")
                            }
                            infoRow(icon: "person.fill.questionmark",
                                    text: "Host sieht, dass du weg bist")
                            infoRow(icon: "clock.arrow.circlepath",
                                    text: "10 Min Cooldown bis neuer Beitritt")
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity)
                }

                VStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("Dabei bleiben")
                            .dropsPrimaryButton()
                    }
                    .dropsPressable()

                    Button(action: onLeave) {
                        Text("Runde verlassen")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .dropsPressable()
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 22)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    @ViewBuilder
    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.brandViolet)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.brandLavender))
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.brandNight.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .liquidGlass(cornerRadius: 18)
    }
}

// MARK: - End-Drop Sheet (Host beendet seinen eigenen Drop)
//
// Gleiches Design-Pattern wie LeaveDropSheet, aber Host-Perspektive:
// klare Konsequenzen + primärer Weiter-Button damit der Host nicht aus
// Versehen einen laufenden Drop killt während Joiner unterwegs sind.
struct EndDropSheet: View {
    let activityEmoji: String
    let activityName: String
    let participantCount: Int
    /// Sekunden seit Drop-Erstellung — ≥ 15 min = Punkte werden vergeben.
    let elapsedSeconds: TimeInterval
    let onEnd: () -> Void
    let onCancel: () -> Void

    /// Subtle Icon-Beat auf der Lavendel-Scheibe.
    @State private var iconBeat = false

    private var qualifiesForPoints: Bool { elapsedSeconds >= 15 * 60 }
    private var hasOthers: Bool { participantCount >= 2 }

    var body: some View {
        ZStack {
            Color.brandCream.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color.brandLavender.opacity(0.9))
                                .frame(width: 92, height: 92)
                                .scaleEffect(iconBeat ? 1.04 : 0.98)
                            Image(systemName: "flag.checkered")
                                .font(.system(size: 38, weight: .heavy))
                                .foregroundColor(.brandOrange)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)

                        VStack(alignment: .leading, spacing: -2) {
                            Text("Runde")
                                .foregroundColor(.brandNight)
                            Text("beenden?")
                                .foregroundColor(.brandViolet)
                        }
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 24)

                        Text("\(activityEmoji) \(activityName)")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.65))
                            .padding(.horizontal, 24)

                        VStack(spacing: 10) {
                            if hasOthers {
                                infoRow(icon: "person.2.fill",
                                        text: (participantCount - 1 == 1
                                               ? tr("shared.participants_notified_singular")
                                               : tr("shared.participants_notified_plural"))
                                            .replacingOccurrences(of: "{count}", with: "\(participantCount - 1)"))
                            } else {
                                infoRow(icon: "person.crop.circle.badge.xmark",
                                        text: tr("shared.no_participants_yet"))
                            }
                            if qualifiesForPoints && hasOthers {
                                infoRow(icon: "sparkles", text: tr("shared.host_points_awarded"))
                            } else if !qualifiesForPoints && hasOthers {
                                infoRow(icon: "hourglass",
                                        text: tr("shared.only_x_min_no_points")
                                            .replacingOccurrences(of: "{mins}", with: "\(Int(elapsedSeconds / 60))"))
                            }
                            infoRow(icon: "map", text: tr("shared.drop_disappears"))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity)
                }

                VStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text(tr("shared.keep_running"))
                            .dropsPrimaryButton()
                    }
                    .dropsPressable()

                    Button(action: onEnd) {
                        Text(tr("shared.end_drop"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .dropsPressable()
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 22)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                iconBeat = true
            }
        }
    }

    @ViewBuilder
    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.brandViolet)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.brandLavender))
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.brandNight.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .liquidGlass(cornerRadius: 18)
    }
}

// MARK: - Drop-Feedback Sheet
//
// Erscheint nach Drop-Ende (für Host nach `cancelDrop`, für Joiner nach
// `leaveActiveJoin` mit Session ≥ 5 min). Zeigt pro Mit-Teilnehmer eine
// Zeile mit 👍/👎. User kann pro Person voten oder einfach "Überspringen"
// drücken — Datenschutz: nichts ist Pflicht.
struct DropFeedbackSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let prompt: AppStore.DropFeedbackPrompt

    /// votes[targetUID] = "up" | "down" | nil (= unentschieden / skip)
    @State private var votes: [String: String] = [:]
    @State private var submitted: Bool = false

    private var headline: String {
        prompt.wasHostMyself ? tr("shared.how_were_guests") : tr("shared.how_was_host")
    }

    private var subline: String {
        "\(prompt.dropEmoji) \(prompt.dropActivity)"
    }

    var body: some View {
        ZStack {
            Color.brandCream.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: -2) {
                    Text(headline)
                        .foregroundColor(.brandNight)
                }
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Text(subline)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 18)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(prompt.targets) { target in
                            feedbackRow(for: target)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(maxHeight: 340)

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    Button { dismiss() } label: {
                        Text(tr("shared.skip"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color.brandLavender.opacity(0.6)))
                    }
                    .dropsPressable()

                    Button { submitAll() } label: {
                        HStack(spacing: 6) {
                            if submitted {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            Text(submitted ? "Danke!" : "Senden")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().fill(votes.isEmpty
                                           ? Color.brandViolet.opacity(0.4)
                                           : Color.brandViolet)
                        )
                    }
                    .dropsPressable()
                    .disabled(votes.isEmpty || submitted)
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private func feedbackRow(for target: AppStore.FeedbackTarget) -> some View {
        let currentVote = votes[target.id]
        HStack(spacing: 14) {
            if let url = target.profileImageURL, !url.isEmpty {
                RemoteProfileImage(url: url, fallbackEmoji: target.emoji,
                                   size: 44, strokeColor: .clear)
            } else {
                Circle()
                    .fill(Color.brandLavender)
                    .frame(width: 44, height: 44)
                    .overlay(Text(target.emoji).font(.system(size: 22)))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(target.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.brandNight)
                    if target.wasHost {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.brandOrange)
                    }
                }
                Text(target.wasHost ? "Host" : "Teilnehmer")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.55))
            }

            Spacer()

            HStack(spacing: 8) {
                voteButton(systemImage: "hand.thumbsdown.fill",
                           selected: currentVote == "down",
                           tint: .brandOrange) {
                    votes[target.id] = currentVote == "down" ? nil : "down"
                }
                voteButton(systemImage: "hand.thumbsup.fill",
                           selected: currentVote == "up",
                           tint: .brandViolet) {
                    votes[target.id] = currentVote == "up" ? nil : "up"
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .liquidGlass(cornerRadius: 18)
    }

    @ViewBuilder
    private func voteButton(systemImage: String, selected: Bool,
                            tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(selected ? .white : tint.opacity(0.8))
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(selected ? tint : Color.brandLavender)
                )
        }
        .dropsPressable()
        .scaleEffect(selected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
    }

    private func submitAll() {
        guard !submitted else { return }
        for (uid, vote) in votes {
            store.submitFeedbackVote(ratedUID: uid, dropID: prompt.dropID, vote: vote)
        }
        withAnimation(.spring(response: 0.3)) { submitted = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { dismiss() }
    }
}

// MARK: - Drop Success Share Sheet

struct DropSuccessShareSheet: View {
    let data: AppStore.DropSuccessShareData
    @Environment(\.dismiss) private var dismiss
    @State private var shareImage: UIImage? = nil
    @State private var showShareSheet = false
    @State private var rendered = false

    var body: some View {
        VStack(spacing: 0) {
            // Drag Handle
            Capsule()
                .fill(Color(UIColor.tertiaryLabel))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // Vorschau der Share-Card
            DropShareCardView(data: data)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
                .padding(.horizontal, 32)
                .scaleEffect(rendered ? 1 : 0.92)
                .opacity(rendered ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: rendered)

            Spacer(minLength: 24)

            // Buttons
            VStack(spacing: 12) {
                Button {
                    renderAndShare()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                        Text(tr("shared.share_story"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(colors: [.auroraOrange, .auroraGreen],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }

                Button(tr("shared.skip")) { dismiss() }
                    .font(.system(size: 15))
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color.bgGrouped)
        .onAppear {
            withAnimation { rendered = true }
            // Image vorab rendern
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                shareImage = renderCard()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = shareImage {
                ShareSheet(items: [img])
            }
        }
    }

    private func renderAndShare() {
        if let img = shareImage {
            presentShareSheet(img)
        } else if let img = renderCard() {
            presentShareSheet(img)
        }
    }

    @MainActor
    private func renderCard() -> UIImage? {
        let card = DropShareCardView(data: data).frame(width: 390, height: 390)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }

    private func presentShareSheet(_ image: UIImage) {
        let av = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            var top = root
            while let presented = top.presentedViewController { top = presented }
            top.present(av, animated: true)
        }
    }
}

// MARK: - Drop Share Card View (wird via ImageRenderer als Bild gerendert)

struct DropShareCardView: View {
    let data: AppStore.DropSuccessShareData

    private var headline: String {
        data.wasHost ? "Ich hab's gedropt! 🎉" : "Ich war dabei! 🎉"
    }
    private var sub: String {
        data.wasHost ? "Heute spontan jemanden getroffen" : "Spontan zugesagt — und hingegangen"
    }

    var body: some View {
        ZStack {
            // Hintergrund-Gradient
            LinearGradient(
                colors: [Color(hex: "0D0D0D"), Color(hex: "1A1A1A")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // Aurora-Glow
            Circle()
                .fill(Color.auroraOrange.opacity(0.35))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: -60, y: -60)
            Circle()
                .fill(Color.auroraGreen.opacity(0.25))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 80, y: 80)

            VStack(spacing: 0) {
                Spacer()

                // Emoji
                Text(data.activityEmoji)
                    .font(.system(size: 80))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                Spacer().frame(height: 16)

                // Aktivität
                Text(data.activityName)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Spacer().frame(height: 8)

                // Headline
                Text(headline)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))

                Spacer().frame(height: 6)

                Text(sub)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))

                Spacer()

                // Branding
                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            LinearGradient(colors: [.auroraOrange, .auroraGreen],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 20, height: 20)
                    Text("Dazu · drops-app.de")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// ShareSheet ist in LiveMapView.swift definiert (projektweite Nutzung)

// MARK: - Activity Category (shared: Map + Feed + CreateDrop)

struct ActivityCategory {
    let key: String
    let icon: String          // SF Symbol
    let emoji: String         // Repräsentatives Emoji für CreateDrop-Chips
    let dropEmojis: [String]  // Alle Emojis die zu dieser Kategorie matchen
    let keywords: [String]    // Keywords die gegen activityName matchen

    /// Lokalisierter Display-Name für die UI. `key` bleibt deutsch als
    /// stabile interne ID (in UserDefaults persistiert, in Filter-State
    /// referenziert) — wir mappen nur fürs Rendering.
    var displayName: String {
        switch key {
        case "Kaffee": return tr("activity.coffee")
        case "Drink":  return tr("activity.drink")
        case "Sport":  return tr("activity.sport")
        case "Essen":  return tr("activity.food")
        case "Zocken": return tr("activity.gaming")
        default:       return key
        }
    }

    static let all: [ActivityCategory] = [
        ActivityCategory(
            key: "Kaffee", icon: "cup.and.saucer.fill", emoji: "☕️",
            dropEmojis: ["☕️", "☕", "🧋", "🍵", "🥐"],
            keywords: ["kaffee", "coffee", "café", "cafe", "espresso", "latte"]
        ),
        ActivityCategory(
            key: "Drink", icon: "wineglass", emoji: "🍺",
            dropEmojis: ["🍺", "🍻", "🍷", "🥂", "🍹", "🍸"],
            keywords: ["drink", "drinks", "bier", "beer", "wein", "wine",
                       "cocktail", "bar", "feierabend", "club", "party", "ausgehen"]
        ),
        ActivityCategory(
            key: "Sport", icon: "figure.run", emoji: "🏃",
            dropEmojis: ["🏃", "🏃‍♂️", "🏃‍♀️", "🏋️", "🧘", "⚽️", "🎾", "🏀", "🚴"],
            keywords: ["sport", "fitness", "gym", "laufen", "run", "joggen",
                       "jog", "fußball", "tennis", "basketball", "yoga", "fahrrad", "bike"]
        ),
        ActivityCategory(
            key: "Essen", icon: "fork.knife", emoji: "🍕",
            dropEmojis: ["🍕", "🍔", "🍣", "🍱", "🍜", "🌮", "🥗"],
            keywords: ["essen", "food", "lunch", "dinner", "pizza", "burger",
                       "restaurant", "brunch", "sushi", "dönner"]
        ),
        ActivityCategory(
            key: "Zocken", icon: "gamecontroller.fill", emoji: "🎮",
            dropEmojis: ["🎮", "🕹️"],
            keywords: ["zocken", "zock", "gaming", "game", "games", "spielen",
                       "xbox", "playstation"]
        )
    ]

    func matches(emoji dropEmoji: String, activity: String) -> Bool {
        if dropEmojis.contains(dropEmoji) { return true }
        let lower = activity.lowercased()
        return keywords.contains(where: { lower.contains($0) })
    }

    /// Prüft ob ein Drop zum aktiven Filter passt. Leerer Filter = alles sichtbar.
    static func matches(filter: String, emoji: String, activity: String) -> Bool {
        guard !filter.isEmpty else { return true }
        guard let cat = all.first(where: { $0.key == filter }) else { return true }
        return cat.matches(emoji: emoji, activity: activity)
    }
}

// MARK: - Shared Activity Filter Chips (Map + Feed)

struct ActivityFilterChipsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: tr("feed.filter_all"), icon: "square.grid.2x2.fill",
                     selected: store.activityCategoryFilter.isEmpty) {
                    store.activityCategoryFilter = ""
                    store.saveAll()
                }
                ForEach(ActivityCategory.all, id: \.key) { cat in
                    chip(title: cat.displayName, icon: cat.icon,
                         selected: store.activityCategoryFilter == cat.key) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            store.activityCategoryFilter =
                                (store.activityCategoryFilter == cat.key) ? "" : cat.key
                        }
                        store.saveAll()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func chip(title: String, icon: String, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(selected ? .white : .brand)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(selected ? .white : .textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    selected
                        ? Color.brand
                        : Color.bgCard
                )
            )
            .shadow(color: selected ? Color.brand.opacity(0.28) : .clear, radius: 8, y: 3)
        }
        .dropsPressable()
    }
}
