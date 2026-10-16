import SwiftUI
import MapKit
import AuthenticationServices
import FirebaseAuth
import UserNotifications
import CoreLocation
import GoogleSignIn

// MARK: - Fake Map Background (fiktive Stadtkarte, Apple-Maps-Stil)

struct FakeMapBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height

            // ── 1. Grundfläche (Apple Maps Hellgrau) ──────────────────────
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(red: 0.918, green: 0.918, blue: 0.933)))

            // ── 2. Wohngebiete (leicht wärmeres Grau, unregelmäßige Blöcke) ─
            let residentialColor = Color(red: 0.882, green: 0.882, blue: 0.900)
            let blocks: [CGRect] = [
                CGRect(x: w*0.00, y: h*0.00, width: w*0.28, height: h*0.18),
                CGRect(x: w*0.32, y: h*0.00, width: w*0.20, height: h*0.13),
                CGRect(x: w*0.58, y: h*0.00, width: w*0.42, height: h*0.22),
                CGRect(x: w*0.00, y: h*0.22, width: w*0.18, height: h*0.25),
                CGRect(x: w*0.22, y: h*0.17, width: w*0.32, height: h*0.20),
                CGRect(x: w*0.60, y: h*0.26, width: w*0.40, height: h*0.18),
                CGRect(x: w*0.00, y: h*0.72, width: w*0.22, height: h*0.28),
                CGRect(x: w*0.26, y: h*0.78, width: w*0.28, height: h*0.22),
                CGRect(x: w*0.62, y: h*0.75, width: w*0.38, height: h*0.25),
            ]
            for b in blocks {
                ctx.fill(Path(b), with: .color(residentialColor))
            }

            // ── 3. Parks (Apple Maps Grün) ────────────────────────────────
            let parkColor = Color(red: 0.780, green: 0.896, blue: 0.737)
            let parks: [(CGRect, CGFloat)] = [
                (CGRect(x: w*0.04, y: h*0.04, width: w*0.20, height: h*0.14), 10),
                (CGRect(x: w*0.54, y: h*0.03, width: w*0.24, height: h*0.18), 14),
                (CGRect(x: w*0.14, y: h*0.52, width: w*0.26, height: h*0.16), 10),
                (CGRect(x: w*0.64, y: h*0.48, width: w*0.20, height: h*0.22), 12),
                (CGRect(x: w*0.34, y: h*0.80, width: w*0.18, height: h*0.14), 8),
            ]
            for (rect, r) in parks {
                ctx.fill(Path(roundedRect: rect, cornerRadius: r), with: .color(parkColor))
            }

            // ── 4. Fluss (geschwungen, Apple-Blau) ────────────────────────
            var river = Path()
            river.move(to: CGPoint(x: -10, y: h*0.44))
            river.addCurve(
                to: CGPoint(x: w+10, y: h*0.60),
                control1: CGPoint(x: w*0.20, y: h*0.38),
                control2: CGPoint(x: w*0.80, y: h*0.66)
            )
            river.addLine(to: CGPoint(x: w+10, y: h*0.69))
            river.addCurve(
                to: CGPoint(x: -10, y: h*0.53),
                control1: CGPoint(x: w*0.80, y: h*0.75),
                control2: CGPoint(x: w*0.20, y: h*0.47)
            )
            river.closeSubpath()
            ctx.fill(river, with: .color(Color(red: 0.616, green: 0.808, blue: 0.933, opacity: 0.85)))

            // ── 5. Nebenstraßen (dünne weiße Linien, unregelmäßig) ────────
            let minorW: CGFloat = 3
            let minor: [(CGPoint, CGPoint)] = [
                (CGPoint(x: 0,     y: h*0.18), CGPoint(x: w,     y: h*0.18)),
                (CGPoint(x: 0,     y: h*0.30), CGPoint(x: w*0.6, y: h*0.30)),
                (CGPoint(x: 0,     y: h*0.42), CGPoint(x: w,     y: h*0.42)),
                (CGPoint(x: 0,     y: h*0.70), CGPoint(x: w,     y: h*0.70)),
                (CGPoint(x: 0,     y: h*0.83), CGPoint(x: w*0.5, y: h*0.83)),
                (CGPoint(x: 0,     y: h*0.93), CGPoint(x: w,     y: h*0.93)),
                (CGPoint(x: w*0.14, y: 0),     CGPoint(x: w*0.14, y: h*0.42)),
                (CGPoint(x: w*0.28, y: 0),     CGPoint(x: w*0.28, y: h)),
                (CGPoint(x: w*0.44, y: 0),     CGPoint(x: w*0.44, y: h*0.40)),
                (CGPoint(x: w*0.60, y: 0),     CGPoint(x: w*0.60, y: h)),
                (CGPoint(x: w*0.76, y: 0),     CGPoint(x: w*0.76, y: h*0.44)),
                (CGPoint(x: w*0.88, y: h*0.22),CGPoint(x: w*0.88, y: h)),
            ]
            for (a, b) in minor {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(.white.opacity(0.95)), lineWidth: minorW)
            }

            // ── 6. Hauptstraßen (breiter, leicht gelblich wie Apple Maps) ─
            let majorColor = Color(red: 1.0, green: 0.97, blue: 0.88)
            let majorW: CGFloat = 7
            let major: [(CGPoint, CGPoint)] = [
                (CGPoint(x: 0,     y: h*0.25), CGPoint(x: w,     y: h*0.25)),
                (CGPoint(x: 0,     y: h*0.57), CGPoint(x: w,     y: h*0.57)),
                (CGPoint(x: w*0.38, y: 0),     CGPoint(x: w*0.38, y: h)),
                (CGPoint(x: w*0.72, y: 0),     CGPoint(x: w*0.72, y: h)),
            ]
            for (a, b) in major {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(majorColor), lineWidth: majorW)
            }

            // ── 7. Diagonalstraßen / Boulevards ──────────────────────────
            let diags: [(CGPoint, CGPoint)] = [
                (CGPoint(x: 0,     y: h*0.16), CGPoint(x: w*0.44, y: 0)),
                (CGPoint(x: w*0.56, y: h),     CGPoint(x: w,      y: h*0.48)),
                (CGPoint(x: 0,     y: h*0.60), CGPoint(x: w*0.30, y: h)),
            ]
            for (a, b) in diags {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(.white.opacity(0.9)), lineWidth: 5)
            }

            // ── 8. Gebäude-Footprints (kleine dunkle Rechtecke in Blöcken) ─
            let buildingColor = Color(red: 0.845, green: 0.845, blue: 0.865)
            let footprints: [CGRect] = [
                CGRect(x: w*0.06, y: h*0.20, width: w*0.06, height: h*0.04),
                CGRect(x: w*0.14, y: h*0.20, width: w*0.04, height: h*0.06),
                CGRect(x: w*0.32, y: h*0.04, width: w*0.08, height: h*0.07),
                CGRect(x: w*0.32, y: h*0.14, width: w*0.05, height: h*0.04),
                CGRect(x: w*0.64, y: h*0.04, width: w*0.06, height: h*0.09),
                CGRect(x: w*0.78, y: h*0.06, width: w*0.09, height: h*0.06),
                CGRect(x: w*0.64, y: h*0.28, width: w*0.07, height: h*0.10),
                CGRect(x: w*0.78, y: h*0.28, width: w*0.10, height: h*0.08),
                CGRect(x: w*0.04, y: h*0.73, width: w*0.08, height: h*0.08),
                CGRect(x: w*0.14, y: h*0.76, width: w*0.06, height: h*0.06),
                CGRect(x: w*0.30, y: h*0.74, width: w*0.06, height: h*0.05),
                CGRect(x: w*0.66, y: h*0.76, width: w*0.08, height: h*0.08),
                CGRect(x: w*0.80, y: h*0.77, width: w*0.07, height: h*0.06),
                CGRect(x: w*0.36, y: h*0.61, width: w*0.05, height: h*0.05),
            ]
            for f in footprints {
                ctx.fill(Path(roundedRect: f, cornerRadius: 2), with: .color(buildingColor))
            }
        }
        .ignoresSafeArea()
    }
}

struct AnimatedDrop: Identifiable {
    let id = UUID()
    let name: String
    let activity: String
    let coordinate: CLLocationCoordinate2D
}

class DropMKAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let activity: String
    let name: String
    let dropID: String
    init(drop: AnimatedDrop) {
        self.coordinate = drop.coordinate
        self.activity = drop.activity
        self.name = drop.name
        self.dropID = drop.id.uuidString
    }
}

class DropMapViewController: UIViewController, MKMapViewDelegate {
    var mapView: MKMapView!

    override func viewDidLoad() {
        super.viewDidLoad()
        mapView = MKMapView(frame: view.bounds)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.mapType = .standard
        mapView.isUserInteractionEnabled = false
        mapView.showsUserLocation = false
        mapView.delegate = self
        view.addSubview(mapView)

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.137, longitude: 11.575),
            span: MKCoordinateSpan(latitudeDelta: 0.14, longitudeDelta: 0.14)
        )
        mapView.setRegion(region, animated: false)
    }

    func showDrop(_ drop: AnimatedDrop) {
        let ann = DropMKAnnotation(drop: drop)
        mapView.addAnnotation(ann)
    }

    func hideDrop(id: String) {
        guard let ann = mapView.annotations
            .first(where: { ($0 as? DropMKAnnotation)?.dropID == id }) else { return }
        if let view = mapView.view(for: ann) {
            UIView.animate(withDuration: 0.35, animations: {
                view.alpha = 0
                view.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            }) { _ in self.mapView.removeAnnotation(ann) }
        } else {
            mapView.removeAnnotation(ann)
        }
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let drop = annotation as? DropMKAnnotation else { return nil }
        let view = MKAnnotationView(annotation: annotation, reuseIdentifier: nil)
        let chip = makeChip(activity: drop.activity, name: drop.name)
        view.addSubview(chip)
        let size = chip.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        chip.frame = CGRect(origin: .zero, size: size)
        view.frame.size = size
        view.centerOffset = CGPoint(x: 0, y: -size.height / 2)
        view.alpha = 0
        view.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        UIView.animate(withDuration: 0.5, delay: 0,
                       usingSpringWithDamping: 0.65, initialSpringVelocity: 0.8) {
            view.alpha = 1
            view.transform = .identity
        }
        return view
    }

    private func makeChip(activity: String, name: String) -> UIView {
        let chip = UIView()
        chip.backgroundColor = .white
        chip.layer.cornerRadius = 14
        chip.layer.shadowColor = UIColor.black.cgColor
        chip.layer.shadowOpacity = 0.10
        chip.layer.shadowRadius = 8
        chip.layer.shadowOffset = CGSize(width: 0, height: 3)
        chip.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "\(activity)  \(name)"
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: chip.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -12),
        ])
        return chip
    }
}

struct StableDropMapView: UIViewControllerRepresentable {
    let controller: DropMapViewController
    func makeUIViewController(context: Context) -> DropMapViewController { controller }
    func updateUIViewController(_ vc: DropMapViewController, context: Context) {}
}

class DropMapControllerHolder: ObservableObject {
    let controller = DropMapViewController()

    private let drops: [AnimatedDrop] = [
        AnimatedDrop(name: "Mia",   activity: "Kaffee",  coordinate: .init(latitude: 48.155, longitude: 11.548)),
        AnimatedDrop(name: "Ben",   activity: "Drink",   coordinate: .init(latitude: 48.125, longitude: 11.592)),
        AnimatedDrop(name: "Zoe",   activity: "Sport",   coordinate: .init(latitude: 48.148, longitude: 11.601)),
        AnimatedDrop(name: "Leo",   activity: "Essen",   coordinate: .init(latitude: 48.120, longitude: 11.558)),
        AnimatedDrop(name: "Max",   activity: "Zocken",  coordinate: .init(latitude: 48.158, longitude: 11.582)),
        AnimatedDrop(name: "Lena",  activity: "Jam",     coordinate: .init(latitude: 48.130, longitude: 11.545)),
        AnimatedDrop(name: "Jonas", activity: "Gym",     coordinate: .init(latitude: 48.143, longitude: 11.610)),
        AnimatedDrop(name: "Sara",  activity: "Kunst",   coordinate: .init(latitude: 48.118, longitude: 11.575)),
        AnimatedDrop(name: "Finn",  activity: "Radeln",  coordinate: .init(latitude: 48.162, longitude: 11.565)),
        AnimatedDrop(name: "Lia",   activity: "Lernen",  coordinate: .init(latitude: 48.128, longitude: 11.600)),
    ]

    func startAnimating() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.runCycle() }
    }

    private func runCycle() {
        var delay: Double = 0
        let order = drops.shuffled()
        for drop in order {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.controller.showDrop(drop)
            }
            let visible = Double.random(in: 7.0...12.0)
            let dropID = drop.id.uuidString
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + visible) {
                self.controller.hideDrop(id: dropID)
            }
            delay += Double.random(in: 1.8...2.8)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 5.0) {
            self.runCycle()
        }
    }
}

class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0
    private var tokens: [NSObjectProtocol] = []

    init() {
        tokens.append(
            NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
            ) { [weak self] n in
                let frame = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero
                self?.height = frame.height
            }
        )
        tokens.append(
            NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.height = 0 }
        )
    }

    deinit {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

enum OnboardingStep {
    case intro, welcome, profile, birthday, done, underage
}


// MARK: - Shared Onboarding UI Helpers

/// Hintergrund mit radialem Farbglow von oben
struct OnboardingStepBackground: View {
    let color: Color
    @Environment(\.colorScheme) var cs
    var body: some View {
        ZStack {
            (cs == .dark ? Color(hex: "0d0f14") : Color(hex: "f5f7fe"))
                .ignoresSafeArea()
            // Oben: Haupt-Akzent
            RadialGradient(
                colors: [color.opacity(0.22), Color.clear],
                center: .top, startRadius: 0, endRadius: 480
            )
            .ignoresSafeArea()
            // Unten: schwacher Akzent damit kein kahler Rand entsteht
            RadialGradient(
                colors: [color.opacity(0.10), Color.clear],
                center: .bottom, startRadius: 0, endRadius: 360
            )
            .ignoresSafeArea()
        }
    }
}

/// Pulsierendes Icon mit drei Ringen
struct OnboardingPulseIcon: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 80
    var iconSize: CGFloat = 34

    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(color.opacity(0.13 - Double(i) * 0.03), lineWidth: 1.5)
                    .frame(width: size + CGFloat(i) * 36,
                           height: size + CGFloat(i) * 36)
                    .scaleEffect(pulse ? 1.12 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.8)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.3),
                        value: pulse
                    )
            }
            Circle()
                .fill(color.opacity(0.14))
                .frame(width: size, height: size)
            DazuIcon(systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(color)
        }
        .onAppear { pulse = true }
    }
}

/// Kapsel-Punkt-Fortschrittsanzeige für Onboarding-Schritte
struct OnboardingDotProgress: View {
    let current: Int   // 1-basiert
    let total: Int
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { i in
                let active = i == current - 1
                Capsule()
                    .fill(active ? color : Color.primary.opacity(0.15))
                    .frame(width: active ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.3), value: active)
            }
        }
    }
}

// MARK: - Animated Backgrounds

// MARK: – Tageszeit-Helper

private func isNightTime() -> Bool {
    let h = Calendar.current.component(.hour, from: Date())
    return h < 6 || h >= 20
}

// MARK: – Adaptive Glow-Hintergrund (Step 1 – Telefon)

struct WarmGlowBackground: View {
    @Environment(\.colorScheme) var cs
    @State private var animate = false
    private var dark: Bool { cs == .dark || (cs != .light && isNightTime()) }

