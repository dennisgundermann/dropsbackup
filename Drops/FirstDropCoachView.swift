import SwiftUI

// ── First-Drop Coach-Mark System ─────────────────────────────────────────────
// Schrittweise Einführung für Erstnutzer direkt in CreateDropView.
// Wird nur angezeigt wenn isWalkthrough=true (kommt vom WelcomeSheet-CTA).
// Drei Schritte: Aktivität → Ort → Drop starten.

enum CoachStep: Int, CaseIterable {
    case activity = 0
    case location = 1
    case start    = 2

    /// Scroll-Anker-ID in der CreateDropView ScrollView
    var scrollID: String {
        switch self {
        case .activity: return "coach_anchor_activity"
        case .location: return "coach_anchor_location"
        case .start:    return "coach_anchor_cta"
        }
    }

    var next: CoachStep? { CoachStep(rawValue: rawValue + 1) }
    var isLast: Bool { next == nil }
}

// MARK: - Overlay View

struct FirstDropCoachOverlay: View {
    @Binding var step: CoachStep?
    /// Frame der aktuell hervorgehobenen Section (global coordinates).
    /// Wird per CoachSpotlightFrameKey-Preference von CreateDropView geliefert.
    var highlightFrame: CGRect = .zero
    /// Wird beim Step-Advance mit der nächsten scrollID aufgerufen
    let scrollTo: (String) -> Void
    let onDone: () -> Void
    let onSkip: () -> Void

    @State private var cardY: CGFloat = 500
    @State private var cardOpacity: Double = 0
    @State private var isAnimating = false
    @State private var glowPulse = false

    /// Karte oben wenn das Spotlight im unteren Bildschirmbereich liegt —
    /// so überlappt sie die hervorgehobene Section nie.
    private var cardAtTop: Bool {
        guard highlightFrame != .zero else { return false }
        return highlightFrame.midY > UIScreen.main.bounds.height * 0.50
    }
    private var offscreenY: CGFloat { cardAtTop ? -600 : 600 }

    var body: some View {
        ZStack(alignment: cardAtTop ? .top : .bottom) {
            // ── Spotlight-Scrim ───────────────────────────────────────────
            // Dunkler Scrim mit Cutout über der aktiven Section.
            // blendMode(.destinationOut) in einem compositingGroup() stanzt
            // ein Loch in die schwarze Fläche — die Section leuchtet dadurch
            // natürlich hervor ohne z-Index-Klimmzüge.
            Color.black.opacity(0.55)
                .mask(
                    ZStack {
                        Rectangle() // volle Fläche sichtbar…
                        if highlightFrame != .zero {
                            // …minus Spotlight-Ausschnitt
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .frame(
                                    width:  highlightFrame.width  + 20,
                                    height: highlightFrame.height + 20
                                )
                                .position(x: highlightFrame.midX,
                                          y: highlightFrame.midY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.35), value: highlightFrame)

            // ── Pulsender Spotlight-Rahmen ────────────────────────────────
            if highlightFrame != .zero {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.brand.opacity(glowPulse ? 1.0 : 0.35), lineWidth: 3)
                    .shadow(color: Color.brand.opacity(glowPulse ? 0.6 : 0.2), radius: 10)
                    .frame(
                        width:  highlightFrame.width  + 20,
                        height: highlightFrame.height + 20
                    )
                    .position(x: highlightFrame.midX, y: highlightFrame.midY)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                               value: glowPulse)
                    .animation(.easeInOut(duration: 0.35), value: highlightFrame)
                    .onAppear { glowPulse = true }
            }

            // ── Coach-Karte ───────────────────────────────────────────────
            // Immer als dieselbe View-Identität im ZStack (kein AnyView),
            // damit @State über Step-Wechsel erhalten bleibt.
            if let current = step {
                coachCard(current)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .offset(y: cardY)
                    .opacity(cardOpacity)
            }
        }
        .ignoresSafeArea()
        .onAppear { if step != nil { slideIn() } }
        .onChange(of: cardAtTop) { _, _ in
            // Wenn sich die Karten-Position ändert (Step-Wechsel),
            // cardY auf den neuen Ausgangspunkt setzen damit die
            // nächste slideIn()-Animation aus der richtigen Richtung kommt.
            if cardOpacity == 0 { cardY = offscreenY }
        }
    }

