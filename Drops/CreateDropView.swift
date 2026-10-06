import SwiftUI
import MapKit
import CoreLocation
import TipKit

// Makes the sheet truly transparent by clearing every UIKit layer
// between UIHostingController.view and the window.
// On modern iOS the white comes from _UISheetDetentContainerView /
// UIDropShadowView which sit ABOVE the hosting VC's own view.
private struct _ClearSheetBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Run once after layout so the sheet hierarchy is fully built
        DispatchQueue.main.async { Self.clearSheetLayers() }
        // Run again slightly later in case iOS re-applies a background
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Self.clearSheetLayers() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { Self.clearSheetLayers() }
    }

    private static func clearSheetLayers() {
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else { return }

        // Walk to the topmost presented VC (our sheet's UIHostingController)
        var vc = window.rootViewController
        while let next = vc?.presentedViewController { vc = next }
        guard let sheetVC = vc else { return }

        // 1. Clear the presentation controller's container view —
        //    this is the UISheetPresentationController's root view and
        //    is typically where the white rounded-rect background lives.
        sheetVC.presentationController?.containerView?.backgroundColor = .clear
        sheetVC.presentationController?.containerView?.subviews.forEach {
            $0.backgroundColor = .clear
        }

        // 2. Clear the VC's own view
        sheetVC.view.backgroundColor = .clear

        // 3. Traverse UP the superview chain (handles _UISheetDetentContainerView,
        //    UIDropShadowView, and other wrapper views on iOS 16–26).
        var view: UIView? = sheetVC.view
        for _ in 0..<6 {
            view?.backgroundColor = .clear
            view = view?.superview
        }
    }
}

class LocationSearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var searchText = ""
    @Published var results: [MKLocalSearchCompletion] = []
    @Published var selectedLocation: DropLocationResult? = nil
    private var completer = MKLocalSearchCompleter()

    /// Bekannte Ortsnamen der Drops-Servicezone für Text-Filterung
    private static let zoneKeywords: [String] = [
        "münchen", "munich",
        "schwabing", "maxvorstadt", "haidhausen", "bogenhausen", "sendling",
        "neuhausen", "nymphenburg", "pasing", "aubing", "moosach", "allach",
        "milbertshofen", "freimann", "trudering", "riem", "perlach", "neuperlach",
        "solln", "forstenried", "hadern", "lochhausen", "feldmoching", "hasenbergl",
        "unterschleißheim", "oberschleißheim", "ismaning", "unterföhring",
        "haar", "ottobrunn", "unterhaching", "grünwald", "gauting",
        "germering", "puchheim", "karlsfeld", "dachau", "gilching",
        "bayern", "bavaria"
    ]

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        // Suche auf aktuelle Region begrenzen (~50 km Radius um Nutzerstandort)
        updateRegion()
    }

    func updateRegion(center: CLLocationCoordinate2D? = nil) {
        let coord = center ?? CLLocationManager().location?.coordinate
            ?? CLLocationCoordinate2D(latitude: 48.137, longitude: 11.575) // München fallback
        completer.region = MKCoordinateRegion(
            center: coord,
            latitudinalMeters: 50_000,
            longitudinalMeters: 50_000
        )
    }

    func search(_ query: String) { completer.queryFragment = query }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let keywords = Self.zoneKeywords
        var seen = Set<String>()
        let filtered = completer.results.filter { r in
            // 1. Nur Ergebnisse aus der Drops-Servicezone
            let combined = (r.title + " " + r.subtitle).lowercased()
            let inZone = keywords.contains { combined.contains($0) }
            guard inZone else { return false }
            // 2. Duplikate: nur der erste Treffer pro Titel zählt
            return seen.insert(r.title.lowercased()).inserted
        }
        results = Array(filtered.prefix(5))
    }

    func selectResult(_ result: MKLocalSearchCompletion, completion: @escaping (DropLocationResult?) -> Void) {
        let request = MKLocalSearch.Request(completion: result)
        MKLocalSearch(request: request).start { response, _ in
            guard let item = response?.mapItems.first else { completion(nil); return }
            let loc = DropLocationResult(
                title: item.name ?? result.title,
                subtitle: result.subtitle,
                coordinate: item.placemark.coordinate
            )
            DispatchQueue.main.async { completion(loc) }
        }
    }
}

struct DropLocationResult {
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Emoji Suggestion Engine

private let emojiKeywords: [(keywords: [String], emoji: String)] = [
    (["fußball", "fussball", "soccer", "football"], "⚽"),
    (["basketball"], "🏀"),
    (["volleyball"], "🏐"),
    (["tennis"], "🎾"),
    (["golf"], "⛳"),
    (["kaffee", "coffee", "café", "cafe"], "☕"),
    (["tee", "tea"], "🍵"),
    (["bier", "beer", "brauen", "craft"], "🍺"),
    (["wein", "wine", "vino"], "🍷"),
    (["cocktail", "bar", "drink"], "🍹"),
    (["pizza"], "🍕"),
    (["burger", "mcdonald", "fastfood"], "🍔"),
    (["sushi", "japanisch"], "🍣"),
    (["eis", "eiscreme", "frozen"], "🍦"),
    (["kuchen", "cake", "torte", "dessert"], "🎂"),
    (["essen", "restaurant", "lunch", "dinner", "mittag", "abend"], "🍽️"),
    (["frühstück", "breakfast", "brunch"], "🥐"),
    (["laufen", "joggen", "running", "jogging", "rennen"], "🏃"),
    (["wandern", "hiking", "hike", "berg", "mountain"], "🥾"),
    (["schwimmen", "swimming", "pool", "freibad"], "🏊"),
    (["fahrrad", "cycling", "bike", "radfahren", "rad"], "🚴"),
    (["yoga", "meditation"], "🧘"),
    (["fitness", "gym", "training", "workout", "sport"], "💪"),
    (["gaming", "zocken", "spielen", "gamer", "game"], "🎮"),
    (["kino", "film", "movie", "cinema"], "🎬"),
    (["musik", "konzert", "concert", "festival", "musik"], "🎵"),
    (["party", "feiern", "club", "disco"], "🎉"),
    (["geburtstag", "birthday"], "🎂"),
    (["shoppen", "shopping", "einkaufen", "kaufen"], "🛍️"),
    (["museum", "ausstellung", "galerie"], "🏛️"),
    (["strand", "beach", "meer", "sea"], "🏖️"),
    (["park", "spazieren", "spaziergang", "garten", "walk"], "🌳"),
    (["hund", "dog", "welpe", "gassi"], "🐕"),
    (["lernen", "studieren", "study", "büfeln", "bibliothek"], "📚"),
    (["arbeiten", "work", "meeting", "büro", "homeoffice"], "💼"),
    (["klettern", "climbing", "bouldern", "boulder"], "🧗"),
    (["ski", "snowboard", "skifahren"], "⛷️"),
    (["tanzen", "dance", "dancing"], "💃"),
    (["picknick", "picnic", "wiese"], "🧺"),
    (["kochen", "cooking", "cook", "küche"], "👨‍🍳"),
    (["flohmarkt", "markt", "market", "antik"], "🏪"),
    (["karten", "brettspiel", "board", "tabletop", "monopoly"], "🎲"),
    (["basteln", "basteln", "craft", "diy", "malen", "paint"], "🎨"),
    (["spazieren", "spaziergang"], "🚶"),
]

func suggestEmojis(for text: String) -> [String] {
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
    let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)
    var matched: [String] = []
    for entry in emojiKeywords {
        for word in words {
            if entry.keywords.contains(where: { word.contains($0) || $0.contains(word) && word.count >= 3 }) {
                if !matched.contains(entry.emoji) { matched.append(entry.emoji) }
                break
            }
        }
        if matched.count >= 6 { break }
    }
    return matched
}

/// Multi-Step Create-Flow — splittet die Felder in überschaubare Pages
/// damit User nicht mehr scrollen müssen.
enum CreateDropStep: Int, CaseIterable, Identifiable {
    case what  = 0  // Aktivität + Emoji
    case when  = 1  // Zeit + Dauer + Max. Teilnehmer
    case whereAt = 2  // Ort + CTA

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .what:    return "Was machst du?"
        case .when:    return "Wann und wie lange?"
        case .whereAt: return "Wo trefft ihr euch?"
        }
    }
}