    var body: some View {
        ZStack {
            (dark ? Color.black : Color.white).ignoresSafeArea()
            Circle()
                .fill(Color(hex: "7C5CFF").opacity(dark ? 0.45 : 0.22))
                .frame(width: 360)
                .offset(x: 110, y: animate ? 220 : 280)
                .blur(radius: dark ? 90 : 70)
            Circle()
                .fill(Color(hex: "4DEBBE").opacity(dark ? 0.30 : 0.15))
                .frame(width: 260)
                .offset(x: -110, y: animate ? -200 : -160)
                .blur(radius: 75)
            Circle()
                .fill(Color(hex: "FF7A59").opacity(dark ? 0.15 : 0.08))
                .frame(width: 200)
                .offset(x: animate ? -60 : 60, y: 80)
                .blur(radius: 60)
        }
        .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: animate)
        .onAppear { animate = true }
    }
}

// MARK: – Adaptive Glow-Hintergrund (Step 2 – SMS)

struct CoolPulseBackground: View {
    @Environment(\.colorScheme) var cs
    @State private var animate = false
    private var dark: Bool { cs == .dark || (cs != .light && isNightTime()) }

    var body: some View {
        ZStack {
            (dark ? Color.black : Color(hex: "F0F4FF")).ignoresSafeArea()
            Circle()
                .fill(Color.blue.opacity(dark ? 0.35 : 0.18))
                .frame(width: 320)
                .offset(x: animate ? -90 : -60, y: animate ? 160 : 220)
                .blur(radius: 80)
            Circle()
                .fill(Color.purple.opacity(dark ? 0.30 : 0.15))
                .frame(width: 280)
                .offset(x: animate ? 100 : 70, y: animate ? -130 : -90)
                .blur(radius: 70)
            Circle()
                .fill(Color.cyan.opacity(dark ? 0.20 : 0.12))
                .frame(width: 200)
                .offset(x: animate ? 40 : -40, y: 20)
                .blur(radius: 55)
        }
        .animation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true), value: animate)
        .onAppear { animate = true }
    }
}

// MARK: – Adaptive Glow-Hintergrund (Name/Bestätigung Step)

struct GreenGlowBackground: View {
    @Environment(\.colorScheme) var cs
    @State private var animate = false
    private var dark: Bool { cs == .dark || (cs != .light && isNightTime()) }

    var body: some View {
        ZStack {
            (dark ? Color.black : Color.white).ignoresSafeArea()
            Circle()
                .fill(Color(hex: "7C5CFF").opacity(dark ? 0.40 : 0.20))
                .frame(width: 400)
                .offset(x: animate ? -20 : 20, y: animate ? -200 : -160)
                .blur(radius: 100)
            Circle()
                .fill(Color(hex: "4DEBBE").opacity(dark ? 0.20 : 0.10))
                .frame(width: 280)
                .offset(x: 130, y: animate ? 280 : 240)
                .blur(radius: 90)
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .stroke(Color(hex: "7C5CFF").opacity(dark ? 0.08 - Double(i)*0.015
                                                               : 0.05 - Double(i)*0.01),
                            lineWidth: 1.5)
                    .frame(width: CGFloat(120 + i * 70))
                    .scaleEffect(animate ? 1.06 : 0.96)
                    .animation(.easeInOut(duration: 2.5 + Double(i)*0.4).repeatForever(autoreverses: true),
                               value: animate)
            }
        }
        .animation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true), value: animate)
        .onAppear { animate = true }
    }
}

// MARK: - DSGVO Consent Step (vor Ausweis-Scan)

// MARK: - Minderjährigen-Sperrscreen

/// Wird angezeigt wenn das eingegebene Geburtsdatum ein Alter unter 18 ergibt.
/// Kein Weiterkommen — der Nutzer muss die App verlassen.
struct UnderAgeBlockView: View {
    /// Callback: Zurück zum ID-Scan (z.B. "anderer Ausweis") oder App-Reset
    let onBack: () -> Void
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Neutraler dunkler Hintergrund — kein bunter Glow
            Color(hex: "1C1C1E").ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.accentRed.opacity(0.14))
                        .frame(width: 96, height: 96)
                    DazuIcon("nosign")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundColor(Color.accentRed)
                }
                .padding(.bottom, 28)

                Text(tr("onboard.access_denied"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 14)

                Text(tr("onboard.under_18"))
                    .font(.system(size: 15))
                    .foregroundColor(Color.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 36)

                Spacer()

                // Rechtlicher Hinweis
                HStack(spacing: 6) {
                    DazuIcon("info.circle.fill", accent: false)
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.35))
                    Text(tr("onboard.legal_notice"))
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 28)

                // Zurück-Button (kein Weiterkommen)
                Button(action: onBack) {
                    HStack(spacing: 8) {
                        DazuIcon("arrow.left")
                        Text(tr("common.back"))
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    )
                }
                .dropsPressable()
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 30)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Age check helper

private func isUserUnderage(birthdate: Date) -> Bool {
    let age = Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year ?? 0
    return age < 18
}


// MARK: - Aurora Overlay (Phone → Name Steps)

