import SwiftUI
import UIKit

/// Dazu Icon-Mark — stilisiertes „a" (offener Ring mit Stamm rechts) +
/// orangener „du"-Dot oben rechts. Dot floated subtil + pulsiert.
///
/// Konstruktion wie im Design-Board:
///   – Großer Open-Ring (3/4 Kreis, oben rechts offen)
///   – Vertikaler Stamm am rechten Rand des Rings
///   – Oranger Punkt (= „du") außerhalb oben rechts
struct DazuLogo: View {
    var size: CGFloat = 48
    var tint: Color = .brandCream
    var background: Color = .brandViolet
    var dotColor: Color = .brandOrange
    /// Mit Hintergrund-Kachel (wie App-Icon) oder nur Mark (für Headers).
    var showBackground: Bool = false
    /// Zeigt den "du"-Dot. False = nur das Ring-"a" (z.B. für Empty-States,
    /// wenn noch niemand "dazu" gekommen ist).
    var showDot: Bool = true
    /// Rotiert langsam (z.B. im Empty-State als "ich warte dass jemand kommt").
    var rotating: Bool = false
    /// Join-Progress 0...1 — animiert den „du"-Dot zum offenen Ring hinein.
    /// 0 = Dot außen (jemand kommt dazu), 1 = Dot ist IM Ring (geschlossen).
    /// Toggle 0↔1 mit Animation für die „kommt dazu" / „geht raus" Animation.
    var joinProgress: Double = 0

    @State private var dotFloat: CGFloat = 0
    @State private var dotScale: CGFloat = 1.0
    @State private var rotation: Double = 0

    private var dotDiameter: CGFloat { size * 0.19 }
    private var strokeWidth: CGFloat { size * 0.16 }

    var body: some View {
        ZStack {
            if showBackground {
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(background)
                    .frame(width: size * 1.3, height: size * 1.3)
            }

            // Offener Ring + Stamm = „a"-Mark
            DazuAShape()
                .stroke(tint,
                        style: StrokeStyle(lineWidth: strokeWidth,
                                           lineCap: .round,
                                           lineJoin: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(rotation))

            // „du"-Dot — wandert bei joinProgress von außen in den Ring
            // (gefüllter Kreis löst sich auf, Ring schließt sich).
            if showDot {
                // Position interpoliert zwischen Außen und Center
                let outerX = size * 0.42
                let outerY = -size * 0.38
                let x = outerX * (1 - joinProgress)
                let y = outerY * (1 - joinProgress) + dotFloat * (1 - joinProgress)
                // Opacity sinkt wenn Dot „aufgenommen" wird
                let dotOpacity = 1.0 - joinProgress * 0.9
                Circle()
                    .fill(dotColor)
                    .frame(width: dotDiameter, height: dotDiameter)
                    .shadow(color: dotColor.opacity(0.5 * dotOpacity), radius: 3, y: 1)
                    .scaleEffect(dotScale * (1 - joinProgress * 0.5))
                    .opacity(dotOpacity)
                    .offset(x: x, y: y)
                    // Explizit auf joinProgress animieren — ohne diesen
                    // Modifier interpoliert SwiftUI die berechneten
                    // offset/opacity-Werte nicht und der Dot snappt.
                    .animation(.spring(response: 0.55, dampingFraction: 0.72),
                               value: joinProgress)
            }

            // Beim „Komm dazu"-Progress erscheint am Ring eine kleine
            // Lücken-Füllung (der Dot wird „aufgenommen").
            if showDot && joinProgress > 0.1 {
                Circle()
                    .fill(dotColor)
                    .frame(width: strokeWidth, height: strokeWidth)
                    .opacity(joinProgress)
                    .offset(x: size * 0.30 * CGFloat(cos(-30 * Double.pi / 180)),
                            y: size * 0.30 * CGFloat(sin(-30 * Double.pi / 180)))
                    .animation(.spring(response: 0.55, dampingFraction: 0.72),
                               value: joinProgress)
            }
        }
        .onAppear {
            if showDot {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    dotFloat = -size * 0.06
                }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    dotScale = 1.14
                }
            }
            if rotating {
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
    }
}

/// Shape des stilisierten „a" — offener Ring + rechter Stamm.
/// Der Ring ist oben rechts offen (bei ~355° bis ~45°), Stamm sitzt
/// am rechten Rand des Rings und zieht leicht nach unten raus.
private struct DazuAShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.42

        // Open ring: beginnt oben rechts (bei etwa -30°), geht counter-clockwise
        // einmal rum und endet bei etwa 20° (oben, leicht rechts).
        // In SwiftUI: 0° = rechts; .degrees(-30) = oben rechts.
        p.addArc(center: center,
                 radius: radius,
                 startAngle: .degrees(-30),
                 endAngle: .degrees(-360 + 20),
                 clockwise: true)

        // Stamm: senkrechte Linie rechts, vom Ring nach unten
        let stemX = center.x + radius * 0.95
        let stemTopY = center.y - radius * 0.5
        let stemBotY = center.y + radius * 0.95
        p.move(to: CGPoint(x: stemX, y: stemTopY))
        p.addLine(to: CGPoint(x: stemX, y: stemBotY))

        return p
    }
}

// MARK: - Join Morph Mark
//
// Submit-Animation für den „Komm dazu"-Button: ein halb offener Ring
// (Lücke oben rechts, wie das AppIcon) schließt sich zu einem vollen
// Ring. Gleichzeitig swipet der Dot von außen rechts in die Lücke und
// löst sich auf — die Metapher: der Neuzugang schließt die Runde.
//
// progress 0 = offen + Dot außen; progress 1 = geschlossener Ring, Dot weg.
struct JoinMorphMark: View {
    var progress: Double = 0
    var size: CGFloat = 28
    var color: Color = .white

    private var ringEnd: Double {
        // Lücken-Ende wandert von 265° (offen) auf ~355° (fast zu).
        265.16 + (355.0 - 265.16) * progress
    }
    private var dotOffsetX: CGFloat {
        // Dot startet außen rechts (ca. 0.6*size vom Zentrum), wandert
        // in die Lücke bei Winkel -48° / Radius 0.33*size (auf der
        // Ringlinie, Lücken-Mitte des halb offenen Rings).
        let a = -48.0 * Double.pi / 180.0
        let startX = size * 0.65
        let endX = CGFloat(cos(a)) * size * 0.33
        return startX + (endX - startX) * CGFloat(progress)
    }
    private var dotOffsetY: CGFloat {
        let a = -48.0 * Double.pi / 180.0
        let startY = -size * 0.30
        let endY = CGFloat(sin(a)) * size * 0.33
        return startY + (endY - startY) * CGFloat(progress)
    }
    private var dotOpacity: Double { 1.0 - progress * 0.95 }
    private var dotScale: CGFloat { 1.0 - 0.5 * CGFloat(progress) }

    var body: some View {
        ZStack {
            MorphRingShape(startAngleDeg: -1.16, endAngleDeg: ringEnd)
                .stroke(color,
                        style: StrokeStyle(lineWidth: size * 0.17, lineCap: .round))
                .frame(width: size, height: size)

            Circle()
                .fill(color)
                .frame(width: size * 0.28, height: size * 0.28)
                .scaleEffect(dotScale)
                .opacity(dotOpacity)
                .offset(x: dotOffsetX, y: dotOffsetY)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: progress)
    }
}

/// Ring mit frei einstellbarem Lücken-Winkel (für die Join-Morph-Animation).
private struct MorphRingShape: Shape {
    var startAngleDeg: Double
    var endAngleDeg: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { .init(startAngleDeg, endAngleDeg) }
        set { startAngleDeg = newValue.first; endAngleDeg = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width, rect.height) * 0.42
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                 radius: r,
                 startAngle: .degrees(startAngleDeg),
                 endAngle: .degrees(endAngleDeg),
                 clockwise: false)
        return p
    }
}

// DazuWordmark (die komplette „dazu" SVG-Wortmarke) ist in OnboardingView.swift
// definiert und wird hier wiederverwendet. API: DazuWordmark(color:, dotColor:)
// und per `.aspectRatio` responsive — Höhe über .frame(height:) setzen.

/// Standard-Tab-Header. Dazu-Logo links, optionaler Title / Trailing-Button.
/// Nutze diese Component oben in jedem Haupt-Tab für Konsistenz.
///
/// 🥚 Easter Egg: 7× schnell aufs Logo tappen → Emoji-Konfetti.
struct DazuTabHeader<Trailing: View>: View {
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    init(subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                DazuWordmark(color: .brandNight, dotColor: .brandOrange)
                    .frame(height: 32)
                    .modifier(DazuEasterEggModifier())
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.brandViolet.opacity(0.65))
                        .tracking(1.2)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }
}

/// Easter-Egg Modifier — 7 schnelle Taps aufs Logo = Emoji-Konfetti-Burst.
struct DazuEasterEggModifier: ViewModifier {
    @State private var tapCount: Int = 0
    @State private var lastTap: Date = .distantPast
    @State private var confetti: [ConfettiEmoji] = []

    private let emojis = ["sparkles", "star.fill", "crown.fill", "flame.fill", "bolt.fill", "sparkle", "leaf.fill", "flag.checkered"]

    func body(content: Content) -> some View {
        // Button-wrapped mit expliziter contentShape — in ScrollViews
        // greift .onTapGesture oft nicht; Button fängt den tap sauber ab.
        Button {
            let now = Date()
            if now.timeIntervalSince(lastTap) < 0.6 {
                tapCount += 1
            } else {
                tapCount = 1
            }
            lastTap = now
            if tapCount >= 7 {
                tapCount = 0
                burstConfetti()
            }
        } label: {
            content
                .contentShape(Rectangle())
                .overlay(alignment: .center) {
                    ZStack {
                        ForEach(confetti) { c in
                            DazuIcon(c.emoji)
                                .font(.system(size: 32))
                                .foregroundColor(.brandViolet)
                                .offset(x: c.x, y: c.y)
                                .opacity(c.opacity)
                                .rotationEffect(.degrees(c.rotation))
                        }
                    }
                    .allowsHitTesting(false)
                }
        }
        .buttonStyle(.plain)
    }

