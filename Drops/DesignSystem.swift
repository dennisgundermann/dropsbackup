import SwiftUI

// MARK: - Color Palette

extension Color {
    // Flächen: neutrale iOS-Systemhintergründe. Die Creme-/Lavendel-/Nacht-
    // Flächen aus dem Redesign 10/2026 sind wieder entfernt.
    /// Primärer Hintergrund — Creme statt reinem Weiß im Light-Mode.
    static let bgPrimary     = Color.adaptive(light: (1.000, 0.965, 0.918),   // #FFF6EA Creme
                                              dark:  (0.090, 0.067, 0.180))   // #17112E Nacht
    /// Sekundärer Hintergrund — leicht wärmer als System-Grau.
    static let bgSecondary   = Color.adaptive(light: (0.969, 0.933, 0.878),   // leicht dunkler als Creme
                                              dark:  (0.140, 0.110, 0.230))
    static let bgTertiary    = Color(UIColor.tertiarySystemBackground)
    /// Seitenhintergrund gruppierter Screens.
    /// Grouped-Hintergrund (für Sheets/Modals) — Creme statt kaltem Grau.
    static let bgGrouped     = Color.adaptive(light: (1.000, 0.965, 0.918),   // #FFF6EA Creme
                                              dark:  (0.090, 0.067, 0.180))
    /// Karten auf gruppierten Screens.
    static let bgCard        = Color(UIColor.secondarySystemGroupedBackground)
    /// Marken-Violett. Im Dark Mode heller, damit Text/Icons in `.brand`
    /// auf dunklem Grund lesbar bleiben (Redesign 10/2026, vorher Grün #3FB852).
    static let brand         = Color.adaptive(light: (0.357, 0.239, 0.961),   // #5B3DF5
                                              dark:  (0.522, 0.439, 1.000))   // #8570FF
    static let brandInverse  = Color.white
    static let accentGreen   = brandMint
    static let accentRed     = Color(hex: "FF3B30")
    /// Warmer Akzent (Koralle) — mappt auf brandCoral.
    static let accentOrange  = brandCoral
    /// Haupttext: Nacht statt reinem Schwarz, im Dark Mode Weiß.
    static let textPrimary   = Color.adaptive(light: (0.090, 0.067, 0.180),   // #17112E
                                              dark:  (1.000, 1.000, 1.000))
    static let textSecondary = Color(UIColor.secondaryLabel)
    static let textTertiary  = Color(UIColor.tertiaryLabel)
    static let textMuted     = Color(UIColor.quaternaryLabel)
    /// Live-/Online-Status in Marken-Mint.
    static let onlineGreen   = brandMint
    /// Community-Marker — jetzt in Mint statt Clero-Grün für konsistente Palette.
    static let cleroGreen    = brandMint
    static let glassBorder   = Color(UIColor.separator)

    // Marken-Palette (Redesign 10/2026) — Violett + Mint, dazu Creme, Nacht,
    // Lavendel und Koralle. Direkt-RGB statt Color(hex:), damit die Tokens bei
    // Hex→Token-Migrationen nicht durch replace_all selbst zerschossen werden.
    static let brandViolet      = Color(red: 0.357, green: 0.239, blue: 0.961) // #5B3DF5
    static let brandVioletLight = Color(red: 0.486, green: 0.361, blue: 1.000) // #7C5CFF
    /// „dazu"-Orange: zweite Hauptfarbe (statt Mint seit Rebrand).
    static let brandOrange      = Color(red: 1.000, green: 0.627, blue: 0.180) // #FFA02E
    /// Mint bleibt als Alias auf Orange — damit alle Call-Sites automatisch
    /// die neue Palette bekommen ohne manuellen Rename.
    static let brandMint        = brandOrange
    static let brandCream       = Color(red: 1.000, green: 0.965, blue: 0.918) // #FFF6EA
    /// „Nacht" als TEXT-Farbe — adaptiv: dunkel im Light-Mode, Creme im Dark-Mode.
    /// Dadurch sind alle Haupt-Texte in beiden Modi lesbar.
    static let brandNight       = Color.adaptive(light: (0.090, 0.067, 0.180),  // #17112E Nacht
                                                  dark:  (1.000, 0.965, 0.918))  // #FFF6EA Creme
    /// Fixer dunkler Nacht-Wert (für backgrounds etc. die immer dunkel sein müssen).
    static let brandNightFixed  = Color(red: 0.090, green: 0.067, blue: 0.180)
    static let brandLavender    = Color(red: 0.914, green: 0.890, blue: 1.000) // #E9E3FF
    /// Koralle (deprecated — zugunsten Orange). Zeigt auf brandOrange.
    static let brandCoral       = brandOrange