struct OnboardingAuroraOverlay: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.brand.opacity(0.30))
                .frame(width: 340, height: 340)
                .blur(radius: 80)
                .offset(x: pulse ? 40 : -50, y: pulse ? -180 : -130)
            Circle()
                .fill(Color(UIColor.systemPurple).opacity(0.22))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: pulse ? -70 : 50, y: pulse ? 80 : 140)
            Circle()
                .fill(Color(UIColor.systemTeal).opacity(0.18))
                .frame(width: 240, height: 240)
                .blur(radius: 65)
                .offset(x: pulse ? 80 : -30, y: pulse ? -60 : 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @AppStorage("appLanguage") private var appLanguage = "de"
    @EnvironmentObject var store: AppStore
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @Environment(\.colorScheme) var systemColorScheme

    @State private var step: OnboardingStep = {
        // Beim allerersten App-Start zeigen wir den Intro-Slide-Flow. Danach
        // speichert `hasSeenIntro` dass der User es schon kennt und wir
        // springen direkt zum Welcome / Sign-up.
        UserDefaults.standard.bool(forKey: "hasSeenIntro") ? .welcome : .intro
    }()
    @State private var isLoginMode: Bool = false
    @State private var userName = ""
    @State private var userPhone = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showDuplicateAccountAlert = false
    @State private var showNotFoundAlert = false
    @StateObject private var auth = FirebaseAuthManager()
    @State private var capturedAppleEmail: String? = nil
    /// Fullscreen für die Phone-Auth-Flow (SMS-Code). Wird vom WelcomeStep
    /// via `onPhone`-Callback gesetzt.
    @State private var showPhoneAuthSheet = false
    // Muss als Property gehalten werden damit ARC es nicht sofort freigibt
    @State private var onboardingLocManager: CLLocationManager? = nil

    /// System-Setting hat Vorrang; bei „Auto" entscheidet die Uhrzeit
    private var prefersDark: Bool {
        switch systemColorScheme {
        case .dark:  return true
        case .light: return false
        default:     return isNightTime()
        }
    }
    private var adaptiveScheme: ColorScheme { prefersDark ? .dark : .light }

    var body: some View {
        ZStack {
            // Basisschicht: verhindert weiße Balken in safe areas —
            // Opake Basis-Farbe IMMER sichtbar → kein Durchschimmern beim Step-Wechsel
            (systemColorScheme == .dark ? Color(hex: "0d0f14") : Color(hex: "f5f7fe"))
                .ignoresSafeArea()

            // Einheitlicher heller Lavendel-Hintergrund für alle Onboarding-
            // Steps — fix (adaptive brandLavender wird im Dark zu Orange und
            // kollidiert mit den orange Logo-Pins in den Demos).
            if step == .underage {
                Color(hex: "1C1C1E").ignoresSafeArea()
            } else if step != .welcome {
                Color(red: 0.914, green: 0.890, blue: 1.000).ignoresSafeArea()
            }

            // Inhalt je nach Step — ausgelagert in @ViewBuilder um Type-Check-Timeout zu vermeiden
            stepContent
                .id(step)
                .animation(.none, value: step)
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { drag in
                    guard drag.translation.width > 80,
                          abs(drag.translation.height) < abs(drag.translation.width) else { return }
                    // kein Swipe-Back auf diesem Step
                }
        )
        .alert(tr("onboard.account_exists_title"), isPresented: $showDuplicateAccountAlert) {
            Button(tr("onboard.sign_in")) {
                withAnimation(.spring(response: 0.4)) {
                    isLoginMode = true
                    step = .welcome
                }
            }
            Button(tr("onboard.cancel"), role: .cancel) {
                withAnimation(.spring(response: 0.4)) { step = .welcome }
            }
        } message: {
            Text(tr("onboard.account_exists"))
        }
        .alert(tr("onboard.no_account_found"), isPresented: $showNotFoundAlert) {
            Button(tr("onboard.register")) {
                withAnimation(.spring(response: 0.4)) {
                    isLoginMode = false
                    step = .welcome
                }
            }
            Button(tr("onboard.cancel"), role: .cancel) { }
        } message: {
            Text(tr("onboard.number_not_registered"))
        }
        .onAppear { }
    }

    // MARK: - Step Content (ausgelagert für schnelleren Compiler)

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .intro:     introStepView
        case .welcome:   welcomeStepView
        case .profile:   profileStepView
        case .birthday:  profileStepView   // Zurück zum Profil-Schritt (Geburtsdatum korrigieren)
        case .done:      doneStepView
        case .underage:  underageStepView
        }
    }

    /// Pre-Sign-up Intro: 3 Slides mit den Core-Features. Nur beim ersten
    /// App-Start sichtbar (via `hasSeenIntro` AppStorage).
    @ViewBuilder private var introStepView: some View {
        IntroSlidesView {
            UserDefaults.standard.set(true, forKey: "hasSeenIntro")
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                step = .welcome
            }
        }
    }

    @ViewBuilder private var welcomeStepView: some View {
        WelcomeStep(
            onPhone: { showPhoneAuthSheet = true },
            onApple: { isNewUser, email in
                capturedAppleEmail = email
                // Apple sendet die Relay-E-Mail nur beim ersten Login → persistent speichern
                if let email = email {
                    UserDefaults.standard.set(email.lowercased(), forKey: "ud_appleEmail")
                }

                // Tombstone-Check: Wurde dieser Apple-Account in der App schon mal
                // gelöscht? Dann als Neuregistrierung behandeln — auch wenn Firebase
                // den User weiterhin als „bekannt" meldet (isNewUser = false).
                Task { @MainActor in
                    var wasDeleted = false
                    if let uid = Auth.auth().currentUser?.uid {
                        wasDeleted = await RealtimeDBManager.shared.consumeDeletionTombstone(uid: uid)
                    }
                    if wasDeleted {
                        print("[auth] Tombstone gefunden → fresh registration")
                        isLoginMode = false
                        withAnimation(.spring(response: 0.4)) { step = .profile }
                        return
                    }

                    // ── Doppelter Sicherheitscheck ───────────────────────
                    // Tombstone-Check kann fehlschlagen (RTDB-Permission,
                    // Network-Race, eventual consistency). Bevor wir bei
                    // isNewUser=false stumm einloggen, verifizieren wir
                    // dass das Profil tatsächlich noch in RTDB existiert.
                    // Falls nicht → Account wurde gelöscht, fresh registration.
                    let profileExists: Bool = await withCheckedContinuation { cont in
                        RealtimeDBManager.shared.hasExistingProfile { exists in
                            cont.resume(returning: exists)
                        }
                    }

                    if !isNewUser && profileExists {
                        // Echter Bestandsuser mit intaktem Profil → einloggen
                        handleAppleSignInResult(exists: true)
                        return
                    }

                    if !isNewUser && !profileExists {
                        // Firebase kennt den User, aber das Profil ist weg →
                        // resurrektion nach Account-Löschung. Fresh registration.
                        print("[auth] isNewUser=false aber kein Profil in RTDB → resurrection")
                        isLoginMode = false
                        withAnimation(.spring(response: 0.4)) { step = .profile }
                        return
                    }

                    // isNewUser=true → echte Neuregistrierung
                    if profileExists {
                        // Edge-Case: Firebase sagt "neu" aber Profil existiert (sollte
                        // selten sein, z.B. Conflict zwischen Auth-Methoden) → einloggen.
                        handleAppleSignInResult(exists: true)
                    } else {
                        handleAppleSignInResult(exists: false)
                    }
                }
            },
            onGoogle: { isNewUser, _ in
                Task { @MainActor in
                    var wasDeleted = false
                    if let uid = Auth.auth().currentUser?.uid {
                        wasDeleted = await RealtimeDBManager.shared.consumeDeletionTombstone(uid: uid)
                    }
                    if wasDeleted {
                        isLoginMode = false
                        withAnimation(.spring(response: 0.4)) { step = .profile }
                        return
                    }
                    let profileExists: Bool = await withCheckedContinuation { cont in
                        RealtimeDBManager.shared.hasExistingProfile { exists in cont.resume(returning: exists) }
                    }
                    if !isNewUser && !profileExists {
                        // Resurrection: Firebase kennt User, Profil fehlt → neu registrieren
                        isLoginMode = false
                        withAnimation(.spring(response: 0.4)) { step = .profile }
                        return
                    }
                    handleAppleSignInResult(exists: profileExists)
                }
            },
            isLoginMode: $isLoginMode,
            onBetaLogin: nil
        )
        // Default: immer Register-Modus (nicht hasOnboarded) — neue Marketing-
        // Strategie. User der schon Konto hat, klickt einfach den „Schon
        // registriert? Anmelden"-Toggle drunter.
        .onAppear { isLoginMode = false }
        // Phone-Auth-Flow (SMS-Code). Routing-Policy:
        //  - bestehender Account (needsProfileSetup=false) → direkt in die
        //    App via isAuthenticated=true
        //  - neuer Account oder Account ohne RTDB-Profil (true) → Sheet
        //    schließen und ins Profile-Setup-Step wechseln. `isAuthenticated`
        //    wird vom ProfileSetupStep nach Name/Alter-Eingabe gesetzt.
        .fullScreenCover(isPresented: $showPhoneAuthSheet) {
            LoginView(
                onCompleted: { needsSetup in
                    showPhoneAuthSheet = false
                    if needsSetup {
                        isLoginMode = false
                        withAnimation(.spring(response: 0.4)) { step = .profile }
                    } else {
                        store.syncReliabilityFromFirestore()
                        store.isAuthenticated = true
                    }
                },
                isLoginMode: isLoginMode
            )
            .environmentObject(store)
        }
    }

    @ViewBuilder private var profileStepView: some View {
        ProfileSetupStep(
            name:   $userName,
            phone:  $userPhone,
            selfie: $store.selfieImage,
            onNext: { name, birthdate, gender, phone in
                if isUserUnderage(birthdate: birthdate) {
                    store.userBirthdate = birthdate
                    withAnimation(.spring(response: 0.4)) { step = .underage }
                    return
                }
                // Content-Filter auf den Profilnamen — keine Slurs,
                // Beleidigungen oder Sexual-Solicitation als Anzeigename.
                if let match = ContentFilter.firstMatch(profileName: name) {
                    store.showInfoToast(
                        tr("onboard.blocked_word").replacingOccurrences(of: "{word}", with: match.word),
                        icon: "exclamationmark.shield.fill"
                    )
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    return
                }
                store.currentUser.name = name.isEmpty ? "Du" : name.capitalizedFirst
                store.userBirthdate    = birthdate
                store.userGender       = gender.lowercased()   // immer lowercase speichern
                if !phone.isEmpty {
                    // saveUserPhone schreibt in Firestore + phoneIndex (damit Kontakte uns finden)
                    store.saveUserPhone(phone)
                }
                store.saveAll()
                // Permissions werden NICHT mehr hier angefragt — sie kommen
                // erst nach dem WelcomeSheet / First-Drop-Walkthrough in
                // MainTabView. So entscheidet der User erst nachdem er die
                // App verstanden hat, ob er Standort/Push/BT erlaubt.
                withAnimation(.spring(response: 0.4)) { step = .done }
            },
            onBack: { withAnimation(.spring(response: 0.4)) { step = .welcome } }
        )
        .environment(\.colorScheme, adaptiveScheme)
        .onAppear {
            // Vorname aus Apple-ID übernehmen — nur wenn das Namensfeld noch leer ist
            // und Apple ihn uns beim initialen Login geliefert hat. Apple sendet
            // fullName nur beim ersten Sign-In, deshalb persistieren wir ihn in
            // UserDefaults (siehe FirebaseAuthManager) und lesen ihn hier zurück.
            if userName.isEmpty {
                if let given = UserDefaults.standard.string(forKey: "ud_appleGivenName"),
                   !given.isEmpty {
                    userName = given
                } else if let display = Auth.auth().currentUser?.displayName,
                          let firstWord = display.split(separator: " ").first,
                          !firstWord.isEmpty {
                    // Fallback: Firebase displayName (wird aus Apple-fullName gesetzt)
                    userName = String(firstWord)
                    UserDefaults.standard.set(String(firstWord), forKey: "ud_appleGivenName")
                }
            }
        }
    }

    @ViewBuilder private var doneStepView: some View {
        Color.clear.onAppear {
            // Firebase UID persistent speichern für stabilen Drop-Filter
            if let uid = Auth.auth().currentUser?.uid {
                UserDefaults.standard.set(uid, forKey: "ud_firebaseUID")
            }
            // Admin-Check (Bootstrap-Credentials siehe AdminConfig)
            let authEmail = (Auth.auth().currentUser?.email ?? "").lowercased()
            if AdminConfig.isBootstrapAdminEmail(authEmail) {
                store.isAdmin = true
            }
            // Gender-Filter nie automatisch aktivieren — muss manuell eingeschaltet werden
            store.genderFilterEnabled = false
            // Profil in Firebase speichern → Nutzer erscheint im Admin-Panel
            saveProfileToFirebase()
            // Registrierungszeitpunkt für Profilbild-Erinnerung (48 h) merken
            PushNotificationManager.shared.recordRegistration()
            // FCM-Token in RTDB schreiben — der Token kam ggf. schon vor Auth (OnApp-Start),
            // konnte aber mangels User-UID nicht persistiert werden. Jetzt nachholen.
            if let token = UserDefaults.standard.string(forKey: "fcmToken"), !token.isEmpty {
                RealtimeDBManager.shared.setMyFCMToken(token)
            }
            // App-Invite-Bonus: wenn der User via Einladungs-Link hergekommen ist,
            // kriegt der Einladende (via Firebase-Transaction) +10 Punkte gutgeschrieben.
            // pendingInviteUsername enthält die UID des Einladenden (aus /invite/{uid}).
            if let inviterUID = store.pendingInviteUsername, !inviterUID.isEmpty {
                RealtimeDBManager.shared.creditAppInviteBonus(inviterUID: inviterUID)
                store.pendingInviteUsername = nil
            }
            // Freundes-Observer starten (noch keine Freunde, aber für zukünftige Adds)
            if let uid = Auth.auth().currentUser?.uid {
                store.startObservingFriends(ownerUID: uid)
                store.startObservingAdminNotices()
                store.startObservingPresence()
            }
            // Online-Heartbeat — sonst sieht einen Freunde nicht als "online" bis
            // zur ersten Background-Return. Inkl. Koord für Admin-Panel-
            // Stadt-Derivation.
            RealtimeDBManager.shared.markOnlineHeartbeat(
                coordinate: store.currentUser.coordinate
            )
            store.syncReliabilityFromFirestore()
            store.isAuthenticated = true
        }
    }

    @ViewBuilder private var underageStepView: some View {
        UnderAgeBlockView { withAnimation(.spring(response: 0.4)) { step = .birthday } }
    }


    /// Fragt Push, Standort UND Bluetooth-Berechtigung am Ende des Onboardings
    /// an. Reihenfolge bewusst gewählt:
    ///   1. Push (am wenigsten kritisch, Default-Allow bei vielen Usern)
    ///   2. Standort (Drop-Suche kernfunktion, hohe Akzeptanz erwartet)
    ///   3. Bluetooth (Anwesenheits-Bestätigung — Drops-USP, vorher
    ///      vergessen → User wurde erst im Map-View beim ersten Join
    ///      gefragt, ohne Kontext)
    /// Alle 3 mit kurzem Stagger damit iOS die Sheets nicht aufeinanderstapelt.
    private func requestOnboardingPermissions() {
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
        // 2. Standort (falls noch nicht bestimmt) — kurzer Versatz damit
        // das iOS-Sheet nicht das Push-Sheet überlappt.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Property halten damit ARC den Manager nicht sofort freigibt
            let locManager = CLLocationManager()
            self.onboardingLocManager = locManager
            if locManager.authorizationStatus == .notDetermined {
                locManager.requestWhenInUseAuthorization()
            }
        }
        // 3. Bluetooth — Trigger durch *Touch* an den BluetoothMeetupManager,
        // der den CBCentralManager initialisiert. iOS zeigt dann automatisch
        // den Bluetooth-Permission-Prompt (NSBluetoothAlwaysUsageDescription
        // aus Info.plist). Wichtig: das passiert erst beim ersten Manager-
        // Zugriff — wir touchen den hier proaktiv, damit der User die
        // Berechtigung direkt im Onboarding-Flow setzt statt erst beim
        // ersten Drop-Join in der Map.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            self.store.bluetoothMeetup.warmUpForPermissionPrompt()
        }
    }

    /// Verarbeitet das Ergebnis des Apple-Sign-In Profil-Checks.
    private func handleAppleSignInResult(exists: Bool) {
        if exists {
            // Bestehender Account — einloggen egal ob login- oder register-Modus.
            //
            // WICHTIG: `isAuthenticated = true` **erst** feuern, wenn die Firebase-
            // Daten (Name, Radius, Altersfilter, Profilbild-URL) im Store liegen —
            // sonst mountet MainTabView mit stalem State, rendert Glass-Cards mit
            // der falschen Höhe, und nach dem Firebase-Update sitzt der Glass-
            // Hintergrund versetzt (v.a. iOS 26 `glassEffect`, das die Shape
            // beim Layout-Wechsel nicht sauber invalidiert).
            isLoading = true
            hasOnboarded = true
            // Bestehender User → WelcomeSheet NICHT zeigen.
            // hasSeenWelcome wird beim Logout geleert, muss daher beim Re-Login
            // explizit gesetzt werden (sonst sieht jeder Re-Login den Walkthrough).
            UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
            // FCM-Token nachziehen (Token kam ggf. vor Login → noch nicht persistiert)
            if let token = UserDefaults.standard.string(forKey: "fcmToken"), !token.isEmpty {
                RealtimeDBManager.shared.setMyFCMToken(token)
            }
            // Online-Heartbeat — markiert User als "online" für Freundes-
            // Observer. Inkl. Koord für Admin-Panel-Stadt-Derivation.
            RealtimeDBManager.shared.markOnlineHeartbeat(
                coordinate: store.currentUser.coordinate
            )
            // Profilbild-URL parallel zum Profil laden (beides hängt am selben UID-Token).
            store.loadProfileImageURL()

            // Safety: falls Firebase hängt, nach 3s trotzdem durchlassen —
            // der User soll nicht auf einer Loading-Spinner-Insel festsitzen.
            var didComplete = false
            let finishAuth: () -> Void = {
                guard !didComplete else { return }
                didComplete = true
                isLoading = false
                store.syncReliabilityFromFirestore()
                store.isAuthenticated = true
                // Freundes-Observer neu starten — `init()` läuft nur einmal,
                // nach Logout ist er gestoppt. Ohne das bleibt die Freundes-
                // liste bei Re-Login ohne App-Neustart leer.
                if let uid = Auth.auth().currentUser?.uid {
                    store.startObservingFriends(ownerUID: uid)
                store.startObservingAdminNotices()
                    store.startObservingPresence()
                }
                // Profilbild-Re-Retrigger falls die erste Runde kein URL hatte
                // (z.B. Token-Race) — jetzt sollte Auth komplett durchgerouted sein.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [store] in
                    if store.profileImageURL == nil || (store.profileImageURL?.isEmpty ?? true) {
                        store.loadProfileImageURL()
                    }
                }
            }
            // Safety-Fallback: wenn Firebase unerwartet hängt, max 1.2s warten.
            // Normal returnt RTDB unter 500ms — der Timeout ist nur für Edge-Cases
            // (Netz weg, DB langsam) damit der User nicht auf dem Login-Screen
            // festsitzt.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { finishAuth() }

            loadProfileFromFirebase {
                finishAuth()
            }
        } else {
            if isLoginMode {
                // Login-Modus aber kein Account gefunden
                try? Auth.auth().signOut()
                showNotFoundAlert = true
            } else {
                // Echter Neuzugang → Profil einrichten
                let firebaseEmail = (Auth.auth().currentUser?.email ?? "").lowercased()
                let appleEmail = (capturedAppleEmail ?? "").lowercased()
                if AdminConfig.isBootstrapAdmin(authEmail: firebaseEmail, storedAppleEmail: appleEmail) {
                    store.isAdmin = true
                }
                withAnimation(.spring(response: 0.4)) { step = .profile }
            }
        }
    }


    private func finishOnboarding() {
        store.applyDefaultAgeGroups()
        hasOnboarded = true
        withAnimation(.spring(response: 0.4)) { step = .profile }
    }

    /// Speichert das vollständige Nutzerprofil in Firebase Realtime DB.
    /// Wird aufgerufen wenn step = .done.
    private func saveProfileToFirebase() {
        let email = (Auth.auth().currentUser?.email
                     ?? UserDefaults.standard.string(forKey: "ud_appleEmail"))
        RealtimeDBManager.shared.saveUserProfile(
            name:      store.currentUser.name,
            emoji:     store.currentUser.emoji,
            email:     email,
            birthdate: store.userBirthdate,
            gender:    store.userGender.isEmpty ? nil : store.userGender
        )
        store.saveAll()
        // Namen persistent für Quick-Login merken
        if !store.currentUser.name.isEmpty {
            UserDefaults.standard.set(store.currentUser.name, forKey: "ud_lastLoginName")
        }
    }

    /// Lädt das Profil aus Firebase und befüllt den Store (z.B. nach Re-Login).
    /// `completion` wird auf Main gefeuert, sobald die Daten (oder ein Fehler) verarbeitet
    /// wurden — Aufrufer können so warten, bevor sie `isAuthenticated = true` setzen.
    private func loadProfileFromFirebase(completion: (() -> Void)? = nil) {
        // Admin-Check per E-Mail (Bootstrap-Credentials siehe AdminConfig)
        let authEmail = (Auth.auth().currentUser?.email ?? "").lowercased()
        let storedApple = (UserDefaults.standard.string(forKey: "ud_appleEmail") ?? "").lowercased()
        if AdminConfig.isBootstrapAdmin(authEmail: authEmail, storedAppleEmail: storedApple) {
            self.store.isAdmin = true
        }
        // Reliability-Score aus Firestore wiederherstellen — greift wenn
        // UserDefaults leer sind (Neuinstallation, Account-Wechsel, Gerätewechsel).
        store.syncReliabilityFromFirestore()
        RealtimeDBManager.shared.loadUserProfile { profile in
            defer {
                DispatchQueue.main.async { completion?() }
            }
            guard let p = profile else { return }
            if let name = p.name, !name.isEmpty {
                self.store.currentUser.name = name.capitalizedFirst
                // Persistiert den Namen für den Quick-Login-Button auf
                // dem Welcome-Screen — überlebt Logout (anders als UDKey.userName).
                UserDefaults.standard.set(name, forKey: "ud_lastLoginName")
                // UDKey.userName ist der Schlüssel, den AppStore.init beim
                // nächsten App-Start prüft (hasNameStored). Ohne diesen
                // Write klemmt die App nach jedem Kill im Post-Logout-Screen.
                UserDefaults.standard.set(name.capitalizedFirst, forKey: "ud_userName")
            }
            // Emoji aus Firebase übernehmen — sonst springt der User-Emoji
            // bei Re-Login / Gerätewechsel zurück auf den Default „😊".
            if let emoji = p.emoji, !emoji.isEmpty {
                self.store.currentUser.emoji = emoji
                // UD persistieren — Key analog zu AppStore.saveAll().
                // (UDKey ist private im Models-Modul, deshalb hier mit
                // dem gleichen Roh-String "ud_userEmoji".)
                UserDefaults.standard.set(emoji, forKey: "ud_userEmoji")
            }
            if let bd = p.birthdate             { self.store.userBirthdate = bd }
            if let gender = p.gender            { self.store.userGender = gender }
            if p.isAdmin                        { self.store.isAdmin = true }

            // Benutzer-Einstellungen (Radius, Altersfilter, Interests, Blocklist …)
            // aus Firebase wiederherstellen — sonst fallen die nach Logout auf Default.
            self.store.applyRemoteUserSettings(p.settings)
        }
    }
}

// MARK: - Drops Logo (Cleane Wordmark — kein Mark)
// Reduziert auf nur das Wort "Drops" in lighter Schrift, ohne den Pulse-Mark
// daneben. Passt zur cleanen Website-Optik (Bricolage Grotesque 700 dort).
// Auf iOS: SF Pro Bold (700) statt Black (900) — leichter, eleganter.

struct DropsLogo: View {
    var fontSize: CGFloat = 52
    var textColor: Color = .white
    /// Wenn true → die Wordmark sitzt in einer Liquid-Glass-Capsule mit
    /// dezenter Text-Gradient. Default false damit Bestandsstellen
    /// (z.B. WelcomeSheet im Header) ihren cleaneren Look behalten.
    var glassy: Bool = false

    /// Schrift: `.rounded` + `.heavy` — chunkige, runde Buchstaben passen
    /// zum App-Icon-„D" (kompakter Halbkreis mit fetten Strichen).
    /// `.default` mit `.bold` war schlanker und passte nicht zur Icon-DNA.
    private var dropsFont: Font {
        .system(size: fontSize, weight: .bold, design: .rounded)
    }

    var body: some View {
        if glassy {
            glassWordmark
        } else {
            plainText
        }
    }

    /// Die gezeichnete Wortmarke „dazu" statt getipptem Text. Höhe so gewählt,
    /// dass sie etwa so viel Platz einnimmt wie vorher „Drops" in SF Rounded.
    private var plainText: some View {
        DazuWordmark(color: textColor)
            .frame(height: fontSize * 0.95)
            .accessibilityLabel("Dazu")
    }

    /// Wortmarke mit Glow — das a in „dazu" ist das Zeichen selbst, deshalb
    /// steht kein zusätzliches Icon daneben.
    private var glassWordmark: some View {
        DazuWordmark(color: textColor)
            .frame(height: fontSize * 0.95)
            .accessibilityLabel("Dazu")
            // Heller Violett-Glow oben-links — wie der Icon-Top
            .shadow(color: Color.brandVioletLight.opacity(0.65), radius: 24, x: -2, y: -3)
            // Orange-Glow unten-rechts — wie der Punkt im Icon
            .shadow(color: Color.brandOrange.opacity(0.40), radius: 22, x: 3, y: 4)
            // Subtle dunkler Drop-Shadow für Boden-Definition
            .shadow(color: Color.black.opacity(0.22), radius: 10, y: 7)
    }
}

// MARK: - Dazu Wortmarke
//
// Die Wortmarke „dazu" als Vektor: d, a und u sind aus demselben Ring gebaut
// wie das Icon (r=78, Strich 40), das a ist das Zeichen selbst mit orangem
// Punkt. Maße wie in Design/dazu-logo/dazu-wortmarke.svg (828 × 288 Einheiten).
struct DazuWordmark: View {
    var color: Color = .textPrimary
    var dotColor: Color = .brandOrange

    var body: some View {
        ZStack {
            DazuLettersShape().fill(color)
            DazuDotShape().fill(dotColor)
        }
        .aspectRatio(828.0 / 288.0, contentMode: .fit)
    }
}