    private func burstConfetti() {
        Haptic.selection()
        for i in 0..<16 {
            let angle = Double.random(in: 0...(2 * Double.pi))
            let dist  = CGFloat.random(in: 80...220)
            let start = ConfettiEmoji(
                id: UUID(),
                emoji: emojis.randomElement() ?? "sparkles",
                x: 0, y: 0,
                opacity: 1.0,
                rotation: 0
            )
            confetti.append(start)
            // Animate out
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.015) {
                if let idx = confetti.firstIndex(where: { $0.id == start.id }) {
                    withAnimation(.easeOut(duration: 1.2)) {
                        confetti[idx].x = cos(angle) * dist
                        confetti[idx].y = sin(angle) * dist - 60
                        confetti[idx].rotation = Double.random(in: -180...180)
                        confetti[idx].opacity = 0
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                confetti.removeAll { $0.id == start.id }
            }
        }
    }
}

struct ConfettiEmoji: Identifiable {
    let id: UUID
    let emoji: String
    var x: CGFloat
    var y: CGFloat
    var opacity: Double
    var rotation: Double
}

/// Live-Indicator — kleine Mint/Orange Pulsing Dot für Live-States
/// (z.B. „Live" neben Section-Titles).
struct DazuLivePulse: View {
    var color: Color = .brandOrange
    var size: CGFloat = 8

    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: size * 2.2, height: size * 2.2)
                .scaleEffect(pulse ? 1.4 : 0.8)
                .opacity(pulse ? 0.0 : 0.6)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.6), radius: 3)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

/// Section-Header im Dazu-Stil — fette rounded caps + optionaler Live-Dot.
struct DazuSectionHeader: View {
    let title: String
    var isLive: Bool = false
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.brandViolet.opacity(0.75))
            if isLive {
                DazuLivePulse(color: .brandOrange, size: 7)
            }
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 20)
    }
}

/// Animiertes Icon für Settings-Section-Headers.
/// On-Tap: Spring-Pop + leichter Haptic.
struct SettingsHeaderIcon: View {
    let icon: String
    /// Legacy-Parameter — die Icon-Farbe ist jetzt immer Violett auf
    /// Lavendel-Background für Konsistenz mit dem dazu-Design.
    var color: Color = .brandViolet
    /// Wenn gesetzt, wird das custom dazu-Set-Icon aus Assets statt des
    /// SF-Symbols gerendert.
    var assetName: String? = nil
    @State private var pop = false

    var body: some View {
        Button {
            Haptic.selection()
            pop = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { pop = false }
        } label: {
            Group {
                if let asset = assetName {
                    DazuAssetIcon(asset: asset)
                        .foregroundColor(.brandViolet)
                        .frame(width: 15, height: 15)
                } else {
                    DazuIcon(icon)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(.brandViolet)
                }
            }
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.brandLavender))
            .scaleEffect(pop ? 1.5 : 1.0)
            .rotationEffect(.degrees(pop ? 15 : 0))
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: pop)
        }
        .buttonStyle(.plain)
    }
}

/// Dazu-Card-Style: Lavendel-Tint statt weiß, dezente Shadow + Border.
/// Adaptive für Dark Mode. Nutze als `.modifier(DazuStatCardStyle())`.
struct DazuStatCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(scheme == .dark
                          ? Color.brandViolet.opacity(0.15)
                          : Color.brandLavender.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.brandViolet.opacity(scheme == .dark ? 0.25 : 0.10),
                            lineWidth: 0.5)
            )
            .shadow(color: Color.brandViolet.opacity(scheme == .dark ? 0.12 : 0.05),
                    radius: 6, y: 2)
    }
}

// MARK: - DazuIcon
//
// Eigene dazu-Icons an Stelle der SF Symbols. Die Imagesets liegen in
// Assets.xcassets/DazuIcons und heißen wie das SF Symbol mit „dazu." davor
// (star.fill → dazu.star.fill).
//
// DazuIcon verhält sich wie Image(systemName:): Größe über .font(...),
// Farbe über .foregroundColor(...). Ein unsichtbares SF Symbol gibt die
// Größe vor, das eigene Icon liegt darüber. Gibt es zu einem Namen kein
// eigenes Icon, erscheint das SF Symbol wie bisher.
struct DazuIcon: View {
    private let name: String
    private let solid: Bool
    private let accent: Bool

    /// - Parameters:
    ///   - name: Name des SF Symbols, z. B. "star.fill".
    ///   - solid: Gefüllte Fassung für sehr kleine Abzeichen (9 pt), sofern
    ///     es zu diesem Symbol eine gibt.
    ///   - accent: Hat das Icon einen Punkt, wird er orange gezeichnet.
    ///     Auf false setzen, wo das Icon weiß, rot oder bewusst blass ist.
    init(_ name: String, solid: Bool = false, accent: Bool = true) {
        self.name = name
        self.solid = solid
        self.accent = accent
    }

    /// Auf false setzen, um überall wieder die SF Symbols zu zeigen.
    static let isEnabled = true

    /// Größe des eigenen Icons im Verhältnis zum Rahmen des SF Symbols.
    static let scale: CGFloat = 1.06

    var body: some View {
        if let asset = DazuIcon.assetName(for: name, solid: solid) {
            Image(systemName: "square")
                .hidden()
                .overlay(
                    GeometryReader { geo in
                        let side = min(geo.size.width, geo.size.height) * DazuIcon.scale
                        DazuAssetIcon(asset: asset, accent: accent && !solid)
                            .frame(width: side, height: side)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                )
                .accessibilityRepresentation {
                    Image(systemName: DazuIcon.symbolName(for: name))
                }
        } else {
            Image(systemName: DazuIcon.symbolName(for: name))
        }
    }

    private static func assetName(for name: String, solid: Bool) -> String? {
        guard isEnabled, assetsInstalled else { return nil }
        if solid, let filled = solidAssets[name] { return filled }
        return names.contains(name) ? "dazu." + name : nil
    }

    /// Prüft einmal, ob die Imagesets im Bundle liegen. Fehlen sie, zeigt
    /// die App überall die SF Symbols.
    private static let assetsInstalled: Bool = UIImage(named: "dazu.checkmark") != nil

    /// Gefüllte Fassungen für Abzeichen und Stufen.
    private static let solidAssets: [String: String] = [
        "crown.fill": "BadgeFounder",
        "checkmark.shield.fill": "BadgeVerifiziert",
        "star.fill": "BadgeGastgeber",
        "bolt.fill": "BadgePlus",
        "checkmark.seal.fill": "BadgeTrusted",
        "sparkle": "BadgeBeta",
        "leaf.fill": "TierNeuling",
        "binoculars.fill": "TierEntdecker",
        "exclamationmark.triangle.fill": "TierWarnung"
    ]

    /// Eigene Icons ohne SF-Vorbild und das SF Symbol, das sie ersetzt,
    /// wenn die eigenen Icons abgeschaltet sind.
    private static let ownIcons: [String: String] = [
        "runde": "circle"
    ]

    private static func symbolName(for name: String) -> String {
        ownIcons[name] ?? name
    }

    /// Alle Namen, für die es ein eigenes Icon gibt: SF Symbols und "runde".
    private static let names: Set<String> = [
        "runde",
        "antenna.radiowaves.left.and.right", "arrow.clockwise",
        "arrow.counterclockwise.circle.fill", "arrow.left", "arrow.right",
        "arrow.triangle.turn.up.right.circle", "arrow.triangle.turn.up.right.circle.fill",
        "arrow.up.arrow.down", "arrow.up.circle.fill", "arrow.up.right.square",
        "arrow.uturn.backward", "arrowtriangle.down.fill", "basketball.fill", "bell.badge",
        "bell.badge.fill", "bicycle", "binoculars.fill", "bolt.circle.fill", "bolt.fill",
        "briefcase.fill", "bubble.left.fill", "building.columns.fill", "calendar",
        "camera.fill", "chart.bar.fill", "checkmark", "checkmark.circle.fill",
        "checkmark.seal.fill", "checkmark.shield.fill", "chevron.down", "chevron.left",
        "chevron.right", "circle", "circle.fill", "circle.lefthalf.filled", "clock",
        "clock.arrow.circlepath", "clock.badge.checkmark.fill", "clock.badge.exclamationmark",
        "clock.badge.xmark", "clock.fill", "crown.fill", "cup.and.saucer.fill", "doc.text.fill",
        "door.left.hand.open", "dot.radiowaves.left.and.right", "dumbbell.fill", "ellipsis",
        "ellipsis.circle", "envelope", "envelope.fill", "exclamationmark.bubble.fill",
        "exclamationmark.shield.fill", "exclamationmark.triangle.fill", "eye.fill",
        "eye.slash.fill", "face.smiling", "face.smiling.inverse", "figure.climbing",
        "figure.dance", "figure.hiking", "figure.martial.arts", "figure.mind.and.body",
        "figure.pool.swim", "figure.run", "figure.skating", "figure.walk",
        "figure.walk.arrival", "figure.walk.circle.fill", "figure.wave", "flag.checkered",
        "flag.fill", "flag.slash", "flame.fill", "fork.knife", "gamecontroller.fill",
        "hand.raised", "hand.raised.circle.fill", "hand.raised.fill", "hand.tap.fill",
        "hand.thumbsdown.fill", "hand.thumbsup.fill", "hand.wave.fill", "hourglass",
        "house.fill", "info.circle", "info.circle.fill", "iphone", "ladybug", "leaf.fill",
        "line.3.horizontal.decrease.circle.fill", "list.bullet.rectangle.portrait",
        "location.fill", "location.slash.fill", "lock.circle.fill", "lock.fill",
        "lock.open.fill", "lock.rotation", "lock.shield.fill", "magnifyingglass", "map",
        "map.fill", "mappin", "mappin.and.ellipse", "mappin.circle.fill", "mappin.slash",
        "megaphone.fill", "moon.fill", "moon.zzz.fill", "nosign", "paperplane.fill",
        "pawprint.fill", "pencil", "person.2.fill", "person.2.slash", "person.2.wave.2.fill",
        "person.3.fill", "person.badge.minus", "person.badge.plus", "person.badge.plus.fill",
        "person.crop.circle.badge.checkmark", "person.crop.circle.badge.minus",
        "person.crop.circle.badge.plus", "person.crop.circle.badge.xmark", "person.fill",
        "person.fill.badge.plus", "person.fill.questionmark", "person.fill.xmark",
        "person.slash", "person.text.rectangle", "person.text.rectangle.fill",
        "person.wave.2.fill", "phone.fill", "plus", "plus.app.fill", "plus.circle.fill",
        "questionmark.circle", "questionmark.circle.fill", "rectangle.portrait.and.arrow.right",
        "rosette", "scope", "shield.fill", "shield.lefthalf.fill", "soccerball", "sparkle",
        "sparkles", "square.and.arrow.up", "square.grid.2x2.fill", "star.circle.fill",
        "star.fill", "star.slash", "star.slash.fill", "sun.max.fill", "tennis.racket",
        "text.alignleft", "text.bubble.fill", "text.cursor", "text.magnifyingglass", "trash",
        "trash.fill", "tray", "volleyball.fill", "water.waves", "wifi", "wifi.slash",
        "wineglass", "xmark", "xmark.circle.fill", "xmark.seal.fill", "xmark.shield.fill"
    ]
}

// MARK: - DazuAssetIcon

/// Ein Icon aus den Assets, als Vorlage in der Vordergrundfarbe.
/// Hat das Icon einen Punkt, wird dieser orange gezeichnet. Dafür gibt es
/// zu jedem solchen Icon zwei weitere Vorlagen: „<Name>.linie" (alles
/// außer dem Punkt) und „<Name>.punkt" (nur der Punkt).
struct DazuAssetIcon: View {
    let asset: String
    var accent: Bool = true
    var dotColor: Color = .brandOrange