    // Legacy Aurora-Namen → zeigen alle auf die neue Drops-Palette.
    // Dadurch rebrandet die ganze App automatisch — jede View die aurora*
    // nutzt bekommt sofort das neue Look-and-Feel ohne Code-Änderung.
    static let auroraOrange    = brandViolet            // war Icon-Anker, jetzt Primary
    static let auroraGreen     = brandMint              // war Icon-Anker, jetzt Live-Accent
    static let auroraAmber     = brandCoral             // war Boost-Amber, jetzt Koralle
    static let auroraGoldLight = brandCoral             // ehemalige Drops+ Gold
    static let auroraGoldDark  = brandCoral.opacity(0.75)
    static let auroraPink      = brandCoral             // war Rose-Glow
    static let auroraViolet    = brandVioletLight       // war Lavender
    static let auroraCyan      = brandMint              // war Cyan
    static let auroraTeal      = brandMint              // war Teal
    static let auroraBlue      = brandViolet            // war Blue
    static let auroraPurple    = Color(red: 0.659, green: 0.333, blue: 0.969) // #a855f7 (purple)
    static let auroraCoral     = Color(red: 1.000, green: 0.478, blue: 0.349) // #FF7A59 (Marken-Koralle)

    /// Farbe mit eigener Hell-/Dunkel-Variante (RGB 0…1).
    static func adaptive(light: (Double, Double, Double),
                         dark: (Double, Double, Double)) -> Color {
        Color(UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(c.0), green: CGFloat(c.1), blue: CGFloat(c.2), alpha: 1)
        })
    }

    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Radius Tokens
/// 3-stufige Eckenradius-Skala. Einheitlich in der gesamten App.
/// SM: Badges, Chips, Icons. MD: Cards, Rows, Sections. LG: Hero-Cards, Sheets.
enum Radius {
    static let sm: CGFloat   = 8   // kleine Chips, Tags
    static let md: CGFloat   = 12  // Input-Felder, Capsules
    static let card: CGFloat = 14  // Standard-Card-Radius
    static let lg: CGFloat   = 16  // Container, Sheets
    static let xl: CGFloat   = 20  // Hero-Elemente, große Sheets
}

// MARK: - Typography Scale
/// Semantische Font-Größen. Statt 25+ Magic Numbers überall dieselben 6 Stufen.
extension Font {
    static let dsCaption2 = Font.system(size: 10, weight: .regular)
    static let dsCaption  = Font.system(size: 12, weight: .regular)
    static let dsBody     = Font.system(size: 14, weight: .regular)
    static let dsBodySemi = Font.system(size: 15, weight: .semibold)
    static let dsHeadline = Font.system(size: 17, weight: .semibold)
    static let dsTitle    = Font.system(size: 20, weight: .bold, design: .rounded)
}

// MARK: - Shadow Presets
/// Dreistufiges Elevations-System. Ergibt konsistente Tiefe ohne Magic Numbers.
extension View {
    /// Elevation 1 — subtile Chips, Badges.
    func shadowSm(color: Color = .black) -> some View {
        self.shadow(color: color.opacity(0.12), radius: 4, x: 0, y: 2)
    }
    /// Elevation 2 — Standard-Karten, Buttons.
    func shadowMd(color: Color = .black) -> some View {
        self.shadow(color: color.opacity(0.14), radius: 8, x: 0, y: 3)
    }
    /// Elevation 3 — Hero-Elemente, Popovers.
    func shadowLg(color: Color = .black) -> some View {
        self.shadow(color: color.opacity(0.18), radius: 16, x: 0, y: 6)
    }
    /// Aurora-Glow — Brand-Gradient-Buttons (Violett).
    func auroraGlow(active: Bool, color: Color = .brand) -> some View {
        self.shadow(color: active ? color.opacity(0.35) : .clear, radius: 10, x: 0, y: 4)
    }
}

// MARK: - Aurora Gradient Helper
extension LinearGradient {
    /// Standard-Aurora-Gradient (helles Violett → Marken-Violett) — für Primary-CTAs.
    static let aurora = LinearGradient(
        colors: [Color.auroraOrange, Color.auroraGreen],
        startPoint: .leading, endPoint: .trailing
    )
    /// Sunset-Variante (Violett → Pink) — für sekundäre Hero-Elemente.
    static let sunset = LinearGradient(
        colors: [Color.auroraOrange, Color.auroraPink],
        startPoint: .leading, endPoint: .trailing
    )
}

// MARK: - Liquid Glass Helpers (iOS 26+)
//
// iOS 27 Note: Apple hat den Glass-Rendering-Algorithmus in iOS 27 verbessert
// (mehr Kontrast, einheitlichere Refraktion). Das System-Slider-Setting für
// „Ultraklar bis vollständig getönt" wird von `.glassEffect()` automatisch
// respektiert — kein App-seitiger Code nötig.