    // MARK: Card

    @ViewBuilder
    private func coachCard(_ step: CoachStep) -> some View {
        VStack(alignment: .leading, spacing: 0) {

            // Progress-Kapseln + Skip
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    ForEach(0..<CoachStep.allCases.count, id: \.self) { i in
                        Capsule()
                            .fill(i <= step.rawValue
                                  ? Color.brand
                                  : Color.primary.opacity(0.12))
                            .frame(width: i == step.rawValue ? 22 : 8, height: 6)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8),
                                       value: step.rawValue)
                    }
                }
                Spacer()
                Button { skipWithAnimation() } label: {
                    Text(tr("coach.skip"))
                        .font(.system(size: 13))
                        .foregroundColor(.textTertiary)
                }
            }
            .padding(.bottom, 18)

            // Icon + Text
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.brand.opacity(0.12))
                        .frame(width: 48, height: 48)
                    DazuIcon(stepIcon(step))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.brand)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(stepTitle(step))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(stepBody(step))
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 22)

            // CTA
            Button { advanceStep(step) } label: {
                HStack(spacing: 8) {
                    Spacer()
                    Text(step.isLast ? tr("coach.start_drop") : tr("coach.next"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    DazuIcon(step.isLast ? "bolt.fill" : "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 15)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color.auroraOrange, Color.brand],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                )
                .shadow(color: Color.brand.opacity(0.25), radius: 8, y: 3)
            }
            .dropsPressable()
            .disabled(isAnimating)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.bgPrimary)
                .shadow(color: .black.opacity(0.15), radius: 28, x: 0, y: -6)
        )
    }

    // MARK: Step Content

    private func stepIcon(_ step: CoachStep) -> String {
        switch step {
        case .activity: return "sparkles"
        case .location: return "mappin.circle.fill"
        case .start:    return "bolt.fill"
        }
    }

    private func stepTitle(_ step: CoachStep) -> String {
        switch step {
        case .activity: return tr("coach.activity_title")
        case .location: return tr("coach.location_title")
        case .start:    return tr("coach.start_title")
        }
    }

    private func stepBody(_ step: CoachStep) -> String {
        switch step {
        case .activity: return tr("coach.activity_body")
        case .location: return tr("coach.location_body")
        case .start:    return tr("coach.start_body")
        }
    }

    // MARK: Animation

    private func slideIn() {
        cardY = offscreenY   // Startpunkt: oben oder unten je nach Position
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            cardY = 0
            cardOpacity = 1
        }
    }

    private func advanceStep(_ current: CoachStep) {
        guard !isAnimating else { return }
        isAnimating = true

        if current.isLast {
            // Letzter Schritt: rausfahren und onDone aufrufen
            slideOut {
                step = nil
                onDone()
            }
        } else {
            // Zwischenschritt: raus → nächsten Step setzen → rein
            slideOut {
                if let next = current.next {
                    step = next
                    scrollTo(next.scrollID)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        slideIn()
                        isAnimating = false
                    }
                }
            }
        }
    }

    private func skipWithAnimation() {
        slideOut {
            step = nil
            onSkip()
        }
    }

    private func slideOut(_ completion: @escaping () -> Void) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            cardY = offscreenY   // raus in dieselbe Richtung wie rein
            cardOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            completion()
        }
    }
}

// MARK: - Spotlight Frame PreferenceKey

/// Propagiert den globalen Frame der aktuell hervorgehobenen Section
/// von CreateDropView nach oben zu FirstDropCoachOverlay.
struct CoachSpotlightFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let n = nextValue()
        if n != .zero { value = n }
    }
}

// MARK: - Highlight Modifier

/// Meldet den globalen Frame der Section per Preference nach oben UND
/// zeichnet einen leichten Akzent-Border als sekundären visuellen Hinweis.
/// Das eigentliche Spotlight (Scrim-Cutout + Glow) läuft in FirstDropCoachOverlay.
struct CoachHighlightModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: CoachSpotlightFrameKey.self,
                        value: active ? geo.frame(in: .global) : .zero
                    )
                }
            )
    }
}

extension View {
    func coachHighlight(active: Bool) -> some View {
        modifier(CoachHighlightModifier(active: active))
    }
}