struct CreateDropView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var currentStep: CreateDropStep = .what

    /// Falls aus dem Community-Dashboard geöffnet — markiert den entstehenden
    /// Drop als Community-Drop und triggert automatischen Push an Mitglieder.
    var communityID: String? = nil
    /// Pre-Fill für die Aktivität (Name + Emoji). Wird vom Community-Dashboard
    /// gesetzt, damit der Tennis-Creator nicht jedes Mal Tennis selber tippen muss.
    var prefilledActivityName: String? = nil
    var prefilledActivityEmoji: String? = nil
    /// Max-Teilnehmer-Cap. Default 15 für normale Drops; Community-Drops
    /// können auf 100 hochgesetzt werden (z.B. Laufgruppen).
    var maxParticipantsLimit: Int = 15
    /// Wenn true: First-Drop-Coach-Overlay wird angezeigt (kommt vom WelcomeSheet-CTA).
    var isWalkthrough: Bool = false

    // ── First-Drop Coach-Mark Overlay ──────────────────────────────────────
    @State private var coachStep: CoachStep? = nil
    @State private var coachHighlightFrame: CGRect = .zero
    @AppStorage("hasCompletedFirstDropWalkthrough") private var walkthroughDone = false

    // Coach-Mark Tips — TipKit zeigt jeden genau einmal (MaxDisplayCount 1),
    // danach werden sie automatisch als gesehen markiert.
    @State private var activityTip = ActivityTip()
    @State private var timeTip    = TimeTip()
    @State private var startTip   = StartDropTip()

    @State private var activityName: String = ""
    @State private var selectedEmoji: String = ""
    @State private var emojiLockedByUser = false
    @State private var dropDescription: String = ""
    @State private var scheduledTime: String = "Jetzt"
    @State private var showCustomTimePicker = false
    @State private var customDate: Date = Date()