/// ViewModifier für `liquidGlass`. Wrapped als Modifier mit
/// @Environment(\.colorScheme), damit das `.glassEffect()` zwingend
/// neu gerendert wird, wenn der User die App-Darstellung umschaltet.
/// Vorher behielt der Glass-Block sein Hell-Material-Rendering nach
/// Wechsel auf Dunkel — `.id(colorScheme)` erzwingt ein clean re-mount.
private struct LiquidGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    func body(content: Content) -> some View {
        // Flat Card mit Lavendel-Tint — passt zum Dazu-Design, kein hartes Weiß.
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(scheme == .dark
                          ? Color.brandViolet.opacity(0.15)
                          : Color.brandLavender.opacity(0.55))
                    .shadow(color: Color.brandViolet.opacity(scheme == .dark ? 0.12 : 0.05),
                            radius: 8, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.brandViolet.opacity(scheme == .dark ? 0.25 : 0.10),
                            lineWidth: 0.5)
            )
            .id(scheme)
    }
}

extension View {
    /// Applies Liquid Glass background — uses native .glassEffect() on iOS 26+
    /// (including iOS 27 with improved rendering), falls back to thinMaterial on earlier OS.
    func liquidGlass(cornerRadius: CGFloat = 18, shadowRadius: CGFloat = 16) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, shadowRadius: shadowRadius))
    }

    /// Drops Chip Style — konsistente Pills im Create-Flow + überall.
    /// isLive=true nutzt Mint (für „Jetzt"-ähnliche Live-States),
    /// sonst Violett. Inactive = Lavendel-Pill.
    func dropsChip(isActive: Bool, isLive: Bool = false) -> some View {
        modifier(DropsChipModifier(isActive: isActive, isLive: isLive))
    }

    /// Press-Animation + leichter Haptic — macht jeden Button lebendig.
    /// Spring-Scale beim Drücken, Haptic.selection() beim Release.
    func dropsPressable(scale: CGFloat = 0.93) -> some View {
        buttonStyle(DropsPressableButtonStyle(scale: scale))
    }

    /// Primary CTA — großer Violett→Mint Gradient-Button mit Press-Animation.
    /// Nutzung: Button(action: ...) { Text("Weiter") }.dropsPrimaryButton()
    func dropsPrimaryButton(isLoading: Bool = false, isEnabled: Bool = true) -> some View {
        modifier(DropsPrimaryButtonModifier(isLoading: isLoading, isEnabled: isEnabled))
    }

    /// Capsule Pill — flat, plattform-agnostisch (Flutter-portierbar).
    func liquidGlassCapsule(shadowRadius: CGFloat = 10) -> some View {
        self
            .background(
                Capsule().fill(Color.white.opacity(0.75))
                    .shadow(color: Color.brandNight.opacity(0.08),
                            radius: shadowRadius * 0.6, x: 0, y: 3)
            )
            .overlay(
                Capsule().stroke(Color.brandNight.opacity(0.08), lineWidth: 0.5)
            )
    }

    /// Circle — flat, plattform-agnostisch.
    func liquidGlassCircle(shadowRadius: CGFloat = 10) -> some View {
        self
            .background(
                Circle().fill(Color.white.opacity(0.78))
                    .shadow(color: Color.brandNight.opacity(0.08),
                            radius: shadowRadius * 0.6, x: 0, y: 3)
            )
            .overlay(
                Circle().stroke(Color.brandNight.opacity(0.08), lineWidth: 0.5)
            )
    }

    /// Sheet background — ultraThinMaterial für Frosted-Glass-Effekt,
    /// so die Karte dahinter leicht sichtbar bleibt.
    @ViewBuilder
    func sheetBackground() -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackground(Color.brandCream)
        } else {
            self
        }
    }
}

// MARK: - GlassCard

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    let content: Content
    init(cornerRadius: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    var body: some View {
        content
            .liquidGlass(cornerRadius: cornerRadius)
    }
}

// MARK: - Primary Button (Brand Green, no glass)

// MARK: - Aurora Card Border

/// Animierter Aurora-Rand für Karten/Sections.
/// Gleiche Farbpalette und Geschwindigkeit wie der Aurora-Button.
struct AuroraCardBorder: View {
    var cornerRadius: CGFloat = 18
    var lineWidth: CGFloat = 1.5

    @State private var hue: Double = 0

    // Animierter Border — Palette aufs App-Icon abgestimmt: Violett,
    // Koralle-Übergang, Mint, zusätzlicher Lavendel-Akzent. Loop endet
    // mit der Start-Farbe, damit der Hue-Rotation-Cycle nahtlos läuft.
    private let gradient: AngularGradient = .init(
        colors: [
            Color.auroraOrange, Color.auroraCoral,
            Color.auroraGreen, Color.brandMint,
            Color.brandLavender, Color.auroraOrange,
        ],
        center: .center
    )