    var body: some View {
        if accent && DazuAssetIcon.layersInstalled && DazuAssetIcon.twoTone.contains(asset) {
            ZStack {
                Image(asset + ".linie")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                Image(asset + ".punkt")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(dotColor)
                    .foregroundColor(dotColor)
            }
        } else {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
        }
    }

    /// Prüft einmal, ob die zweiteiligen Vorlagen im Bundle liegen.
    private static let layersInstalled: Bool = UIImage(named: "dazu.house.fill.punkt") != nil

    /// Icons mit Punkt.
    private static let twoTone: Set<String> = [
        "akt.baum", "akt.bier", "akt.buch", "akt.burger", "akt.cocktail", "akt.controller",
        "akt.eis", "akt.funkeln", "akt.golf", "akt.kaffee", "akt.kamera", "akt.kampfsport",
        "akt.klappe", "akt.klettern", "akt.koffer", "akt.korb", "akt.kuchen", "akt.laufen",
        "akt.markt", "akt.note", "akt.palette", "akt.party", "akt.pin", "akt.pizza",
        "akt.schwimmen", "akt.ski", "akt.strand", "akt.sushi", "akt.tanz", "akt.tee",
        "akt.tennis", "akt.topf", "akt.wandern", "akt.wuerfel", "akt.yoga", "akt.zufuss",
        "SetAdmin", "SetAltersgruppen", "SetAuge", "SetAusweis", "SetBug", "SetCommunity",
        "SetDarstellung", "SetFeedback", "SetGlocke", "SetHeimzone", "SetHilfe", "SetInfo", "SetInstagram",
        "SetKartenPin", "SetKontoLoeschen", "SetMond", "SetRadius", "SetSchloss", "SetSchutz",
        "SetSonne", "SetTelefon", "SetZuFuss", "dazu.antenna.radiowaves.left.and.right",
        "dazu.arrow.triangle.turn.up.right.circle",
        "dazu.arrow.triangle.turn.up.right.circle.fill", "dazu.bell.badge",
        "dazu.bell.badge.fill", "dazu.briefcase.fill", "dazu.calendar", "dazu.camera.fill",
        "dazu.circle.lefthalf.filled", "dazu.clock.badge.checkmark.fill",
        "dazu.clock.badge.exclamationmark", "dazu.clock.badge.xmark", "dazu.crown.fill",
        "dazu.cup.and.saucer.fill", "dazu.door.left.hand.open",
        "dazu.dot.radiowaves.left.and.right", "dazu.ellipsis",
        "dazu.exclamationmark.bubble.fill", "dazu.exclamationmark.shield.fill",
        "dazu.exclamationmark.triangle.fill", "dazu.eye.fill", "dazu.figure.climbing",
        "dazu.figure.dance", "dazu.figure.hiking", "dazu.figure.martial.arts",
        "dazu.figure.mind.and.body", "dazu.figure.pool.swim", "dazu.figure.run",
        "dazu.figure.walk", "dazu.figure.walk.arrival", "dazu.figure.walk.circle.fill",
        "dazu.figure.wave", "dazu.flag.checkered", "dazu.flame.fill",
        "dazu.gamecontroller.fill", "dazu.hand.raised", "dazu.hand.raised.circle.fill",
        "dazu.hand.raised.fill", "dazu.hand.wave.fill", "dazu.house.fill", "dazu.info.circle",
        "dazu.info.circle.fill", "dazu.iphone", "dazu.ladybug", "dazu.lock.circle.fill",
        "dazu.lock.fill", "dazu.lock.open.fill", "dazu.lock.rotation", "dazu.lock.shield.fill",
        "dazu.map", "dazu.map.fill", "dazu.mappin", "dazu.mappin.and.ellipse",
        "dazu.mappin.circle.fill", "dazu.moon.fill", "dazu.person.2.fill",
        "dazu.person.2.wave.2.fill", "dazu.person.3.fill", "dazu.person.badge.minus",
        "dazu.person.badge.plus", "dazu.person.badge.plus.fill",
        "dazu.person.crop.circle.badge.checkmark", "dazu.person.crop.circle.badge.minus",
        "dazu.person.crop.circle.badge.plus", "dazu.person.crop.circle.badge.xmark",
        "dazu.person.fill", "dazu.person.fill.badge.plus", "dazu.person.fill.questionmark",
        "dazu.person.fill.xmark", "dazu.person.text.rectangle",
        "dazu.person.text.rectangle.fill", "dazu.person.wave.2.fill", "dazu.phone.fill",
        "dazu.questionmark.circle", "dazu.questionmark.circle.fill", "dazu.rosette",
        "dazu.runde", "dazu.scope", "dazu.sparkles", "dazu.square.grid.2x2.fill",
        "dazu.star.circle.fill", "dazu.sun.max.fill", "dazu.tennis.racket", "dazu.wifi"
    ]
}

// MARK: - Ring und Punkt (Ladeanimation, Start)

/// Ring und Punkt des dazu-Zeichens in einem Zustand der Animation.
/// Der Ring nimmt die Farbe aus `.tint(...)`.
///
/// - arrive: 0 = Punkt noch außerhalb, 1 = Punkt sitzt in der Lücke.
/// - close:  0 = Ring offen wie im Logo, 1 = Ring geschlossen.
struct DazuRingMark: View {
    var arrive: Double
    var close: Double
    var dotColor: Color = .brandOrangeFixed