@State private var selectedLocationType: LocationType = CLLocationManager().authorizationStatus == .authorizedWhenInUse || CLLocationManager().authorizationStatus == .authorizedAlways ? .current : .searched
    @State private var maxParticipants: Int = 10   // 2–15
    @State private var durationMinutes: Int = 120  // 0 = kein Limit
    @State private var isCreating = false
    @State private var created = false
    /// Nach erfolgreichem Swipe → zeigt die Full-Screen Logo-Celebration
    /// an, die von allen Seiten in Richtung Zentrum aufbaut. Löst nach
    /// Fertigstellung den eigentlichen `performCreate` aus.
    @State private var showJoinCelebration = false
    @State private var showPinMap = false
    @StateObject private var searchVM = LocationSearchViewModel()
    @State private var selectedLocationResult: DropLocationResult? = nil
    @State private var pinnedCoordinate: CLLocationCoordinate2D? = nil

    @State private var sheetPulse = false
    @State private var pendingHomeZoneCoord: CLLocationCoordinate2D? = nil
    @State private var showEmojiPicker = false
    // Sheet-States für den Satz-Flow (tap auf ein Wort → öffnet Sheet)
    @State private var showDurationSheet = false
    @State private var showParticipantsSheet = false
    @State private var showLocationSheet = false

    var suggestedEmojis: [String] { suggestEmojis(for: activityName) }

    /// Nur leer oder explizit vom Nutzer gewählt — kein Auto-Vorschlag im Kreis.
    var displayEmoji: String { selectedEmoji }

    var locationSubtitle: String {
        switch selectedLocationType {
        case .current:  return tr("create.current_location")
        case .searched: return selectedLocationResult?.title ?? tr("create.search_place")
        case .pin:      return pinnedCoordinate != nil ? tr("create.pin_set") : tr("create.tap_on_map_caps")
        }
    }

    var body: some View {
        let isCommunityDrop = communityID != nil
        return ZStack {
            // Vollflächiger App-Hintergrund — bei Community-Drop in Clero-Grün-Tint,
            // sonst der normale Aurora-Background.
            if isCommunityDrop {
                LinearGradient(
                    colors: [
                        Color.cleroGreen.opacity(0.35),
                        Color.cleroGreen.opacity(0.18),
                        Color.bgPrimary
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            } else {
                AppAuroraBackground().ignoresSafeArea()
            }

            // Creme-Hintergrund (neues Design-System) + sanfte Violett-Blobs
            Color.brandCream.ignoresSafeArea()
            ZStack {
                Circle()
                    .fill(Color.brandViolet.opacity(0.14))
                    .frame(width: 320, height: 320)
                    .blur(radius: 90)
                    .offset(x: sheetPulse ? 60 : -40, y: sheetPulse ? -80 : -20)
                Circle()
                    .fill(Color.brandMint.opacity(0.18))
                    .frame(width: 240, height: 240)
                    .blur(radius: 75)
                    .offset(x: sheetPulse ? -70 : 40, y: sheetPulse ? 20 : -60)
                Circle()
                    .fill(Color.brandLavender.opacity(0.5))
                    .frame(width: 280, height: 280)
                    .blur(radius: 80)
                    .offset(x: sheetPulse ? 30 : -50, y: sheetPulse ? 60 : 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // ── Sticky Navigationszeile: Titel + Schließen-Button ────
                // Liegt OBERHALB des ScrollViews und scrollt nicht mit —
                // damit "Drop erstellen" beim Scrollen nicht hinter dem
                // Status-Bar / der Uhrzeit verschwindet.
                //
                // Bewusst KEIN eigener Material-Hintergrund: Inhalt scrollt
                // im ScrollView darunter, nicht hinter dem Header durch.
                // Eine Material-Schicht würde sich farblich vom darunter
                // liegenden AppAuroraBackground absetzen und unschön
                // aussehen.
                // Rondesignlab-Style Top: Wortmarke + X + Riesige Hero-Headline
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center) {
                        DazuWordmark(color: .brandNight, dotColor: .brandOrange)
                            .frame(height: 24)
                        Spacer()
                        Button {
                            Haptic.selection()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.brandNight.opacity(0.75))
                                .padding(11)
                                .background(Circle().fill(Color.brandLavender.opacity(0.55)))
                                .overlay(Circle().stroke(Color.brandViolet.opacity(0.15), lineWidth: 0.8))
                        }
                        .dropsPressable()
                    }

                    VStack(alignment: .leading, spacing: -4) {
                        Text("Lust auf eine")
                            .foregroundColor(.brandNight)
                        Text("Runde?")
                            .foregroundColor(.brandViolet)
                    }
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 12)

                ScrollViewReader { proxy in
                GeometryReader { geo in
                let scrollMinHeight = geo.size.height
                ScrollView(showsIndicators: false) {
                    // minHeight = ScrollView-Höhe (von GeometryReader außen)
                    // erzwingt dass das innere VStack die volle Höhe füllt —
                    // so greift der Spacer vor dem Swipe-Button und schiebt
                    // ihn an den unteren Rand.
                    VStack(alignment: .leading, spacing: 8) {
                    // Neuer Satz-Flow — passt zur dazu-Wortmarke.
                    // Jedes Wort ist tappbar und öffnet seinen eigenen Picker.
                    sentenceFlowBody
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    #if false
                    // ── Wann ──────────────────────────────────────────────
                    createSection(label: tr("create.when_section")) {
                        if !isWalkthrough {
                            TipView(timeTip, arrowEdge: .top)
                                .tipBackground(Color.white.opacity(0.85))
                                .padding(.horizontal, 4)
                                .padding(.bottom, 4)
                        }
                        // Quick-Chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // "Jetzt"-Chip
                                let nowLabel = "Jetzt"
                                let isJetzt = scheduledTime == nowLabel && !showCustomTimePicker
                                Button(action: {
                                    Haptic.selection()
                                    scheduledTime = nowLabel
                                    showCustomTimePicker = false
                                }) {
                                    Text(tr("shared.now"))
                                        .font(.system(size: 13, weight: .semibold))
                                        .dropsChip(isActive: isJetzt, isLive: true)
                                }
                                .dropsPressable()

                                // Uhrzeit-Chip direkt neben Jetzt
                                Button(action: {
                                    Haptic.selection()
                                    withAnimation(.spring(response: 0.3)) { showCustomTimePicker.toggle() }
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "clock").font(.system(size: 12))
                                        Text(showCustomTimePicker
                                             ? customDate.formatted(date: .omitted, time: .shortened)
                                             : tr("create.time"))
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    .dropsChip(isActive: showCustomTimePicker)
                                }
                                .dropsPressable()

                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                        }

                        // Compact time picker row
                        if showCustomTimePicker {
                            Divider().padding(.leading, 16)
                            HStack {
                                Text(tr("create.time"))
                                    .font(.system(size: 14))
                                    .foregroundColor(.textSecondary)
                                Spacer()
                                DatePicker(
                                    "",
                                    selection: $customDate,
                                    in: Date()...,
                                    displayedComponents: [.hourAndMinute]
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(.brand)
                                .onChange(of: customDate) { _, _ in
                                    let f = DateFormatter()
                                    let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "de"
                                    f.dateFormat = lang == "de" ? "HH:mm 'Uhr'" : "h:mm a"
                                    scheduledTime = f.string(from: customDate)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    // ── Dauer ──────────────────────────────────────────────
                    createSection(label: tr("create.duration_section")) {
                        let durationOptions: [(String, Int)] = [
                            (tr("create.dur_30min"), 30), (tr("create.dur_1h"), 60), (tr("create.dur_2h"), 120),
                            (tr("create.duration_4h"), 240), (tr("create.no_limit"), 0)
                        ]
                        HStack(spacing: 6) {
                            ForEach(durationOptions, id: \.1) { label, value in
                                let isActive = durationMinutes == value
                                Button {
                                    Haptic.selection()
                                    durationMinutes = value
                                } label: {
                                    Text(label)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 2)
                                        .dropsChip(isActive: isActive)
                                }
                                .dropsPressable()
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)

                        if durationMinutes > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle").font(.system(size: 11))
                                Text(tr("create.ends_after").replacingOccurrences(of: "{duration}", with: durationMinutes < 60 ? tr("create.duration_min").replacingOccurrences(of: "{n}", with: "\(durationMinutes)") : tr("create.duration_hours").replacingOccurrences(of: "{n}", with: "\(durationMinutes / 60)")))
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.textTertiary)
                            .padding(.horizontal, 16).padding(.bottom, 8)
                            .transition(.opacity)
                        }
                    }

                    // ── Max. Teilnehmer ────────────────────────────────────
                    createSection(label: tr("create.max_section")) {
                        VStack(spacing: 2) {
                            HStack {
                                Text("\(maxParticipants)")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(.textPrimary)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                Text(tr("create.people"))
                                    .font(.system(size: 13)).foregroundColor(.textSecondary.opacity(0.85))
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.top, 12)

                            Slider(
                                value: Binding(
                                    get: { Double(maxParticipants) },
                                    set: { v in
                                        let new = Int(v.rounded())
                                        if new != maxParticipants {
                                            maxParticipants = new
                                            Haptic.selection()
                                        }
                                    }
                                ),
                                in: 2...Double(maxParticipantsLimit), step: 1
                            )
                            .tint(Color.brand)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        }
                        .animation(.spring(response: 0.25), value: maxParticipants)
                    }
                    // ── Ort ────────────────────────────────────────────────
                    createSection(label: tr("create.location_section")) {
                        let locStatus = CLLocationManager().authorizationStatus
                        let locationAllowed = locStatus == .authorizedWhenInUse || locStatus == .authorizedAlways

                        if locationAllowed {
                            locationOptionRow(
                                icon: "location.fill",
                                title: tr("create.current_location"),
                                subtitle: tr("create.current_location_subtitle"),
                                isSelected: selectedLocationType == .current
                            ) {
                                selectedLocationType = .current
                                searchVM.searchText = ""
                            }
                            Divider().padding(.leading, 60)
                        }

                        locationOptionRow(
                            icon: "magnifyingglass",
                            title: tr("create.search_place_title"),
                            subtitle: selectedLocationResult?.title ?? tr("create.search_place_subtitle"),
                            isSelected: selectedLocationType == .searched
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                selectedLocationType = .searched
                            }
                        }

                        // Inline-Suche klappt auf wenn "Ort suchen" aktiv
                        if selectedLocationType == .searched {
                            VStack(spacing: 0) {
                                Divider().padding(.leading, 16)
                                HStack(spacing: 10) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color.brand)
                                    TextField(tr("create.location_search_full"), text: $searchVM.searchText)
                                        .font(.system(size: 14))
                                        .foregroundColor(.textPrimary)
                                        .onChange(of: searchVM.searchText) { _, newValue in searchVM.search(newValue) }
                                        .submitLabel(.search)
                                    if !searchVM.searchText.isEmpty {
                                        Button { searchVM.searchText = "" } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.textTertiary)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)

                                if !searchVM.results.isEmpty {
                                    Divider()
                                    ForEach(Array(searchVM.results.prefix(5).enumerated()), id: \.element.title) { idx, result in
                                        Button(action: {
                                            Haptic.selection()
                                            searchVM.selectResult(result) { loc in
                                                if let loc = loc {
                                                    selectedLocationResult = loc
                                                    searchVM.searchText = loc.title
                                                    searchVM.results = []
                                                }
                                            }
                                        }) {
                                            HStack(spacing: 12) {
                                                Image(systemName: "mappin.circle.fill")
                                                    .font(.system(size: 18))
                                                    .foregroundColor(.brand)
                                                    .frame(width: 28)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(result.title)
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundColor(.textPrimary)
                                                    if !result.subtitle.isEmpty {
                                                        Text(result.subtitle)
                                                            .font(.system(size: 12))
                                                            .foregroundColor(.textSecondary)
                                                            .lineLimit(1)
                                                    }
                                                }
                                                Spacer()
                                            }
                                            .padding(.horizontal, 16).padding(.vertical, 11)
                                        }
                                        .dropsPressable()
                                        if idx < min(searchVM.results.count, 5) - 1 {
                                            Divider().padding(.leading, 56)
                                        }
                                    }
                                } else if searchVM.searchText.isEmpty && selectedLocationResult == nil {
                                    HStack(spacing: 8) {
                                        Image(systemName: "text.magnifyingglass")
                                            .foregroundColor(.textTertiary)
                                        Text(tr("create.tap_to_search"))
                                            .font(.system(size: 13))
                                            .foregroundColor(.textTertiary)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 14)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        Divider().padding(.leading, 60)

                        locationOptionRow(
                            icon: "mappin",
                            title: tr("create.set_pin"),
                            subtitle: pinnedCoordinate != nil ? tr("create.pin_set") : tr("create.set_pin_subtitle"),
                            isSelected: selectedLocationType == .pin
                        ) { selectedLocationType = .pin; showPinMap = true }
                    }
                    .id(CoachStep.location.scrollID)
                    .coachHighlight(active: coachStep == .location)

                    #endif // end legacy sections

                    // ── Drops+ Upsell (nur für Free-User, vor CTA) ──────────
                    // Aus für den Launch (FeatureFlags.dropsPlusEnabled).
                    if FeatureFlags.dropsPlusEnabled && !store.isDropsPlusActive && !created {
                        plusReachUpsell
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                    }

                    // Flex-Spacer: füllt die Fläche zwischen Satz-Flow und
                    // Swipe-Button, damit die CTA an den unteren Rand rutscht
                    // und der Screen vertikal "gefüllt" wirkt.
                    Spacer(minLength: 0)

                    // ── CTA ────────────────────────────────────────────────
                    if created {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20, weight: .heavy))
                                .foregroundColor(.brandViolet)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color.brandLavender))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Deine Runde läuft.")
                                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                                    .foregroundColor(.brandNight)
                                Text(tr("create.drop_live_msg"))
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.brandNight.opacity(0.6))
                            }
                            Spacer()
                        }
                        .padding(14).frame(maxWidth: .infinity)
                        .liquidGlass(cornerRadius: 20)
                        .padding(.horizontal, 16)
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        // Validierung: Aktivitätsname + München-Grenze
                        let locationSelected = selectedLocationType == .current
                            || (selectedLocationType == .searched && selectedLocationResult != nil)
                            || (selectedLocationType == .pin && pinnedCoordinate != nil)
                        let isValid = !activityName.trimmingCharacters(in: .whitespaces).isEmpty && locationSelected
                        let dropCoordPreview: CLLocationCoordinate2D = {
                            switch selectedLocationType {
                            case .current:  return store.currentUser.coordinate
                            case .searched: return selectedLocationResult?.coordinate ?? store.currentUser.coordinate
                            case .pin:      return pinnedCoordinate ?? store.currentUser.coordinate
                            }
                        }()
                        // Drop-Erstellen-Gate: Drop-Koordinate muss in einer
                        // der 5 Launch-Städte liegen (Berlin, Hamburg, München,
                        // Köln, Frankfurt). Bei deaktiviertem Gate ist alles
                        // erlaubt.
                        let isInServiceArea = !BetaConfig.cityRestrictionEnabled
                            || ServiceCities.isInside(dropCoordPreview)
                        // Swipe-to-Confirm statt Tap-Button: der User zieht
                        // den weißen Handle nach rechts, der offene Ring in
                        // der Mitte schließt sich live mit der Geste. Immer
                        // swipebar (auch bei leerem Formular) damit man die
                        // Morph-Animation ausprobieren kann; onConfirm wird
                        // intern geblockt wenn !isValid oder !isInServiceArea.
                        SwipeToConfirm(
                            label: isCreating ? "Startet…" : "Zum Starten swipen",
                            isEnabled: !isCreating,
                            canConfirm: isValid && isInServiceArea && !isCreating,
                            onConfirm: {
                                // 1. Full-Screen Logo-Celebration triggern
                                withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) {
                                    showJoinCelebration = true
                                }
                                // 2. Nach der Transition (0.9s) den echten
                                //    Create / HomeZone-Flow auslösen.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                                    if store.isInHomeZone(dropCoordPreview) {
                                        pendingHomeZoneCoord = dropCoordPreview
                                    } else {
                                        performCreate(coord: dropCoordPreview)
                                    }
                                }
                            }
                        )
                        .padding(.horizontal, 16)
                        // Coach-Mark Schritt 3: Drop starten
                        .popoverTip(startTip, arrowEdge: .bottom)
                        .id(CoachStep.start.scrollID)
                        .coachHighlight(active: coachStep == .start)
                        if !isValid {
                            Text(activityName.trimmingCharacters(in: .whitespaces).isEmpty
                                 ? tr("create.enter_activity_first")
                                 : tr("create.select_location"))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.brandNight.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .transition(.opacity)
                        } else if !isInServiceArea {
                            HStack(spacing: 5) {
                                Image(systemName: "mappin.slash")
                                    .font(.system(size: 12, weight: .bold))
                                Text(tr("create.cities_only"))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.brandOrange)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .transition(.opacity)
                        }
                    }
                    // Walkthrough-Puffer: damit auch der CTA (letztes Element)
                    // per scrollTo(anchor:.top) über die Coach-Karte gescrollt
                    // werden kann.
                    if coachStep != nil {
                        Spacer().frame(height: 360)
                    } else {
                        Spacer().frame(height: 12)
                    }
                }
                .frame(minHeight: scrollMinHeight, alignment: .top)
                }  // ScrollView
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .scrollDismissesKeyboard(.immediately)
                .scrollDisabled(coachStep != nil)
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: coachStep) { _, newStep in
                    guard let newStep else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                            proxy.scrollTo(newStep.scrollID, anchor: .top)
                        }
                    }
                }
                }  // GeometryReader
            } // ScrollViewReader
            } // VStack(spacing: 0)

            // ── Join-Celebration Overlay ───────────────────────────────────
            // Full-Screen: offener Ring + Dot bauen von allen Seiten in
            // Richtung Zentrum auf. Schließt sich dann zur Mark.
            if showJoinCelebration {
                JoinCelebrationOverlay()
                    .zIndex(200)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            // ── First-Drop Coach-Mark Overlay ──────────────────────────────
            // Liegt im ZStack über dem gesamten Inhalt (inkl. Sticky-Header).
            if coachStep != nil {
                FirstDropCoachOverlay(
                    step: $coachStep,
                    highlightFrame: coachHighlightFrame,
                    scrollTo: { _ in }, // Scroll via onChange in ScrollViewReader
                    onDone: {
                        coachStep = nil
                        walkthroughDone = true
                    },
                    onSkip: {
                        coachStep = nil
                        walkthroughDone = true
                    }
                )
                .zIndex(100)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: coachStep == nil)
            }
        } // ZStack
        // Frame der aktiven Coach-Section einsammeln (kommt per Preference
        // aus CoachHighlightModifier via GeometryReader in global coordinates).
        .onPreferenceChange(CoachSpotlightFrameKey.self) { frame in
            coachHighlightFrame = frame
        }
        .sheet(isPresented: $showEmojiPicker) {
            EmojiPickerSheet(selected: selectedEmoji) { emoji in
                selectedEmoji = emoji
                emojiLockedByUser = true
            }
            .presentationDetents([.height(460)])
            .presentationDragIndicator(.hidden)
            .sheetBackground()
        }
        // Sentence-Flow Picker Sheets
        .sheet(isPresented: $showDurationSheet) {
            durationPickerSheet
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showParticipantsSheet) {
            participantsPickerSheet
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLocationSheet) {
            locationPickerSheet
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
        }
        // Custom Heimzone-Warn-Sheet (statt System-Alert) — bietet wärmere
        // Optik, klare Hinweise und einen "Anderen Ort wählen"-Primärbutton
        // damit die sichere Wahl die offensichtliche bleibt.
        .sheet(isPresented: Binding(
            get: { pendingHomeZoneCoord != nil },
            set: { if !$0 { pendingHomeZoneCoord = nil } }
        )) {
            HomeZoneWarningSheet(
                onProceed: {
                    if let coord = pendingHomeZoneCoord {
                        pendingHomeZoneCoord = nil
                        performCreate(coord: coord)
                    }
                },
                onCancel: {
                    pendingHomeZoneCoord = nil
                }
            )
            // 0.78 statt 0.65 — auf SE/mini wurden sonst die Buttons
            // unten abgeschnitten. Der Inhalt ist jetzt zusätzlich
            // scrollbar (Footer fix), das ist die Belt-and-Suspenders-
            // Lösung für sehr kompakte Display Zoom-Modi.
            .presentationDetents([.fraction(0.78)])
            // Heimzone-Warnung darf nicht versehentlich weggewischt werden —
            // User soll bewusst „Anderen Ort" oder „Trotzdem erstellen"
            // wählen, sonst geht der Sicherheits-Check ins Leere.
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
            .sheetBackground()
        }
        .fullScreenCover(isPresented: $showPinMap) {
            ZStack(alignment: .bottom) {
                InteractivePinMapView(pinnedCoordinate: $pinnedCoordinate, initialCenter: pinnedCoordinate ?? store.currentUser.coordinate)
                VStack(spacing: 10) {
                    PrimaryButton(title: pinnedCoordinate != nil ? tr("create.confirm_pin") : tr("create.tap_on_map")) {
                        if pinnedCoordinate != nil { showPinMap = false }
                    }
                    .disabled(pinnedCoordinate == nil)
                    .opacity(pinnedCoordinate != nil ? 1 : 0.45)
                }
                .padding(20)
            }
            .overlay(alignment: .topLeading) {
                Button(action: { showPinMap = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.textSecondary)
                        .padding(20)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                sheetPulse = true
            }
            // First-Drop Walkthrough — kurze Verzögerung damit Sheet erst
            // vollständig eingefahren ist bevor die Coach-Karte erscheint.
            if isWalkthrough && !walkthroughDone {
                // TipKit-Tips unterdrücken: würden sich sonst mit dem
                // Coach-Overlay überlagern und verwirren.
                activityTip.invalidate(reason: .actionPerformed)
                timeTip.invalidate(reason: .actionPerformed)
                startTip.invalidate(reason: .actionPerformed)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    coachStep = .activity
                }
            }
            // Pre-Fill aus Community-Kontext — Aktivität + Emoji + sinnvoller
            // Default für Teilnehmerzahl (Community-Drops sind oft Gruppen-Events).
            if let name = prefilledActivityName, activityName.isEmpty {
                activityName = name
            }
            if let emoji = prefilledActivityEmoji, selectedEmoji.isEmpty {
                selectedEmoji = emoji
                emojiLockedByUser = true   // verhindert dass das Auto-Pick es überschreibt
            }
            // Community-Drops bekommen 25 als Default (mehr als 10, weniger als max).
            if communityID != nil && maxParticipants == 10 {
                maxParticipants = min(25, maxParticipantsLimit)
            }
        }
    }

    // MARK: - Sentence Flow (dazu-Wortmarke-Style, Partiful-inspired)

    @ViewBuilder private var sentenceFlowBody: some View {
        VStack(spacing: 18) {
            // Satz-Flow — linksbündig, groß, lesbar
            sentenceLinesView
                .padding(.top, 4)

            // Emoji-Suggestions wenn Text eingegeben + kein Emoji
            if selectedEmoji.isEmpty && !suggestedEmojis.isEmpty {
                VStack(spacing: 8) {
                    Text("WÄHLE EIN EMOJI")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(.brandViolet.opacity(0.6))
                    HStack(spacing: 14) {
                        ForEach(suggestedEmojis.prefix(5), id: \.self) { emoji in
                            Button {
                                selectedEmoji = emoji
                                emojiLockedByUser = true
                                Haptic.selection()
                            } label: {
                                Text(emoji).font(.system(size: 32))
                            }
                            .dropsPressable()
                        }
                        Button {
                            showEmojiPicker = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.brandViolet)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.brandLavender))
                        }
                        .dropsPressable()
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .padding(.top, 4)
            }
        }
    }

    // Der eigentliche „Satz" — große, linksbündige Zeilen im Rondesignlab-Stil.
    // Kompakter Rhythmus damit nichts verwaist unten rumsteht.
    @ViewBuilder private var sentenceLinesView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Zeile 1: Ich mache eine Runde
            sentenceText("Ich mache eine Runde")

            // Zeile 2: Aktivität (groß, prominent, Violett)
            sentenceInputWord(placeholder: "Tennis", text: $activityName)
                .padding(.bottom, 4)

            // Zeile 3: {jetzt/zeit} für {dauer}
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                sentenceWord(timePreviewLabel, action: {
                    withAnimation(.spring(response: 0.3)) {
                        showCustomTimePicker.toggle()
                    }
                    Haptic.selection()
                })
                sentenceText("für")
                sentenceWord(durationMinutes <= 0 ? "offen" :
                             (durationMinutes < 60 ? "\(durationMinutes)m" : "\(durationMinutes/60)h"),
                             action: { showDurationSheet = true })
            }

            // Zeile 4: mit {N} Leuten {Ort} — Ort kommt direkt dahinter,
            // damit "hier" nicht alleine in einer eigenen Zeile verwaist.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                sentenceText("mit")
                sentenceWord("\(maxParticipants) Leuten", action: { showParticipantsSheet = true })
                sentenceText("·")
                sentenceWord(sentenceLocationLabel, action: { showLocationSheet = true })
            }

            // Inline Time Picker (klappt auf wenn tap auf Zeit-Wort)
            if showCustomTimePicker {
                DatePicker("", selection: $customDate, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxHeight: 150)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    // Simple statisches Text-Element im Satz-Flow
    private func sentenceText(_ s: String) -> Text {
        Text(s)
            .font(.system(size: 32, weight: .semibold, design: .rounded))
            .foregroundColor(.brandNight.opacity(0.85))
    }

    // Tappable Wort im Satz — unterstrichen, Violett, Press-feedback
    @ViewBuilder private func sentenceWord(_ s: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(s)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.brandViolet)
                .underline(true, color: .brandViolet.opacity(0.45))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .dropsPressable()
    }

    // Inline-editable Word (für Aktivitäts-Name) — unterstrichen wie die
    // tappbaren Wörter, damit visuell klar wird: hier einfach reintippen.
    @ViewBuilder private func sentenceInputWord(placeholder: String, text: Binding<String>) -> some View {
        TextField("",
                  text: text,
                  prompt: Text(placeholder)
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundColor(.brandViolet.opacity(0.55)))
            .font(.system(size: 38, weight: .heavy, design: .rounded))
            .foregroundColor(.brandViolet)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.brandViolet.opacity(0.45))
                    .frame(height: 2)
                    .offset(y: 4)
            }
            .onChange(of: text.wrappedValue) { _, _ in
                if text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    selectedEmoji = ""
                    emojiLockedByUser = false
                } else if !emojiLockedByUser {
                    selectedEmoji = ""
                }
            }
    }

    private var sentenceLocationLabel: String {
        switch selectedLocationType {
        case .current:  return "hier"
        case .searched: return selectedLocationResult?.title ?? "woanders"
        case .pin:      return pinnedCoordinate != nil ? "am Pin" : "Pin setzen"
        }
    }

    // MARK: - Sentence Flow Picker Sheets

    private var durationPickerSheet: some View {
        VStack(spacing: 20) {
            Text("Wie lange?")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.brandNight)
                .padding(.top, 24)
            let options: [(String, Int)] = [
                ("30 Min", 30), ("1 Stunde", 60), ("2 Stunden", 120), ("4 Stunden", 240), ("offen", 0)
            ]
            VStack(spacing: 10) {
                ForEach(options, id: \.1) { label, value in
                    Button {
                        durationMinutes = value
                        Haptic.selection()
                        showDurationSheet = false
                    } label: {
                        HStack {
                            Text(label)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Spacer()
                            if durationMinutes == value {
                                Image(systemName: "checkmark").foregroundColor(.brandOrange)
                            }
                        }
                        .foregroundColor(.brandNight)
                        .padding(.horizontal, 20).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.brandLavender.opacity(durationMinutes == value ? 0.9 : 0.5)))
                    }
                    .dropsPressable()
                }
            }
            .padding(.horizontal, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandCream.ignoresSafeArea())
    }

    private var participantsPickerSheet: some View {
        VStack(spacing: 20) {
            Text("Wie viele Leute?")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.brandNight)
                .padding(.top, 24)
            Text("\(maxParticipants)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundColor(.brandViolet)
                .monospacedDigit()
                .contentTransition(.numericText())
            Slider(
                value: Binding(
                    get: { Double(maxParticipants) },
                    set: { v in
                        let new = Int(v.rounded())
                        if new != maxParticipants { maxParticipants = new; Haptic.selection() }
                    }
                ),
                in: 2...Double(maxParticipantsLimit), step: 1
            )
            .tint(.brandViolet)
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandCream.ignoresSafeArea())
    }

    private var locationPickerSheet: some View {
        VStack(spacing: 16) {
            Text("Wo?")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.brandNight)
                .padding(.top, 24)
            VStack(spacing: 10) {
                locationChoice(icon: "location.fill", label: "Hier", isSelected: selectedLocationType == .current) {
                    selectedLocationType = .current
                    searchVM.searchText = ""
                    showLocationSheet = false
                }
                locationChoice(icon: "magnifyingglass", label: "Ort suchen", isSelected: selectedLocationType == .searched) {
                    selectedLocationType = .searched
                    // Suchfeld kommt auf, Sheet bleibt für Interaktion offen
                }
                locationChoice(icon: "mappin", label: "Pin setzen", isSelected: selectedLocationType == .pin) {
                    selectedLocationType = .pin
                    showPinMap = true
                    showLocationSheet = false
                }
                if selectedLocationType == .searched {
                    TextField("Adresse suchen...", text: $searchVM.searchText)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.brandLavender.opacity(0.5)))
                        .padding(.horizontal, 20)
                        .onChange(of: searchVM.searchText) { _, newValue in searchVM.search(newValue) }
                }
            }
            .padding(.horizontal, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandCream.ignoresSafeArea())
    }

    private func locationChoice(icon: String, label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { action(); Haptic.selection() }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .brandViolet)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(isSelected ? Color.brandViolet : Color.brandLavender))
                Text(label)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.brandNight)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundColor(.brandOrange)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.brandLavender.opacity(isSelected ? 0.9 : 0.5)))
        }
        .dropsPressable()
    }

    // MARK: - Legacy Hero Block (nicht mehr verwendet, nur im #if false Pfad)

    @ViewBuilder private var newHeroBlock: some View {
        VStack(spacing: 20) {
            // Großes tappbares Emoji
            Button(action: { showEmojiPicker = true }) {
                Group {
                    if displayEmoji.isEmpty {
                        ZStack {
                            Circle()
                                .fill(Color.brandLavender)
                                .frame(width: 110, height: 110)
                                .overlay(
                                    Circle().stroke(Color.brandViolet.opacity(0.25),
                                                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                                )
                            Image(systemName: "face.smiling.inverse")
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(Color.brandViolet.opacity(0.6))
                        }
                    } else {
                        Text(displayEmoji)
                            .font(.system(size: 100))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .dropsPressable()
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: displayEmoji)

            // Title Input (zentriert, Headline-Font, keine Border)
            TextField("",
                      text: $activityName,
                      prompt: Text("Dein Plan")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Color.brandNight.opacity(0.3)))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(Color.brandNight)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .onChange(of: activityName) { _, _ in
                    if activityName.trimmingCharacters(in: .whitespaces).isEmpty {
                        selectedEmoji = ""
                        emojiLockedByUser = false
                    } else if !emojiLockedByUser {
                        selectedEmoji = ""
                    }
                }

            // Emoji-Suggestions wenn Name eingegeben + noch kein Emoji
            if selectedEmoji.isEmpty && !suggestedEmojis.isEmpty {
                HStack(spacing: 10) {
                    ForEach(suggestedEmojis.prefix(5), id: \.self) { emoji in
                        Button(action: {
                            selectedEmoji = emoji
                            emojiLockedByUser = true
                            Haptic.selection()
                        }) {
                            Text(emoji).font(.system(size: 28))
                        }
                        .dropsPressable()
                    }
                    Button(action: { showEmojiPicker = true }) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.brandNight.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.brandLavender))
                    }
                    .dropsPressable()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if activityName.trimmingCharacters(in: .whitespaces).isEmpty {
                // Quick-Templates nur wenn kein Name
                DropQuickTemplatesBar { tpl in
                    activityName = tpl.name
                    selectedEmoji = tpl.emoji
                    emojiLockedByUser = true
                    Haptic.selection()
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Step 1 — Was? (Minimalist / Apple-Setup-Style, LEGACY — nicht mehr genutzt)

    @ViewBuilder private var step1WhatBody: some View {
        VStack(spacing: 36) {
            Spacer(minLength: 4)

            // Großes centered Emoji (oder dezentes +)
            minimalEmojiHero
                .id(CoachStep.activity.scrollID)
                .coachHighlight(active: coachStep == .activity)

            // Thin TextField mit Unterstrich
            minimalActivityField

            // Templates als dezente Pills
            if activityName.trimmingCharacters(in: .whitespaces).isEmpty {
                minimalTemplatesRow
            } else if selectedEmoji.isEmpty && !suggestedEmojis.isEmpty {
                minimalEmojiSuggestionsRow
            }

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Minimalist Hero / Field / Rows (Step 1)

    private var minimalEmojiHero: some View {
        Button(action: { showEmojiPicker = true }) {
            Group {
                if displayEmoji.isEmpty {
                    ZStack {
                        Circle()
                            .stroke(Color.textTertiary.opacity(0.3),
                                    style: StrokeStyle(lineWidth: 1.2, dash: [5, 5]))
                            .frame(width: 120, height: 120)
                        Image(systemName: "plus")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(.textTertiary.opacity(0.65))
                    }
                } else {
                    Text(displayEmoji)
                        .font(.system(size: 110))
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .dropsPressable()
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: displayEmoji)
    }

    private var minimalActivityField: some View {
        VStack(spacing: 8) {
            TextField("", text: $activityName,
                      prompt: Text("Was machst du?")
                        .font(.system(size: 20, weight: .regular, design: .rounded))
                        .foregroundColor(.textTertiary.opacity(0.5)))
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
                .onChange(of: activityName) { _, _ in
                    if activityName.trimmingCharacters(in: .whitespaces).isEmpty {
                        selectedEmoji = ""
                        emojiLockedByUser = false
                    } else if !emojiLockedByUser {
                        selectedEmoji = ""
                    }
                }
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.textTertiary.opacity(0.0),
                            Color.textTertiary.opacity(0.4),
                            Color.textTertiary.opacity(0.0)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
    }

    private var minimalTemplatesRow: some View {
        VStack(spacing: 12) {
            Text("ODER")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(.textTertiary.opacity(0.6))

            DropQuickTemplatesBar { tpl in
                activityName = tpl.name
                selectedEmoji = tpl.emoji
                emojiLockedByUser = true
                Haptic.selection()
            }
        }
        .transition(.opacity)
    }

    private var minimalEmojiSuggestionsRow: some View {
        VStack(spacing: 10) {
            Text("Wähle ein Emoji")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textTertiary)

            HStack(spacing: 10) {
                ForEach(suggestedEmojis.prefix(5), id: \.self) { emoji in
                    Button(action: {
                        selectedEmoji = emoji
                        emojiLockedByUser = true
                        Haptic.selection()
                    }) {
                        Text(emoji)
                            .font(.system(size: 32))
                    }
                    .dropsPressable()
                    .transition(.scale.combined(with: .opacity))
                }
                Button(action: { showEmojiPicker = true }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(.textTertiary)
                        .frame(width: 32, height: 32)
                }
                .dropsPressable()
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Minimalist Compact Hero (Step 2 + 3)

    /// Kleines Emoji oben + Aktivitäts-Name als Titel. Zeigt dem User
    /// weiterhin was er erstellt, ohne vom aktuellen Schritt abzulenken.
    @ViewBuilder private var minimalCompactHero: some View {
        VStack(spacing: 8) {
            if !displayEmoji.isEmpty {
                Text(displayEmoji)
                    .font(.system(size: 56))
                    .transition(.scale.combined(with: .opacity))
            }
            Text(activityName.trimmingCharacters(in: .whitespaces).isEmpty
                 ? "Dein Plan"
                 : activityName)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Rectangle()
                .fill(Color.textTertiary.opacity(0.25))
                .frame(width: 32, height: 1)
                .padding(.top, 4)
        }
    }

    // MARK: - Live Preview Pin (unused since minimalist redesign — kept for ref)

    @ViewBuilder private var livePreviewPin: some View {
        let hasActivity = !activityName.trimmingCharacters(in: .whitespaces).isEmpty
        let pinColor: Color = (communityID != nil) ? .cleroGreen : .accentOrange

        VStack(spacing: 10) {
            ZStack {
                // Weiche pulsierende Radar-Welle außen
                Circle()
                    .stroke(pinColor.opacity(0.4), lineWidth: 2)
                    .frame(width: 160, height: 160)
                    .scaleEffect(sheetPulse ? 1.15 : 0.95)
                    .opacity(sheetPulse ? 0.0 : 0.7)
                    .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false),
                               value: sheetPulse)

                // Zweite Welle (versetzt)
                Circle()
                    .stroke(pinColor.opacity(0.35), lineWidth: 2)
                    .frame(width: 160, height: 160)
                    .scaleEffect(sheetPulse ? 1.15 : 0.95)
                    .opacity(sheetPulse ? 0.0 : 0.7)
                    .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false).delay(1.0),
                               value: sheetPulse)

                // Weicher Glow unter dem Pin
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [pinColor.opacity(0.35), .clear],
                            center: .center, startRadius: 10, endRadius: 80
                        )
                    )
                    .frame(width: 180, height: 180)

                // Pin selbst (nachgebildet dem Map-Pin-Style)
                Button(action: { showEmojiPicker = true }) {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 108, height: 108)
                            .overlay(
                                Circle().stroke(
                                    LinearGradient(
                                        colors: [pinColor, pinColor.opacity(0.6)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                            )
                            .shadow(color: pinColor.opacity(0.5), radius: 14, y: 6)
                            .scaleEffect(hasActivity ? 1.0 : 0.95)
                            .animation(.spring(response: 0.4, dampingFraction: 0.65),
                                       value: hasActivity)

                        if displayEmoji.isEmpty {
                            Image(systemName: "plus")
                                .font(.system(size: 36, weight: .light))
                                .foregroundStyle(pinColor)
                                .scaleEffect(sheetPulse ? 1.1 : 1.0)
                                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                           value: sheetPulse)
                        } else {
                            Text(displayEmoji)
                                .font(.system(size: 56))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .dropsPressable()
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: displayEmoji)
            }
            .frame(height: 190)

            // Live-Label unter dem Pin: Name + Status-Chips
            VStack(spacing: 6) {
                Text(hasActivity ? activityName : "Dein Plan")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(hasActivity ? .textPrimary : .textTertiary.opacity(0.7))
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .id(hasActivity ? "set" : "empty")

                // Chips zeigen die aktuell gesetzten Felder (updaten live mit Steps)
                HStack(spacing: 6) {
                    if currentStep.rawValue >= 1 {
                        previewChip(icon: "clock.fill", text: timePreviewLabel,
                                    tint: pinColor, dim: !isTimePickerPopulated)
                    }
                    if currentStep.rawValue >= 1 && durationMinutes > 0 {
                        previewChip(icon: "hourglass", text: durationPreviewLabel,
                                    tint: pinColor, dim: false)
                    }
                    if currentStep.rawValue >= 2 {
                        previewChip(icon: locationIconName,
                                    text: locationPreviewLabel,
                                    tint: pinColor,
                                    dim: !isLocationPicked)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func previewChip(icon: String, text: String, tint: Color, dim: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(dim ? .textTertiary : tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(dim ? Color.gray.opacity(0.12) : tint.opacity(0.14))
        )
        .overlay(
            Capsule().stroke(dim ? Color.gray.opacity(0.2) : tint.opacity(0.4), lineWidth: 0.8)
        )
    }

    // MARK: - Preview helpers

    private var isTimePickerPopulated: Bool {
        !scheduledTime.isEmpty || showCustomTimePicker
    }

    private var timePreviewLabel: String {
        if showCustomTimePicker {
            return customDate.formatted(date: .omitted, time: .shortened)
        }
        if scheduledTime.isEmpty || scheduledTime == "Jetzt" {
            return "Jetzt"
        }
        return scheduledTime
    }

    private var durationPreviewLabel: String {
        if durationMinutes <= 0 { return "offen" }
        if durationMinutes < 60 { return "\(durationMinutes)m" }
        return "\(durationMinutes / 60)h"
    }

    private var isLocationPicked: Bool {
        switch selectedLocationType {
        case .current:  return true
        case .searched: return selectedLocationResult != nil
        case .pin:      return pinnedCoordinate != nil
        }
    }

    private var locationIconName: String {
        switch selectedLocationType {
        case .current:  return "location.fill"
        case .searched: return "magnifyingglass"
        case .pin:      return "mappin"
        }
    }

    private var locationPreviewLabel: String {
        switch selectedLocationType {
        case .current:  return "Hier"
        case .searched: return selectedLocationResult?.title ?? "Ort wählen"
        case .pin:      return pinnedCoordinate == nil ? "Pin setzen" : "Pin gesetzt"
        }
    }

    private var activityInputCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.textTertiary)
                TextField(tr("create.activity_field_placeholder"),
                          text: $activityName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.textPrimary)
                    .onChange(of: activityName) { _, _ in
                        if activityName.trimmingCharacters(in: .whitespaces).isEmpty {
                            selectedEmoji = ""
                            emojiLockedByUser = false
                        } else if !emojiLockedByUser {
                            selectedEmoji = ""
                        }
                    }
                if !activityName.isEmpty {
                    Button(action: { activityName = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundColor(.textTertiary)
                    }
                    .dropsPressable()
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            // Emoji-Suggestions wenn Name eingegeben + noch kein Emoji
            if selectedEmoji.isEmpty && !suggestedEmojis.isEmpty {
                Divider().padding(.leading, 18)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestedEmojis, id: \.self) { emoji in
                            Button(action: {
                                selectedEmoji = emoji
                                emojiLockedByUser = true
                                Haptic.selection()
                            }) {
                                Text(emoji).font(.system(size: 26))
                                    .frame(width: 48, height: 48)
                                    .background(
                                        Circle().fill(.white.opacity(0.3))
                                    )
                                    .overlay(
                                        Circle().stroke(.white.opacity(0.5), lineWidth: 0.8)
                                    )
                            }
                            .dropsPressable()
                        }
                        Button(action: { showEmojiPicker = true }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.textSecondary)
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(.white.opacity(0.2)))
                        }
                        .dropsPressable()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if selectedEmoji.isEmpty && !activityName.trimmingCharacters(in: .whitespaces).isEmpty {
                Divider().padding(.leading, 18)
                Button(action: { showEmojiPicker = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 15, weight: .medium))
                        Text(tr("create.pick_emoji"))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.brand)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .dropsPressable()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Oder wähle etwas Spontanes")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textSecondary)
                .padding(.leading, 6)
            DropQuickTemplatesBar { tpl in
                activityName = tpl.name
                selectedEmoji = tpl.emoji
                emojiLockedByUser = true
                Haptic.selection()
            }
        }
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Step Navigation

    private var canAdvanceFromCurrentStep: Bool {
        switch currentStep {
        case .what:
            return !activityName.trimmingCharacters(in: .whitespaces).isEmpty
        case .when, .whereAt:
            return true
        }
    }

    @ViewBuilder private var stepProgressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(CreateDropStep.allCases) { step in
                Capsule()
                    .fill(step == currentStep
                          ? LinearGradient(colors: [Color.accentOrange, Color.pink],
                                           startPoint: .leading, endPoint: .trailing)
                          : LinearGradient(colors: [.textTertiary.opacity(0.3), .textTertiary.opacity(0.3)],
                                           startPoint: .leading, endPoint: .trailing))
                    .frame(height: 4)
                    .frame(maxWidth: step == currentStep ? .infinity : 24)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentStep)
            }
        }
    }

    private func advanceStep() {
        guard let next = CreateDropStep(rawValue: currentStep.rawValue + 1) else { return }
        Haptic.selection()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            currentStep = next
        }
    }

    private func backStep() {
        guard let prev = CreateDropStep(rawValue: currentStep.rawValue - 1) else { return }
        Haptic.selection()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            currentStep = prev
        }
    }

    @ViewBuilder private var stepBackButton: some View {
        Button(action: backStep) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                Text("Zurück")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.white.opacity(0.75)))
            .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        }
        .dropsPressable()
    }

    @ViewBuilder private var stepNavigationButtons: some View {
        HStack(spacing: 12) {
            if currentStep != .what {
                stepBackButton
            }
            Spacer()
            Button(action: advanceStep) {
                HStack(spacing: 6) {
                    Text("Weiter")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: canAdvanceFromCurrentStep
                                ? [Color.accentOrange, Color.pink]
                                : [Color.gray.opacity(0.5), Color.gray.opacity(0.5)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                )
                .shadow(color: canAdvanceFromCurrentStep ? Color.accentOrange.opacity(0.4) : .clear,
                        radius: 10, y: 4)
            }
            .dropsPressable()
            .disabled(!canAdvanceFromCurrentStep)
        }
    }

    // MARK: - Section Container (New Drops Design System: Lavendel-Card)

    @ViewBuilder
    private func createSection<Content: View>(label: String, aurora: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundColor(Color.brandViolet.opacity(0.65))
                .padding(.horizontal, 24)

            VStack(spacing: 0) { content() }
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.brandLavender.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.brandViolet.opacity(aurora ? 0.35 : 0.12), lineWidth: 1)
                )
                .shadow(color: Color.brandViolet.opacity(0.08), radius: 10, y: 4)
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func locationOptionRow(icon: String, title: String, subtitle: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(isSelected ? Color.brand.opacity(0.18) : Color.white.opacity(0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundColor(isSelected ? .brand : .textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundColor(.textPrimary)
                    Text(subtitle).font(.system(size: 12)).foregroundColor(.textSecondary)
                }
                Spacer()
                // Radio-Button Indikator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.brand : Color.primary.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle()
                            .fill(Color.brand)
                            .frame(width: 11, height: 11)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(isSelected ? Color.brand.opacity(0.06) : Color.clear)
        }
        .dropsPressable()
        .animation(.spring(response: 0.2), value: isSelected)
    }

    // MARK: - Drops+ Reichweite-Upsell (nur Free-User)

    /// Subtile Gold-Karte direkt vor dem „Drop erstellen"-Button.
    /// Öffnet die Paywall beim Tap. Zeigt konkreten Nutzen (Boost + Priority Listing)
    /// statt einer generischen „Pro"-Werbung.
    private var plusReachUpsell: some View {
        Button {
            store.showDropsPlusPaywall = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.auroraAmber.opacity(0.35), .clear],
                                center: .center,
                                startRadius: 0, endRadius: 22
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.auroraAmber, Color.auroraAmber],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("create.reach_more_plus"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(tr("create.plus_features"))
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.auroraAmber)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.auroraAmber.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.auroraAmber.opacity(0.55), Color.auroraAmber.opacity(0.15)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .dropsPressable()
    }

    // MARK: - Create Helper

    private func performCreate(coord: CLLocationCoordinate2D) {
        // Content-Filter: Beleidigungen, Slurs, Sexual-Solicitation und
        // Drohwörter blockieren den Drop bevor er überhaupt erstellt wird.
        // Whole-Word-Match auf normalisiertem Text (Leetspeak rückwärts) —
        // siehe ContentFilter.swift. Aktiviert für Drop-Name + Beschreibung.
        if let match = ContentFilter.firstMatch(
            activityName: activityName,
            description: dropDescription
        ) {
            store.showInfoToast(
                tr("create.blocked_words").replacingOccurrences(of: "{word}", with: match.word),
                icon: "exclamationmark.shield.fill"
            )
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }

        isCreating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let loc = DropLocation(
                title: locationSubtitle, subtitle: "München",
                coordinate: coord, type: selectedLocationType
            )
            let name = activityName.trimmingCharacters(in: .whitespaces).isEmpty ? "Plan" : activityName.trimmingCharacters(in: .whitespaces)
            // Reihenfolge: 1) explizite User-Auswahl, 2) erster Auto-Match,
            // 3) ✨-Fallback damit der Drop-Pin auf der Karte nie leer ist.
            let emoji: String
            if !displayEmoji.isEmpty {
                emoji = displayEmoji
            } else if let auto = suggestedEmojis.first {
                emoji = auto
            } else {
                emoji = "✨"
            }
            let finalActivity = Activity(id: UUID(), name: name, emoji: emoji)
            store.createDrop(activity: finalActivity, location: loc,
                             description: dropDescription, scheduledTime: scheduledTime,
                             maxParticipants: maxParticipants,
                             durationMinutes: durationMinutes,
                             communityID: communityID)
            isCreating = false
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { created = true }
            // Kurz die Erfolgsmeldung zeigen, dann zum Aktiv-Tab wechseln
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                dismiss()
                store.selectedTab = .create   // .create ist der Aktiv-Tab
            }
        }
    }
}