private struct DazuLettersShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / 828.0, rect.height / 288.0)
        let ox = rect.midX - 414 * s          // linke Kante der Wortmarke
        let oy = rect.midY - 144 * s + 190 * s // y=0 ist die Mitte der runden Buchstaben
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        var line = Path()
        // d — Ring und hoher Stamm
        line.addEllipse(in: CGRect(x: ox + 20 * s, y: oy - 78 * s, width: 156 * s, height: 156 * s))
        line.move(to: p(176, -170)); line.addLine(to: p(176, 78))
        // a — offener Ring (Lücke oben rechts) und kurzer Stamm
        line.move(to: p(322 + 78 * CGFloat(cos(-1.16 * Double.pi / 180)), 78 * CGFloat(sin(-1.16 * Double.pi / 180))))
        line.addArc(center: p(322, 0), radius: 78 * s,
                    startAngle: .degrees(-1.16), endAngle: .degrees(265.16), clockwise: false)
        line.move(to: p(400, 0)); line.addLine(to: p(400, 78))
        // z
        line.move(to: p(464, -75)); line.addLine(to: p(584, -75))
        line.addLine(to: p(464, 75)); line.addLine(to: p(584, 75))
        // u — Bogen unten, rechter Stamm bis zur Grundlinie
        line.move(to: p(652, -78)); line.addLine(to: p(652, 0))
        line.addArc(center: p(730, 0), radius: 78 * s,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        line.move(to: p(808, -78)); line.addLine(to: p(808, 78))

        return line.strokedPath(StrokeStyle(lineWidth: 40 * s, lineCap: .round, lineJoin: .round))
    }
}

private struct DazuDotShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / 828.0, rect.height / 288.0)
        let ox = rect.midX - 414 * s
        let oy = rect.midY - 144 * s + 190 * s
        let r = 27 * s
        // Punkt in der Lücke des a (−48° auf der Ringlinie)
        let cx = ox + 374.19 * s
        let cy = oy - 57.97 * s
        return Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
    }
}

// MARK: - Drops Mark („Offene Runde")
//
// Das Zeichen aus dem App-Icon: ein offener Kreis und der Punkt, der die
// Lücke schließt. Geometrie auf einem 256er-Raster, identisch zu den
// SVG-Ebenen in AppIcon.icon (Ring r=78, Strich 40, Lücke bei −48°,
// Punkt r=27 auf der Ringlinie).
struct DropsMark: View {
    var ringColor: Color = .white
    var dotColor: Color = .brandOrange
    /// Zeigt den orangen „du"-Dot in der Lücke. False = nur das offene „a"
    /// (Empty-States: noch niemand ist dazu gekommen).
    var showDot: Bool = true

    var body: some View {
        ZStack {
            DropsRingShape().fill(ringColor)
            if showDot {
                DropsDotShape().fill(dotColor)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct DropsRingShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 256.0
        var arc = Path()
        // Bogen läuft von kurz vor 3 Uhr über unten und links bis kurz vor
        // 12 Uhr — die Lücke sitzt oben rechts.
        arc.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                   radius: 78 * s,
                   startAngle: .degrees(-1.16), endAngle: .degrees(265.16),
                   clockwise: false)
        var mark = arc.strokedPath(StrokeStyle(lineWidth: 40 * s, lineCap: .round))
        // Stamm rechts unten: macht aus dem offenen Ring das „a" der Wortmarke.
        mark.addRoundedRect(
            in: CGRect(x: rect.midX + 58 * s, y: rect.midY - 20 * s, width: 40 * s, height: 118 * s),
            cornerSize: CGSize(width: 20 * s, height: 20 * s)
        )
        return mark
    }
}

private struct DropsDotShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 256.0
        // Punkt auf der Ringlinie, Mitte der Lücke (−48°).
        let angle = -48.0 * Double.pi / 180.0
        let cx = rect.midX + CGFloat(cos(angle)) * 78 * s
        let cy = rect.midY + CGFloat(sin(angle)) * 78 * s
        let r = 27 * s
        return Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
    }
}

// MARK: - Drops Icon Hero
//
// SwiftUI-Replik des App-Icons als Login/Welcome-Hero. Spiegelt die
// Komposition aus icon.json wider:
//   - Violett-Gradient (hell → voll) als Hintergrund
//   - Offener Ring in Creme, zentriert
//   - Oranger Punkt in der Lücke oben rechts, mit sanft pulsierendem Glow
// MARK: - Radar Pulse Divider
//
// Kleiner animierter Radar-Trenner für den Login: drei weiße Halbkreis-
// Wellen die direkt unterhalb der "Drops"-Wordmark entspringen und nach
// unten expandieren und faden — wie das Radar aus dem App-Icon, aber als
// horizontales Spacer-Element. Kein Sender-Dot, weil der Anker visuell
// die Wordmark selbst ist (Wellen "strömen" aus dem Text).
//
// Die Wellen sind staggered (0s/0.6s/1.2s Delay), jede einzelne Welle
// expandiert in 1.8s von 0.4× auf 1.0× Scale und fadet 80% → 0% Opacity.
// Repeat-forever erzeugt einen kontinuierlichen "Sendet"-Vibe.
struct RadarPulseDivider: View {
    var width: CGFloat = 140
    var color: Color = .white

    @State private var w0 = false
    @State private var w1 = false
    @State private var w2 = false

    /// Animation-Timing — zentral hier, damit Stagger und Loop synchron
    /// bleiben wenn man den Look anpasst. Werte gewählt für „natürliches"
    /// Radar/Wassertropfen-Feeling: lange Easing-Out-Kurve, viel Atemraum
    /// zwischen den Wellen. Cycle-Total = duration → wenn duration ein
    /// Vielfaches von stagger × 3 ist, läuft der Loop nahtlos.
    private static let waveDuration: Double = 4.5   // entspannter, natürlich
    private static let waveStagger: Double = 1.5    // 1.5s zwischen Wellen
    private static let waveBaseScale: CGFloat = 0.3
    private static let waveMaxScale: CGFloat = 1.7   // weit nach unten
    private static let waveLineWidth: CGFloat = 4.5  // dicker

    /// Halbkreis-Wave: ein 180°-Bogen am oberen Rand des Frames, mit
    /// Stroke-Round-Caps. Wird per `.scaleEffect(_:anchor: .top)`
    /// vom Top-Center aus expandiert (= Anker direkt am Wordmark-Bottom).
    @ViewBuilder
    private func wave(active: Bool, opacity: Double) -> some View {
        SemiCircleShape()
            .stroke(color, style: StrokeStyle(lineWidth: Self.waveLineWidth, lineCap: .round))
            .frame(width: width, height: width / 2)
            .scaleEffect(active ? Self.waveMaxScale : Self.waveBaseScale, anchor: .top)
            .opacity(active ? 0.0 : opacity)
    }

    var body: some View {
        // Frame bleibt schmal — Welle scaled über `waveMaxScale > 1`
        // visuell über das Frame raus, ohne das umgebende Layout
        // (Slogan, Buttons) nach unten zu verschieben.
        ZStack(alignment: .top) {
            wave(active: w2, opacity: 0.45)
            wave(active: w1, opacity: 0.65)
            wave(active: w0, opacity: 0.85)
        }
        .frame(width: width, height: width / 2)
        .onAppear {
            // Drei Wellen zeitversetzt anstoßen — Stagger 1s ergibt einen
            // ruhigen, kontinuierlichen Sweep statt hektischem Flackern.
            withAnimation(.easeOut(duration: Self.waveDuration).repeatForever(autoreverses: false)) {
                w0 = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.waveStagger) {
                withAnimation(.easeOut(duration: Self.waveDuration).repeatForever(autoreverses: false)) {
                    w1 = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.waveStagger * 2) {
                withAnimation(.easeOut(duration: Self.waveDuration).repeatForever(autoreverses: false)) {
                    w2 = true
                }
            }
        }
    }
}

/// Halbkreis-Bogen am oberen Rand — Mittelpunkt zentral oben, Bogen
/// öffnet nach unten (180° Sweep von 0° → 180°).
private struct SemiCircleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: 0),
            radius: rect.width / 2,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: false
        )
        return path
    }
}

struct DropsIconHero: View {
    var size: CGFloat = 120

    @State private var dotPulse = false

    /// iOS-App-Icon-Ratio (~22.5% des kleineren Achsmaßes).
    private var cornerRadius: CGFloat { size * 0.225 }

    var body: some View {
        ZStack {
            // Gradient-Background (helles → volles Violett, wie icon.json)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.brandVioletLight, Color.brandViolet],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.brandViolet.opacity(0.35), radius: 30, y: 12)

            // Innerer Glanz-Stroke für Liquid-Glass-Feel
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), Color.white.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )

            // Offene Runde: cremefarbener Ring, oranger Punkt in der Lücke.
            DropsMark(ringColor: .brandCream, dotColor: .brandOrange)
                .frame(width: size * 0.78, height: size * 0.78)
                .shadow(color: Color.brandOrange.opacity(dotPulse ? 0.55 : 0.15), radius: size * 0.05)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                dotPulse = true
            }
        }
    }
}

/// Nicht mehr verwendet seit dem Redesign 10/2026 (ersetzt durch `DropsMark`).
/// Hohler D-Buchstabe als SwiftUI-Path — 1:1 Replik des LetterD-D.svg.
/// Outer-Path + Inner-Path, beide CW gezeichnet → mit `FillStyle(eoFill: true)`
/// bekommt der innere Pfad einen Cutout-Effekt (klassischer "donut hole").
private struct LetterDShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024.0
        var path = Path()

        // ── Outer D ────────────────────────────────────────────
        path.move(to: CGPoint(x: 314 * s, y: 232 * s))
        path.addLine(to: CGPoint(x: 512 * s, y: 232 * s))
        // Großer Halbkreis nach rechts (bulge)
        path.addArc(center: CGPoint(x: 512 * s, y: 512 * s),
                    radius: 280 * s,
                    startAngle: .degrees(-90), endAngle: .degrees(90),
                    clockwise: false)
        path.addLine(to: CGPoint(x: 314 * s, y: 792 * s))
        // Bottom-left rounded corner
        path.addArc(center: CGPoint(x: 314 * s, y: 742 * s),
                    radius: 50 * s,
                    startAngle: .degrees(90), endAngle: .degrees(180),
                    clockwise: false)
        path.addLine(to: CGPoint(x: 264 * s, y: 282 * s))
        // Top-left rounded corner
        path.addArc(center: CGPoint(x: 314 * s, y: 282 * s),
                    radius: 50 * s,
                    startAngle: .degrees(180), endAngle: .degrees(270),
                    clockwise: false)
        path.closeSubpath()

        // ── Inner Cutout ───────────────────────────────────────
        path.move(to: CGPoint(x: 414 * s, y: 342 * s))
        path.addLine(to: CGPoint(x: 512 * s, y: 342 * s))
        path.addArc(center: CGPoint(x: 512 * s, y: 512 * s),
                    radius: 170 * s,
                    startAngle: .degrees(-90), endAngle: .degrees(90),
                    clockwise: false)
        path.addLine(to: CGPoint(x: 414 * s, y: 682 * s))
        path.addArc(center: CGPoint(x: 414 * s, y: 642 * s),
                    radius: 40 * s,
                    startAngle: .degrees(90), endAngle: .degrees(180),
                    clockwise: false)
        path.addLine(to: CGPoint(x: 374 * s, y: 382 * s))
        path.addArc(center: CGPoint(x: 414 * s, y: 382 * s),
                    radius: 40 * s,
                    startAngle: .degrees(180), endAngle: .degrees(270),
                    clockwise: false)
        path.closeSubpath()

        return path
    }
}

struct PulsingRing: View {
    let delay: Double
    let baseSize: CGFloat
    let color: Color
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.55), lineWidth: 1.5)
            .frame(width: baseSize, height: baseSize)
            .scaleEffect(animate ? 3.2 : 1.0)
            .opacity(animate ? 0 : 0.7)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeOut(duration: 3.2).repeatForever(autoreverses: false)) {
                        animate = true
                    }
                }
            }
    }
}

// MARK: - Welcome Step (Dark & Light Variante)


// MARK: - Custom Apple Button (UIViewRepresentable)

/// Nativer ASAuthorizationAppleIDButton ohne automatisches System-Credential-Sheet.
/// Muss in OnboardingView.swift stehen, da UIViewRepresentable SwiftUI benötigt.
struct AppleSignInButtonView: UIViewRepresentable {
    let type: ASAuthorizationAppleIDButton.ButtonType
    let style: ASAuthorizationAppleIDButton.Style
    let cornerRadius: CGFloat
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let btn = ASAuthorizationAppleIDButton(type: type, style: style)
        btn.cornerRadius = cornerRadius
        btn.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return btn
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        uiView.cornerRadius = cornerRadius
    }

    class Coordinator: NSObject {
        let onTap: () -> Void
        init(onTap: @escaping () -> Void) { self.onTap = onTap }
        @objc func tapped() { onTap() }
    }
}

// MARK: - Welcome Step

// MARK: - Onboarding Language Chip