    var body: some View {
        GeometryReader { geo in
            let s: CGFloat = min(geo.size.width, geo.size.height)
            let radius: CGFloat = s * 0.342
            let line: CGFloat = s * 0.175
            let gapHalf: Double = 47.0 * (1.0 - close)
            let start: Double = -48.0 + gapHalf
            let sweep: Double = min(max((360.0 - 2.0 * gapHalf) / 360.0, 0.0), 1.0)
            let reach: Double = 1.0 + (1.0 - arrive) * 1.1
            let angle: Double = -48.0 * Double.pi / 180.0
            let dx: CGFloat = CGFloat(cos(angle) * reach) * radius
            let dy: CGFloat = CGFloat(sin(angle) * reach) * radius
            ZStack {
                Circle()
                    .trim(from: 0, to: CGFloat(sweep))
                    .stroke(.tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(start))
                    .frame(width: radius * 2, height: radius * 2)
                Circle()
                    .fill(dotColor)
                    .frame(width: s * 0.237, height: s * 0.237)
                    .opacity(min(1.0, max(0.0, arrive * 1.6)))
                    .offset(x: dx, y: dy)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Ladeanimation: der Punkt kommt dazu, der Ring schließt sich, öffnet sich
/// wieder. Ersetzt `ProgressView()`. Die Ringfarbe kommt wie dort aus
/// `.tint(...)`.
struct DazuLoader: View {
    var size: CGFloat = 20
    var dotColor: Color = .brandOrangeFixed
    /// Dauer eines Durchlaufs in Sekunden.
    var duration: Double = 1.5

    var body: some View {
        TimelineView(.animation) { context in
            let seconds: Double = context.date.timeIntervalSinceReferenceDate
            let p: Double = seconds.truncatingRemainder(dividingBy: duration) / duration
            DazuRingMark(arrive: DazuLoader.arrive(p),
                         close: DazuLoader.close(p),
                         dotColor: dotColor)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Lädt"))
    }

    private static func ease(_ x: Double) -> Double {
        let c = min(max(x, 0.0), 1.0)
        return c * c * (3.0 - 2.0 * c)
    }

    /// Punkt: kommt, bleibt, geht wieder.
    static func arrive(_ p: Double) -> Double {
        if p < 0.30 { return ease(p / 0.30) }
        if p < 0.85 { return 1.0 }
        return 1.0 - ease((p - 0.85) / 0.15)
    }

    /// Ring: schließt sich, bleibt zu, öffnet sich.
    static func close(_ p: Double) -> Double {
        if p < 0.25 { return 0.0 }
        if p < 0.50 { return ease((p - 0.25) / 0.25) }
        if p < 0.70 { return 1.0 }
        if p < 0.90 { return 1.0 - ease((p - 0.70) / 0.20) }
        return 0.0
    }
}

/// Start-Animation. Beginnt genau so, wie der Startbildschirm aufhört
/// (offener Ring auf `LaunchBackground`, Bild `LaunchMark`).
/// Solange die App lädt, dreht sich der Ring, und rundherum leuchten
/// „Komm dazu" in fünf Sprachen auf und verblassen wieder. Ist alles geladen,
/// bremst der Ring in die Lage des Logos ab, der Punkt kommt dazu, dann blendet
/// alles aus. Der Ring bleibt offen wie im Logo. Läuft einmal je App-Start.
///
/// Gedreht und eingeblendet wird mit Core Animation (DazuSplashCanvas). Das
/// läuft auch dann flüssig weiter, wenn der Haupt-Thread beim Start mit dem
/// Aufbau von Karte und Tabs beschäftigt ist.
struct DazuSplashView: View {
    /// Daten für den ersten Bildschirm sind da (oder werden nicht gebraucht).
    /// Spätestens nach `maxLoad` Sekunden geht es trotzdem weiter.
    var dataReady: Bool = true

    @State private var visible = true
    @State private var dataOK = false
    @State private var finish = false
    @State private var fade: Double = 1.0

    /// So lange mindestens, damit alle fünf Sprachen einmal zu sehen sind.
    private static let minLoad: Double = 1.6
    private static let maxLoad: Double = 3.0

    var body: some View {
        if visible {
            ZStack {
                Color("LaunchBackground")
                DazuSplashCanvas(finish: finish) {
                    withAnimation(.easeOut(duration: 0.35)) { fade = 0.0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        visible = false
                    }
                }
            }
            .opacity(fade)
            .ignoresSafeArea()
            .allowsHitTesting(fade > 0.5)
            .accessibilityHidden(true)
            .onAppear { dataOK = dataReady }
            .onChange(of: dataReady) { _, now in dataOK = now }
            .task {
                let begin = Date()
                try? await Task.sleep(nanoseconds: UInt64(Self.minLoad * 1_000_000_000))
                while !dataOK && Date().timeIntervalSince(begin) < Self.maxLoad {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                finish = true
            }
        }
    }
}

/// Ring, Punkt und Sprachen der Start-Animation als Core-Animation-Ebenen.
struct DazuSplashCanvas: UIViewRepresentable {
    let finish: Bool
    let onDone: () -> Void

    func makeUIView(context: Context) -> CanvasView {
        let view = CanvasView()
        view.onDone = onDone
        return view
    }

    func updateUIView(_ uiView: CanvasView, context: Context) {
        uiView.onDone = onDone
        if finish { uiView.finish() }
    }

    final class CanvasView: UIView {
        var onDone: (() -> Void)? = nil

        /// Kantenlänge des Zeichens wie `LaunchMark`.
        private let size: CGFloat = 132
        /// Drehgeschwindigkeit in Grad je Sekunde.
        private let speed: Double = 540
        /// Die letzten Grad bis zur Lage des Logos werden abgebremst.
        private let settle: Double = 60
        private let arriveDuration: Double = 0.45
        private let hold: Double = 0.3

        /// „Komm dazu" in den Sprachen der Website, mit Lage um das Logo (pt).
        /// `accent` ist der Teil, der orange leuchtet (wie „dazu" im Logo).
        private let phrases: [(text: String, accent: String, x: CGFloat, y: CGFloat)] = [
            ("Komm dazu", "dazu", -92, -150), ("Join in", "Join", 104, -104),
            ("Únete", "Únete", 112, 100), ("Unisciti", "Unisciti", -104, 118),
            ("Rejoins-nous", "Rejoins", 0, 178)
        ]
        private let stagger: Double = 0.3

        private let mark = CALayer()
        private let ring = CAShapeLayer()
        private let dot = CAShapeLayer()
        private var labels: [UILabel] = []
        private var started = false
        private var finished = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            setUp()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setUp()
        }

        private func setUp() {
            backgroundColor = .clear
            isUserInteractionEnabled = false
            let cream = UIColor(red: 1.000, green: 0.965, blue: 0.918, alpha: 1)
            let orange = UIColor(red: 1.000, green: 0.627, blue: 0.180, alpha: 1)

            // Maße wie DazuRingMark.
            let radius: CGFloat = size * 0.342
            let line: CGFloat = size * 0.175
            let c = CGPoint(x: size / 2, y: size / 2)
            mark.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            ring.frame = mark.bounds
            ring.path = UIBezierPath(arcCenter: c, radius: radius,
                                     startAngle: CGFloat(-1.0 * Double.pi / 180),
                                     endAngle: CGFloat(265.0 * Double.pi / 180),
                                     clockwise: true).cgPath
            ring.strokeColor = cream.cgColor
            ring.fillColor = nil
            ring.lineWidth = line
            ring.lineCap = .round
            mark.addSublayer(ring)

            let d: CGFloat = size * 0.237
            dot.bounds = CGRect(x: 0, y: 0, width: d, height: d)
            dot.path = UIBezierPath(ovalIn: dot.bounds).cgPath
            dot.fillColor = orange.cgColor
            dot.position = dotPoint(reach: 1.0)
            dot.opacity = 0
            mark.addSublayer(dot)
            layer.addSublayer(mark)

            // Schrift wie in der App: SF Rounded, kräftig.
            var font = UIFont.systemFont(ofSize: 24, weight: .heavy)
            if let rounded = font.fontDescriptor.withDesign(.rounded) {
                font = UIFont(descriptor: rounded, size: 24)
            }
            for p in phrases {
                let label = UILabel()
                let text = NSMutableAttributedString(
                    string: p.text,
                    attributes: [.font: font, .foregroundColor: cream, .kern: -0.3])
                let range = (p.text as NSString).range(of: p.accent)
                if range.location != NSNotFound {
                    text.addAttribute(.foregroundColor, value: orange, range: range)
                }
                label.attributedText = text
                label.sizeToFit()
                label.layer.opacity = 0
                addSubview(label)
                labels.append(label)
            }
        }

        /// Lage des Punkts: in der Lücke des Rings (reach 1) oder weiter außen.
        private func dotPoint(reach: Double) -> CGPoint {
            let radius = Double(size * 0.342)
            let angle = -48.0 * Double.pi / 180
            return CGPoint(x: Double(size / 2) + cos(angle) * reach * radius,
                           y: Double(size / 2) + sin(angle) * reach * radius)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let mid = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            mark.position = mid
            CATransaction.commit()
            for (i, label) in labels.enumerated() {
                label.center = CGPoint(x: mid.x + phrases[i].x, y: mid.y + phrases[i].y)
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, !started else { return }
            started = true
            startSpin()
            startPhrases()
        }

        private func startSpin() {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0.0
            spin.toValue = 2.0 * Double.pi
            spin.duration = 360.0 / speed
            spin.repeatCount = .infinity
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            mark.add(spin, forKey: "spin")
        }

        /// Jede Sprache leuchtet nacheinander auf und verblasst wieder, im Kreis.
        private func startPhrases() {
            let now = CACurrentMediaTime()
            let period: Double = stagger * Double(phrases.count) + 0.4
            for (i, label) in labels.enumerated() {
                let glow = CAKeyframeAnimation(keyPath: "opacity")
                glow.values = [0.0, 1.0, 1.0, 0.0, 0.0]
                glow.keyTimes = [0, 0.18 / period, 0.8 / period, 1.15 / period, 1].map { NSNumber(value: $0) }
                let grow = CAKeyframeAnimation(keyPath: "transform.scale")
                grow.values = [0.92, 1.0, 1.0, 0.92, 0.92]
                grow.keyTimes = glow.keyTimes
                let group = CAAnimationGroup()
                group.animations = [glow, grow]
                group.duration = period
                group.repeatCount = .infinity
                group.beginTime = now + stagger * Double(i)
                group.fillMode = .backwards
                label.layer.add(group, forKey: "glow")
            }
        }

        /// Fertig geladen: Sprachen aus, Ring bremst in die Lage des Logos,
        /// der Punkt kommt dazu.
        func finish() {
            guard !finished else { return }
            finished = true
            guard started else {
                // Nie im Fenster gewesen: nichts zu zeigen, gleich weiter.
                DispatchQueue.main.async { [weak self] in self?.onDone?() }
                return
            }

            // Sprachen von ihrem aktuellen Stand aus ausblenden.
            for label in labels {
                let current = label.layer.presentation()?.opacity ?? 0
                label.layer.removeAnimation(forKey: "glow")
                label.layer.opacity = 0
                let out = CABasicAnimation(keyPath: "opacity")
                out.fromValue = current
                out.toValue = 0.0
                out.duration = 0.3
                label.layer.add(out, forKey: "out")
            }

            // Aktueller Winkel, dann gleichmäßig weiter bis `settle` Grad vor
            // der nächsten Logo-Lage und ohne Ruck auf null abbremsen.
            let shown = (mark.presentation()?.value(forKeyPath: "transform.rotation.z") as? NSNumber)?.doubleValue ?? 0
            var current = shown
            if current < 0 { current += 2.0 * Double.pi }
            let omega = speed * Double.pi / 180
            let settleRad = settle * Double.pi / 180
            var target = 2.0 * Double.pi
            if target - current < settleRad { target += 2.0 * Double.pi }
            let cruise = (target - settleRad - current) / omega
            let brake = 3.0 * settleRad / omega
            mark.removeAnimation(forKey: "spin")
            mark.transform = CATransform3DIdentity
            let stop = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            stop.values = [current, target - settleRad, target]
            stop.keyTimes = [NSNumber(value: 0.0), NSNumber(value: cruise / (cruise + brake)), NSNumber(value: 1.0)]
            stop.timingFunctions = [CAMediaTimingFunction(name: .linear),
                                    CAMediaTimingFunction(controlPoints: 0.33, 1.0, 0.68, 1.0)]
            stop.duration = cruise + brake
            mark.add(stop, forKey: "stop")

            // Der Punkt fliegt von außen in die Lücke.
            let landed = CACurrentMediaTime() + cruise + brake
            dot.opacity = 1
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(cgPoint: dotPoint(reach: 2.1))
            move.toValue = NSValue(cgPoint: dotPoint(reach: 1.0))
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            let show = CAKeyframeAnimation(keyPath: "opacity")
            show.values = [0.0, 1.0, 1.0]
            show.keyTimes = [NSNumber(value: 0.0), NSNumber(value: 0.6), NSNumber(value: 1.0)]
            let arrive = CAAnimationGroup()
            arrive.animations = [move, show]
            arrive.duration = arriveDuration
            arrive.beginTime = landed
            arrive.fillMode = .backwards
            dot.add(arrive, forKey: "arrive")

            let total = cruise + brake + arriveDuration + hold
            DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in
                self?.onDone?()
            }
        }
    }
}

// MARK: - Aktivitäts-Icons
//
// Jede Aktivität hat ein eigenes Icon. Gespeichert wird weiterhin ein Emoji
// (Datenbank, Push-Texte, Live Activity): `emoji` ist das, was beim Wählen
// eines Icons gespeichert wird, `aliases` führen zum selben Icon. Die
// Imagesets liegen in Assets.xcassets/DazuIcons/Aktivitaeten („akt.…").

struct DazuActivity: Identifiable {
    let id: String          // Name des Imagesets, z. B. "akt.kaffee"
    let de: String
    let en: String
    let emoji: String
    let aliases: [String]

    func title(_ language: String) -> String {
        language == "en" ? en : de
    }

    static let groups: [DazuActivityGroup] = [
        DazuActivityGroup(id: "essen", de: "Essen und Trinken", en: "Food and drinks", items: [
            DazuActivity(id: "akt.kaffee", de: "Kaffee", en: "Coffee", emoji: "☕️", aliases: []),
            DazuActivity(id: "akt.tee", de: "Tee", en: "Tea", emoji: "🍵", aliases: ["🧋"]),
            DazuActivity(id: "akt.bier", de: "Bier", en: "Beer", emoji: "🍺", aliases: ["🍻"]),
            DazuActivity(id: "akt.glas", de: "Wein", en: "Wine", emoji: "🍷", aliases: ["🥂"]),
            DazuActivity(id: "akt.cocktail", de: "Cocktail", en: "Cocktail", emoji: "🍹", aliases: ["🍸"]),
            DazuActivity(id: "akt.besteck", de: "Essen", en: "Food", emoji: "🍽️", aliases: ["🍜", "🌮", "🥗", "🍝", "🥙", "🍴"]),
            DazuActivity(id: "akt.croissant", de: "Brunch", en: "Brunch", emoji: "🥐", aliases: []),
            DazuActivity(id: "akt.pizza", de: "Pizza", en: "Pizza", emoji: "🍕", aliases: []),
            DazuActivity(id: "akt.burger", de: "Burger", en: "Burger", emoji: "🍔", aliases: []),
            DazuActivity(id: "akt.sushi", de: "Sushi", en: "Sushi", emoji: "🍣", aliases: ["🍱"]),
            DazuActivity(id: "akt.eis", de: "Eis", en: "Ice cream", emoji: "🍦", aliases: []),
            DazuActivity(id: "akt.kuchen", de: "Kuchen", en: "Cake", emoji: "🎂", aliases: ["🍰", "🧁"]),
            DazuActivity(id: "akt.topf", de: "Kochen", en: "Cooking", emoji: "👨‍🍳", aliases: ["🧑‍🍳", "👩‍🍳", "🍳"]),
            DazuActivity(id: "akt.korb", de: "Picknick", en: "Picnic", emoji: "🧺", aliases: [])
        ]),
        DazuActivityGroup(id: "draussen", de: "Draußen", en: "Outdoors", items: [
            DazuActivity(id: "akt.zufuss", de: "Spazieren", en: "Walk", emoji: "🚶", aliases: []),
            DazuActivity(id: "akt.baum", de: "Park", en: "Park", emoji: "🌳", aliases: ["🌲"]),
            DazuActivity(id: "akt.pfote", de: "Hund", en: "Dog", emoji: "🐕", aliases: ["🐶", "🐾"]),
            DazuActivity(id: "akt.strand", de: "Strand", en: "Beach", emoji: "🏖️", aliases: ["🏝"]),
            DazuActivity(id: "akt.wandern", de: "Wandern", en: "Hiking", emoji: "🥾", aliases: ["⛰", "🏔"])
        ]),
        DazuActivityGroup(id: "sport", de: "Sport", en: "Sports", items: [
            DazuActivity(id: "akt.laufen", de: "Laufen", en: "Running", emoji: "🏃", aliases: []),
            DazuActivity(id: "akt.hantel", de: "Fitness", en: "Fitness", emoji: "💪", aliases: ["🏋"]),
            DazuActivity(id: "akt.yoga", de: "Yoga", en: "Yoga", emoji: "🧘", aliases: []),
            DazuActivity(id: "akt.fahrrad", de: "Radfahren", en: "Cycling", emoji: "🚴", aliases: ["🚲"]),
            DazuActivity(id: "akt.schwimmen", de: "Schwimmen", en: "Swimming", emoji: "🏊", aliases: []),
            DazuActivity(id: "akt.klettern", de: "Klettern", en: "Climbing", emoji: "🧗", aliases: []),
            DazuActivity(id: "akt.tanz", de: "Tanzen", en: "Dancing", emoji: "💃", aliases: []),
            DazuActivity(id: "akt.fussball", de: "Fußball", en: "Football", emoji: "⚽️", aliases: []),
            DazuActivity(id: "akt.basketball", de: "Basketball", en: "Basketball", emoji: "🏀", aliases: []),
            DazuActivity(id: "akt.volleyball", de: "Volleyball", en: "Volleyball", emoji: "🏐", aliases: []),
            DazuActivity(id: "akt.tennis", de: "Tennis", en: "Tennis", emoji: "🎾", aliases: ["🏸", "🏓"]),
            DazuActivity(id: "akt.golf", de: "Golf", en: "Golf", emoji: "⛳", aliases: []),
            DazuActivity(id: "akt.ski", de: "Ski", en: "Skiing", emoji: "⛷️", aliases: ["🎿", "🏂"]),
            DazuActivity(id: "akt.wellen", de: "Surfen", en: "Surfing", emoji: "🏄", aliases: ["🌊"]),
            DazuActivity(id: "akt.kampfsport", de: "Kampfsport", en: "Martial arts", emoji: "🥋", aliases: []),
            DazuActivity(id: "akt.skaten", de: "Skaten", en: "Skating", emoji: "🛹", aliases: ["⛸", "🛼"])
        ]),
        DazuActivityGroup(id: "kultur", de: "Spiel und Kultur", en: "Play and culture", items: [
            DazuActivity(id: "akt.controller", de: "Zocken", en: "Gaming", emoji: "🎮", aliases: ["🕹", "👾"]),
            DazuActivity(id: "akt.wuerfel", de: "Brettspiel", en: "Board games", emoji: "🎲", aliases: ["♟", "🃏"]),
            DazuActivity(id: "akt.klappe", de: "Kino", en: "Cinema", emoji: "🎬", aliases: ["🍿", "🎥"]),
            DazuActivity(id: "akt.note", de: "Konzert", en: "Concert", emoji: "🎵", aliases: ["🎶", "🎸", "🎤"]),
            DazuActivity(id: "akt.party", de: "Party", en: "Party", emoji: "🎉", aliases: ["🥳", "🪩"]),
            DazuActivity(id: "akt.gebaeude", de: "Museum", en: "Museum", emoji: "🏛️", aliases: []),
            DazuActivity(id: "akt.palette", de: "Malen", en: "Painting", emoji: "🎨", aliases: ["🖌"]),
            DazuActivity(id: "akt.kamera", de: "Foto-Walk", en: "Photo walk", emoji: "📸", aliases: ["📷"])
        ]),
        DazuActivityGroup(id: "alltag", de: "Alltag", en: "Everyday", items: [
            DazuActivity(id: "akt.tuete", de: "Bummeln", en: "Shopping", emoji: "🛍️", aliases: ["🛒"]),
            DazuActivity(id: "akt.markt", de: "Flohmarkt", en: "Flea market", emoji: "🏪", aliases: []),
            DazuActivity(id: "akt.buch", de: "Lernen", en: "Studying", emoji: "📚", aliases: ["📖"]),
            DazuActivity(id: "akt.koffer", de: "Arbeiten", en: "Working", emoji: "💼", aliases: ["💻"]),
            DazuActivity(id: "akt.funkeln", de: "Etwas anderes", en: "Something else", emoji: "✨", aliases: ["✏"])
        ])
    ]

    static let all: [DazuActivity] = DazuActivity.groups.flatMap { $0.items }

    /// Emoji ohne Variationsauswahl und Hautton, damit ☕ und ☕️ gleich sind.
    static func normalize(_ emoji: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in emoji.unicodeScalars {
            if scalar.value == 0xFE0F { continue }
            if scalar.value >= 0x1F3FB && scalar.value <= 0x1F3FF { continue }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// Name des Imagesets zu einem Emoji, oder nil, wenn es dafür kein Icon gibt.
    static func asset(for emoji: String) -> String? {
        guard installed, !emoji.isEmpty else { return nil }
        let key = normalize(emoji)
        if let hit = table[key] { return hit }
        // Varianten wie 🏃‍♀️: alles ab dem ersten Verbinder weglassen.
        var base = String.UnicodeScalarView()
        for scalar in key.unicodeScalars {
            if scalar.value == 0x200D { break }
            base.append(scalar)
        }
        return table[String(base)]
    }

    /// Prüft einmal, ob die Imagesets im Bundle liegen.
    static let installed: Bool = UIImage(named: "akt.kaffee") != nil

    /// Icon für Aktivitäten ohne eigenes Icon.
    static let fallbackAsset = "akt.funkeln"

    private static let table: [String: String] = {
        // 📍 setzt die App selbst als Platzhalter ein.
        var result: [String: String] = ["📍": "akt.pin"]
        for activity in DazuActivity.all {
            result[DazuActivity.normalize(activity.emoji)] = activity.id
            for alias in activity.aliases {
                result[DazuActivity.normalize(alias)] = activity.id
            }
        }
        return result
    }()
}

struct DazuActivityGroup: Identifiable {
    let id: String
    let de: String
    let en: String
    let items: [DazuActivity]

    func title(_ language: String) -> String {
        language == "en" ? en : de
    }
}

extension MapAnnotationItem {
    /// Bei Freunden und Mitkommenden steht in `emoji` das Profil-Emoji der
    /// Person. Sammel- und Community-Einträge zählen hier nicht als Aktivität.
    var hasActivityEmoji: Bool {
        switch type {
        case .myDrop, .stranger, .suggested: return true
        case .friend, .joiner, .cluster, .community: return false
        }
    }
}

/// Zeigt das eigene Icon einer Aktivität an Stelle ihres Emojis. Verhält sich
/// wie `Text(emoji)`: Größe über .font(...). Ein unsichtbares Emoji gibt nur
/// die Größe vor – gezeigt wird nie ein Emoji. Gibt es zu einem Emoji kein
/// Icon (Treffen aus älteren App-Versionen), erscheint das allgemeine Icon.
struct DazuActivityIcon: View {
    private let emoji: String
    private let enabled: Bool
    private let tint: Color
    private let dotColor: Color
    private let accent: Bool

    /// - Parameters:
    ///   - emoji: Das gespeicherte Emoji der Aktivität.
    ///   - enabled: false, wenn das Emoji zu einer Person gehört. Dann
    ///     erscheint das Personen-Icon.
    ///   - tint: Farbe der Linien. Auf Flächen, die im Dunkelmodus hell
    ///     bleiben, `.brandVioletFixed` und `.brandOrangeFixed` übergeben.
    ///   - dotColor: Farbe des Punkts.
    ///   - accent: false zeichnet auch den Punkt in `tint`.
    init(_ emoji: String, when enabled: Bool = true, tint: Color = .brandViolet,
         dotColor: Color = .brandOrange, accent: Bool = true) {
        self.emoji = emoji
        self.enabled = enabled
        self.tint = tint
        self.dotColor = dotColor
        self.accent = accent
    }

    var body: some View {
        if !enabled {
            DazuPersonIcon(tint: tint)
        } else if DazuActivity.installed {
            Text(emoji.isEmpty ? "✨" : emoji)
                .hidden()
                .overlay(
                    GeometryReader { geo in
                        let side = min(geo.size.width, geo.size.height) * 0.92
                        DazuAssetIcon(asset: DazuActivity.asset(for: emoji) ?? DazuActivity.fallbackAsset,
                                      accent: accent, dotColor: dotColor)
                            .foregroundColor(tint)
                            .frame(width: side, height: side)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                )
                .accessibilityHidden(true)
        } else {
            // Nur wenn die Imagesets im Bundle fehlen.
            Text(emoji)
        }
    }
}

/// Platzhalter für eine Person ohne Profilbild, an Stelle ihres Emojis.
/// Verhält sich wie `Text(emoji)`: Größe über .font(...).
struct DazuPersonIcon: View {
    var tint: Color = .brandViolet

    var body: some View {
        Text("👤")
            .hidden()
            .overlay(
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height) * 0.86
                    DazuAssetIcon(asset: "dazu.person.fill")
                        .foregroundColor(tint)
                        .frame(width: side, height: side)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            )
            .accessibilityHidden(true)
    }
}

/// Auswahl der Aktivität beim Erstellen: eigene Icons statt Emojis. Gleiche
/// Schnittstelle wie `EmojiPickerSheet` – zurück kommt das Emoji, das zu dem
/// gewählten Icon gespeichert wird.
struct ActivityIconPickerSheet: View {
    let selected: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "de"

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        let current = DazuActivity.asset(for: selected)
        VStack(spacing: 0) {
            Capsule().fill(Color(UIColor.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 10).padding(.bottom, 16)

            HStack {
                Text(appLanguage == "en" ? "What are you up to?" : "Was machst du?")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(DazuActivity.groups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title(appLanguage).uppercased())
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(1.2)
                                .foregroundColor(.brandViolet.opacity(0.65))
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(group.items) { activity in
                                    cell(activity, isSelected: activity.id == current)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private func cell(_ activity: DazuActivity, isSelected: Bool) -> some View {
        Button {
            Haptic.selection()
            onSelect(activity.emoji)
            dismiss()
        } label: {
            VStack(spacing: 6) {
                DazuAssetIcon(asset: activity.id)
                    .foregroundColor(.brandViolet)
                    .frame(width: 30, height: 30)
                Text(activity.title(appLanguage))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.brandNight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.brandLavender.opacity(isSelected ? 1.0 : 0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.brandViolet.opacity(isSelected ? 1.0 : 0.0), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Runde starten: Punkt in den Ring ziehen
//
// Ersetzt in CreateDropView den Knopf „Runde starten".
//
// Das Zeichen sitzt zuerst da wie im Logo: Ring mit Lücke oben rechts, Punkt
// in der Lücke. Dann dreht sich der Ring, bis die Lücke nach oben zeigt, und
// der Punkt springt nach oben heraus. Gestartet wird, indem man den Punkt
// zurück nach unten in die Lücke zieht. Sitzt er, dreht sich das Zeichen
// zurück in die Lage des Logos und `onStart` läuft. Der Ring bleibt dabei
// offen.
//
// Zwei Orte:
//   - in der Tab-Leiste, genau auf dem dazu-Icon (DazuTabMark, der Normalfall)
//   - im Formular (Ersatz, wenn die Lage des Icons nicht zu ermitteln ist,
//     und für CreateDropView als Sheet, z. B. aus einer Community)
struct DazuStartPull: View {
    /// Maße des Zeichens. `box` ist das Quadrat um den Ring.
    struct Metrics {
        var box: CGFloat
        var radius: CGFloat
        var line: CGFloat
        var dotSeated: CGFloat
        var dotFree: CGFloat
        var travel: CGFloat
        /// Radius der Öffnung in der Tab-Leiste über dem Ring; 0 = keine.
        var mouth: CGFloat = 0

        /// Höhe der ganzen Steuerung: Ring unten, Punkt in Ruhe oben.
        var height: CGFloat { box / 2 + radius + travel + dotFree / 2 + 6 }

        /// Groß, für das Formular.
        static let form = Metrics(box: 80, radius: 27.5, line: 10.5,
                                  dotSeated: 18.5, dotFree: 30, travel: 80)

        /// Klein, deckungsgleich mit dem Tab-Icon (Zeichenfläche 228).
        static func tab(icon: CGFloat) -> Metrics {
            let k: CGFloat = icon / 228.0
            var m = Metrics(box: icon, radius: 80.0 * k, line: 30.0 * k,
                            dotSeated: 54.0 * k, dotFree: 58, travel: 98)
            m.mouth = 20
            return m
        }
    }

    var metrics: Metrics = .form
    /// Formular vollständig: der Punkt lässt sich ziehen.
    let isEnabled: Bool
    /// Die Runde wird gerade erstellt: das Zeichen bleibt in der Lage des Logos.
    let isBusy: Bool
    let onStart: () -> Void

    /// Auf false setzen, dann zeigt CreateDropView wieder den Knopf.
    static let isOn = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Ring gedreht (Lücke oben) statt wie im Logo (Lücke oben rechts).
    @State private var opened = false
    /// 0 = Punkt sitzt in der Lücke, 1 = Punkt steht frei darüber.
    @State private var out: CGFloat = 0.0
    @State private var dragging = false
    @State private var committed = false
    /// Finger liegt auf dem Punkt.
    @GestureState private var touching = false
    /// Diese Berührung hat schon ausgelöst; erst nach dem Loslassen geht es wieder.
    @State private var spent = false
    /// Ob das Formular vollständig war, als die Berührung begann.
    @State private var dragEnabled = false
    /// Spiegel von `isBusy`, damit verzögerte Aufrufe den aktuellen Wert lesen.
    @State private var busyNow = false
    /// Zählt hoch, sobald ein neuer Ablauf beginnt. Verzögerte Aufrufe
    /// eines älteren Ablaufs erkennen daran, dass sie nicht mehr gelten.
    @State private var run = 0

    /// Kräftiges Orange für den Punkt (wie im aktiven Tab-Icon, #FF8A1F).
    static let dotColor = Color(red: 1.0, green: 0.541, blue: 0.122)

    private static let touch: CGFloat = 76
    /// Drehung vom Logo (Lücke bei 48° über der Waagerechten) bis Lücke oben.
    private static let logoTurn: Double = 42

    private var active: Bool { isEnabled && !isBusy && !committed }

    var body: some View {
        let h = metrics.height
        let pivot = UnitPoint(x: 0.5, y: (h - metrics.box / 2) / h)
        ZStack(alignment: .bottom) {
            mouth
            track
            ring
            dot
        }
        .frame(width: 140, height: h, alignment: .bottom)
        .rotationEffect(.degrees(opened ? 0.0 : DazuStartPull.logoTurn), anchor: pivot)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(DazuStartPull.title))
        .accessibilityHint(Text(isBusy ? DazuStartPull.hint(busy: true)
                                : (isEnabled ? "" : DazuStartPull.notReady)))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if isEnabled && !isBusy { commit() }
        }
        .onAppear { appear() }
        .onDisappear {
            run += 1
            opened = false
            out = 0.0
            dragging = false
            committed = false
        }
        .onChange(of: isBusy) { _, busy in
            busyNow = busy
            if busy {
                run += 1
                committed = true
                dragging = false
                withAnimation(.easeInOut(duration: 0.25)) {
                    out = 0.0
                    opened = false
                }
            } else {
                // Meist wechselt jetzt ohnehin der Tab. Bleibt die Ansicht
                // stehen, dreht sich der Ring nach kurzer Pause wieder auf.
                run += 1
                let token = run
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    guard token == run, !busyNow else { return }
                    reopen()
                }
            }
        }
        .onChange(of: touching) { _, down in
            guard !down else { return }
            spent = false
            if dragging {
                // Berührung abgebrochen, onEnded kam nicht.
                dragging = false
                if !committed {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { out = 1.0 }
                }
            }
        }
    }

    // MARK: Teile

    /// Öffnung in der Tab-Leiste (nur dort): ein runder Ausschnitt in der
    /// Farbe des Hintergrunds unterbricht die Oberkante der Leiste direkt über
    /// dem Ring. Zusammen mit der Lücke des Rings wirkt die Leiste dort nach
    /// oben offen. Die Leiste selbst gehört iOS und lässt sich nicht
    /// ausschneiden; deshalb liegt der Ausschnitt als Fläche darüber.
    @ViewBuilder private var mouth: some View {
        if metrics.mouth > 0 {
            let r: CGFloat = metrics.mouth
            let reach: CGFloat = metrics.box / 2 + metrics.radius + metrics.line / 2 + 1.5
            Circle()
                .fill(Color.brandCream)
                .frame(width: r * 2, height: r * 2)
                .scaleEffect(opened ? 1.0 : 0.01, anchor: .bottom)
                .opacity(opened ? 1.0 : 0.0)
                .offset(y: -reach)
                .allowsHitTesting(false)
        }
    }

    /// Bahn, auf der der Punkt nach unten gezogen wird.
    private var track: some View {
        let length: CGFloat = metrics.travel + metrics.dotFree + 10
        let middle: CGFloat = metrics.box / 2 + metrics.radius + metrics.travel / 2
        let shown: Double = Double(min(max(out, 0.0), 1.0))
        return Capsule()
            .fill(Color.brand.opacity(0.09))
            .frame(width: metrics.dotFree + 10, height: length)
            .overlay(
                DazuIcon("chevron.down", accent: false)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.brand.opacity(0.45))
                    .offset(y: metrics.dotFree / 2)
            )
            .offset(y: length / 2 - middle)
            .opacity(active ? shown : 0.0)
            .animation(.easeInOut(duration: 0.25), value: active)
            .allowsHitTesting(false)
    }

    private var ring: some View {
        // Der Ring bleibt immer offen wie im Logo.
        let gapHalf: Double = 47.0
        let sweep: Double = (360.0 - 2.0 * gapHalf) / 360.0
        return Circle()
            .trim(from: 0, to: CGFloat(sweep))
            .stroke(Color.brand, style: StrokeStyle(lineWidth: metrics.line, lineCap: .round))
            .rotationEffect(.degrees(-90.0 + gapHalf))
            .frame(width: metrics.radius * 2, height: metrics.radius * 2)
            .frame(width: metrics.box, height: metrics.box)
            .allowsHitTesting(false)
    }

    private var dot: some View {
        let free: CGFloat = min(max(out, 0.0), 1.0)
        let size: CGFloat = metrics.dotSeated + (metrics.dotFree - metrics.dotSeated) * free
        let rise: CGFloat = metrics.box / 2 + metrics.radius + out * metrics.travel
        let waiting: Bool = active && !dragging && !reduceMotion
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !waiting)) { context in
            let t: Double = context.date.timeIntervalSinceReferenceDate
            let bob: CGFloat = waiting ? CGFloat(sin(t * 2.6) + 1.0) * 3.0 * free : 0.0
            Circle()
                .fill(DazuStartPull.dotColor)
                .frame(width: metrics.dotFree, height: metrics.dotFree)
                .scaleEffect(size / metrics.dotFree)
                .shadow(color: DazuStartPull.dotColor.opacity(active ? 0.5 : 0.0),
                        radius: 9.0 * free, x: 0, y: 3.0 * free)
                .opacity(isEnabled || isBusy || committed ? 1.0 : 1.0 - 0.2 * Double(free))
                .offset(y: bob)
        }
        .animation(.easeInOut(duration: 0.25), value: isEnabled)
        .frame(width: DazuStartPull.touch, height: DazuStartPull.touch)
        .contentShape(Rectangle())
        .offset(y: DazuStartPull.touch / 2 - rise)
        .highPriorityGesture(pull)
        // Sitzt der Punkt im Ring, bleibt die Tab-Leiste darunter bedienbar.
        .allowsHitTesting(opened && !committed && !isBusy)
    }

    // MARK: Ziehen

    private var pull: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { value in
                guard opened, !spent, !committed, !isBusy else { return }
                if !dragging {
                    dragging = true
                    dragEnabled = isEnabled
                }
                let pulled: CGFloat = min(max(value.translation.height, 0.0) / metrics.travel, 1.0)
                if dragEnabled {
                    out = 1.0 - pulled
                    if pulled >= 1.0 {
                        spent = true
                        commit()
                    }
                } else {
                    // Formular unvollständig: der Punkt gibt nur ein Stück nach.
                    out = 1.0 - pulled * 0.14
                }
            }
            .onEnded { value in
                guard dragging, !spent, !committed else { return }
                dragging = false
                guard opened, !isBusy else { return }
                let pulled: CGFloat = min(max(value.translation.height, 0.0) / metrics.travel, 1.0)
                if dragEnabled && isEnabled && pulled >= 0.6 {
                    commit()
                } else if pulled < 0.06 {
                    nudge()
                } else {
                    if !dragEnabled {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { out = 1.0 }
                }
            }
    }

    /// Nur angetippt statt gezogen: der Punkt zeigt kurz, wohin es geht.
    private func nudge() {
        let token = run
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            out = isEnabled ? 0.7 : 0.9
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard token == run, !committed, !dragging else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { out = 1.0 }
        }
    }

    private func commit() {
        guard !committed else { return }
        committed = true
        dragging = false
        run += 1
        let token = run
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { out = 0.0 }
        // Der Ring bleibt offen: mit dem Punkt in der Lücke dreht sich das
        // Zeichen zurück in die Lage des Logos.
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.12)) { opened = false }
        onStart()
        // Wurde nichts gestartet (Hinweis, Abbruch, Rückfrage), dreht sich
        // der Ring wieder auf und der Punkt springt zurück.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard token == run, !busyNow else { return }
            reopen()
        }
    }

    private func reopen() {
        run += 1
        committed = false
        dragging = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { opened = true }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.55).delay(0.25)) { out = 1.0 }
    }

    private func appear() {
        run += 1
        let token = run
        busyNow = isBusy
        committed = false
        dragging = false
        if isBusy {
            opened = false
            out = 0.0
            return
        }
        if reduceMotion {
            opened = true
            out = 1.0
            return
        }
        opened = false
        out = 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard token == run else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) { opened = true }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.52).delay(0.3)) { out = 1.0 }
        }
    }