struct DropLocationRow: View {
    let icon: String; let title: String; let subtitle: String
    var isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            DropLocationRowContent(icon: icon, title: title, subtitle: subtitle, isSelected: isSelected)
        }
        .dropsPressable()
        .animation(.spring(response: 0.2), value: isSelected)
    }
}

struct DropLocationRowContent: View {
    let icon: String; let title: String; let subtitle: String; var isSelected: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16))
                .foregroundColor(isSelected ? .brand : .textSecondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundColor(.textPrimary)
                Text(subtitle).font(.system(size: 12)).foregroundColor(.textSecondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                    .foregroundColor(.brand)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.white.opacity(0.75)))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .stroke(isSelected ? Color.brand.opacity(0.5) : Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

struct DropLocationSearchSheet: View {
    @ObservedObject var searchVM: LocationSearchViewModel
    let onSelect: (DropLocationResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color(UIColor.systemGray4))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12).padding(.bottom, 16)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundColor(.textTertiary)
                    TextField(tr("create.location_search_short"), text: $searchVM.searchText)
                        .font(.system(size: 16)).foregroundColor(.textPrimary)
                        .onChange(of: searchVM.searchText) { _, newValue in searchVM.search(newValue) }
                    if !searchVM.searchText.isEmpty {
                        Button(action: { searchVM.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.textTertiary)
                        }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.white.opacity(0.75)))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Color.white.opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 16).padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(searchVM.results, id: \.title) { result in
                            Button(action: {
                                searchVM.selectResult(result) { loc in
                                    if let loc = loc { onSelect(loc) }
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 20)).foregroundColor(.brand)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.textPrimary)
                                        Text(result.subtitle)
                                            .font(.system(size: 12)).foregroundColor(.textSecondary)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Color.white.opacity(0.75)))
                                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Color.white.opacity(0.15), lineWidth: 0.8))
                            }
                            .dropsPressable()
                        }
                    }
                    .padding(.horizontal, 16)
                }
                Spacer()
            }
        }
        .presentationDetents([.fraction(0.75)])
        .sheetBackground()
    }
}