/// Kompaktes Sprach-Menu für den Welcome- und Login-Screen. Zeigt den
/// 2-stelligen Kürzel + Chevron und klappt bei Tap ein Menu mit allen
/// AppLanguage-Fällen auf. Stand-alone (kein Parent-Store nötig), nutzt
/// `@AppStorage("appLanguage")` direkt.
struct OnboardingLanguageChip: View {
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                Button {
                    if appLanguage != lang.rawValue {
                        Haptic.selection()
                        withAnimation(.easeInOut(duration: 0.18)) {
                            appLanguage = lang.rawValue
                        }
                    }
                } label: {
                    HStack {
                        Text("\(lang.flag)  \(lang.label)")
                        if appLanguage == lang.rawValue {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            let current = AppLanguage(rawValue: appLanguage) ?? .german
            HStack(spacing: 6) {
                Text(current.flag).font(.system(size: 14))
                Text(current.shortCode)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.7))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.brandNight.opacity(0.5))
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(
                Capsule().fill(Color.white.opacity(0.6))
            )
            .overlay(
                Capsule().stroke(Color.brandNight.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

struct WelcomeStep: View {
    let onPhone: () -> Void
    let onApple: (Bool, String?) -> Void  // isNewUser, appleEmail
    let onGoogle: (Bool, String?) -> Void // isNewUser, googleEmail
    @AppStorage("appLanguage") private var appLanguage = "de"
    @Binding var isLoginMode: Bool
    var onBetaLogin: (() -> Void)? = nil   // Beta-Bypass: anonym einloggen

    @Environment(\.colorScheme) var systemColorScheme
    @State private var appeared = false
    @State private var typedSlogan = ""
    @State private var showCursor = false
    @State private var typewriterTask: Task<Void, Never>? = nil
    @StateObject private var appleAuth = AppleSignInManager()
    @StateObject private var googleAuth = GoogleSignInManager()

    // Quick-Login: wenn der letzte User im UserDefaults persistiert ist,
    // zeigen wir oberhalb der Standard-Apple-Buttons einen großen "Weiter
    // als X"-Button mit Avatar + Name. Tap löst sofort Apple Sign In aus
    // (Face ID übernimmt in ~1-2s, keine weitere Eingabe nötig).
    @State private var showAlternativeLogin = false
    @State private var isLinkingApple = false
    private var lastLoginName: String {
        UserDefaults.standard.string(forKey: "ud_lastLoginName") ?? ""
    }
    private var lastLoginImageURL: String? {
        let url = UserDefaults.standard.string(forKey: "ud_lastProfileImageURL") ?? ""
        return url.isEmpty ? nil : url
    }
    /// Quick-Login sichtbar, sobald ein Name persistiert ist. Bleibt auch
    /// sichtbar wenn der User "Anderes Konto verwenden" wählt — er sieht
    /// dann beide Optionen gleichzeitig (Quick-Login oben + alternative
    /// Apple-Sign-In/Sign-Up unten).
    private var hasQuickLogin: Bool {
        !lastLoginName.isEmpty
    }

    /// Slogan-Konstante — synchron zum Login-Block-Slogan und der App-
    /// Store-Subtitle „Drops — Triff Leute". Wird vom Typewriter konsumiert
    /// falls aktiviert. Vorher: "Sei dabei wenn's passiert." (out of sync).
    private let fullSlogan = "Triff Leute. Spontan."

    /// System-Setting hat Vorrang; sonst entscheidet die Uhrzeit
    private var isLight: Bool {
        switch systemColorScheme {
        case .light: return true
        case .dark:  return false
        default:     return !isNightTime()
        }
    }

    // MARK: Farbsystem je Variante
    // WelcomeStep läuft wie LoginView auf tiefviolettem Launch-Hintergrund —
    // alle Texte fix auf weiß invertiert.
    private var textPrimary: Color   { .white }
    private var textSecondary: Color { .white.opacity(0.75) }
    private var overlayColor: Color  { isLight ? .white : .black }
    private var overlayOpacity: Double { isLight ? 0.60 : 0.72 }
    private var mapBlur: CGFloat     { isLight ? 9 : 16 }
    private var appleButtonStyle: ASAuthorizationAppleIDButton.Style { isLight ? .black : .white }
    private var screenH: CGFloat  { UIScreen.main.bounds.height }
    // Wordmark deutlich größer als vorher (52/68 → 64/82) — gibt dem
    // "Drops"-Hero mehr Präsenz auf dem Aurora, passt zur reduzierten
    // Layout-Hierarchie (kein Icon mehr drüber).
    private var logoSize: CGFloat { screenH < 700 ? 64 : 82 }
    private var buttonPadV: CGFloat { screenH < 700 ? 12 : screenH < 850 ? 14 : 16 }

    @State private var blobPhase: CGFloat = 0

    var body: some View {
        // `.id(appLanguage)` zwingt SwiftUI den View-Tree komplett neu zu
        // bauen, wenn der Sprach-Chip die Sprache wechselt — sonst bleiben
        // die mit `tr(...)` aufgelösten Strings auf dem alten Wert cached.
        welcomeBody.id(appLanguage)
    }

    @ViewBuilder
    private var welcomeBody: some View {
        ZStack(alignment: .topTrailing) {
            // Launch-Screen-Violet, konsistent zum SplashView und LoginView.
            Color("LaunchBackground").ignoresSafeArea()

            // ── Inhalt ───────────────────────────────────────────────
            VStack(spacing: 0) {
                    Spacer(minLength: screenH < 700 ? 30 : 60)

                    // ── Logo + Hero ────────────────────────────────────
                    VStack(spacing: screenH < 700 ? 18 : 26) {
                        // Wordmark mit Aurora-Glow als Background — die
                        // Glow-Circles sind rein dekorativ und expandieren
                        // das Layout NICHT (sonst würde der Slogan zu weit
                        // unten sitzen). Bewusst KEIN Radar-Pulse mehr —
                        // der globale `AppAuroraBackground` liefert schon
                        // ambient Bewegung, doppelte Animation hier wäre
                        // visuelle Überladung auf einem Welcome-Screen.
                        // Normale SF-Rounded-Heavy-Wordmark — der Custom-D
                        // (LetterDShape) wirkte mit dem Aurora-Glow drum
                        // herum zu busy. Auf User-Wunsch ein einheitlicher
                        // Look mit dem Login-Screen.
                        DropsLogo(fontSize: logoSize, textColor: textPrimary)

                        // Hauptbotschaft — knüpft an den App-Store-Untertitel
                        // ("Drops — Triff Leute") an. Erste Zeile = Brand-Anker
                        // identisch zum Store, zweite Zeile pointiert den
                        // Spontan-Charakter der App.
                        VStack(spacing: 6) {
                            Text(tr("onboard.meet_people"))
                                .font(.system(size: screenH < 700 ? 28 : 32, weight: .bold, design: .default))
                                .foregroundColor(textPrimary)
                            Text(tr("onboard.spontaneously"))
                                .font(.system(size: screenH < 700 ? 28 : 32, weight: .bold, design: .default))
                                .foregroundColor(textPrimary)
                        }
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)

                    Spacer(minLength: 20)

                    // ── Buttons ───────────────────────────────────────
                    VStack(spacing: screenH < 700 ? 8 : 10) {

                        // Quick-Login bleibt immer oben sichtbar wenn ein Name
                        // persistiert ist — auch wenn der User "Anderes Konto
                        // verwenden" klickt (dann sieht er beide Optionen).
                        if hasQuickLogin {
                            quickLoginButton

                            if !showAlternativeLogin {
                                // Noch nicht aufgeklappt → zeig den Link zum Alternativ-Flow
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        showAlternativeLogin = true
                                    }
                                }) {
                                    Text(tr("onboard.use_different_account"))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                        .underline()
                                }
                                .dropsPressable()
                                .padding(.top, 6)
                            } else {
                                // Sichtbarer Trenner zwischen Quick-Login und Alternativ-Flow
                                HStack(spacing: 8) {
                                    Rectangle().fill(textSecondary.opacity(0.15)).frame(height: 1)
                                    Text(tr("onboard.or"))
                                        .font(.system(size: 11))
                                        .foregroundColor(textSecondary.opacity(0.5))
                                    Rectangle().fill(textSecondary.opacity(0.15)).frame(height: 1)
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        // Alternative Apple-Sign-In/Sign-Up-Buttons:
                        // — wenn Quick-Login NICHT verfügbar ist (Erstinstall) → immer anzeigen
                        // — wenn Quick-Login verfügbar ist → nur wenn User "Anderes Konto" geklickt hat
                        if !hasQuickLogin || showAlternativeLogin {
                            // ── Standard Apple Sign In / Sign Up ──────
                            // Conditional Rendering mit .id() — opacity-Lösung war
                            // unzuverlässig (iOS recycled den native UIView).
                            Button {
                                appleAuth.signIn { success, isNewUser in
                                    if success { onApple(isNewUser, appleAuth.lastAppleEmail) }
                                }
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: screenH < 700 ? 22 : 25)
                                        .fill(appleButtonStyle == .black ? Color.black : Color.white)
                                    if appleAuth.isLoading {
                                        DazuLoader()
                                            .tint(appleButtonStyle == .black ? .white : .black)
                                    } else {
                                        HStack(spacing: 10) {
                                            DazuIcon("apple.logo")
                                                .font(.system(size: 20, weight: .medium))
                                                .foregroundColor(appleButtonStyle == .black ? .white : .black)
                                            Text(tr(isLoginMode ? "onboard.apple_signin" : "onboard.apple_signup"))
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(appleButtonStyle == .black ? .white : .black)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: screenH < 700 ? 50 : 56, maxHeight: screenH < 700 ? 50 : 56)
                            .dropsPressable()
                            .disabled(appleAuth.isLoading)

                            // ── Google Sign In ──────────────────────────────
                            Button {
                                googleAuth.signIn { success, isNewUser in
                                    if success { onGoogle(isNewUser, googleAuth.lastGoogleEmail) }
                                }
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: screenH < 700 ? 22 : 25)
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(isLight ? 0.10 : 0.20), radius: 4, x: 0, y: 2)
                                    if googleAuth.isLoading {
                                        DazuLoader().tint(Color(hex: "1F1F1F"))
                                    } else {
                                        HStack(spacing: 10) {
                                            GoogleGLogo(size: 22)
                                            Text(tr("onboard.google_continue"))
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(Color(hex: "1F1F1F"))
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: screenH < 700 ? 50 : 56, maxHeight: screenH < 700 ? 50 : 56)
                            .dropsPressable()
                            .disabled(googleAuth.isLoading || appleAuth.isLoading)

                            // ── Phone (SMS-Code) ────────────────────────────
                            // Dritte Option neben Apple/Google. Delegiert den
                            // Phone-Auth-Flow ans Parent-View (OnboardingView),
                            // das die LoginView als fullScreenCover öffnet und
                            // Zugriff auf den `store` hat.
                            Button {
                                onPhone()
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: screenH < 700 ? 22 : 25)
                                        // Kräftigeres Lavendel als der Seitenhintergrund (#E9E3FF), sonst
                                        // verschwindet der Button darin. Fest, auch im Dark Mode.
                                        .fill(Color(red: 0.835, green: 0.800, blue: 1.000)) // #D5CCFF
                                        .shadow(color: .black.opacity(isLight ? 0.10 : 0.20), radius: 4, x: 0, y: 2)
                                    HStack(spacing: 10) {
                                        DazuIcon("phone.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.brandVioletFixed)
                                        Text(tr(isLoginMode
                                                ? "onboard.phone_signin"
                                                : "onboard.phone_signup"))
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.brandVioletFixed)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: screenH < 700 ? 50 : 56, maxHeight: screenH < 700 ? 50 : 56)
                            .dropsPressable()

                            // Toggle Login ↔ Registrieren — Button nimmt volle Breite,
                            // Label innen zentriert. Ohne .frame(maxWidth:.infinity)
                            // sitzt der Button mit natural width linksbündig.
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) { isLoginMode.toggle() }
                            }) {
                                (
                                    Text(isLoginMode ? tr("onboard.no_account_question") : tr("onboard.already_registered"))
                                        .foregroundColor(.white.opacity(0.72))
                                    + Text(" ")
                                    // Akzent-Text: Orange statt Brand-Violett — sonst
                                    // auf dem violetten Welcome-Hintergrund unsichtbar.
                                    + Text(isLoginMode ? tr("onboard.register_now") : tr("common.sign_in"))
                                        .foregroundColor(.accentOrange)
                                        .fontWeight(.bold)
                                )
                                .font(.system(size: 14))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                            }
                            .frame(maxWidth: .infinity)
                            .dropsPressable()
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                        }

                        // Fehler anzeigen (Apple + Google)
                        if let appleErr = appleAuth.errorMessage {
                            Text(appleErr)
                                .font(.system(size: 12))
                                .foregroundColor(.accentRed)
                                .multilineTextAlignment(.center)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        if let googleErr = googleAuth.errorMessage {
                            Text(googleErr)
                                .font(.system(size: 12))
                                .foregroundColor(.accentRed)
                                .multilineTextAlignment(.center)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // AGB nur bei Registrierung — opacity statt if, verhindert Layout-Shift
                        Text(tr("onboard.tos_notice"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .padding(.top, 8)
                            .opacity(isLoginMode ? 0 : 1)
                            .animation(.easeInOut(duration: 0.2), value: isLoginMode)
                    }
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 30)
                    .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.25), value: appeared)
                }
            .padding(.top, 12)
        }
        .onAppear {
            appeared = true
        }
        // ── Account-Linking Alert ─────────────────────────────────────────────
        .alert(
            "Konto bereits vorhanden",
            isPresented: Binding(
                get: { googleAuth.pendingLinkEmail != nil },
                set: { if !$0 { googleAuth.cancelLinking() } }
            )
        ) {
            Button("Mit Apple verbinden") { isLinkingApple = true }
            Button("Abbrechen", role: .cancel) { googleAuth.cancelLinking() }
        } message: {
            if let email = googleAuth.pendingLinkEmail {
                Text(tr("auth.link_apple_body").replacingOccurrences(of: "{email}", with: email))
            }
        }
        .onChange(of: isLinkingApple) { _, linking in
            guard linking else { return }
            isLinkingApple = false
            appleAuth.signIn { success, _ in
                guard success else { return }
                googleAuth.completeLinkingAfterAppleSignIn { linked in
                    if linked { onGoogle(false, googleAuth.lastGoogleEmail) }
                }
            }
        }
    }

    // MARK: Quick-Login-Button
    /// Großer Button "Weiter als [Name]" mit Avatar. Wenn Firebase noch
    /// eine gültige Auth-Session hat (was beim normalen Logout der Fall
    /// ist), wird das Apple-System-Sheet **übersprungen** und direkt
    /// re-authentifiziert. Sonst Fallback auf Apple Sign In mit Face ID.
    @ViewBuilder private var quickLoginButton: some View {
        Button(action: {
            // Silent re-auth wenn Firebase-Session noch lebt (kein Apple-Sheet)
            if Auth.auth().currentUser != nil {
                onApple(false, nil)   // exists=true Pfad in handleAppleSignInResult
                return
            }
            // Fallback: Firebase-Session weg → Apple Sign In nötig
            appleAuth.signIn { success, isNewUser in
                if success { onApple(isNewUser, appleAuth.lastAppleEmail) }
            }
        }) {
            HStack(spacing: 14) {
                // Avatar mit halb-offenem Orange-Ring (dazu-Logo-Signatur) —
                // Lücke oben rechts (zwischen 12 und 3 Uhr).
                ZStack {
                    Circle()
                        .trim(from: 0.0, to: 0.75)
                        .stroke(Color.brandOrangeFixed,
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 50, height: 50)
                    if let urlStr = lastLoginImageURL {
                        RemoteProfileImage(
                            url: urlStr,
                            fallbackEmoji: "👋",
                            size: 43,
                            strokeColor: .clear
                        )
                        .clipShape(Circle())
                    } else {
                        ZStack {
                            Circle().fill(Color.brandLavender).frame(width: 43, height: 43)
                            DazuProfileIcon(size: 26)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Text-Farben hier fix dunkel (brandNight) — der Button-
                    // Hintergrund ist eine weiße Capsule auf tiefviolettem
                    // Launch-Bg; weiße Texte wären unlesbar.
                    Text(tr("onboard.continue_as"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.brandNight.opacity(0.55))
                        .tracking(0.3)
                    Text(lastLoginName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.brandNight)
                        .lineLimit(1)
                }

                Spacer()

                // Arrow-Circle statt Apple-Logo — provider-agnostisch
                ZStack {
                    Circle()
                        .fill(Color.brandNight.opacity(0.07))
                        .frame(width: 32, height: 32)
                    DazuIcon("arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.brandNight.opacity(0.55))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: screenH < 700 ? 64 : 70)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 14, x: 0, y: 5)
            )
        }
        .dropsPressable()
        .disabled(appleAuth.isLoading)
        .overlay(
            Group {
                if appleAuth.isLoading {
                    Capsule().fill(.black.opacity(0.3))
                    DazuLoader().tint(.white)
                }
            }
        )
    }

    // MARK: Typewriter
    private func startTypewriter() {
        typewriterTask?.cancel()
        typewriterTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            for char in fullSlogan {
                guard !Task.isCancelled else { return }
                typedSlogan.append(char)
                try? await Task.sleep(nanoseconds: 95_000_000)
            }
        }
    }
}

struct OnboardingProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Color.brand : Color.primary.opacity(0.12))
                    .frame(height: 4)
                    .animation(.spring(response: 0.4), value: current)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Simple Name Step (new: name only)

struct SimpleNameStep: View {
    @Binding var name: String
    let onNext: () -> Void
    @AppStorage("appLanguage") private var appLanguage = "de"
    @FocusState private var focused: Bool
    @State private var appeared = false

    private let stepColor = Color.brand

    var body: some View {
        ZStack {
            // Markenviolett als Vollflächen-Hintergrund (statt neutralem
            // Lavendel), damit der Register-Screen klar als dazu-Flow lesbar
            // ist. OnboardingStepBackground legt noch die Blobs/Noise drüber.
            Color("LaunchBackground").ignoresSafeArea()
            OnboardingStepBackground(color: stepColor)

            VStack(spacing: 0) {
                Spacer()

                OnboardingPulseIcon(systemName: "person.fill", color: stepColor)
                    .padding(.bottom, 28)

                VStack(spacing: 10) {
                    Text(tr("onboard.whats_your_name"))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(tr("onboard.first_name_visible"))
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 36)

                // Name field
                ZStack(alignment: .leading) {
                    if name.isEmpty {
                        Text(tr("onboard.first_name"))
                            .foregroundColor(.textTertiary)
                            .font(.system(size: 17))
                            .padding(.leading, 20)
                    }
                    TextField("", text: $name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .onSubmit { if !name.trimmingCharacters(in: .whitespaces).isEmpty { onNext() } }
                        .onChange(of: name) { _, newValue in
                            let filtered = newValue.filter { $0.isLetter }
                            if filtered != newValue { name = filtered }
                        }
                }
                .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Color.white.opacity(0.75)))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(stepColor.opacity(0.3), lineWidth: 1))
                .padding(.horizontal, 28)

                Spacer()

                // Weiter-Button
                Button(action: onNext) {
                    Text(tr("onboard.continue"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            Capsule().fill(name.trimmingCharacters(in: .whitespaces).isEmpty
                                          ? Color.brand.opacity(0.4) : Color.brand)
                        )
                }
                .dropsPressable()
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 24)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: appeared)
            }
        }
        .onAppear {
            appeared = true
            // Apple-/Google-Name übernehmen falls Feld noch leer. In jedem
            // Fall NUR das erste Wort (= Vorname). Nachname nie ins Feld —
            // selbst wenn ud_appleGivenName fälschlich einen vollen Namen
            // enthält (Legacy-Installs), hier auf firstWord trimmen.
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                func firstName(from raw: String) -> String? {
                    let w = raw.split(separator: " ").first.map(String.init) ?? ""
                    return w.isEmpty ? nil : w
                }
                if let given = UserDefaults.standard.string(forKey: "ud_appleGivenName"),
                   let first = firstName(from: given) {
                    name = first
                } else if let display = Auth.auth().currentUser?.displayName,
                          let first = firstName(from: display) {
                    name = first
                    UserDefaults.standard.set(first, forKey: "ud_appleGivenName")
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
        }
    }
}

// MARK: - Birthday Step

struct BirthdayStep: View {
    let onNext: (Date) -> Void
    let onBack: (() -> Void)?
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var birthdate = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var appeared = false

    private let stepColor = Color.brand

    var body: some View {
        ZStack {
            OnboardingStepBackground(color: stepColor)

            VStack(spacing: 0) {
                // Back
                if let back = onBack {
                    HStack {
                        Button(action: back) {
                            DazuIcon("chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.textSecondary)
                                .padding(12)
                        }
                        .dropsPressable()
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }

                Spacer()

                OnboardingPulseIcon(systemName: "calendar", color: stepColor)
                    .padding(.bottom, 28)

                VStack(spacing: 10) {
                    Text(tr("onboard.when_born"))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(tr("onboard.age_private"))
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 28)

                DatePicker(
                    "",
                    selection: $birthdate,
                    in: ...Calendar.current.date(byAdding: .year, value: -18, to: Date())!,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.horizontal, 20)

                Spacer()

                Button(action: { onNext(birthdate) }) {
                    Text(tr("onboard.continue"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(Capsule().fill(Color.brand))
                }
                .dropsPressable()
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 24)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Gender Step

struct GenderStep: View {
    @Binding var selected: String
    let onNext: () -> Void
    let onBack: (() -> Void)?
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var appeared = false

    private let stepColor = Color.brand
    private var options: [(String, String, Bool)] {
        [
            (tr("onboard.gender_male_cap"), "♂",    false),
            (tr("onboard.gender_female_cap"), "♀",    false),
            (tr("onboard.gender_diverse_cap"),   "person.2.fill", true)
        ]
    }

    var body: some View {
        ZStack {
            OnboardingStepBackground(color: stepColor)

            VStack(spacing: 0) {
                // Back
                if let back = onBack {
                    HStack {
                        Button(action: back) {
                            DazuIcon("chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.textSecondary)
                                .padding(12)
                        }
                        .dropsPressable()
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }

                Spacer()

                OnboardingPulseIcon(systemName: "person.2.fill", color: stepColor)
                    .padding(.bottom, 28)

                VStack(spacing: 10) {
                    Text(tr("onboard.what_gender"))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(tr("onboard.set_once"))
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 36)

                VStack(spacing: 12) {
                    ForEach(options, id: \.0) { label, symbol, isSFSymbol in
                        let isSelected = selected == label
                        Button(action: { selected = label }) {
                            HStack(spacing: 14) {
                                if isSFSymbol {
                                    DazuIcon(symbol, accent: false)
                                        .font(.system(size: 22, weight: .medium))
                                        .frame(width: 28)
                                } else {
                                    Text(symbol)
                                        .font(.system(size: 24))
                                        .frame(width: 28)
                                }
                                Text(label)
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundColor(isSelected ? .white : .textPrimary)
                                Spacer()
                                if isSelected {
                                    DazuIcon("checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.lg)
                                    .fill(isSelected ? Color.brand : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.lg)
                                            .stroke(isSelected ? Color.clear : Color.primary.opacity(0.15), lineWidth: 1)
                                    )
                            )
                            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Color.white.opacity(0.75)))
                        }
                        .dropsPressable()
                        .animation(.spring(response: 0.3), value: isSelected)
                    }
                }
                .padding(.horizontal, 28)

                Spacer()

                Button(action: onNext) {
                    Text(tr("onboard.continue"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            Capsule().fill(selected.isEmpty ? Color.brand.opacity(0.4) : Color.brand)
                        )
                }
                .dropsPressable()
                .disabled(selected.isEmpty)
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 24)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Profile Setup Step (Name + Geburtstag + Geschlecht + Foto + Telefon)

struct ProfileSetupStep: View {
    @Binding var name:   String
    @Binding var phone:  String
    @Binding var selfie: UIImage?
    /// name, birthdate, gender (lowercase), phone
    let onNext: (String, Date, String, String) -> Void
    let onBack: (() -> Void)?

    @State private var birthdateText = ""          // "TT.MM.JJJJ" — Zahleneingabe
    @State private var parsedBirthdate: Date? = nil
    @State private var gender:  String = ""
    @State private var appeared = false
    @State private var showImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var showImageSourceSheet = false
    @FocusState private var nameFocused: Bool
    @FocusState private var dateFocused: Bool

    private let stepColor = Color.brand
    private var genderOptions: [(label: String, symbol: String, isSF: Bool)] {
        [
            (tr("onboard.gender_male_cap"), "♂", false),
            (tr("onboard.gender_female_cap"), "♀", false),
            (tr("onboard.gender_diverse_cap"),   "person.2.fill", true)
        ]
    }

    /// Mindestens 18 Jahre alt
    private var dateIsValid: Bool { parsedBirthdate != nil }
    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !gender.isEmpty
            && dateIsValid
            && phoneIsValid
    }

    /// Handynummer ist optional. Wenn der User eine angibt, müssen es ≥ 6 Ziffern sein.
    /// Ohne Nummer können Kontakte aus dem Adressbuch den User nicht finden.
    private var phoneIsValid: Bool {
        let digits = phone.filter { $0.isNumber }.count
        return digits == 0 || digits >= 6
    }

    /// Formatiert Roheingabe zu "TT.MM.JJJJ"
    private func formatBirthdateInput(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        var result = ""
        for (i, ch) in digits.prefix(8).enumerated() {
            if i == 2 || i == 4 { result += "." }
            result.append(ch)
        }
        return result
    }

    private func parseBirthdate(_ text: String) -> Date? {
        let parts = text.split(separator: ".").map { String($0) }
        guard parts.count == 3,
              let day   = Int(parts[0]), let month = Int(parts[1]), let year = Int(parts[2]),
              parts[2].count == 4
        else { return nil }
        // Explizite Bereichsprüfung — Calendar.date(from:) macht sonst Overflow
        let currentYear = Calendar.current.component(.year, from: Date())
        guard (1...12).contains(month),
              (1...31).contains(day),
              (1900...currentYear).contains(year)
        else { return nil }
        var comps = DateComponents()
        comps.day = day; comps.month = month; comps.year = year
        // date(from:) nochmal prüfen — fängt ungültige Tage ab (z.B. 31. Feb)
        guard let date = Calendar.current.date(from: comps),
              Calendar.current.component(.month, from: date) == month, // kein Overflow
              let min18 = Calendar.current.date(byAdding: .year, value: -18, to: Date()),
              date <= min18
        else { return nil }
        return date
    }

    var body: some View {
        ZStack {
            OnboardingStepBackground(color: stepColor)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Back-Button
                    if let back = onBack {
                        HStack {
                            Button(action: back) {
                                DazuIcon("chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.textSecondary).padding(12)
                            }
                            .dropsPressable()
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.top, 8)
                    }

                    // ── Profilfoto ────────────────────────────────────
                    Button { showImageSourceSheet = true } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 88, height: 88)
                            if let img = selfie {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipShape(Circle())
                            } else {
                                DazuIcon("person.fill", accent: false)
                                    .font(.system(size: 34))
                                    .foregroundColor(.textTertiary)
                            }
                            // Kamera-Badge
                            Circle()
                                .fill(stepColor)
                                .frame(width: 26, height: 26)
                                .overlay(DazuIcon("camera.fill", accent: false)
                                    .font(.system(size: 12)).foregroundColor(.white))
                                .offset(x: 30, y: 30)
                        }
                    }
                    .dropsPressable()
                    .padding(.top, 24).padding(.bottom, 16)

                    VStack(spacing: 6) {
                        Text(tr("onboard.tell_about_you"))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.textPrimary).multilineTextAlignment(.center)
                        Text(tr("onboard.your_profile_minute"))
                            .font(.system(size: 15)).foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28).padding(.bottom, 24)

                    VStack(alignment: .leading, spacing: 20) {

                        // ── Name ──────────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Label { Text(tr("onboard.first_name")) } icon: { DazuIcon("person.fill") }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            ZStack(alignment: .leading) {
                                if name.isEmpty {
                                    Text(tr("onboard.your_first_name"))
                                        .foregroundColor(.textTertiary).font(.system(size: 16))
                                        .padding(.leading, 16)
                                }
                                TextField("", text: $name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.textPrimary)
                                    .padding(.horizontal, 16).padding(.vertical, 14)
                                    .focused($nameFocused)
                                    .autocorrectionDisabled()
                                    .textContentType(.givenName)
                                    .onChange(of: name) { _, v in
                                        let f = v.filter { $0.isLetter }
                                        if f != v { name = f }
                                    }
                            }
                            .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.white.opacity(0.75)))
                            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(stepColor.opacity(0.3), lineWidth: 1))
                            HStack(spacing: 4) {
                                DazuIcon("lock.fill", accent: false).font(.system(size: 10))
                                Text(tr("onboard.cant_change_later"))
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.textTertiary)
                        }

                        // ── Geburtstag (Zahleneingabe) ────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Label { Text(tr("onboard.birthday")) } icon: { DazuIcon("calendar") }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            ZStack(alignment: .leading) {
                                if birthdateText.isEmpty {
                                    Text(tr("onboard.date_format"))
                                        .foregroundColor(.textTertiary).font(.system(size: 16))
                                        .padding(.leading, 16)
                                }
                                TextField("", text: $birthdateText)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(dateIsValid ? .textPrimary : (birthdateText.count == 10 ? .red : .textPrimary))
                                    .keyboardType(.numberPad)
                                    .padding(.horizontal, 16).padding(.vertical, 14)
                                    .focused($dateFocused)
                                    .onChange(of: birthdateText) { _, raw in
                                        let formatted = formatBirthdateInput(raw)
                                        if formatted != birthdateText { birthdateText = formatted }
                                        parsedBirthdate = parseBirthdate(birthdateText)
                                    }
                            }
                            .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.white.opacity(0.75)))
                            .overlay(RoundedRectangle(cornerRadius: Radius.card)
                                .stroke(birthdateText.count == 10 && !dateIsValid
                                        ? Color.red.opacity(0.5) : stepColor.opacity(0.3), lineWidth: 1))
                            HStack(spacing: 4) {
                                DazuIcon("lock.fill", accent: false).font(.system(size: 10))
                                Text(tr("onboard.cant_change_later"))
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.textTertiary)
                        }

                        // ── Geschlecht ────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Label { Text(tr("onboard.gender_label")) } icon: { DazuIcon("person.2.fill") }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            HStack(spacing: 10) {
                                ForEach(genderOptions, id: \.label) { opt in
                                    let isSelected = gender == opt.label
                                    Button { gender = opt.label } label: {
                                        VStack(spacing: 4) {
                                            if opt.isSF {
                                                DazuIcon(opt.symbol, accent: false)
                                                    .font(.system(size: 18)).frame(height: 22)
                                            } else {
                                                Text(opt.symbol).font(.system(size: 20)).frame(height: 22)
                                            }
                                            Text(opt.label).font(.system(size: 12, weight: .semibold))
                                        }
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .foregroundColor(isSelected ? .white : .textPrimary)
                                        .background(RoundedRectangle(cornerRadius: Radius.card)
                                            .fill(isSelected ? stepColor : Color.clear))
                                        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.white.opacity(0.75)))
                                        .overlay(RoundedRectangle(cornerRadius: Radius.card)
                                            .stroke(isSelected ? Color.clear : Color.primary.opacity(0.15), lineWidth: 1))
                                    }
                                    .dropsPressable()
                                    .animation(.spring(response: 0.25), value: isSelected)
                                }
                            }
                            HStack(spacing: 4) {
                                DazuIcon("lock.fill", accent: false).font(.system(size: 10))
                                Text(tr("onboard.cant_change_later"))
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.textTertiary)
                        }

                        // Telefonnummer-Block raus — die wird jetzt
                        // ausschließlich im Profil später hinterlegt (nicht
                        // beim Registrieren). Vermeidet Konflikte mit
                        // bestehenden Phone-Account-Verknüpfungen.
                    }
                    .padding(.horizontal, 24)

                    // ── Weiter-Button ─────────────────────────────────
                    Button {
                        nameFocused = false
                        dateFocused = false
                        guard let bd = parsedBirthdate else { return }
                        onNext(name.trimmingCharacters(in: .whitespaces),
                               bd,
                               gender,
                               phone.trimmingCharacters(in: .whitespaces))
                    } label: {
                        Text(tr("onboard.continue"))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(Capsule().fill(canContinue ? stepColor : stepColor.opacity(0.4)))
                    }
                    .dropsPressable()
                    .disabled(!canContinue)
                    .padding(.horizontal, 24)
                    .padding(.top, 28).padding(.bottom, 48)
                    .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 24)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: appeared)
                }
            }
        }
        .onAppear {
            appeared = true
            // Tastatur sofort beim Namen-Feld öffnen
            nameFocused = true
        }
        .confirmationDialog(tr("onboard.add_photo"), isPresented: $showImageSourceSheet) {
            Button(tr("onboard.camera")) { imagePickerSource = .camera; showImagePicker = true }
            Button(tr("onboard.photo_library")) { imagePickerSource = .photoLibrary; showImagePicker = true }
            Button(tr("onboard.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(image: $selfie, isPresented: $showImagePicker,
                            sourceType: imagePickerSource)
        }
    }
}