    var body: some View {
        ZStack {
            // Weicher Glow (verschwommene breite Linie)
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(gradient, lineWidth: lineWidth + 4)
                .hueRotation(.degrees(hue))
                .blur(radius: 5)
                .opacity(0.38)
            // Scharfe Mittellinie
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(gradient, lineWidth: lineWidth)
                .hueRotation(.degrees(hue))
                .opacity(0.65)
        }
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                hue = 360
            }
        }
    }
}

// MARK: - Aurora Drop Button (animiert, kein Emoji)

struct AuroraDropButton: View {
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        Button(action: { guard isEnabled && !isLoading else { return }; action() }) {
            ZStack {
                // Flat dazu-Button: solid Violett, kein Aurora-Gradient.
                Capsule()
                    .fill(Color.brandViolet)

                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    HStack(spacing: 8) {
                        Text("Komm dazu")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(AuroraButtonStyle())
    }
}

private struct AuroraButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Group {
                if isLoading { ProgressView().tint(Color.brandInverse) }
                else {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
            }
            .foregroundColor(Color.brandInverse)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                Capsule()
                    .fill(Color.brand)
                    .shadow(color: Color.brand.opacity(0.35), radius: 12, x: 0, y: 6)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Secondary Button (Glass)

struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .liquidGlass(cornerRadius: 50)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pulse Dot

struct PulseDot: View {
    var color: Color = .onlineGreen
    @State private var scale: CGFloat = 1.0
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.25)).frame(width: 18, height: 18)
                .scaleEffect(scale)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: scale)
            Circle().fill(color).frame(width: 10, height: 10)
        }
        .onAppear { scale = 1.5 }
    }
}

// MARK: - Avatar Badge

struct AvatarBadge: View {
    let emoji: String
    var size: CGFloat = 44
    var isAvailable: Bool = false
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.white.opacity(0.75))
                .frame(width: size, height: size)
                .overlay(Text(emoji).font(.system(size: size * 0.5)))
                .overlay(
                    Circle()
                        .stroke(isAvailable ? Color.onlineGreen : Color.clear, lineWidth: 2.5)
                        .padding(-2)
                )
            if isAvailable {
                Circle().fill(Color.onlineGreen)
                    .frame(width: size * 0.22, height: size * 0.22)
                    .overlay(Circle().stroke(Color.bgPrimary, lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
        }
    }
}

// MARK: - Section Label

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(.textTertiary)
            .kerning(0.8)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

// MARK: - Activity Chip (Glass)

struct ActivityChip: View {
    let title: String
    var isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(isSelected ? Color.brandInverse : .textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(
                    Group {
                        if isSelected {
                            Capsule().fill(Color.brand)
                                .shadow(color: Color.brand.opacity(0.3), radius: 8, y: 3)
                        } else {
                            Capsule().fill(Color.white.opacity(0.75))
                        }
                    }
                )
                .overlay(
                    {
                        let borderStyle: AnyShapeStyle = isSelected
                            ? AnyShapeStyle(Color.clear)
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [.white.opacity(0.4), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                              )
                        return AnyView(
                            Capsule()
                                .stroke(borderStyle, lineWidth: 0.8)
                        )
                    }()
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25), value: isSelected)
    }
}

// MARK: - Custom Switch (iOS 26 native Toggle)

struct CustomSwitch: View {
    let isOn: Bool
    let onToggle: () -> Void
    var body: some View {
        Toggle("", isOn: Binding(
            get: { isOn },
            set: { _ in onToggle() }
        ))
        .labelsHidden()
        .tint(Color.brand)
    }
}

// MARK: - Reliability Score

struct ReliabilityScore {
    var totalCommits: Int
    var showUps: Int
    var noShows: Int
    /// Zähler für Host-Erfolge (Drop gehostet und kam zustande — min. 1 Teilnehmer zusätzlich).
    var hostSuccesses: Int = 0
    /// Akkumulierte Bonus-Punkte.
    var streakBonusPoints: Int = 0       // +20 nach 5 Drops in Folge ohne No-Show
    var firstArrivalPoints: Int = 0      // +5 pro Mal als Erster vor Ort
    var dropInvitesPoints: Int = 0       // +5 pro Einladung die gejoint ist (Drop-Einladung)
    var newcomerHostPoints: Int = 0      // +3 pro neuem User (Drop-Entdecker) bei deinem Drop
    var appInvitesPoints: Int = 0        // +10 pro Freund der Drops neu installiert & onboarded hat
    var creationBonusPoints: Int = 0     // +5 für jeden erstellten Drop (Launch-Motivation)
    var boostBonusPoints: Int = 0        // +5 wenn Drop erstellt/bestätigt während Boost-Phase
                                          // (Umgebung leer: <5 Drops in der Nähe → extra Anreiz)
    /// Aktueller Show-Up-Streak (Anzahl Drops in Folge ohne No-Show).
    /// Jeder 5er-Block löst +20 Streak-Bonus aus; Counter läuft danach weiter (alle 5 erneut).
    var currentStreak: Int = 0
    var appLanguage: String = "de"