struct InteractivePinMapView: View {
    @Binding var pinnedCoordinate: CLLocationCoordinate2D?
    var initialCenter: CLLocationCoordinate2D? = nil
    @State private var region: MKCoordinateRegion
    @AppStorage("appLanguage") private var appLanguage = "de"

    init(pinnedCoordinate: Binding<CLLocationCoordinate2D?>, initialCenter: CLLocationCoordinate2D? = nil) {
        self._pinnedCoordinate = pinnedCoordinate
        let center = initialCenter ?? CLLocationCoordinate2D(latitude: 48.137, longitude: 11.575)
        self._region = State(initialValue: MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        ))
    }

    var body: some View {
        ZStack {
            InteractivePinMap(region: $region, coordinate: $pinnedCoordinate)
                .ignoresSafeArea()
            if pinnedCoordinate == nil {
                VStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill").font(.system(size: 28))
                        .foregroundColor(.textPrimary)
                    Text(tr("create.tap_on_map"))
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.85)))
                }
            }
        }
    }
}

struct InteractivePinMap: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var coordinate: CLLocationCoordinate2D?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.setRegion(region, animated: false)
        map.showsUserLocation = true
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
        if let coord = coordinate {
            let ann = MKPointAnnotation()
            ann.coordinate = coord
            map.addAnnotation(ann)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: InteractivePinMap
        init(_ parent: InteractivePinMap) { self.parent = parent }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let coord = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                parent.coordinate = coord
            }
            map.setCenter(coord, animated: true)
        }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            view.markerTintColor = .black
            view.animatesWhenAdded = true
            return view
        }
    }
}