// MARK: - Country Code Picker

struct CountryCode: Identifiable, Equatable {
    let id = UUID()
    let flag: String
    let name: String
    let dial: String
}

// Nur Länder deren Vorwahl in der Firebase-SMS-Region-Policy auf whitelist
// steht (DACH + die 5 App-Sprachen). Vorher: 25 Länder — davon konnten die
// meisten eh keine SMS empfangen weil Firebase sie blockiert.
private var countryCodes: [CountryCode] {
    [
        CountryCode(flag: "🇩🇪", name: tr("country.germany"),         dial: "+49"),
        CountryCode(flag: "🇦🇹", name: tr("onboard.country_austria"), dial: "+43"),
        CountryCode(flag: "🇨🇭", name: tr("country.switzerland"),     dial: "+41"),
        CountryCode(flag: "🇮🇹", name: tr("country.italy"),           dial: "+39"),
        CountryCode(flag: "🇫🇷", name: tr("country.france"),          dial: "+33"),
        CountryCode(flag: "🇪🇸", name: tr("country.spain"),           dial: "+34"),
        CountryCode(flag: "🇬🇧", name: tr("onboard.country_uk"),      dial: "+44"),
        CountryCode(flag: "🇺🇸", name: tr("country.usa"),             dial: "+1"),
    ]
}