    // MARK: - Punktesystem (1.0.2 — höhere Werte für Launch-Phase)
    // Start 100 · Joinen+vor Ort +20 · Hosten+klappt +12 · No-Show -25
    // Boni: Streak +30, Erster +10, Drop-Einladung +10, Neuling-Host +5, App-Einladung +25
    static let startingPoints       = 100
    static let pointsPerShowUp      = 20
    static let pointsPerHostSuccess = 12
    static let pointsPerNoShow      = -25

    /// Gesamtpunktzahl — aus Ereignissen und Boni.
    /// showUps enthält historisch ALLE Anwesenheiten (Joiner + Host). hostSuccesses trennt
    /// die Host-Ankünfte raus damit sie korrekt mit 8 statt 15 Punkten verrechnet werden.
    var points: Int {
        let joinArrivals = max(0, showUps - hostSuccesses)
        return Self.startingPoints
            + joinArrivals * Self.pointsPerShowUp
            + hostSuccesses * Self.pointsPerHostSuccess
            + noShows * Self.pointsPerNoShow
            + bonusPoints
    }

    var bonusPoints: Int {
        streakBonusPoints + firstArrivalPoints + dropInvitesPoints + newcomerHostPoints + appInvitesPoints + creationBonusPoints + boostBonusPoints
    }

    /// Deckungsgleich mit badge — damit überall die gleiche Stufe erscheint.
    var label: String { badge }

    var color: Color {
        switch points {
        case ..<0:      return .accentRed
        case 0..<50:    return .accentOrange
        case 50..<200:  return Color.auroraAmber
        case 200..<500: return .onlineGreen
        default:        return .brand
        }
    }

    var badge: String {
        switch points {
        case ..<0:      return tr("tier.dropout")
        case 0..<50:    return tr("tier.restart")
        case 50..<200:  return tr("tier.explorer")
        case 200..<500: return tr("tier.regular")
        default:        return tr("tier.legend")
        }
    }

    /// SF-Symbol passend zum Tier.
    var badgeIcon: String {
        switch points {
        case ..<0:      return "exclamationmark.triangle.fill"
        case 0..<50:    return "leaf.fill"
        case 50..<200:  return "binoculars.fill"
        case 200..<500: return "star.fill"
        default:        return "crown.fill"
        }
    }

    /// Punktzahl als String fürs Hero-Label.
    var displayText: String { "\(points)" }

    /// Sekundär-Label.
    var displayLabel: String {
        totalCommits == 0 ? tr("tier.welcome") : badge
    }

    /// Wie viele Punkte bis zum nächsten Tier. nil = höchstes erreicht.
    var pointsToNextTier: Int? {
        switch points {
        case ..<0:      return -points
        case 0..<50:    return 50 - points
        case 50..<200:  return 200 - points
        case 200..<500: return 500 - points
        default:        return nil
        }
    }

    var nextTierName: String? {
        switch points {
        case ..<0:      return tr("tier.restart")
        case 0..<50:    return tr("tier.explorer")
        case 50..<200:  return tr("tier.regular")
        case 200..<500: return tr("tier.legend")
        default:        return nil
        }
    }

    /// Fortschritt (0–1) innerhalb des aktuellen Tiers bis zur nächsten Schwelle.
    var tierProgress: Double {
        switch points {
        case ..<0:      return 0
        case 0..<50:    return Double(points) / 50.0
        case 50..<200:  return Double(points - 50) / 150.0
        case 200..<500: return Double(points - 200) / 300.0
        default:        return 1.0
        }
    }

    // MARK: - Trust-Model (vereinfacht: nur ein binäres „Verlässlich"-Badge)
    //
    // Statt 5 Tier-Stufen mit Punkte-Rechnerei zeigen wir nur noch ein
    // ✓-Badge für User die eine gewisse Historie haben. Der Punkte-
    // Score läuft im Backend weiter (für Spam-Detection, später evtl.
    // wieder einblenden), ist aber im UI nicht sichtbar.

    /// Schwelle ab der ein User als „verlässlich" gilt.
    static let trustThreshold: Int = 200

    static func isTrusted(forPoints points: Int) -> Bool {
        points >= trustThreshold
    }

    /// Badge-Text — leer wenn nicht trusted. Caller zeigt das Badge nur
    /// wenn der String nicht leer ist.
    static func badge(forPoints points: Int) -> String {
        isTrusted(forPoints: points) ? tr("tier.trusted") : ""
    }

    /// Icon für das Trust-Badge — leer wenn nicht trusted.
    static func badgeIcon(forPoints points: Int) -> String {
        isTrusted(forPoints: points) ? "checkmark.seal.fill" : ""
    }