// MARK: - Quick Drop Templates

/// One-Tap-Vorlagen für häufige Aktivitäten — füllen Name + Emoji direkt aus.
/// Erspart Tippen für die Standard-Cases (Kaffee, Spaziergang, Sport).
struct DropTemplate: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let emoji: String
}

extension DropTemplate {
    /// Statische Default-Vorlagen falls weder Past-Drops noch Interests etwas
    /// Brauchbares ergeben (Erst-User ohne Interests). `var` (nicht `let`)
    /// damit der Name bei Sprachwechsel zur Laufzeit neu lokalisiert wird.
    static var universalDefaults: [DropTemplate] {
        [
            DropTemplate(name: tr("activity.coffee"), emoji: "☕️"),
            DropTemplate(name: tr("activity.walk"),   emoji: "🚶"),
            DropTemplate(name: tr("activity.beer"),   emoji: "🍻"),
        ]
    }

    /// Mapping von Onboarding-Interest-Keys auf Drop-Vorlagen.
    static func fromInterest(_ key: String) -> DropTemplate? {
        switch key {
        case "interest.coffee":   return DropTemplate(name: tr("activity.coffee"),  emoji: "☕️")
        case "interest.food":     return DropTemplate(name: tr("activity.food"),    emoji: "🍽")
        case "interest.sport":    return DropTemplate(name: tr("activity.sport"),   emoji: "🏃")
        case "interest.music":    return DropTemplate(name: "Konzert",              emoji: "🎵")
        case "interest.cinema":   return DropTemplate(name: "Kino",                 emoji: "🎬")
        case "interest.gaming":   return DropTemplate(name: tr("activity.gaming"),  emoji: "🎮")
        case "interest.shopping": return DropTemplate(name: "Bummeln",              emoji: "🛍")
        case "interest.outdoor":  return DropTemplate(name: "Park-Hangout",         emoji: "🌳")
        case "interest.party":    return DropTemplate(name: tr("activity.beer"),    emoji: "🍻")
        case "interest.photo":    return DropTemplate(name: "Foto-Walk",            emoji: "📸")
        case "interest.cooking":  return DropTemplate(name: "Brunch",               emoji: "🥐")
        case "interest.travel":   return nil   // Reise passt nicht als Spontan-Drop
        default: return nil
        }
    }
}