struct CountryPickerSheet: View {
    @Binding var selected: CountryCode
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var filtered: [CountryCode] {
        guard !search.isEmpty else { return countryCodes }
        return countryCodes.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.dial.contains(search)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandCream.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Header
                        Text(tr("onboard.country_dial_title"))
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundColor(.brandNight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 16)

                        // Suchfeld — rounded Chip auf Lavendel
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textTertiary)
                            TextField(tr("onboard.search_country"), text: $search)
                                .font(.system(size: 15))
                                .foregroundColor(.textPrimary)
                            if !search.isEmpty {
                                Button {
                                    search = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 15))
                                        .foregroundColor(.textTertiary)
                                }
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Capsule().fill(Color.brandLavender))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                        // Länder-Liste als liquidGlass-Card
                        VStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, cc in
                                Button {
                                    selected = cc
                                    dismiss()
                                } label: {
                                    HStack(spacing: 14) {
                                        // Flagge als rund-Chip auf Creme
                                        ZStack {
                                            Circle()
                                                .fill(Color.brandCream)
                                                .frame(width: 36, height: 36)
                                            Text(cc.flag).font(.system(size: 22))
                                        }
                                        Text(cc.name)
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            .foregroundColor(.brandNight)
                                        Spacer()
                                        Text(cc.dial)
                                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                                            .foregroundColor(.brandViolet)
                                            .monospacedDigit()
                                        if cc == selected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(.brandOrange)
                                        }
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 14)
                                }
                                .dropsPressable()
                                if idx < filtered.count - 1 {
                                    Divider().padding(.leading, 68)
                                }
                            }
                        }
                        .liquidGlass(cornerRadius: 20)
                        .padding(.horizontal, 16)

                        if filtered.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 28))
                                    .foregroundColor(.textTertiary)
                                Text(tr("onboard.search_country"))
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(.textSecondary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                        }

                        Spacer(minLength: 24)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("onboard.cancel")) { dismiss() }
                        .foregroundColor(.brand)
                }
            }
        }
    }
}

// MARK: - Login View (für bereits registrierte Nutzer)

struct LoginView: View {
    /// Wird nach erfolgreichem SMS-Verify aufgerufen. Parameter:
    /// `needsProfileSetup = true` → Phone-Nummer gehört zu einem frischen
    /// Account (oder einem Account ohne RTDB-Profil); der Parent muss ins
    /// Onboarding-Profile-Step routen und darf `isAuthenticated` NICHT
    /// setzen, sonst landet der User ohne Namen/Alter in der Hauptapp.
    /// `needsProfileSetup = false` → bestehender Account, direkt in die App.
    /// Default `nil` → LoginView übernimmt selbst (`isAuthenticated=true`).
    var onCompleted: ((_ needsProfileSetup: Bool) -> Void)? = nil
    /// Mode-Hint vom Caller — steuert nur Welcome-Text + CTA-Label.
    /// Default `false` = Signup-Flow (Registrierung); Caller aus Login-
    /// Button setzt es auf `true`.
    var isLoginMode: Bool = false

    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "de"
    @EnvironmentObject var store: AppStore
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @StateObject private var keyboard = KeyboardObserver()
    @StateObject private var auth = FirebaseAuthManager()
    @State private var phoneNumber = ""
    @State private var enteredCode = ""
    @State private var loginStep: LoginStep = .phone
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @FocusState private var fieldFocused: Bool
    @State private var appeared = false
    @State private var selectedCountry = countryCodes[0]
    @State private var showCountryPicker = false
    @Environment(\.colorScheme) var systemColorScheme

    enum LoginStep { case phone, code }

    // ── Identisches Farbsystem wie WelcomeStep ──
    private var isLight: Bool {
        switch systemColorScheme {
        case .light: return true
        case .dark:  return false
        default:     return !isNightTime()
        }
    }
    // LoginView läuft auf tiefviolettem Hintergrund — alle Text- und
    // Field-Farben sind fix hell (invertiert), unabhängig von System-
    // Dark/Light-Mode. `isLight` bleibt für Legacy-Properties nutzbar,
    // beeinflusst aber die Haupt-UI nicht mehr.
    private var textPrimaryColor: Color   { .white }
    private var textSecondaryColor: Color { .white.opacity(0.75) }
    private var overlayColor: Color  { .white }
    private var overlayOpacity: Double { 0.18 }
    private var mapBlur: CGFloat     { 0 }
    private var fieldTint: Color     { .white.opacity(0.14) }
    private var fieldStroke: Color   { .white.opacity(0.22) }

    // ── Adaptive Größen je Gerät ──────────────────────────────────────────
    private var screenH: CGFloat { UIScreen.main.bounds.height }
    private var fieldPadV: CGFloat  { screenH < 700 ? 11 : screenH < 850 ? 13 : 15 }
    private var buttonPadV: CGFloat { screenH < 700 ? 12 : screenH < 850 ? 14 : 16 }
    private var formSpacing: CGFloat { screenH < 700 ? 10 : 14 }
    private var formFontSize: CGFloat { screenH < 700 ? 15 : 16 }
    private var logoSize: CGFloat { screenH < 700 ? 52 : 68 }

    var body: some View {
        // `.id(appLanguage)` zwingt den View-Tree bei Sprachwechsel neu zu
        // bauen, damit `tr(...)` die neuen Strings auflöst (siehe
        // WelcomeStep.body für denselben Trick).
        loginBody.id(appLanguage)
    }

    @ViewBuilder
    private var loginBody: some View {
        ZStack(alignment: .topLeading) {
            // ── Launch-Screen-Violet-Hintergrund — identisch zum SplashView
            // damit der SMS-Flow sich direkt wie eine Fortsetzung des App-
            // Launches anfühlt. Alle Texte invertiert (weiß auf violett).
            Color("LaunchBackground").ignoresSafeArea()

            // Floating Zurück-Button — kein NavigationStack-Wrap nötig,
            // deshalb als eigenes Overlay oben links. Dismissed den
            // fullScreenCover zurück zum WelcomeStep.
            Button(action: { dismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                    Text(tr("onboard.cancel"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .padding(.top, 12)
            .padding(.leading, 16)
            .zIndex(10)

            VStack(spacing: 0) {
                    Spacer()

                    // ── Logo-Block ────────────────────────────────────────
                    // Reine Wordmark auf Lavendel — die alten Aurora-Glow-
                    // Circles (Orange + Grün) sind weg, sie liefen auf dem
                    // Lavendel-Hintergrund optisch warm/creme und brachen
                    // die Markenfarbe. Welcome-Text ist jetzt mode-abhängig.
                    VStack(spacing: 0) {
                        DropsLogo(fontSize: logoSize, textColor: textPrimaryColor)
                            .padding(.bottom, 18)

                        Text(isLoginMode
                             ? tr("onboard.welcome_back")
                             : tr("onboard.phone_signup_subtitle"))
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundColor(textSecondaryColor)
                            .kerning(0.3)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)

                    Spacer()

                    // ── Formular & Buttons ────────────────────────────────
                    VStack(spacing: formSpacing) {
                        if loginStep == .phone {
                            // Telefonnummer-Eingabe
                            HStack(spacing: 8) {
                                Button { showCountryPicker = true } label: {
                                    HStack(spacing: 6) {
                                        Text(selectedCountry.dial)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(textPrimaryColor)
                                        DazuIcon("chevron.down")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(textSecondaryColor)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, fieldPadV)
                                    .background(fieldTint, in: RoundedRectangle(cornerRadius: Radius.card))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.card)
                                        .stroke(fieldStroke, lineWidth: 1))
                                }
                                .dropsPressable()

                                TextField("", text: $phoneNumber)
                                    .placeholder(when: phoneNumber.isEmpty) {
                                        Text(tr("onboard.phone_number")).foregroundColor(textSecondaryColor.opacity(0.6))
                                    }
                                    .font(.system(size: formFontSize))
                                    .foregroundColor(textPrimaryColor)
                                    .keyboardType(.phonePad)
                                    .focused($fieldFocused)
                                    .padding(.horizontal, 14).padding(.vertical, fieldPadV)
                                    .background(fieldTint, in: RoundedRectangle(cornerRadius: Radius.card))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.card)
                                        .stroke(fieldFocused ? Color.brand.opacity(0.7) : fieldStroke,
                                                lineWidth: 1.5))
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))

                            Button(action: { sendLoginSMS() }) {
                                HStack {
                                    if isLoading { DazuLoader().tint(phoneNumber.count >= 6 ? .white : textPrimaryColor) }
                                    else { Text(tr("onboard.send_code_arrow")).font(.system(size: 16, weight: .semibold)) }
                                }
                                .foregroundColor(phoneNumber.count >= 6 ? .white : textSecondaryColor)
                                .frame(maxWidth: .infinity).padding(.vertical, buttonPadV)
                                .background(
                                    Capsule()
                                        .fill(phoneNumber.count >= 6 ? Color.brand : (isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.15)))
                                        .shadow(color: phoneNumber.count >= 6 ? Color.brand.opacity(0.4) : .clear,
                                                radius: 14, y: 6)
                                )
                            }
                            .dropsPressable()
                            .disabled(phoneNumber.count < 6 || isLoading)
                            .animation(.easeInOut(duration: 0.2), value: phoneNumber.count >= 6)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))


                        } else {
                            // Code-Eingabe
                            Text(tr("onboard.code_sent_to").replacingOccurrences(of: "{dial}", with: selectedCountry.dial).replacingOccurrences(of: "{number}", with: phoneNumber))
                                .font(.system(size: 13))
                                .foregroundColor(textSecondaryColor)
                                .transition(.opacity)

                            TextField("", text: $enteredCode)
                                .placeholder(when: enteredCode.isEmpty) {
                                    Text(tr("onboard.six_digit_code"))
                                        .foregroundColor(textSecondaryColor.opacity(0.6))
                                        .font(.system(size: 22, weight: .semibold))
                                }
                                .font(.system(size: 28, weight: .bold))
                                .multilineTextAlignment(.center)
                                .keyboardType(.numberPad)
                                .foregroundColor(textPrimaryColor)
                                .focused($fieldFocused)
                                .onChange(of: enteredCode) { _, v in
                                    if v.count > 6 { enteredCode = String(v.prefix(6)) }
                                }
                                .padding(.vertical, fieldPadV)
                                .background(fieldTint, in: RoundedRectangle(cornerRadius: Radius.card))
                                .overlay(RoundedRectangle(cornerRadius: Radius.card)
                                    .stroke(Color.brand.opacity(0.5), lineWidth: 1.5))
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))

                            Button(action: { verifyLoginCode() }) {
                                HStack {
                                    if isLoading { DazuLoader().tint(enteredCode.count == 6 ? .white : textPrimaryColor) }
                                    else { Text(tr("onboard.sign_in_arrow")).font(.system(size: 16, weight: .semibold)) }
                                }
                                .foregroundColor(enteredCode.count == 6 ? .white : textSecondaryColor)
                                .frame(maxWidth: .infinity).padding(.vertical, buttonPadV)
                                .background(
                                    Capsule()
                                        .fill(enteredCode.count == 6 ? Color.brand : (isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.15)))
                                        .shadow(color: enteredCode.count == 6 ? Color.brand.opacity(0.4) : .clear,
                                                radius: 14, y: 6)
                                )
                            }
                            .dropsPressable()
                            .disabled(enteredCode.count < 6 || isLoading)
                            .animation(.easeInOut(duration: 0.2), value: enteredCode.count == 6)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))

                            Button(tr("onboard.other_number")) {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    loginStep = .phone; enteredCode = ""
                                }
                            }
                            .font(.system(size: 13)).foregroundColor(textSecondaryColor.opacity(0.7))
                            .transition(.opacity)
                        }

                        if let err = errorMessage {
                            Text(err).font(.system(size: 12)).foregroundColor(.accentRed)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .animation(.easeInOut(duration: 0.22), value: loginStep)
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 24)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 30)
                    .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.25), value: appeared)

                    // Bottom-Link ist mode-abhängig: im Signup-Flow weisen
                    // wir zurück auf „Schon registriert? Anmelden", im
                    // Login-Flow auf „Noch kein Account? Registrieren".
                    // Tap dismissed den Sheet — der User kann im WelcomeStep
                    // dann die andere Variante wählen.
                    Button(action: { dismiss() }) {
                        Text(isLoginMode
                             ? tr("onboard.no_account_register")
                             : tr("onboard.already_registered_login"))
                            .font(.system(size: 13))
                            .foregroundColor(textSecondaryColor.opacity(0.6))
                    }
                    .padding(.top, 16)
                    .padding(.bottom, keyboard.height > 0 ? 16 : 40)
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: keyboard.height)
                }
            .padding(.top, 12)
        }
        // Kein `.ignoresSafeArea(.keyboard)` mehr: iOS schiebt das Formular
        // jetzt automatisch über die Tastatur, so dass das Nummer- und Code-
        // Feld sichtbar bleiben.
        .onTapGesture { fieldFocused = false }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(tr("onboard.finish")) { fieldFocused = false }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.brand)
            }
        }
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerSheet(selected: $selectedCountry)
        }
        .onAppear {
            appeared = true
            // Tastatur NICHT automatisch öffnen
        }
    }

    private func sendLoginSMS() {
        guard phoneNumber.count >= 6 else {
            errorMessage = tr("onboard.invalid_number")
            return
        }
        isLoading = true; errorMessage = nil
        let fullNumber = selectedCountry.dial + phoneNumber
        Task {
            await auth.sendVerificationCode(to: fullNumber)
            isLoading = false
            if case .smsSent = auth.state {
                withAnimation(.easeInOut(duration: 0.22)) { loginStep = .code }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { fieldFocused = true }
            } else if case .error(let msg) = auth.state {
                errorMessage = msg
            }
        }
    }

    private func verifyLoginCode() {
        isLoading = true; errorMessage = nil
        Task {
            let result = await auth.verifyCode(enteredCode)
            if !result.success {
                isLoading = false
                if case .error(let msg) = auth.state { errorMessage = msg }
                return
            }

            // ── Dupe-Account-Prevention ───────────────────────────────
            // Firebase legt bei jedem SMS-Login einen eigenständigen Phone-
            // UID an. Wenn diese Nummer schon zu einem Apple-/Google-
            // Konto gehört, bekäme der User zwei getrennte Accounts →
            // Dialog + Signout + Orphan-UID aufräumen.
            guard let currentUser = Auth.auth().currentUser else {
                isLoading = false; return
            }
            let currentUID = currentUser.uid
            let fullPhone = currentUser.phoneNumber ?? "\(selectedCountry.dial)\(phoneNumber)"
            let existingUID: String? = await withCheckedContinuation { cont in
                RealtimeDBManager.shared.findUserByPhone(fullPhone, excluding: currentUID) { uid in
                    cont.resume(returning: uid)
                }
            }
            if existingUID != nil {
                // Orphan-UID sofort wieder aufräumen damit nicht beim nächsten
                // Login dieselbe stub-UID eingeloggt wird.
                try? Auth.auth().signOut()
                try? await currentUser.delete()
                isLoading = false
                errorMessage = tr("auth.phone_belongs_to_other")
                return
            }

            // Prüfen ob dieser Firebase-User schon ein RTDB-Profil hat.
            // Firebase meldet `isNewUser` nur, wenn der Auth-Account frisch
            // angelegt wurde — ein Resurrection-Case (Konto gelöscht und
            // neu registriert) kann `isNewUser=false` sein, obwohl kein
            // Profil mehr existiert. Beide Fälle brauchen Profile-Setup.
            let profileExists: Bool = await withCheckedContinuation { cont in
                RealtimeDBManager.shared.hasExistingProfile { exists in
                    cont.resume(returning: exists)
                }
            }
            let needsSetup = result.isNewUser || !profileExists

            // Phone-Index aktualisieren (eigene UID beansprucht die Nummer).
            RealtimeDBManager.shared.claimPhoneIndex(fullPhone)

            isLoading = false

            if let onCompleted = onCompleted {
                // Parent übernimmt Routing (OnboardingView). WICHTIG: hier
                // NICHT `isAuthenticated = true` setzen — sonst mountet
                // LinkUpApp die MainTabView und das Onboarding-Profile-
                // Step geht verloren.
                onCompleted(needsSetup)
            } else {
                // Stand-alone-Fallback (kein Parent-Callback): nur bei
                // bestehendem Profil in die App; neue User sehen eine
                // Fehlermeldung mit Hinweis zur Registrierung.
                if needsSetup {
                    errorMessage = tr("auth.phone_no_account")
                    try? Auth.auth().signOut()
                } else {
                    store.syncReliabilityFromFirestore()
                    store.isAuthenticated = true
                }
            }
        }
    }
}