    /// Farbe für das Trust-Badge — klar wenn nicht trusted (unsichtbar).
    static func color(forPoints points: Int) -> Color {
        isTrusted(forPoints: points) ? Color.brandViolet : Color.clear
    }

    /// Progress-API bleibt für den Settings-Progress-Balken erhalten
    /// (0 bis trustThreshold → noch nicht verlässlich; danach 1).
    static func tierProgress(forPoints points: Int) -> Double {
        min(1.0, max(0.0, Double(points) / Double(trustThreshold)))
    }
}

struct ReliabilityBadgeView: View {
    let score: ReliabilityScore
    @AppStorage("appLanguage") private var appLanguage = "de"
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(score.color.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: score.badgeIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(score.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(score.badge)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("\(score.points) \(tr("design.points_short")) · \(score.showUps) Pläne")
                    .font(.system(size: 11)).foregroundColor(.textSecondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .liquidGlass(cornerRadius: 14, shadowRadius: 8)
    }
}

// MARK: - Safety Sheet

struct SafetySheetView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        NavigationView {
            ZStack {
                Color.brandCream.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color.brandLavender.opacity(0.9))
                                .frame(width: 92, height: 92)
                            Image(systemName: "shield.fill")
                                .font(.system(size: 40, weight: .heavy))
                                .foregroundColor(.brandOrange)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)

                        VStack(alignment: .leading, spacing: -2) {
                            Text("Sicher")
                                .foregroundColor(.brandNight)
                            Text("unterwegs.")
                                .foregroundColor(.brandViolet)
                        }
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 24)

                        VStack(spacing: 10) {
                            SafetyRow(icon: "star.circle.fill",
                                      title: tr("design.reliability_score"),
                                      subtitle: tr("design.no_show_30"))
                            SafetyRow(icon: "hand.raised.circle.fill",
                                      title: tr("design.one_tap_block"),
                                      subtitle: tr("design.instant_no_explanation"))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle(tr("settings.security"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(.brandViolet)
                }
            }
        }
        .presentationDetents([.fraction(0.65)])
        .sheetBackground()
    }
}

struct SafetyRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.brandViolet)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.brandLavender))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.brandNight)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .liquidGlass(cornerRadius: 18)
    }
}

// MARK: - Placeholder modifier

extension View {
    func placeholder<C: View>(when show: Bool, @ViewBuilder placeholder: () -> C) -> some View {
        ZStack(alignment: .center) {
            placeholder().opacity(show ? 1 : 0)
            self
        }
    }
}



// MARK: - Reliability Info Sheet (Premium Redesign)
// Modernes Layout: Hero-Punktekarte mit Gradient + Progress zur nächsten Stufe,
// Punkte-Events-Tabelle mit Werten, Bonus-Liste, Stufen-Übersicht, Stats.

struct ReliabilityInfoSheet: View {
    let score: ReliabilityScore
    @Environment(\.dismiss) private var dismiss
    @State private var animateProgress = false

    private let tiers: [(label: String, threshold: Int, color: Color, icon: String)] = [
        ("Ghost",         -999, .accentRed,              "exclamationmark.triangle.fill"),
        ("Neustart",         0,   .accentOrange,           "leaf.fill"),
        ("Entdecker",   50,  Color.auroraAmber,    "binoculars.fill"),
        ("Stammgast",        200, .onlineGreen,            "star.fill"),
        ("Legende",     500, .brand,                  "crown.fill"),
    ]