struct DropQuickTemplatesBar: View {
    @EnvironmentObject var store: AppStore
    var onSelect: (DropTemplate) -> Void

    /// Vorlagen-Pipeline:
    /// 1. Letzte 4 unterschiedliche Aktivitäten aus pastDrops (frisch zuerst)
    /// 2. Auffüllen mit Interest-Mappings (max. 8 gesamt)
    /// 3. Universal-Defaults nur wenn Liste sonst leer
    private var templates: [DropTemplate] {
        var list: [DropTemplate] = []
        var seen: Set<String> = []
        let key = { (t: DropTemplate) in "\(t.emoji)|\(t.name.lowercased())" }

        // 1. Past Drops (neueste zuerst, deduped)
        for drop in store.pastDrops.reversed() {
            let tpl = DropTemplate(name: drop.activityName, emoji: drop.activityEmoji)
            let k = key(tpl)
            if seen.contains(k) { continue }
            seen.insert(k)
            list.append(tpl)
            if list.count >= 4 { break }
        }

        // 2. Fallback wenn keine Past-Drops
        if list.isEmpty { return DropTemplate.universalDefaults }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section-Header — kräftiger uppercase-Cut mit Tracking,
            // stärkere Farbe. Vorher wirkten Header + Chips gemeinsam
            // „ausgegraut" auf dem Aurora-Background — beides sah aus
            // wie blasse Sektionslabels.
            Text(store.pastDrops.isEmpty ? tr("create.popular") : tr("create.templates"))
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(templates) { tpl in
                        Button { onSelect(tpl) } label: {
                            HStack(spacing: 6) {
                                Text(tpl.emoji).font(.system(size: 16))
                                Text(tpl.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            // Solides Brand-Gradient statt ultraThin/10%-Tönung —
                            // die alte Glass-Variante wirkte ausgegraut auf der
                            // Aurora. Jetzt klarer Tap-Affordance: vollfarbige
                            // Capsule mit Sunset-Gradient (passt zur App-Icon-
                            // Identity).
                            .background(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [Color.auroraOrange, Color.auroraGreen],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                            )
                            .shadow(color: Color.auroraOrange.opacity(0.30), radius: 8, y: 3)
                        }
                        .dropsPressable()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)   // Damit der Glass-Shadow nicht abgeschnitten wird
            }
        }
    }
}

