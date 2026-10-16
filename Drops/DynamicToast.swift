import SwiftUI

// MARK: - DynamicToast — Pill-Overlay oben am Screen
//
// In-App-Benachrichtigungen im Dynamic-Island-Stil: schmale Pill, die von
// oben einspringt (Spring), 3s steht, dann automatisch verschwindet. Swipe
// nach oben oder Tap dismisst manuell. Queue-fähig — mehrere Trigger
// hintereinander laufen durch.
//
// Nutzung:
//   ToastCenter.shared.show(.init(title: "Neu", message: "…", symbol: "bell"))
// Wo immer sinnvoll — iOS zeigt System-Push im Foreground meist nicht,
// deshalb forwarden wir dort auf diese UI. System-Push bleibt für Background.

/// Welcher Tab geöffnet werden soll wenn der User auf den Toast tippt.
/// Routing erfolgt in `DynamicToastOverlay` über den injected `AppStore`.
enum ToastRoute: Equatable {
    case friends    // Freund-Request / Freund-Added → Freunde-Tab
    case live       // Drop-Events → Live/Map-Tab
    case map        // Allgemein Karte
    case nearby     // Nahe-Drops → Umgebungs-Tab
    case profile    // Profil
    case none
}

struct ToastItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    var message: String? = nil
    /// SF-Symbol-Name (z.B. "person.fill.badge.plus").
    var symbol: String? = nil
    /// Remote-Avatar-URL — vor dem Symbol priorisiert.
    var avatarURL: String? = nil
    /// Akzentfarbe für Symbol/Avatar-Rahmen.
    var accent: Color = .brandViolet
    /// Auto-Dismiss nach x Sekunden. `nil` = bleibt bis manuell geschlossen.
    var duration: Double? = 6.0
    /// Welcher Tab beim Tap geöffnet werden soll.
    var route: ToastRoute = .none

    static func == (lhs: ToastItem, rhs: ToastItem) -> Bool { lhs.id == rhs.id }
}

@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    /// Aktuell sichtbarer Toast — nil wenn keiner.
    @Published private(set) var current: ToastItem? = nil

    private var queue: [ToastItem] = []
    private var dismissTask: Task<Void, Never>? = nil

    private init() {}

    /// Toast anzeigen. Wenn gerade einer sichtbar ist → in die Queue.
    func show(_ item: ToastItem) {
        if current == nil {
            present(item)
        } else {
            queue.append(item)
        }
    }

    /// Aktuellen Toast sofort schließen (Swipe/Tap/externes Dismiss).
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            current = nil
        }
        // Nach Animation nächsten aus Queue holen
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            await MainActor.run {
                guard let self else { return }
                if let next = self.queue.first {
                    self.queue.removeFirst()
                    self.present(next)
                }
            }
        }
    }

    private func present(_ item: ToastItem) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
            current = item
        }
        if let dur = item.duration {
            dismissTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(dur * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.dismiss() }
            }
        }
    }
}

// MARK: - View

struct DynamicToastOverlay: View {
    @StateObject private var center = ToastCenter.shared
    @EnvironmentObject var store: AppStore

    var body: some View {
        // Toast absolute positioniert — Pille startet an Island-Position,
        // wandert dann via Spring zur Card-Position unterhalb. Nutzt die
        // Original-Konstanten aus `constants/notification.consts.ts`.
        ZStack(alignment: .top) {
            Color.clear
            if let item = center.current {
                ToastPill(item: item, onTap: { handleTap(item) },
                          onDismiss: { center.dismiss() })
                    .id(item.id)
                    .transition(.identity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.15), value: center.current?.id)
    }

    /// Routet den Tap zur passenden App-Section.
    private func handleTap(_ item: ToastItem) {
        switch item.route {
        case .friends:  store.selectedTab = .alerts
        case .live:     store.selectedTab = .create
        case .map:      store.selectedTab = .map
        case .nearby:   store.selectedTab = .map       // Umgebung → Karte (ggf. anpassen)
        case .profile:  store.selectedTab = .profile
        case .none:     break
        }
        center.dismiss()
    }
}

/// Dynamic-Island-Replik: 3-Phasen-Animation wie im expo-dynamic-notifications-
/// Original. Phase 1 "Drop" (kleine Pille erscheint von oben, Island-Größe).
/// Phase 2 "Expand" (zur vollen Card-Breite + Höhe, Overshoot-Spring).
/// Phase 3 "Reveal" (Content fade-in). Beim Dismiss reverse: Content fade-out,
/// Collapse zurück zur Island-Pille, Retract nach oben.
private struct ToastPill: View {
    let item: ToastItem
    let onTap: () -> Void
    let onDismiss: () -> Void

    // Timeline-Phasen (0 → 1)
    @State private var drop: CGFloat = 0        // Island erscheint (y + opacity)
    @State private var expand: CGFloat = 0      // Pille → Card (width/height)
    @State private var reveal: CGFloat = 0      // Content fade-in
    @State private var dragOffset: CGFloat = 0
    @State private var dismissed = false