    // MARK: Texte

    private static var german: Bool {
        (UserDefaults.standard.string(forKey: "appLanguage") ?? "de") == "de"
    }

    static var title: String { german ? "Runde starten" : "Start plan" }

    static var notReady: String {
        german ? "Gib zuerst an, was ihr macht, und wähle einen Ort."
               : "First enter what you're doing and pick a location."
    }

    static func hint(busy: Bool) -> String {
        if busy { return tr("create.starting") }
        return tr("create.drag_dot")
    }
}

// MARK: - Runde starten in der Tab-Leiste

/// Verbindet das Formular (CreateDropView) mit dem Zeichen in der Tab-Leiste.
final class DazuTabLink: ObservableObject {
    static let shared = DazuTabLink()

    /// Auf false setzen, dann liegt die Steuerung im Formular statt in der
    /// Tab-Leiste.
    static let inTabBar = true

    /// Kantenlänge des Tab-Icons (tab-dazu.svg).
    static let iconSize: CGFloat = 28
    /// Platz, den das Formular unten für die Bahn des Punkts frei lässt.
    static let laneHeight: CGFloat = 122

    /// Mitte des dazu-Icons in der Tab-Leiste, im Koordinatensystem von
    /// DazuTabMark. nil, solange sie nicht ermittelt ist.
    @Published private(set) var iconCenter: CGPoint? = nil
    /// Formular vollständig.
    @Published var canStart = false
    /// Runde wird gerade erstellt.
    @Published var isBusy = false
    /// Startet die Runde; das Formular setzt sie bei jedem Neuzeichnen.
    var start: (() -> Void)? = nil