// MARK: - Join Celebration Overlay
//
// Full-Screen Transition die nach erfolgreichem SwipeToConfirm läuft. Vier
// Beam-Streifen schießen von Top/Right/Bottom/Left in Richtung Zentrum,
// treffen sich dort und formen den geschlossenen Dazu-Ring mit orangem Dot.
// Signal: „Deine Runde entsteht gerade — alle kommen dazu."
private struct JoinCelebrationOverlay: View {
    @State private var beamProgress: CGFloat = 0  // 0 = außen, 1 = Zentrum
    @State private var markScale: CGFloat = 0.2
    @State private var markOpacity: Double = 0
    @State private var ringPulse: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w / 2
            let cy = h / 2
            let beamLength: CGFloat = min(w, h) * 0.6

            ZStack {
                // Dim-Cream-Backdrop
                Color.brandCream.opacity(0.92)
                    .ignoresSafeArea()

                // Vier Violett-Beams von den Seiten
                Group {
                    beam()  // oben
                        .offset(x: cx - 2, y: cy - beamLength * (1 - beamProgress) - beamLength / 2)
                    beam()
                        .offset(x: cx - 2, y: cy + beamLength * (1 - beamProgress) + beamLength / 2 - beamLength)
                        .rotationEffect(.degrees(180), anchor: .top)
                    beam()
                        .rotationEffect(.degrees(90))
                        .offset(x: cx - beamLength * (1 - beamProgress) - beamLength / 2, y: cy - 2)
                    beam()
                        .rotationEffect(.degrees(-90))
                        .offset(x: cx + beamLength * (1 - beamProgress) + beamLength / 2 - beamLength, y: cy - 2)
                }
                .opacity(1.0 - beamProgress * 0.7)

                // Zentrum: der echte DropsMark mit Dot, baut auf
                DropsMark(ringColor: .brandViolet, dotColor: .brandOrange, showDot: true)
                    .frame(width: 180, height: 180)
                    .scaleEffect(markScale * ringPulse)
                    .opacity(markOpacity)
                    .shadow(color: Color.brandViolet.opacity(0.4), radius: 30, y: 10)
            }
        }
        .onAppear { runSequence() }
    }

    private func beam() -> some View {
        // Senkrechter Violett-Streifen mit weichen Enden (vertikal gezeichnet,
        // dann rotiert für die Himmelsrichtungen).
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Color.brandViolet.opacity(0), Color.brandViolet, Color.brandViolet.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: 4, height: 220)
            .blur(radius: 1.5)
    }

    private func runSequence() {
        // Phase 1 (0.0–0.55s): Beams fliegen zum Zentrum
        withAnimation(.easeOut(duration: 0.55)) {
            beamProgress = 1.0
        }
        // Phase 2 (0.35–0.9s): Mark baut sich im Zentrum auf
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                markScale = 1.0
                markOpacity = 1.0
            }
        }
        // Phase 3 (0.9s): sanfter Pulse am Ende als Finisher
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                ringPulse = 1.05
            }
        }
    }
}