// MARK: - App Intro Step (nach Registrierung)

struct AppIntroStep: View {
    let onFinish: () -> Void

    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var appeared = false

    /// Sunset-Palette aus dem App-Branding (matched zu Logo, Buttons, Aurora-BG).
    private let orange = Color.auroraOrange
    private let green  = Color.auroraGreen
    private var brandGradient: LinearGradient {
        LinearGradient(colors: [orange, green],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private struct Feature {
        let icon: String
        let tint: Color
        let title: String
        let subtitle: String
    }

    /// Konkretere Features mit Brand-konformer Palette (Sunset-Orange-Akzente,
    /// kein Cyan/Purple mehr — passt nicht zu Drops). Subtitles sind präziser:
    /// statt „Privatsphäre inklusive" jetzt klar „BLE-Bestätigung" — der USP.
    private var features: [Feature] {
        [
            Feature(icon: "plus.circle.fill",
                    tint: Color.auroraOrange,
                    title: tr("onboard.feature_drop_title"),
                    subtitle: tr("onboard.feature_create_drop_subtitle")),
            Feature(icon: "dot.radiowaves.left.and.right",
                    tint: Color.auroraGreen,
                    title: tr("onboard.feature_ble_title"),
                    subtitle: tr("onboard.feature_ble_subtitle")),
            Feature(icon: "lock.shield.fill",
                    tint: Color(hex: "B49BE0"),
                    title: tr("onboard.feature_privacy_title"),
                    subtitle: tr("onboard.feature_privacy_subtitle")),
        ]
    }

    var body: some View {
        ZStack {
            // Aurora-Background statt OnboardingStepBackground — matched zum
            // Welcome-Step und der gesamten App. Sieht hochwertiger aus als
            // ein statischer RadialGradient.
            AppAuroraBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // ── App-Icon-Replik + Titel ───────────────────────────────
                VStack(spacing: 16) {
                    // Stylisierte App-Icon-Tile mit Violett-Gradient + Zeichen
                    // (DropsMark) — visuell deckungsgleich zum echten
                    // App-Icon ohne Asset-Referenz. Plus Glow.
                    ZStack {
                        Circle()
                            .fill(orange.opacity(0.18))
                            .frame(width: 130, height: 130)
                            .blur(radius: 14)
                        Circle()
                            .fill(green.opacity(0.14))
                            .frame(width: 110, height: 110)
                            .blur(radius: 18)
                            .offset(x: 8, y: 8)
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(brandGradient)
                            .frame(width: 88, height: 88)
                            .shadow(color: orange.opacity(0.35), radius: 14, y: 6)
                            .overlay(
                                DropsMark(ringColor: .brandCream, dotColor: .brandOrange)
                                    .frame(width: 68, height: 68)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.05), value: appeared)

                    VStack(spacing: 6) {
                        Text(tr("onboard.welcome_drops"))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(tr("onboard.meet_spontaneously"))
                            .font(.system(size: 16))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.12), value: appeared)
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 32)

                // ── Feature-Reihen (Fitness+-Stil) ────────────────────────
                VStack(spacing: 0) {
                    ForEach(features.indices, id: \.self) { idx in
                        let f = features[idx]
                        HStack(alignment: .top, spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .fill(f.tint.opacity(0.14))
                                    .frame(width: 48, height: 48)
                                DazuIcon(f.icon)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(f.tint)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.title)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                Text(f.subtitle)
                                    .font(.system(size: 13))
                                    .foregroundColor(.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8)
                            .delay(0.18 + Double(idx) * 0.08), value: appeared)

                        if idx < features.count - 1 {
                            Divider()
                                .padding(.leading, 88)
                                .opacity(0.5)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.75)))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.07), lineWidth: 1))
                .padding(.horizontal, 20)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.15), value: appeared)

                Spacer(minLength: 32)

                // ── „Los geht's"-Button mit Sunset-Gradient ───────────────
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onFinish()
                } label: {
                    HStack(spacing: 8) {
                        Text(tr("onboard.lets_go"))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        DazuIcon("arrow.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(brandGradient, in: RoundedRectangle(cornerRadius: Radius.lg))
                    .shadow(color: orange.opacity(0.35), radius: 14, y: 5)
                }
                .dropsPressable()
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.42), value: appeared)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { appeared = true }
    }
}


// MARK: - Pre-Sign-up Intro Slides
//
// 3 Slides mit den dazu-Core-Features. Beim ersten App-Start zu sehen,
// dann via `hasSeenIntro` ausgeblendet und der User landet direkt im
// Welcome/Sign-up-Step.
private struct IntroSlidesView: View {
    let onFinish: () -> Void
    @State private var currentIndex = 0

    private let slides: [IntroSlide] = [
        IntroSlide(
            title: "Spontan treffen.",
            subtitle: "Kein Chat, kein Smalltalk. Wer Bock hat, kommt dazu.",
            kind: .joinDemo
        ),
        IntroSlide(
            title: "In deiner Nähe.",
            subtitle: "Freunde und offene Runden siehst du live — ohne Umwege.",
            kind: .mapDemo
        ),
        IntroSlide(
            title: "Dein Standort bleibt deins.",
            subtitle: "Freunde sehen dich live. Fremde nur zeitversetzt und ungefähr.",
            kind: .privacyDemo
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                DazuWordmark(color: .brandNight, dotColor: .brandOrange)
                    .frame(height: 24)
                Spacer()
                Button(action: onFinish) {
                    Text(tr("common.skip"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.55))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer(minLength: 0)

            TabView(selection: $currentIndex) {
                ForEach(Array(slides.enumerated()), id: \.offset) { idx, slide in
                    IntroSlideCard(slide: slide, isActive: currentIndex == idx)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: currentIndex) { _, _ in
                Haptic.selection()
            }

            // Rondesignlab-Dot-Indicator: aktive Pille ist orange, inaktive Lavendel
            HStack(spacing: 8) {
                ForEach(slides.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == currentIndex ? Color.brandOrange : Color.brandLavender)
                        .frame(width: i == currentIndex ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentIndex)
                }
            }
            .padding(.vertical, 16)

            Spacer(minLength: 0)

            Button {
                Haptic.selection()
                if currentIndex < slides.count - 1 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        currentIndex += 1
                    }
                } else {
                    onFinish()
                }
            } label: {
                Text(currentIndex < slides.count - 1 ? "Weiter" : "Loslegen")
                    .dropsPrimaryButton()
            }
            .dropsPressable()
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Color.brandCream.ignoresSafeArea()
                AppAuroraBackground().ignoresSafeArea()
            }
        )
    }
}

private enum IntroSlideKind {
    case joinDemo       // Dot kommt zum Ring
    case mapDemo        // Pulsierende Ring-Pins auf Mini-Karte
    case privacyDemo    // Fuzzy-Lavendel-Zone über scharfem Dot
}

private struct IntroSlide {
    let title: String
    let subtitle: String
    let kind: IntroSlideKind
}

/// Jeder Slide hat eine eigene animierte Visual-Demo statt eines
/// statischen Icons — macht das Onboarding lebendig und zeigt direkt
/// wie das Feature wirkt.
private struct IntroSlideCard: View {
    let slide: IntroSlide
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 0)
            // Animiertes Hero-Visual (per Slide-Kind)
            Group {
                switch slide.kind {
                case .joinDemo:    JoinDotDemo(active: isActive)
                case .mapDemo:     MapPulseDemo(active: isActive)
                case .privacyDemo: PrivacyFuzzDemo(active: isActive)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 240)

            VStack(alignment: .leading, spacing: 12) {
                (Text(slide.title.dropLast()).foregroundColor(.brandViolet)
                 + Text(".").foregroundColor(.brandOrange))
                    .font(.system(size: 36, weight: .heavy, design: .rounded))

                Text(slide.subtitle)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
    }
}

/// Slide 1: Oranger Dot kreist außen um offenen Ring und dockt in der
/// Lücke oben rechts an — Signatur-Animation vom dazu-Logo.
private struct JoinDotDemo: View {
    let active: Bool
    @State private var phase: Int = 0

    // Dock-Position: Lücke oben rechts beim offenen Ring. Ring hat Radius
    // ca. 60pt in 160x160 Frame; Dot sitzt bei (-45°) = oben rechts.
    private let dockAngle: Double = -45
    private let orbitRadius: CGFloat = 95
    private let dockRadius: CGFloat = 60

    var body: some View {
        ZStack {
            // Offener Ring in Violett.
            OpenRingShape()
                .fill(Color.brandViolet)
                .frame(width: 160, height: 160)
                .shadow(color: Color.brandViolet.opacity(0.25), radius: 24, y: 8)

            // Oranger Dot der um den Ring kreist und dann in die Lücke dockt.
            ZStack {
                Circle()
                    .fill(Color.brandOrange.opacity(0.4))
                    .frame(width: 36, height: 36)
                    .blur(radius: 8)
                Circle()
                    .fill(Color.brandOrange)
                    .frame(width: 24, height: 24)
            }
            .offset(x: phase == 2 ? dockRadius : orbitRadius)
            .rotationEffect(.degrees(phase == 0 ? dockAngle - 360 : dockAngle))
            .scaleEffect(phase == 2 ? 1.15 : 1.0)
            .animation(phase == 0
                       ? nil
                       : phase == 1
                            ? .easeInOut(duration: 1.6)
                            : .spring(response: 0.5, dampingFraction: 0.6),
                       value: phase)
        }
        .onAppear { if active { runLoop() } }
        .onChange(of: active) { _, new in if new { runLoop() } }
    }

    private func runLoop() {
        // 0: Reset (snap zu Start ohne Animation) → 1: orbit → 2: dock
        phase = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            phase = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.75) {
            phase = 2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            if active { runLoop() }
        }
    }
}

/// Slide 2: Drei Mini-Ring-Pins pulsieren versetzt auf einer leeren
/// Karten-Fläche — zeigt „offene Runden in der Nähe".
private struct MapPulseDemo: View {
    let active: Bool
    @State private var pulses: [Bool] = [false, false, false]

    var body: some View {
        ZStack {
            // Karten-Simulacrum: weißer Container mit Lavendel-Flächen die
            // wie Stadtblöcke wirken.
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
                .frame(width: 280, height: 220)
                .shadow(color: Color(red: 0.357, green: 0.239, blue: 0.961).opacity(0.1), radius: 12, y: 6)

            // Städte-"Blocks" als Deko
            Group {
                RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.95, green: 0.93, blue: 1.0))
                    .frame(width: 60, height: 42).offset(x: -75, y: -55)
                RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.95, green: 0.93, blue: 1.0))
                    .frame(width: 50, height: 36).offset(x: 70, y: -62)
                RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.95, green: 0.93, blue: 1.0))
                    .frame(width: 70, height: 40).offset(x: 65, y: 45)
                // Straßen-Linien
                Rectangle().fill(Color(red: 0.95, green: 0.93, blue: 1.0))
                    .frame(width: 240, height: 4).offset(y: -10)
                Rectangle().fill(Color(red: 0.95, green: 0.93, blue: 1.0))
                    .frame(width: 4, height: 180).offset(x: 10)
            }

            // Drei Pins an versetzten Positionen
            miniPin(0).offset(x: -60, y: -40)
            miniPin(1).offset(x: 50, y: -10)
            miniPin(2).offset(x: -20, y: 60)
        }
        .onAppear { if active { runPulses() } }
        .onChange(of: active) { _, new in if new { runPulses() } }
    }

    private func miniPin(_ idx: Int) -> some View {
        ZStack {
            // Pulse-Ring in Orange (nicht violett) damit Puls klar sichtbar.
            Circle()
                .stroke(Color(red: 1.0, green: 0.627, blue: 0.180).opacity(0.6), lineWidth: 2)
                .frame(width: 42, height: 42)
                .scaleEffect(pulses[idx] ? 1.8 : 0.9)
                .opacity(pulses[idx] ? 0.0 : 0.9)

            // Pin: Weißer Kreis mit orangenem Ring (wie Friend-Pin auf Karte)
            Circle()
                .fill(Color.white)
                .frame(width: 36, height: 36)
                .overlay(Circle().stroke(Color(red: 1.0, green: 0.627, blue: 0.180), lineWidth: 3))
                .shadow(color: Color(red: 1.0, green: 0.627, blue: 0.180).opacity(0.3), radius: 6, y: 2)

            // DazuProfileIcon mittig
            DazuProfileIcon(size: 20)
        }
    }

    private func runPulses() {
        for i in pulses.indices {
            pulses[i] = false
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.4) {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    pulses[i] = true
                }
            }
        }
    }
}

/// Slide 3: Ein scharfer orangener Dot (echter Standort) wird von einem
/// weichen Lavendel-Blur (die „ungefähre" Sichtbarkeit) überdeckt — zeigt
/// den Privacy-Schutz direkt visuell.
private struct PrivacyFuzzDemo: View {
    let active: Bool
    @State private var showFuzz: Bool = false

    var body: some View {
        // Zwei Karten nebeneinander: "Du siehst dich scharf" (links) vs.
        // "Andere sehen dich unscharf" (rechts). Die rechte Karte animiert
        // ihre Fuzz-Blur-Welle und zeigt damit das 500m-Rounding.
        HStack(spacing: 16) {
            privacyCard(
                title: "Freunde",
                tint: Color.brandOrange,
                showPrecise: true
            )
            privacyCard(
                title: "Fremde",
                tint: Color.brandViolet,
                showPrecise: false
            )
        }
        .onAppear { if active { startAnimation() } }
        .onChange(of: active) { _, new in if new { startAnimation() } else { showFuzz = false } }
    }

    private func startAnimation() {
        showFuzz = false
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            showFuzz = true
        }
    }

    @ViewBuilder
    private func privacyCard(title: String, tint: Color, showPrecise: Bool) -> some View {
        VStack(spacing: 10) {
            ZStack {
                // Karten-Card
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 140, height: 160)
                    .shadow(color: Color.brandViolet.opacity(0.1), radius: 8, y: 4)

                // Mini Stadt-Blöcke
                Group {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.95, green: 0.93, blue: 1.0))
                        .frame(width: 36, height: 24)
                        .offset(x: -36, y: -42)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.95, green: 0.93, blue: 1.0))
                        .frame(width: 28, height: 20)
                        .offset(x: 36, y: -45)
                    Rectangle()
                        .fill(Color(red: 0.95, green: 0.93, blue: 1.0))
                        .frame(width: 110, height: 2.5)
                        .offset(y: -15)
                }

                if showPrecise {
                    // Links: scharfer oranger Pin mit kleinem Ring
                    ZStack {
                        Circle()
                            .fill(Color.brandOrange.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .blur(radius: 4)
                        Circle()
                            .fill(Color.brandOrange)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .shadow(color: Color.brandOrange.opacity(0.5), radius: 4)
                    }
                    .offset(y: 10)
                } else {
                    // Rechts: unscharfer Blob (so sehen andere dich).
                    // Animiert zwischen zwei Blur-Zuständen und bewegt sich
                    // leicht, um das "ungefähr" visuell zu machen.
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.brandViolet.opacity(0.55),
                                         Color.brandViolet.opacity(0.0)],
                                center: .center, startRadius: 4, endRadius: 60
                            )
                        )
                        .frame(width: 110, height: 110)
                        .blur(radius: showFuzz ? 14 : 8)
                        .scaleEffect(showFuzz ? 1.1 : 0.9)
                        .offset(x: showFuzz ? 8 : -6,
                                y: showFuzz ? -4 : 14)
                }
            }
            // Caption-Chip — Freunde (Person-Icon) vs. Fremde (Eye-Icon).
            HStack(spacing: 4) {
                Image(systemName: showPrecise ? "person.2.fill" : "eye.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
            }
            .foregroundColor(tint)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.15)))
        }
    }
}