    // Original-Werte 1:1 aus `src/constants/notification.consts.ts`.
    private let islandWidth: CGFloat  = 126
    private let islandHeight: CGFloat = 37.33
    private let islandTop: CGFloat    = 11      // Y vom Screen-Top
    private let cardMaxWidth: CGFloat = 360     // ≤ screen - 2*CARD_MARGIN
    private let cardHeight: CGFloat   = 74
    private let cardGap: CGFloat      = 34      // Lücke zwischen Island und Card
    private var cardTop: CGFloat { islandTop + islandHeight + cardGap }

    // Interpolierte Werte für die Animation
    private var currentWidth: CGFloat {
        islandWidth + (cardMaxWidth - islandWidth) * expand
    }
    private var currentHeight: CGFloat {
        islandHeight + (cardHeight - islandHeight) * expand
    }
    private var currentRadius: CGFloat { currentHeight / 2 }
    /// Y-Position wandert von Island-Top zu Card-Top während Expand.
    private var currentTop: CGFloat {
        islandTop + (cardTop - islandTop) * expand
    }

    var body: some View {
        // Container nimmt die Card-Max-Breite + volle Höhe, Pill ist darin
        // zentriert und wächst symmetrisch (nicht nur nach rechts).
        ZStack {
            // Die Pill selbst
            RoundedRectangle(cornerRadius: currentRadius, style: .continuous)
                .fill(Color(white: 0.08))                       // sehr dunkel, wie Dynamic Island
                .overlay(
                    RoundedRectangle(cornerRadius: currentRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .frame(width: currentWidth, height: currentHeight)
                .shadow(color: .black.opacity(0.35 * drop), radius: 20, y: 10)
                .shadow(color: .black.opacity(0.15 * drop), radius: 4, y: 2)

            // Content separat überlagert, mittig in der Pill
            HStack(spacing: 11) {
                avatarOrSymbol
                    .scaleEffect(0.88 + 0.12 * reveal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let msg = item.message, !msg.isEmpty {
                        Text(msg)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.72))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: max(currentWidth - 4, 0), height: currentHeight, alignment: .leading)
            .opacity(reveal)                                   // Content erst in Phase 3
            .allowsHitTesting(false)
        }
        .frame(width: cardMaxWidth, height: max(cardHeight, islandHeight), alignment: .center)
        .position(x: UIScreen.main.bounds.width / 2,
                  y: currentTop + max(cardHeight, islandHeight) / 2 + min(dragOffset, 0))
        .opacity(Double(drop))
        .gesture(
            DragGesture()
                .onChanged { v in dragOffset = v.translation.height }
                .onEnded { v in
                    if v.translation.height < -30 { triggerDismiss() }
                    else { withAnimation(.spring(response: 0.3)) { dragOffset = 0 } }
                }
        )
        .onTapGesture {
            onTap()
        }
        .onAppear { animateIn() }
        .onChange(of: item.id) { _, _ in animateIn() }
    }

    @ViewBuilder private var avatarOrSymbol: some View {
        ZStack {
            // Violetter Chip auf cremefarbenem Pill — passt zur App-Palette.
            Circle().fill(Color.brandViolet)
                .frame(width: 38, height: 38)
            if let url = item.avatarURL, !url.isEmpty {
                RemoteProfileImage(url: url, fallbackEmoji: "",
                                   size: 34, strokeColor: Color.brandViolet)
            } else {
                Image(systemName: item.symbol ?? "bell.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    private func animateIn() {
        drop = 0; expand = 0; reveal = 0; dismissed = false
        // ─── 1:1 Timings aus `src/constants/notification.consts.ts` ──
        //   ENTER_EXPAND_DELAY = 340ms
        //   ENTER_REVEAL_DELAY = 560ms
        // Springs aus `src/conf/springs.ts`:
        //   DROP   duration 1150ms, dampingRatio 0.82
        //   EXPAND duration 1000ms, dampingRatio 0.80
        //   REVEAL duration  700ms, dampingRatio 1.00
        if #available(iOS 17.0, *) {
            withAnimation(.spring(duration: 1.15, bounce: 0.22)) {
                drop = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                withAnimation(.spring(duration: 1.0, bounce: 0.24)) {
                    expand = 1
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) {
                withAnimation(.spring(duration: 0.7, bounce: 0)) {
                    reveal = 1
                }
            }
        } else {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.82)) { drop = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                withAnimation(.spring(response: 0.65, dampingFraction: 0.78)) { expand = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) {
                withAnimation(.easeOut(duration: 0.4)) { reveal = 1 }
            }
        }
    }

    private func triggerDismiss() {
        guard !dismissed else { return }
        dismissed = true
        // Reverse: Content zuerst weg, dann Collapse, dann Drop nach oben.
        withAnimation(.easeIn(duration: 0.18)) { reveal = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                expand = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.easeIn(duration: 0.22)) {
                drop = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            onDismiss()
        }
    }
}