    private var currentTierIndex: Int {
        tiers.indices.last(where: { score.points >= tiers[$0].threshold }) ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    heroCard
                    progressCard
                    pointsEventsCard
                    bonusCard
                    tiersCard
                    statsRow
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Color.bgGrouped.ignoresSafeArea())
            .navigationTitle(tr("design.reliability"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("design.done")) { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.9).delay(0.15)) { animateProgress = true } }
        .presentationDragIndicator(.visible)
    }

    // MARK: Hero — Punkte, Tier-Icon, Gradient-Karte

    private var heroCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(score.color.opacity(0.14)).frame(width: 62, height: 62)
                Image(systemName: score.badgeIcon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(score.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(score.badge)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(score.points)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(score.color)
                    Text(tr("design.points_short"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color.bgCard,
                    in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Fortschritt zur nächsten Stufe

    @ViewBuilder private var progressCard: some View {
        if let remaining = score.pointsToNextTier, let next = score.nextTierName {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tr("design.pts_until_next").replacingOccurrences(of: "{pts}", with: "\(remaining)").replacingOccurrences(of: "{next}", with: next))
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                    Spacer()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.textTertiary.opacity(0.15))
                            .frame(height: 6)
                        Capsule()
                            .fill(score.color)
                            .frame(width: geo.size.width * (animateProgress ? CGFloat(score.tierProgress) : 0),
                                   height: 6)
                    }
                }
                .frame(height: 6)
            }
            .padding(14)
            .background(Color.bgCard,
                        in: RoundedRectangle(cornerRadius: Radius.lg))
        } else {
            HStack(spacing: 10) {
                Image(systemName: "crown.fill").foregroundColor(.brand)
                Text(tr("design.top_tier_reached"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
            }
            .padding(14)
            .background(Color.bgCard,
                        in: RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    // MARK: Punkte-Events

    private var pointsEventsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(tr("reliab.section_earn"))
            VStack(spacing: 0) {
                eventRow(icon: "figure.walk.circle.fill", color: .onlineGreen,
                         title: tr("reliab.join_show"), value: "+20")
                Divider().padding(.leading, 56)
                eventRow(icon: "plus.circle.fill", color: Color(hex: "06b6d4"),
                         title: tr("reliab.host_success"), value: "+12")
                Divider().padding(.leading, 56)
                eventRow(icon: "xmark.circle.fill", color: .accentRed,
                         title: tr("reliab.no_show"), value: "-25",
                         negative: true)
            }
        }
        .background(Color.bgCard,
                    in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Boni

    private var bonusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(tr("reliab.section_extras"))
            VStack(spacing: 0) {
                eventRow(icon: "flame.fill", color: .accentOrange,
                         title: tr("reliab.streak"), value: "+30")
                Divider().padding(.leading, 56)
                eventRow(icon: "bolt.fill", color: Color.auroraAmber,
                         title: tr("reliab.first_arrival"), value: "+10")
                Divider().padding(.leading, 56)
                eventRow(icon: "paperplane.fill", color: .brand,
                         title: tr("reliab.invitee_joins"), value: "+10")
                Divider().padding(.leading, 56)
                eventRow(icon: "sparkles", color: Color(hex: "8b5cf6"),
                         title: tr("reliab.newcomer_join"), value: "+5")
                Divider().padding(.leading, 56)
                eventRow(icon: "person.badge.plus.fill", color: Color(hex: "ec4899"),
                         title: tr("reliab.friend_installs"), value: "+25")
                Divider().padding(.leading, 56)
                eventRow(icon: "plus.app.fill", color: Color(hex: "10b981"),
                         title: tr("reliab.create_drop"), value: "+10")
                Divider().padding(.leading, 56)
                eventRow(icon: "bolt.circle.fill", color: .accentOrange,
                         title: tr("reliab.boost_phase"), value: "+15")
            }
        }
        .background(Color.bgCard,
                    in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Stufen

    private var tiersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(tr("reliab.section_tiers"))
            VStack(spacing: 0) {
                ForEach(tiers.indices, id: \.self) { i in
                    let tier = tiers[i]
                    let isNow = i == currentTierIndex
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(tier.color.opacity(isNow ? 0.22 : 0.10))
                                .frame(width: 34, height: 34)
                            Image(systemName: tier.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(tier.color)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tier.label)
                                .font(.system(size: 14, weight: isNow ? .bold : .medium))
                                .foregroundColor(isNow ? tier.color : .textPrimary)
                            Text(tierRangeText(i))
                                .font(.system(size: 11))
                                .foregroundColor(.textTertiary)
                        }
                        Spacer()
                        if isNow {
                            Text("Du")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(tier.color)
                                .padding(.horizontal, 9).padding(.vertical, 3)
                                .background(tier.color.opacity(0.15), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if i < tiers.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
        }
        .background(Color.bgCard,
                    in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func tierRangeText(_ i: Int) -> String {
        switch i {
        case 0: return "unter 0 Pkt"
        case 1: return "0 – 49 Pkt"
        case 2: return "50 – 199 Pkt"
        case 3: return "200 – 499 Pkt"
        case 4: return "ab 500 Pkt"
        default: return ""
        }
    }

    // MARK: Stats-Zeile

    private var statsRow: some View {
        HStack(spacing: 10) {
            rsStatPill(value: "\(score.showUps)", label: "Erschienen",
                       icon: "checkmark.circle.fill", color: .onlineGreen)
            rsStatPill(value: "\(score.noShows)", label: "No-Shows",
                       icon: "xmark.circle.fill", color: .accentRed)
            rsStatPill(value: "+\(score.bonusPoints)", label: "Boni",
                       icon: "star.fill", color: Color.auroraAmber)
        }
    }

    // MARK: Helper

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.textSecondary)
            .tracking(0.5)
            .textCase(.uppercase)
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
    }

    private func eventRow(icon: String, color: Color, title: String,
                          value: String, negative: Bool = false) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.14)).frame(width: 34, height: 34)
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(negative ? .accentRed : color)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

private func rsStatPill(value: String, label: String, icon: String, color: Color) -> some View {
    VStack(spacing: 4) {
        Image(systemName: icon)
            .font(.system(size: 15))
            .foregroundColor(color)
        Text(value)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(.textPrimary)
        Text(label)
            .font(.system(size: 10))
            .foregroundColor(.textSecondary)
            .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(Color.bgCard,
                in: RoundedRectangle(cornerRadius: Radius.md))
}

// MARK: - String Helpers

extension String {
    /// Ersten Buchstaben großschreiben, Rest unverändert lassen.
    /// "max" → "Max" · "MAX" → "MAX" · "" → ""
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// MARK: - Haptic Manager

/// Zentrale Haptic-Sprache für Drops.
/// Alle Funktionen dispatchen intern auf den Main Thread — sicher aus
/// Firebase-Callbacks, Combine-Streams und Background-Queues aufrufbar.
enum Haptic {

    // MARK: - Main-Thread-sicherer Dispatch

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() }
        else { DispatchQueue.main.async { work() } }
    }

    private static func onMainAfter(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() }
    }

    // MARK: - Primitive

    /// Leichte Selektion (Chips, Toggles, Picker)
    static func selection() {
        onMain { UISelectionFeedbackGenerator().selectionChanged() }
    }

    /// Einfacher Impact
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        onMain { UIImpactFeedbackGenerator(style: style).impactOccurred() }
    }

    /// System-Notification-Haptic
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(type) }
    }

    // MARK: - Semantisch

    /// Drop geht live — zwei Schläge wie Raketenstart
    static func dropCreated() {
        onMain {
            let g = UIImpactFeedbackGenerator(style: .heavy)
            g.prepare()
            g.impactOccurred()
        }
        onMainAfter(0.09) { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    /// Join-Anfrage angenommen — Freude, Dopamine-Hit
    static func joinAccepted() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        onMainAfter(0.13) { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    /// Join-Anfrage abgelehnt — klar, eindeutig
    static func joinRejected() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    }

    /// Drop beendet — finaler Abschluss
    static func dropEnded() {
        onMain { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    }

    /// BLE-Treffen bestätigt — Doppelpuls "wir sind beide da!"
    static func meetupConfirmed() {
        onMain {
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(.success)
        }
        onMainAfter(0.18) { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    /// GPS-Bestätigung — Show-Up erkannt
    static func gpsArrival() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    /// Punkte-Toast erscheint — Belohnungs-Tap
    static func pointsEarned() {
        onMain { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        onMainAfter(0.10) { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }

    /// Freundschaft bestätigt — Social Win
    static func friendAdded() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    /// Freundschaftsanfrage gesendet
    static func friendRequestSent() {
        onMain { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    /// Join-Anfrage abgeschickt
    static func joinRequestSent() {
        onMain { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    /// Incoming Join Request Sheet erscheint (Host-Seite)
    static func incomingRequest() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    }

    /// Timer auf null — scharfe finale Warnung
    static func timerExpired() {
        onMain { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    }

    /// Namensänderung genehmigt
    static func nameChangeApproved() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    /// Namensänderung abgelehnt
    static func nameChangeDenied() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    }

    /// Allgemeiner Erfolg
    static func success() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    /// Allgemeine Warnung
    static func warning() {
        onMain { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    }
}


// MARK: - Drops Chip Modifier

private struct DropsChipModifier: ViewModifier {
    let isActive: Bool
    let isLive: Bool

    func body(content: Content) -> some View {
        let tint: Color = isLive ? .brandMint : .brandViolet
        content
            .foregroundColor(isActive ? (isLive ? .brandNight : .white) : .brandNight.opacity(0.78))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(
                    isActive ? tint : Color.brandLavender.opacity(0.55)
                )
            )
            .overlay(
                Capsule().stroke(
                    isActive ? Color.clear : Color.brandViolet.opacity(0.15),
                    lineWidth: 0.8
                )
            )
            .shadow(color: isActive ? tint.opacity(0.35) : .clear, radius: 8, y: 3)
            .scaleEffect(isActive ? 1.0 : 0.98)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isActive)
    }
}

// MARK: - Drops Pressable Button Style (spring-pop + haptic)

struct DropsPressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.93
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6),
                       value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptic.selection() }
            }
    }
}

// MARK: - Drops Primary Button Modifier

private struct DropsPrimaryButtonModifier: ViewModifier {
    let isLoading: Bool
    let isEnabled: Bool

    func body(content: Content) -> some View {
        // Flat dazu-Button: solid Violett, kein Gradient / kein Hue-Rotate.
        // Konsistent mit dem rest des Designs — keine „Aurora"-Buttons mehr.
        content
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Capsule().fill(Color.brandViolet))
            .opacity(isEnabled ? 1.0 : 0.4)
            .overlay(
                Group {
                    if isLoading { ProgressView().tint(.white) }
                }
            )
    }
}