    private var candidate: CGPoint? = nil
    private var misses = 0

    /// Die Lage des Icons ist bekannt, die Steuerung kann in die Tab-Leiste.
    var usesTabBar: Bool {
        DazuTabLink.inTabBar && iconCenter != nil
    }

    /// Nimmt eine Messung an. Ein neuer Wert gilt erst, wenn er zweimal
    /// hintereinander gemessen wurde; so zählen Zwischenstände einer
    /// Animation der Tab-Leiste nicht. Ist die Tab-Leiste da, das Icon aber
    /// dreimal in Folge nicht zu finden (`center` nil), gilt die Lage als
    /// unbekannt und die Steuerung liegt wieder im Formular.
    func report(center: CGPoint?) {
        guard let center else {
            candidate = nil
            misses += 1
            if misses >= 3 && iconCenter != nil { iconCenter = nil }
            return
        }
        misses = 0
        if let now = iconCenter, DazuTabLink.near(now, center) {
            candidate = nil
            return
        }
        if let waiting = candidate, DazuTabLink.near(waiting, center) {
            candidate = nil
            iconCenter = center
        } else {
            candidate = center
        }
    }

    private static func near(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 0.75 && abs(a.y - b.y) < 0.75
    }

    /// Durchsichtiges Tab-Icon: hält den Platz frei, während DazuTabMark das
    /// Zeichen selbst zeichnet.
    static let clearIcon: UIImage = {
        let size = CGSize(width: iconSize, height: iconSize)
        return UIGraphicsImageRenderer(size: size).image { _ in }
            .withRenderingMode(.alwaysOriginal)
    }()

}

/// Steht in CreateDropView dort, wo früher der Knopf war. Liegt die
/// Steuerung in der Tab-Leiste, meldet diese Ansicht nur den Stand des
/// Formulars dorthin und hält die Bahn des Punkts frei. Sonst zeigt sie die
/// Steuerung selbst.
struct DazuStartControl: View {
    /// CreateDropView läuft als Tab (nicht als Sheet).
    let inTab: Bool
    let isEnabled: Bool
    let isBusy: Bool
    let onStart: () -> Void

    @ObservedObject private var link = DazuTabLink.shared
    /// Die Tastatur verdeckt die Tab-Leiste; so lange liegt die Steuerung
    /// im Formular.
    @State private var keyboardUp = false

    var body: some View {
        let _ = keep()
        // VStack statt Group: onAppear/onDisappear gelten für den Rahmen und
        // nicht für jeden Zweig einzeln. Sonst löscht beim Wechsel zwischen
        // Bahn und Steuerung (Tastatur auf/zu) das Abmelden des alten Zweigs
        // den Stand, den der neue gerade gemeldet hat.
        VStack(spacing: 0) {
            if inTab && link.usesTabBar && !keyboardUp {
                Color.clear
                    .frame(height: DazuTabLink.laneHeight)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            } else {
                DazuStartPull(isEnabled: isEnabled, isBusy: isBusy, onStart: onStart)
            }
        }
        .onAppear { push() }
        .onChange(of: isEnabled) { _, _ in push() }
        .onChange(of: isBusy) { _, _ in push() }
        .onChange(of: keyboardUp) { _, _ in push() }
        .onChange(of: link.usesTabBar) { _, _ in push() }
        .onDisappear {
            guard inTab else { return }
            link.start = nil
            if link.canStart { link.canStart = false }
            if link.isBusy { link.isBusy = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
    }

    /// Hält die Start-Aktion aktuell (kein veröffentlichter Wert, deshalb
    /// beim Zeichnen erlaubt).
    private func keep() {
        if inTab { link.start = onStart }
    }

    private func push() {
        guard inTab else { return }
        if link.canStart != isEnabled { link.canStart = isEnabled }
        if link.isBusy != isBusy { link.isBusy = isBusy }
    }
}

/// Das dazu-Zeichen in der Tab-Leiste, solange der dazu-Tab offen ist: liegt
/// genau auf dem Tab-Icon, dreht sich auf, der Punkt springt in den
/// Zeichnet das TabDazu-Logo rotierend direkt über dem mittleren Tab-Icon,
/// solange eine Runde live ist. Overlay statt tabItem-Icon, weil UITabBar
/// SwiftUI-Rotation im tabItem-Slot wegsnapshotet — als normales SwiftUI
/// Overlay auf TabView läuft die Animation hingegen flüssig weiter.
struct DazuLiveSpinOverlay: View {
    /// Eine Runde ist aktiv — Icon dreht sich.
    let active: Bool
    /// `true` während der mittlere Tab ausgewählt ist, damit wir die
    /// Markenfarben-Variante zeichnen (sonst Template, damit die TabBar
    /// den Idle-Tint anwendet — Overlay bringt keinen eigenen Tint mit).
    let selected: Bool

    @ObservedObject private var link = DazuTabLink.shared

    var body: some View {
        GeometryReader { _ in
            if active, link.usesTabBar, let center = link.iconCenter {
                SpinningDazu(selected: selected)
                    .position(center)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }

    private struct SpinningDazu: View {
        let selected: Bool

        var body: some View {
            TimelineView(.animation) { ctx in
                content(for: ctx.date)
            }
        }

        private func content(for date: Date) -> some View {
            let degrees = (date.timeIntervalSinceReferenceDate * 180)
                .truncatingRemainder(dividingBy: 360)
            // Kein deckender Hintergrund mehr: das Tab-Item hat im Live-
            // Modus ein transparentes `clearIcon`, deshalb darf das Overlay
            // ohne Pfropf drüberliegen und zeigt die TabBar-Fläche durch.
            return icon
                .frame(width: DazuTabLink.iconSize,
                       height: DazuTabLink.iconSize)
                .rotationEffect(.degrees(degrees))
        }

        @ViewBuilder
        private var icon: some View {
            // Aktive Runde = immer die farbige Variante — der laufende
            // Zustand soll aus jedem Tab sichtbar bleiben, nicht nur wenn
            // der dazu-Tab ausgewählt ist. Vorher: nur bei selected, sonst
            // grauer Idle-Tint, was den Live-Status unsichtbar machte.
            Image("TabDazuAktiv")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
        }
    }
}

/// Bildschirm und wird zum Starten zurück in den Ring gezogen.
/// Liegt als Overlay über der TabView (MainTabView).
struct DazuTabMark: View {
    /// dazu-Tab gewählt und das Formular ist zu sehen (keine laufende Runde).
    let active: Bool

    @ObservedObject private var link = DazuTabLink.shared

    var body: some View {
        // Die Sonde sitzt im Ursprung dieser Fläche und misst in ihren
        // eigenen Koordinaten; damit stimmt die Lage auch, während ein Sheet
        // die Ansicht dahinter verkleinert.
        GeometryReader { _ in
            DazuTabBarProbe()
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if active, DazuStartPull.isOn, link.usesTabBar, let center = link.iconCenter {
                let m = DazuStartPull.Metrics.tab(icon: DazuTabLink.iconSize)
                DazuStartPull(metrics: m,
                              isEnabled: link.canStart,
                              isBusy: link.isBusy,
                              onStart: { link.start?() })
                    .frame(width: 140, height: m.height)
                    .position(x: center.x,
                              y: center.y + m.box / 2 - m.height / 2)
            }
        }
        .ignoresSafeArea()
    }
}

/// Ermittelt, wo das mittlere Icon der Tab-Leiste sitzt, und meldet es an
/// DazuTabLink. Sucht in der Tab-Leiste die Bildfläche des mittleren Eintrags;
/// findet sich keine, hilft die Beschriftung darunter.
struct DazuTabBarProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ uiView: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        private var timer: Timer?
        private weak var bar: UITabBar?
        private var ticks = 0
        /// Das Icon selbst wurde schon einmal gefunden; ab dann zählt die
        /// ungenauere Schätzung über die Beschriftung nicht mehr.
        private var foundIcon = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            timer?.invalidate()
            timer = nil
            guard window != nil else { return }
            let ticker = Timer(timeInterval: 0.15, target: self, selector: #selector(tick),
                               userInfo: nil, repeats: true)
            RunLoop.main.add(ticker, forMode: .common)
            timer = ticker
        }

        /// Solange die Lage unbekannt ist, wird oft gemessen, danach selten.
        @objc private func tick() {
            ticks += 1
            if DazuTabLink.shared.iconCenter != nil && ticks % 4 != 0 { return }
            measure()
        }

        private func measure() {
            guard let window = window else { return }
            if bar == nil || bar?.window !== window {
                bar = ProbeView.firstTabBar(in: window)
            }
            guard let bar = bar, !bar.isHidden, bar.alpha > 0.01 else { return }
            let barFrame: CGRect = bar.convert(bar.bounds, to: self)
            let barMid: CGFloat = barFrame.midX
            var icons: [CGPoint] = []
            var labels: [CGPoint] = []      // x = Mitte, y = Oberkante der Beschriftung
            ProbeView.visit(bar) { view in
                let size: CGSize = view.bounds.size
                if view is UIImageView {
                    if size.width >= 16, size.width <= 44, size.height >= 16, size.height <= 44 {
                        icons.append(view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: self))
                    }
                } else if view is UILabel {
                    if size.height >= 8, size.height <= 20, size.width > 4 {
                        let frame: CGRect = view.convert(view.bounds, to: self)
                        labels.append(CGPoint(x: frame.midX, y: frame.minY))
                    }
                }
            }
            var center: CGPoint? = nil
            if let icon = ProbeView.middle(of: icons, barMid: barMid) {
                foundIcon = true
                center = icon
            } else if let label = ProbeView.middle(of: labels, barMid: barMid) {
                if foundIcon { return }
                center = CGPoint(x: label.x, y: label.y - 2.0 - DazuTabLink.iconSize / 2)
            }
            // Nur eine Lage innerhalb der Tab-Leiste zählt.
            if let found = center, !barFrame.insetBy(dx: 0, dy: -4).contains(found) {
                center = nil
            }
            DazuTabLink.shared.report(center: center)
        }

        /// Der mittlere von mehreren nebeneinander liegenden Einträgen. Die
        /// Einträge der Tab-Leiste sind verschieden breit, der mittlere sitzt
        /// deshalb nicht genau in der Mitte der Leiste.
        private static func middle(of points: [CGPoint], barMid: CGFloat) -> CGPoint? {
            var columns: [CGPoint] = []
            for point in points.sorted(by: { $0.x < $1.x }) {
                if let last = columns.last, abs(point.x - last.x) < 6 { continue }
                columns.append(point)
            }
            var hit: CGPoint? = nil
            if columns.count >= 3 && columns.count % 2 == 1 {
                hit = columns[columns.count / 2]
            } else {
                hit = columns.min(by: { abs($0.x - barMid) < abs($1.x - barMid) })
            }
            if let found = hit, abs(found.x - barMid) > 40 { return nil }
            return hit
        }

        private static func firstTabBar(in view: UIView) -> UITabBar? {
            if let bar = view as? UITabBar { return bar }
            for child in view.subviews {
                if let bar = firstTabBar(in: child) { return bar }
            }
            return nil
        }

        /// Geht alle sichtbaren Ansichten durch; versteckte samt Inhalt nicht.
        private static func visit(_ view: UIView, _ body: (UIView) -> Void) {
            if view.isHidden || view.alpha < 0.01 { return }
            body(view)
            for child in view.subviews { visit(child, body) }
        }
    }
}

// MARK: - Umgebung: leere Liste (animiert)

/// Animierte Fassung von `LeerTreffen`: Straßen im Hintergrund, der offene
/// Ring schwebt leicht, der Punkt fliegt mit seiner Spur immer wieder auf die
/// Lücke zu und wieder zurück, die kleinen Punkte leuchten auf.
/// Gezeichnet im 720×540-Raster der Vorlage, Seitenverhältnis 4:3.
/// Mit „Bewegung reduzieren" steht die Grafik still.
struct DazuNearbyEmptyArt: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { ctx in
            let t: Double = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                draw(g, size: size, t: t)
            }
        }
        .aspectRatio(720.0 / 540.0, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var dark: Bool { scheme == .dark }
    private var road: Color {
        dark ? Color(red: 0.176, green: 0.145, blue: 0.341) : Color(red: 0.902, green: 0.882, blue: 0.996)
    }
    private var speck: Color {
        dark ? Color(red: 0.545, green: 0.502, blue: 0.784) : Color(red: 0.851, green: 0.824, blue: 0.992)
    }
    private var floor: Color {
        dark ? Color(red: 0.690, green: 0.659, blue: 0.855) : Color(red: 0.890, green: 0.871, blue: 0.988)
    }

    private func draw(_ g: GraphicsContext, size: CGSize, t: Double) {
        let k: CGFloat = min(size.width / 720, size.height / 540)
        let ox: CGFloat = (size.width - 720 * k) / 2
        let oy: CGFloat = (size.height - 540 * k) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * k, y: oy + y * k) }

        // Straßen
        var roads = Path()
        roads.move(to: p(182, -10)); roads.addQuadCurve(to: p(128, 550), control: p(200, 300))
        roads.move(to: p(580, -10)); roads.addQuadCurve(to: p(615, 550), control: p(560, 300))
        roads.move(to: p(-10, 375)); roads.addCurve(to: p(730, 325), control1: p(250, 330), control2: p(470, 440))
        g.stroke(roads, with: .color(road), style: StrokeStyle(lineWidth: 38 * k, lineCap: .butt))

        // Kleine Punkte im Hintergrund, leuchten versetzt auf
        let specks: [(CGFloat, CGFloat, CGFloat)] = [(288, 78, 12), (90, 180, 15), (666, 444, 15)]
        for (i, s) in specks.enumerated() {
            let w: Double = 0.5 + 0.5 * sin(t * 1.7 + Double(i) * 2.1)
            let r: CGFloat = s.2 * CGFloat(0.85 + 0.25 * w) * k
            let c = p(s.0, s.1)
            g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                   with: .color(speck.opacity(0.55 + 0.45 * w)))
        }

        // Takt: 3,6 s. Ring schwebt, Punkt nimmt Anlauf auf die Lücke.
        let period: Double = 3.6
        let ph: Double = (t.truncatingRemainder(dividingBy: period)) / period
        let bob: CGFloat = CGFloat(sin(2 * .pi * ph)) * 10
        let u: Double = min(max((ph - 0.42) / 0.36, 0), 1)
        let bump: Double = pow(sin(.pi * u), 2)

        // Schatten unter dem Ring
        let sw: CGFloat = 228 * (1 + bob * 0.006) * k
        let sh: CGFloat = 36 * (1 + bob * 0.006) * k
        let sc = p(360, 473)
        g.fill(Path(ellipseIn: CGRect(x: sc.x - sw / 2, y: sc.y - sh / 2, width: sw, height: sh)),
               with: .color(floor.opacity(Double(0.9 + bob * 0.01))))

        // Offener Ring (Lücke oben rechts wie im Logo)
        let cx: CGFloat = 360, cy: CGFloat = 275 + bob, rr: CGFloat = 120
        var ring = Path()
        for j in 0...96 {
            let a = (-1.0 + 266.0 * Double(j) / 96.0) * .pi / 180
            let q = p(cx + rr * CGFloat(cos(a)), cy + rr * CGFloat(sin(a)))
            if j == 0 { ring.move(to: q) } else { ring.addLine(to: q) }
        }
        g.stroke(ring, with: .color(.brandViolet), style: StrokeStyle(lineWidth: 60 * k, lineCap: .round, lineJoin: .round))

        // Punkt mit Spur
        let ang: Double = -48 * .pi / 180
        let reach: CGFloat = CGFloat(1.54 - 0.36 * bump)
        let dx: CGFloat = cx + rr * reach * CGFloat(cos(ang))
        let dy: CGFloat = cy + rr * reach * CGFloat(sin(ang))
        let trail: [(CGFloat, CGFloat, CGFloat)] = [(54, -17, 6.5), (76, -37, 7), (100, -54, 7.5), (127, -67, 7.5), (156, -72, 7)]
        let stretch: CGFloat = CGFloat(1 + 0.45 * bump)
        for (i, d) in trail.enumerated() {
            let c = p(dx + d.0 * stretch, dy + d.1 * stretch)
            let r: CGFloat = d.2 * k
            g.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.1, y: c.y - r, width: 2.2 * r, height: 2 * r)),
                   with: .color(Color.brandOrange.opacity(1 - Double(i) * 0.13)))
        }
        let dr: CGFloat = 40 * CGFloat(1 + 0.05 * bump) * k
        let dc = p(dx, dy)
        g.fill(Path(ellipseIn: CGRect(x: dc.x - dr, y: dc.y - dr, width: 2 * dr, height: 2 * dr)),
               with: .color(.brandOrange))
    }
}
