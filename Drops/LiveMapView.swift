import SwiftUI
import MapKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseDatabase

// MARK: - Map Style Helper

enum MapStyleMode: String, CaseIterable {
    case auto   = "auto"
    case light  = "hell"
    case dark   = "dunkel"

    var label: String {
        switch self {
        case .auto:  return tr("map.style.auto")
        case .light: return  tr("map.style.light")
        case .dark:  return tr("map.style.dark")
        }
    }

    func isDark(for date: Date = Date()) -> Bool {
        switch self {
        case .light: return false
        case .dark:  return true
        case .auto:
            let hour = Calendar.current.component(.hour, from: date)
            return hour < 6 || hour >= 20
        }
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var userLocation: CLLocationCoordinate2D? = nil
    /// Horizontale GPS-Genauigkeit in Metern — für den Accuracy-Ring um den Pin.
    @Published var horizontalAccuracy: CLLocationAccuracy = 0
    /// Zeitpunkt des letzten akzeptierten Updates — für die Stale-Detection.
    private var lastAcceptedAt: Date? = nil

    /// Ab dieser Accuracy (in Metern) gilt ein Update als "schlechter Empfang".
    private let maxAcceptableAccuracy: CLLocationAccuracy = 250
    /// Wenn letzter guter Fix älter als X Sekunden → schlechte Updates akzeptieren
    /// (sonst bleibt der Pin nach langer U-Bahn-Fahrt am alten Standort hängen).
    private let staleThresholdSeconds: TimeInterval = 60
    /// Wenn neuer Punkt weiter als X Meter vom alten entfernt ist → akzeptieren,
    /// egal wie schlecht die Accuracy ist (User ist offensichtlich woanders).
    private let bigJumpThresholdMeters: CLLocationDistance = 500

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // startUpdatingLocation() NUR wenn Berechtigung bereits erteilt.
        // iOS 17+ zeigt den Location-Dialog auch ohne explizites
        // requestWhenInUseAuthorization() sobald startUpdatingLocation()
        // bei Status .notDetermined aufgerufen wird — das würde den
        // Permission-Dialog vor dem WelcomeSheet auslösen.
        // locationManagerDidChangeAuthorization startet es automatisch
        // sobald der User in requestAllPermissions() (nach WelcomeSheet)
        // die Berechtigung erteilt hat.
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // Negative Accuracy = ungültig (Simulator-Feature oder Hardwarefehler)
        guard loc.horizontalAccuracy >= 0 else { return }

        let isPoorAccuracy = loc.horizontalAccuracy > maxAcceptableAccuracy

        if let prev = userLocation, let lastAt = lastAcceptedAt, isPoorAccuracy {
            // Wir haben schon eine Position + das neue Update ist schlecht.
            // Verwerfen nur wenn der alte Fix **frisch** ist UND der neue
            // Punkt **nicht weit** weg ist. Sonst: U-Bahn-Fahrt → Pin updaten.
            let secsSinceLast = Date().timeIntervalSince(lastAt)
            let prevLoc = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            let movedDistance = prevLoc.distance(from: loc)

            let isStillFresh = secsSinceLast < staleThresholdSeconds
            let isSmallJump = movedDistance < bigJumpThresholdMeters

            if isStillFresh && isSmallJump {
                return  // kurzer Empfangsausfall, alten Pin behalten
            }
            // Sonst: entweder der alte Fix ist schon veraltet (>60s) oder der
            // neue Punkt ist >500m weg → Update akzeptieren auch wenn unscharf.
        }

        userLocation = loc.coordinate
        horizontalAccuracy = loc.horizontalAccuracy
        lastAcceptedAt = Date()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }
}

struct LiveMapView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("appLanguage") private var appLanguage = "de"
    /// Einmaliger Power-Hour-Hinweis nach Update. Wird auf true gesetzt
    /// sobald der User den Hinweis-Sheet einmal gesehen hat.
    // hasSeenPowerHourIntro entfernt — Power-Hour wurde eingestampft.
    @AppStorage("ud_presenceShareEnabled") private var presenceSharing = false
    // showPowerHourIntro entfernt — Power-Hour wurde eingestampft.
    @StateObject private var locationManager = LocationManager()
    /// MKMapView-Region: ersetzt das vorherige SwiftUI MapCameraPosition.
    /// MKMapView wrapped in MapKitMapView — Drop-Pins werden nativ verwaltet,
    /// kein Wobble bei Pan/Zoom mehr.
    /// Nil solange der User frei scrollt. Wird nur gesetzt wenn wir die Kamera
    /// programmatisch bewegen wollen (Initial-Zoom, focusedDrop, Cluster-Zoom).
    /// MapKitMapView konsumiert den Wert einmalig und cleared ihn — kein Feedback-Loop.
    @State private var targetRegion: MKCoordinateRegion? = nil
    /// Vorberechnete Bildschirmpunkte der GeoZone-Grenze.
    /// Referenz auf die echte MKMapView — für Live-Koordinaten im polygonsProvider.
    /// @State damit dieselbe Instanz über alle SwiftUI-Re-Renders erhalten bleibt
    /// (LiveMapView ist ein Struct — `let` würde bei jedem Re-Render neu allozieren).
    @State private var mapViewBox = MapViewBox()
    @State private var hasInitiallyZoomed = false
    @State private var selectedItem: MapAnnotationItem? = nil
    /// Drop für den der Quick-Reply-Sheet (Anfrage senden mit optionaler
    /// Schnellantwort) aktuell offen ist. Wird gesetzt wenn User auf
    /// dem Map-Pin-Detail-Sheet „Ich komme vorbei" tippt — geschickt
    /// wird erst nach Quick-Chip-Auswahl + „Senden"-Tap im Sheet.
    @State private var joinComposeItem: MapAnnotationItem? = nil
    @State private var joinedIDs: Set<UUID> = []
    @State private var showSafety = false
    @State private var mapId = UUID()
    /// Angetippte Community auf der Karte — öffnet CommunityJoinSheet.
    @State private var selectedCommunity: Community? = nil

    // MARK: - Clustering
    /// Fertige Cluster-Gruppen — werden bei Kamera-Bewegungsende neu berechnet.
    /// Jede Gruppe enthält ≥1 MapAnnotationItem. Gruppen mit 1 Item = normaler Pin.
    @State private var clusterGroups: [[MapAnnotationItem]] = []
    /// Pixel-Radius innerhalb dem zwei Pins zu einem Cluster zusammengefasst werden.
    private let clusterThreshold: CGFloat = 36

    /// Bündelt `filteredAnnotations` nach Bildschirm-Nähe.
    /// Setzt clusterGroups ohne Animation — verhindert das Pin-Ruckeln
    /// beim .onEnd-Recompute (sonst animiert SwiftUI Position-Diffs).
    private func setClusterGroups(_ groups: [[MapAnnotationItem]]) {
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { clusterGroups = groups }
    }

    /// Eigene Drops (type == .myDrop) werden NIE geclustert — sie erscheinen immer einzeln.
    /// Algorithmus: greedy O(n²), reicht für ~100 Pins problemlos.
    func computeClusters(mapView: MKMapView) {
        let items = filteredAnnotations
        var groups:   [[MapAnnotationItem]] = []
        var clustered = Set<UUID>()

        for item in items {
            guard !clustered.contains(item.id) else { continue }
            // Eigene Drops + Demo-Drops: immer solo.
            // Demo-Drops sollen einzeln tippbar sein — Clustering würde den
            // Zoom-in-Pflicht erzeugen und den Tap auf einzelne Pins blockieren.
            if item.type == .myDrop || item.isDemo {
                groups.append([item])
                clustered.insert(item.id)
                continue
            }
            let pt = mapView.convert(item.coordinate, toPointTo: mapView)
            var group = [item]
            clustered.insert(item.id)
            for other in items where !clustered.contains(other.id) && other.type != .myDrop {
                let otherPt = mapView.convert(other.coordinate, toPointTo: mapView)
                if hypot(pt.x - otherPt.x, pt.y - otherPt.y) < clusterThreshold {
                    group.append(other)
                    clustered.insert(other.id)
                }
            }
            groups.append(group)
        }
        setClusterGroups(groups)
    }

    /// Geografischer Mittelpunkt einer Gruppe.
    private func centroid(of group: [MapAnnotationItem]) -> CLLocationCoordinate2D {
        let n = Double(group.count)
        let lat = group.map { $0.coordinate.latitude  }.reduce(0, +) / n
        let lon = group.map { $0.coordinate.longitude }.reduce(0, +) / n
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Zoomt die Kamera so, dass alle Pins im Cluster sichtbar sind.
    private func zoomToCluster(_ group: [MapAnnotationItem]) {
        let coords = group.map { $0.coordinate }
        guard let minLat = coords.map({ $0.latitude  }).min(),
              let maxLat = coords.map({ $0.latitude  }).max(),
              let minLon = coords.map({ $0.longitude }).min(),
              let maxLon = coords.map({ $0.longitude }).max() else { return }
        let center = CLLocationCoordinate2D(
            latitude:  (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta:  max(0.003, (maxLat - minLat) * 3.0),
            longitudeDelta: max(0.003, (maxLon - minLon) * 3.0)
        )
        targetRegion = MKCoordinateRegion(center: center, span: span)
    }

    /// Eigener 8-Char BLE-Token — wird explizit an DropMapPin übergeben (nicht per @EnvironmentObject,
    /// da Map-Annotation-Content nicht zuverlässig den SwiftUI-Environment erbt).
    var myPinToken: String {
        // Konsistent mit dem AppStore.myBLEToken (firebaseUID-prefix).
        // Vorher nutzte das die lokale UUID — das hat NICHT mit den
        // BLE-confirmedTokens gematched, weil die Joiner ihren BLE-Token
        // aus firebaseUID ableiten. UI-Filter wie "p.token == myToken"
        // sahen dann nie eine Übereinstimmung → Joiner blieb auf
        // "Unterwegs" obwohl BLE bestätigt hatte.
        store.myBLEToken
    }

    var filteredAnnotations: [MapAnnotationItem] {
        // Volle Stranger-Drops von der Karte entfernen — sie sollen nicht
        // mehr beitretbar erscheinen. Im Umgebungstab bleiben sie aber
        // sichtbar (dort als „Voll" markiert), damit User sehen dass es
        // den Drop gibt. Eigene Drops und der gerade gejointe Drop bleiben
        // immer auf der Karte (sonst verschwindet er einem unter den
        // Füßen während man hinläuft).
        let joinedDropID = store.activeJoinedDropID?.uuidString
        let base = store.allMapAnnotations.filter { ann in
            guard ann.type == .stranger else { return true }
            if ann.id.uuidString == joinedDropID { return true }
            // Ghost-Drops (beendet) immer anzeigen — egal ob sie voll waren.
            // Aktive, volle Drops dagegen ausblenden (nicht mehr beitretbar).
            if ann.isGhost { return true }
            return !ann.isFull
        }
        // Der „Nur weiblich"-Filter läuft jetzt im Umgebungs-Tab, nicht mehr hier.
        guard !store.activityCategoryFilter.isEmpty else { return base }
        return base.filter {
            ActivityCategory.matches(filter: store.activityCategoryFilter,
                                     emoji: $0.emoji, activity: $0.activity)
        }
    }

    /// Finale Annotations-Liste für MapKitMapView:
    /// – clustered Drops → ein Cluster-Proxy-Item pro Gruppe
    /// – solo Drops → normales MapAnnotationItem
    /// – Suggested Spots → .suggested Items (non-interactive)
    /// – Community Pins → .community Items
    var mapDisplayAnnotations: [MapAnnotationItem] {
        var items: [MapAnnotationItem] = []

        // Drops: clustered oder solo
        if clusterGroups.isEmpty {
            items += filteredAnnotations
        } else {
            for group in clusterGroups {
                if group.count == 1 {
                    items.append(group[0])
                } else {
                    let coord = centroid(of: group)
                    let stableKey = group.map(\.id.uuidString).sorted().joined()
                    var proxy = MapAnnotationItem(
                        id: AppStore.stableUUID(from: stableKey),
                        name: "\(group.count) Pläne",
                        emoji: group[0].emoji,
                        activity: "",
                        coordinate: coord,
                        type: .cluster
                    )
                    proxy.clusterGroup = group
                    items.append(proxy)
                }
            }
        }

        // Suggested-Spots aus pastDrops-Historie bewusst DEAKTIVIERT —
        // die kleinen Icons verwirrten User ("warum sehe ich hier Ghost-
        // Runden?"). Falls später wieder gewünscht: Loop wiederherstellen.

        // Community Pins
        for community in (FeatureFlags.communitiesEnabled ? store.nearbyCommunities : []) {
            var ann = MapAnnotationItem(
                id: AppStore.stableUUID(from: "community_\(community.id)"),
                name: community.displayName,
                emoji: community.emoji,
                activity: community.displayName,
                coordinate: community.coordinate,
                type: .community
            )
            ann.communityRef = community
            items.append(ann)
        }

        return items
    }

    static func allCityPolygonsPts(mapView: MKMapView) -> [[CGPoint]] {
        ServiceCities.all.map { city in
            var closed = city.polygon
            if let first = closed.first { closed.append(first) }
            return closed.map { mapView.convert($0, toPointTo: mapView) }
        }
    }

    var body: some View {
        // In NavigationStack wrappen — gleiche Safe-Area-Insets wie bei den
        // anderen Tabs (Umgebung/Profil/Settings). Logo sitzt dadurch auf
        // identischer Höhe.
        NavigationStack { mapBody }
    }

    @ViewBuilder
    private var mapBody: some View {
        ZStack {
            // Phase 1: MKMapView-Wrapper ersetzt SwiftUI Map.
            // — Drop-Pins (active + ghost) rendern als MKAnnotation, nativ verwaltet.
            // — User-Standort via showsUserLocation = true (blauer Punkt).
            // Phase 2: Aurora-Overlay, Community-Pins, Suggested-Spots, Cluster-Logic.
            MapKitMapView(
                targetRegion: $targetRegion,
                annotations: mapDisplayAnnotations,
                myToken: myPinToken,
                confirmedTokens: store.bluetoothMeetup.confirmedTokens,
                isJoinedProvider: { id in
                    joinedIDs.contains(id)
                        || store.hasJoinedDrop(dropID: id)
                        || store.activeJoinedDropID == id
                },
                onTapAnnotation: { item in
                    if let group = item.clusterGroup {
                        zoomToCluster(group)
                    } else if let community = item.communityRef {
                        selectedCommunity = community
                    } else {
                        selectedItem = item
                    }
                },
                onCameraChange: { mapView in
                    computeClusters(mapView: mapView)
                },
                preferredColorScheme: nil,
                mapViewBox: mapViewBox
            )
            .ignoresSafeArea()
            .onAppear {
                if let loc = locationManager.userLocation {
                    if !hasInitiallyZoomed {
                        targetRegion = MKCoordinateRegion(
                            center: loc,
                            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                        )
                        hasInitiallyZoomed = true
                    }
                    store.updateUserLocation(loc)
                }
            }
            .onChange(of: locationManager.userLocation) { _, loc in
                guard let loc = loc else { return }
                if !hasInitiallyZoomed {
                    targetRegion = MKCoordinateRegion(
                        center: loc,
                        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                    )
                    hasInitiallyZoomed = true
                }
                store.updateUserLocation(loc)
            }
            .onChange(of: store.pendingDropID) { _, dropID in
                guard let dropID = dropID else { return }
                store.pendingDropID = nil
                // Drop auf der Karte finden und Sheet öffnen
                if let match = store.allMapAnnotations.first(where: { $0.id == dropID }) {
                    targetRegion = MKCoordinateRegion(
                        center: match.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        selectedItem = match
                    }
                }
            }
            .onChange(of: store.focusedDropCoordinate) { _, coord in
                guard let coord = coord else { return }
                targetRegion = MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )
                // Reset nach dem Fokussieren, damit erneutes Tippen erneut feuert
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    store.focusedDropCoordinate = nil
                }
            }

            // ── Aurora Zone-Overlay (Phase 2) ────────────────────────────
            // Koordinaten kommen aus cityPolygonPts, das bei jeder Kamera-
            // Bewegung (onCameraChange) synchron aktualisiert wird.
            // .allowsHitTesting(false) damit Taps auf Karte + Pins durchkommen.
            // Nur zeigen, wenn die City-Restriction aktiv ist — sonst sind die
            // Linien irreführend (suggerieren Service-Grenze, die es nicht gibt).
            if BetaConfig.cityRestrictionEnabled {
                MultiZoneOverlay(polygonsProvider: {
                    guard let mv = mapViewBox.mapView else { return [] }
                    return LiveMapView.allCityPolygonsPts(mapView: mv)
                })
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // ── Eigenes Profilbild als Standort-Marker ────────────────────
            // Ersetzt den blauen UserLocation-Punkt wenn Presence-Sharing
            // aktiv ist. Rendert an echter Position (nicht gefuzzt).
            // Während einer aktiven Runde wird der Self-Marker ausgeblendet,
            // weil der Drop-Pin bereits den Standort markiert — sonst
            // überdeckt der Avatar die eigene Runde.
            if presenceSharing && !store.isInActiveDrop {
                SelfCharacterOverlay(
                    profileImageURL: store.profileImageURL,
                    fallbackEmoji: store.currentUser.emoji,
                    pointProvider: {
                        guard let mv = mapViewBox.mapView else { return nil }
                        let coord = store.currentUser.coordinate
                        guard CLLocationCoordinate2DIsValid(coord),
                              abs(coord.latitude) > 0.001 || abs(coord.longitude) > 0.001
                        else { return nil }
                        return mv.convert(coord, toPointTo: mv)
                    }
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .onAppear  { mapViewBox.mapView?.showsUserLocation = false }
                .onDisappear { mapViewBox.mapView?.showsUserLocation = true  }
            }
            // Blauer System-UserLocation-Punkt zusätzlich auch während einer
            // aktiven Runde ausblenden — der Drop-Pin markiert die Position.
            Color.clear
                .frame(width: 0, height: 0)
                .onChange(of: store.isInActiveDrop) { _, inDrop in
                    if inDrop { mapViewBox.mapView?.showsUserLocation = false }
                }

            // ── Presence-Overlay (Delayed Location Sharing) ──────────────
            // Freunde als Emoji/Bild-Avatar, Fremde als anonyme graue Punkte.
            // Positionen werden pro Frame frisch aus MKMapView projiziert.
            PresenceOverlay(pinsProvider: {
                guard let mv = mapViewBox.mapView else { return [] }
                let (friends, strangers) = store.filteredPresences()
                let friendPins = friends.map { e -> PresencePin in
                    PresencePin(
                        id: e.uid,
                        point: mv.convert(e.coordinate, toPointTo: mv),
                        emoji: e.emoji,
                        name: e.name,
                        profileImageURL: e.profileImageURL,
                        ageLabel: e.ageLabel,
                        isFriend: true
                    )
                }
                let strangerPins = strangers.map { e -> PresencePin in
                    PresencePin(
                        id: e.uid,
                        point: mv.convert(e.coordinate, toPointTo: mv),
                        emoji: e.emoji,
                        name: nil,
                        // Bild bleibt sichtbar — Schutz liegt in Position+Delay, nicht in Anonymität
                        profileImageURL: e.profileImageURL,
                        ageLabel: e.ageLabel,
                        isFriend: false
                    )
                }
                return friendPins + strangerPins
            })
            .ignoresSafeArea()
            .allowsHitTesting(false)  // Map-Pinch/Pan muss durchkommen

            VStack {
                // Dazu-Floating-Branding (links oben). Nur die Karte hat
                // keine Hero-Headline, deshalb hebt sich hier eine
                // kräftige brand-lila Capsule mit cream-Wortmarke ab —
                // klar lesbar auf jedem Map-Tile-Hintergrund.
                HStack {
                    DazuWordmark(color: .brandCream, dotColor: .brandOrange)
                        .frame(height: 24)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.brandViolet))
                        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                        .shadow(color: Color.brandViolet.opacity(0.35), radius: 10, y: 3)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // ── Activity-Indikator (links oben) ──────────────────────
                // Zeigt wie viele Drops in der gefilterten Sicht sichtbar
                // sind. Hilft dem User einzuschätzen ob's gerade „los ist"
                // ohne erst die Karte abzuscannen. Erscheint nur wenn ≥1
                // Drop sichtbar ist — bei Null würde die Empty-Map sich
                // selbst erklären.
                HStack {
                    // Ghost-Drops aus dem "X in der Nähe"-Counter ausschließen —
                    // die sind vorbei, sollten nicht als "aktive Drops" zählen.
                    let count = filteredAnnotations.filter {
                        !$0.isGhost && ($0.type == .stranger || $0.type == .friend || $0.type == .myDrop)
                    }.count
                    if count > 0 {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.onlineGreen)
                                .frame(width: 6, height: 6)
                            Text((count == 1 ? tr("map.drops_nearby_singular") : tr("map.drops_nearby_plural")).replacingOccurrences(of: "{count}", with: "\(count)"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textPrimary)
                        }
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.75)))
                        .overlay(
                            Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                        .padding(.leading, 16)
                    }
                    Spacer()
                }
                .padding(.top, 8)

                // ── Power-Hour Countdown-Pille (oben) ────────────────────
                // Auto-updates jede Minute via TimelineView. Sichtbar in
                // zwei Phasen:
                //   – ≤60 Min vor Start → "Power-Hour in 47 Min"
                //   – ≤60 Min vor Ende eines aktiven Slots → "endet in 23 Min"
                // Sonst nil → keine Pille.
                // Power-Hour-Pill entfernt (Feature deaktiviert).
                EmptyView()

                Spacer()

                // ── Bottom-Row: Boost-Phase-Banner (links, full-width) +
                //               Recenter-Button (rechts) ──────────────────
                // Banner ist DAUERHAFT solange Boost-Phase aktiv ist:
                //   – nicht aus-/einklappbar
                //   – nicht draggable / verschiebbar
                //   – Tap überall am Banner → öffnet Drop-Erstellen
                // Banner spannt von der linken Bildschirmkante bis kurz vor
                // dem Recenter-Button (`maxWidth: .infinity` im HStack
                // teilt sich den verfügbaren Platz gegen den Recenter).
                HStack(alignment: .center, spacing: 10) {
                    // Power-Hour-Banner auf der Karte entfernt (Feature deaktiviert).
                    // Spacer drückt den Recenter-Button rechts an die Kante.
                    Spacer(minLength: 0)

                    Button(action: {
                        let loc = locationManager.userLocation
                            ?? CLLocationCoordinate2D(latitude: 48.1371, longitude: 11.5754)
                        targetRegion = MKCoordinateRegion(
                            center: loc,
                            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                        )
                    }) {
                        DazuIcon("location.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.brand)
                            .padding(13)
                            .liquidGlassCircle()
                    }
                    .accessibilityLabel(tr("map.recenter"))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .sheet(item: $selectedItem) { item in
            // Joiner-Pin: das ist KEIN Drop, sondern eine Person die zu
            // unserem Drop unterwegs ist. DropJoinSheet würde fälschlich
            // "Ich komme vorbei" anzeigen — wir routen stattdessen auf
            // eine kompakte Info-Ansicht ohne CTA.
            if item.type == .joiner {
                JoinerLiveInfoSheet(item: item)
                    .environmentObject(store)
                    .presentationDetents([.fraction(0.4)])
                    .presentationDragIndicator(.visible)
                    .sheetBackground()
            } else if item.isDemo {
                // Demo-Drop: Wachstums-Nudge statt Join-UI.
                DemoDropCTASheet(item: item)
                    .environmentObject(store)
                    .presentationDetents([.fraction(0.65), .large])
                    .presentationDragIndicator(.visible)
                    .sheetBackground()
            } else if item.isGhost {
                // Ghost-Drop: bereits beendet, kein Join möglich.
                // Kompakte Info-Karte statt DropJoinSheet (kein "Beitreten").
                GhostDropInfoSheet(item: item)
                    .environmentObject(store)
                    .presentationDetents([.fraction(0.42)])
                    .presentationDragIndicator(.visible)
                    .sheetBackground()
            } else {
                // isJoined deckt drei Quellen ab:
                //  - lokal: gerade eben angetappt (joinedIDs)
                //  - Pending/Accepted Request im Store
                //  - bereits aktiv gejoinder Drop (activeJoinedDropID)
                // Sonst wäre der Button "Ich komme vorbei" auch dann aktiv,
                // wenn der User den Drop schon gejoinder hat und nochmal tappt.
                DropJoinSheet(
                    item: item,
                    isJoined: joinedIDs.contains(item.id)
                        || store.hasJoinedDrop(dropID: item.id)
                        || store.activeJoinedDropID == item.id
                ) {
                    // Detail-Sheet schließen + Quick-Reply-Sheet öffnen.
                    // User wählt einen Schnellantwort-Chip und tippt
                    // „Senden" — erst dann geht die Anfrage raus.
                    // Konsistent zum FeedView-Pfad (FeedDropCard).
                    let toCompose = item
                    selectedItem = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        joinComposeItem = toCompose
                    }
                }
                .environmentObject(store)
                // Adaptives Sizing je nach Content-Dichte:
                //   fuzzy + keine Extras       → 0.42 (minimal: nur Header + Disclaimer + Button)
                //   myDrop / normaler Drop      → 0.48 (kompakt: Info + Button)
                //   mit Teilnehmern ODER Text   → 0.55 (mehr Platz für Participant-Row)
                // Zweiter Detent = hochziehbar für mehr Details.
                .presentationDetents({
                    let hasExtras = !item.participants.isEmpty
                        || (item.dropDescription.map { !$0.isEmpty } ?? false)
                    if item.isFuzzy && !hasExtras {
                        return [PresentationDetent.fraction(0.42), .fraction(0.60)]
                    } else if hasExtras {
                        return [.fraction(0.55), .fraction(0.72)]
                    } else {
                        return [.fraction(0.48), .fraction(0.65)]
                    }
                }())
                .presentationDragIndicator(.visible)
                .sheetBackground()
            }
        }
        // ── Quick-Reply-Sheet (Map-Pfad) ────────────────────────────────
        // Wird vom DropJoinSheet ausgelöst — User wählt einen Schnell-
        // antwort-Chip und sendet damit die Beitrittsanfrage. Identisch
        // zum FeedView-Pfad damit beide Wege gleichen UX bieten.
        .sheet(item: $joinComposeItem) { item in
            JoinConfirmSheet(item: item) {
                joinedIDs.insert(item.id)
            }
            .environmentObject(store)
            .presentationDetents([.fraction(0.55)])
            .presentationDragIndicator(.hidden)
            .sheetBackground()
        }
        // Community Join Sheet — wird bei Tap auf einen Community-Map-Pin gezeigt.
        .sheet(item: $selectedCommunity) { community in
            CommunityJoinSheet(community: community)
                .environmentObject(store)
                .presentationDetents([.fraction(0.45)])
                .presentationDragIndicator(.visible)
                .sheetBackground()
        }
        // Hinweis: das `IncomingJoinRequestSheet` (Host-seitig) ist
        // auf MainTabView-Ebene angehängt, damit es egal in welchem
        // Tab der Host gerade ist auftaucht. Wäre es nur hier, würde
        // bei Host im Profil/Umgebung gar kein Pop-up kommen — nur
        // die Push-Notification.
        .sheet(isPresented: $showSafety) {
            SafetySheetView().environmentObject(store)
        }
        // Power-Hour-Onboarding-Sheet komplett entfernt (Feature eingestampft).
    }

}

// MARK: - Drop Map Pin

struct DropMapPin: View {
    let item: MapAnnotationItem
    var isJoined: Bool
    let onTap: () -> Void
    /// Eigener 8-Char-Token (vom Parent übergeben, da @EnvironmentObject in Map-Annotations nicht zuverlässig ist)
    var myToken: String = ""
    /// BLE-bestätigte Partner-Tokens (vom Parent übergeben)
    var confirmedTokens: Set<String> = []
    @State private var pressed = false
    @State private var freshPulse = false
    /// Langsamer Atemeffekt auf dem Fog-Ring des Fuzzy-Pins.
    @State private var fogPulse = false

    /// Drop ist „frisch" wenn er weniger als 5 Min alt ist — bekommt
    /// einen pulsierenden Ring als „neu hier"-Signal. Greift nicht bei
    /// Boost-Drops (deren Gold-Ring hat Priorität).
    private var isFresh: Bool {
        Date().timeIntervalSince(item.createdAt) < 300
    }

    /// Nur bestätigte Teilnehmer anzeigen (BLE-confirmed oder eigener Token als Host).
    var confirmedParticipants: [DropParticipant] {
        item.participants.filter { p in
            p.token == myToken || confirmedTokens.contains(p.token)
        }
    }

    var pinColor: Color {
        // Community-Drops überschreiben die normale Farbe — sie erscheinen
        // immer in Clero-Grün, egal welcher type (myDrop/stranger).
        if item.isCommunityDrop { return .cleroGreen }
        switch item.type {
        case .friend:   return isJoined ? .onlineGreen : .brand
        case .myDrop:   return .accentOrange
        case .joiner:   return .onlineGreen
        case .stranger:
            return item.creatorAgeGroup?.color ?? Color.auroraCyan
        case .cluster, .suggested, .community:
            return Color.auroraCyan
        }
    }

    // Skalierung basierend auf bestätigten Teilnehmern
    var emojiCircleSize: CGFloat {
        let count = confirmedParticipants.count
        switch count {
        case 0, 1: return 24
        case 2, 3: return 28
        case 4, 5: return 32
        default:   return 38
        }
    }

    var emojiFontSize: CGFloat { emojiCircleSize * 0.54 }
    var labelFontSize: CGFloat { emojiCircleSize < 30 ? 12 : 13 }

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { pressed = false }
            onTap()
        }) {
            if item.isFuzzy {
                // ── Fremde / fuzzy-Standort-Pin ─────────────────────────
                // Gleiche Grundform wie der Freundes-Pin (OpenRing + Icon-
                // Puck + Activity-Capsule darunter), damit sie sich auf der
                // Karte als eine Sprache lesen. Unterschiede, die "fremd,
                // Ort ungefähr" signalisieren:
                //  • Ring gestrichelt statt solid (dashed = unsicher)
                //  • Immer das Activity-Icon im Puck (nie Avatar) → anonym
                //  • Puck in Lavender statt dem Avatar-Hintergrund
                //  • Leicht pulsierender Fog-Halo bleibt — "Zone, kein Punkt"
                VStack(spacing: 4) {
                    ZStack {
                        // Weicher Fog-Halo (pulsiert) — "ungefähre Zone"
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [pinColor.opacity(fogPulse ? 0.22 : 0.12),
                                             pinColor.opacity(0.0)],
                                    center: .center,
                                    startRadius: 6,
                                    endRadius: 36
                                )
                            )
                            .frame(width: 72, height: 72)
                            .scaleEffect(fogPulse ? 1.06 : 1.0)

                        // Gestrichelter OpenRing — gleicher Shape wie Freundes-
                        // Pin, aber dashed statt gefüllt. "Form bekannt, Rand
                        // offen" = fremd + ungefähr.
                        OpenRingShape()
                            .stroke(pinColor,
                                    style: StrokeStyle(lineWidth: 3,
                                                       dash: [5, 3]))
                            .frame(width: 48, height: 48)
                            .shadow(color: pinColor.opacity(0.35),
                                    radius: 5, y: 2)

                        // Activity-Icon im Puck (statt Avatar). Lavender-
                        // Hintergrund — identisch zum eigenen Drop-Pin, aber
                        // ohne violetten Ring außen → bleibt klar fremd.
                        ZStack {
                            Circle().fill(Color.brandLavender)
                                .frame(width: 32, height: 32)
                            DazuActivityIcon(item.emoji, when: item.hasActivityEmoji)
                                .font(.system(size: 18))
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                    }

                    Text(item.activity)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.brandNight)
                        .lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.brandCream.opacity(0.9)))
                        .overlay(Capsule().stroke(pinColor.opacity(0.35),
                                                  lineWidth: 0.5))
                }
                .scaleEffect(pressed ? 1.06 : 1.0)
            } else {
                // Exakter Pin: Offener violetter Ring (dazu-Logo-Metapher).
                // Im Ring das Profilbild des Hosts (falls hinterlegt), sonst
                // der Emoji des Drops. Darunter der Aktivitäts-Text.
                let hostParticipant = item.participants.first
                // Für Stranger / Ghost-Drops ist `participants` leer — in dem
                // Fall nutzen wir das beim publishDrop eingefrorene URL (im
                // Annotation-Item), damit der Pin trotzdem das Avatar zeigt.
                let hostImageURL = hostParticipant?.profileImageURL ?? item.hostProfileImageURL
                let hostSelfie = hostParticipant?.selfie
                VStack(spacing: 4) {
                    ZStack {
                        if isFresh {
                            Circle()
                                .stroke(pinColor.opacity(0.55), lineWidth: 1.8)
                                .frame(width: 48, height: 48)
                                .scaleEffect(freshPulse ? 1.7 : 0.9)
                                .opacity(freshPulse ? 0.0 : 0.8)
                        }

                        // Offener Ring (dazu-Logo-Mark)
                        OpenRingShape()
                            .fill(Color.brandViolet)
                            .frame(width: 48, height: 48)
                            .shadow(color: Color.brandViolet.opacity(0.4), radius: 6, y: 2)

                        // Profilbild im Ring (wenn vorhanden), sonst der
                        // zwei-ton dazu-Profil-Icon-Fallback (statt des
                        // Activity-Emojis — der Pin ist ein Personen-Avatar,
                        // kein Activity-Marker).
                        // Ausnahme: der EIGENE Drop zeigt das Activity-Icon,
                        // nicht das eigene Profilbild — der User weiß ja dass
                        // es seine Runde ist, braucht sich nicht selbst zu sehen.
                        Group {
                            if item.type == .myDrop {
                                ZStack {
                                    Circle().fill(Color.brandLavender)
                                        .frame(width: 32, height: 32)
                                    DazuActivityIcon(item.emoji)
                                        .font(.system(size: 18))
                                }
                            } else if let img = hostSelfie {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                            } else if let url = hostImageURL, !url.isEmpty {
                                RemoteProfileImage(url: url,
                                                   fallbackEmoji: item.emoji,
                                                   size: 32,
                                                   strokeColor: .clear)
                            } else {
                                // Kein Profilbild → Activity-Icon im Puck
                                // (statt generischem DazuProfileIcon). Das
                                // passt deutlich besser zur dazu-Markenlogik
                                // und zeigt sofort worum's bei der Runde geht.
                                ZStack {
                                    Circle().fill(Color.brandLavender)
                                        .frame(width: 32, height: 32)
                                    DazuActivityIcon(item.emoji.isEmpty ? "✨" : item.emoji,
                                                     when: item.hasActivityEmoji)
                                        .font(.system(size: 18))
                                }
                            }
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())

                        // Dot in der Ring-Lücke bei confirmed participants
                        if confirmedParticipants.count >= 2 {
                            Text("\(confirmedParticipants.count)")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.brandOrange))
                                .offset(x: 14, y: -14)
                        }
                    }

                    Text(item.type == .myDrop ? item.activity : (item.isStranger ? item.activity : item.name))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.brandNight)
                        .lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.brandCream.opacity(0.9)))
                        .overlay(Capsule().stroke(Color.brandViolet.opacity(0.2), lineWidth: 0.5))
                }
                .scaleEffect(pressed ? 1.08 : 1.0)
            }
        }
        .dropsPressable()
        // Ghost-Drops: leicht verblasst + leicht entsättigt damit der Pin
        // klar als "vergangen" erkennbar ist, aber noch lesbar bleibt.
        // Demo-Drops: noch matter + kleiner — sie sind Seeder-Platzhalter,
        // keine echten Community-Drops. Visuell klar untergeordnet.
        .scaleEffect(item.isDemo ? 0.93 : 1.0)
        .opacity(item.isDemo ? 0.82 : (item.isGhost ? 0.85 : 1.0))
        .saturation(item.isDemo ? 0.80 : (item.isGhost ? 0.65 : 1.0))
        .onAppear {
            // Fresh-Pin-Pulse (< 5 Min alt) — Ghost-Drops nicht pulsieren.
            if isFresh && !item.isGhost {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    freshPulse = true
                }
            }
            // Fog-Ring-Atem (nur bei Fuzzy-Pins): langsamer Sinus-Loop
            // der den gestrichelten Ring leicht skaliert + blinkt.
            if item.isFuzzy && !item.isGhost {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    fogPulse = true
                }
            }
        }
    }
}

// MARK: - Suggested Spot Pin

/// Subtiler Marker für einen Spot wo der User schon mehrfach gedroppt hat.
/// Kein Tap-Handler — rein Hinweis ("hier hat dir's gefallen"). Spätere
/// Iteration kann Tap → CreateDrop pre-filled mit Activity öffnen.
struct SuggestedSpotPin: View {
    let spot: AppStore.SuggestedSpot

    var body: some View {
        ZStack {
            // Doppel-Glow als „beliebter Spot"-Signal — sehr dezent.
            Circle()
                .fill(Color.brand.opacity(0.08))
                .frame(width: 44, height: 44)
            Circle()
                .fill(Color.white.opacity(0.75))
                .frame(width: 26, height: 26)
                .overlay(
                    Circle().strokeBorder(Color.brand.opacity(0.4), lineWidth: 1.2)
                )
            DazuActivityIcon(spot.activityEmoji, tint: .brandVioletFixed, dotColor: .brandOrangeFixed)
                .font(.system(size: 13))
        }
        .opacity(0.7)
        .allowsHitTesting(false)   // Stört Drop-Pins nicht beim Tappen
    }
}

// MARK: - Drop Cluster Pin

/// Zeigt mehrere zusammengefasste Drops als einen Cluster-Pin.
/// Tap → zoomt rein bis alle Pins getrennt sichtbar sind.
struct DropClusterPin: View {
    let group:  [MapAnnotationItem]
    let onTap:  () -> Void

    /// Bis zu 3 Emojis aus der Gruppe für den visuellen Vorgeschmack.
    private var previewEmojis: [String] {
        Array(group.prefix(3).map { $0.emoji })
    }

    /// Alle Aktivitätsnamen — für AccessibilityLabel.
    private var activitiesLabel: String {
        group.prefix(5).map { $0.activity }.joined(separator: ", ")
    }

    @State private var pressed = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Weicher Schein
                Circle()
                    .fill(Color.brandVioletFixed.opacity(0.16))
                    .frame(width: 58, height: 58)

                // Geschlossener Ring: mehrere Runden an einem Ort
                Circle()
                    .fill(Color.brandCreamFixed)
                    .frame(width: 46, height: 46)
                    .shadow(color: Color.brandVioletFixed.opacity(0.35), radius: 8, x: 0, y: 3)
                Circle()
                    .strokeBorder(Color.brandVioletFixed, lineWidth: 6)
                    .frame(width: 46, height: 46)

                VStack(spacing: 1) {
                    // Emoji-Stack (max 2 übereinander, sonst Zahl)
                    if previewEmojis.count <= 2 {
                        HStack(spacing: -4) {
                            ForEach(Array(group.prefix(3).enumerated()), id: \.offset) { _, member in
                                DazuActivityIcon(member.emoji, when: member.hasActivityEmoji,
                                                 tint: .brandVioletFixed, dotColor: .brandOrangeFixed)
                                    .font(.system(size: 14))
                            }
                        }
                    }
                    // Anzahl
                    Text("\(group.count)")
                        .font(.system(size: previewEmojis.count <= 2 ? 11 : 17,
                                      weight: .bold, design: .rounded))
                        .foregroundColor(.brandNightFixed)
                }

                // Der Punkt aus dem Logo, oben rechts auf dem Ring
                Circle()
                    .fill(Color.brandOrangeFixed)
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(Color.brandCreamFixed, lineWidth: 2))
                    .offset(x: 16, y: -16)
            }
        }
        .dropsPressable()
        .scaleEffect(pressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
        .accessibilityLabel("\(group.count) Pläne: \(activitiesLabel)")
        .accessibilityHint(tr("map.tap_to_zoom"))
    }
}

// MARK: - Drop Join Sheet

// MARK: - Incoming Join Request Sheet (Host)

struct IncomingJoinRequestSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let request: IncomingJoinRequest

    @State private var timeLeft: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var autoAcceptSeconds: Int {
        max(0, Int(request.autoAcceptAt.timeIntervalSinceNow))
    }

    /// Entfernung Joiner → Drop-Standort, berechnet aus Live-Koordinaten.
    private var joinerDistanceMeters: Double? {
        guard let coord = store.joinerLiveCoordinates[request.id],
              let drop  = store.activeDrops.first(where: { $0.id.uuidString == request.dropID })
        else { return nil }
        let joinerLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let dropLoc   = CLLocation(latitude: drop.location.coordinate.latitude,
                                    longitude: drop.location.coordinate.longitude)
        return joinerLoc.distance(from: dropLoc)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters)) m entfernt" }
        return String(format: "%.1f km entfernt", meters / 1000)
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Drag handle ───────────────────────────────────────
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // ── Header-Chip ───────────────────────────────────────
            HStack(spacing: 6) {
                DazuIcon("person.fill.badge.plus")
                    .font(.system(size: 11, weight: .bold))
                Text(store.activeDrops.first?.activity.name ?? tr("map.join_request"))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .textCase(.uppercase)
            }
            .foregroundColor(.brandViolet)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Color.brandLavender))

            // Mehrere Anfragen in Queue
            let waitingCount = max(0, store.pendingJoinRequests.count - 1)
            if waitingCount > 0 {
                HStack(spacing: 5) {
                    DazuIcon("person.2.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text((waitingCount == 1 ? tr("map.more_requests_singular") : tr("map.more_requests_plural")).replacingOccurrences(of: "{count}", with: "\(waitingCount)"))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundColor(.brandOrange)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.brandOrange.opacity(0.14)))
                .padding(.top, 8)
            }

            // ── Avatar + Name ─────────────────────────────────────
            let tierColor = ReliabilityScore.color(forPoints: request.joinerReliabilityPoints)
            VStack(spacing: 14) {
                // Avatar mit Tier-Ring
                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [tierColor.opacity(0.7), tierColor.opacity(0.2)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 106, height: 106)

                    if let urlStr = request.joinerProfileImageURL, !urlStr.isEmpty {
                        RemoteProfileImage(url: urlStr, fallbackEmoji: request.joinerEmoji, size: 96)
                    } else {
                        ZStack {
                            Circle().fill(Color.brandLavender).frame(width: 96, height: 96)
                            DazuPersonIcon().font(.system(size: 48))
                        }
                    }
                }
                .padding(.top, 20)

                // Name + Alter
                HStack(spacing: 6) {
                    Text(request.joinerName)
                        .font(.system(size: 24, weight: .bold))
                    if let age = request.joinerAge {
                        Text("\(age)")
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(.textSecondary)
                    }
                    if request.joinerIsPlus {
                        HStack(spacing: 3) {
                            DazuIcon("bolt.fill").font(.system(size: 9, weight: .bold))
                            Text("PLUS").font(.system(size: 10, weight: .heavy))
                        }
                        .foregroundStyle(Color(hex: "7a4e05"))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(
                            LinearGradient(colors: [Color.auroraGoldLight, Color.auroraGoldDark],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Capsule()
                        )
                    }
                }

                // Trust-Badge + Entfernung — Badge nur wenn verlässlich.
                HStack(spacing: 8) {
                    if ReliabilityScore.isTrusted(forPoints: request.joinerReliabilityPoints) {
                        HStack(spacing: 4) {
                            DazuIcon("checkmark.seal.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(tr("tier.trusted"))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.brandViolet)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.brandLavender))
                    }

                    if let meters = joinerDistanceMeters {
                        HStack(spacing: 4) {
                            DazuIcon("location.fill").font(.system(size: 10, weight: .bold))
                            Text(formatDistance(meters))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.brandOrange)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.brandOrange.opacity(0.14)))
                    }
                }
            }

            // ── Nachricht ─────────────────────────────────────────
            if let msg = request.joinerMessage,
               !msg.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    DazuIcon("bubble.left.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.brandViolet)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.brandLavender))
                    Text(msg)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .liquidGlass(cornerRadius: 18)
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }

            // ── Auto-Accept Timer ─────────────────────────────────
            if timeLeft > 0 {
                let total  = max(1, Double(Int(request.autoAcceptAt.timeIntervalSince1970
                    - request.autoAcceptAt.timeIntervalSinceNow + Double(timeLeft))))
                let progress = Double(timeLeft) / total

                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.brandLavender, lineWidth: 2.5)
                            .frame(width: 22, height: 22)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.brandOrange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .frame(width: 22, height: 22)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: timeLeft)
                    }
                    Text(tr("map.auto_confirmed_in").replacingOccurrences(of: "{time}", with: "\(timeLeft / 60):\(String(format: "%02d", timeLeft % 60))"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.65))
                }
                .padding(.top, 16)
            }

            Spacer(minLength: 20)

            // ── Buttons ───────────────────────────────────────────
            HStack(spacing: 10) {
                Button {
                    store.declineJoinRequest(request)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        DazuIcon("xmark")
                            .font(.system(size: 14, weight: .bold))
                        Text(tr("map.reject"))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.brandNight.opacity(0.65))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.brandLavender.opacity(0.6)))
                }
                .dropsPressable()

                Button {
                    store.acceptJoinRequest(request)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        DazuIcon("checkmark")
                            .font(.system(size: 14, weight: .bold))
                        Text(tr("map.confirm"))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.brandViolet))
                }
                .dropsPressable()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .onReceive(timer) { _ in
            timeLeft = autoAcceptSeconds
            if timeLeft <= 0 { dismiss() }
        }
        .onAppear { timeLeft = autoAcceptSeconds }
    }
}

struct DropJoinSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "de"
    let item: MapAnnotationItem
    var isJoined: Bool
    /// Wird bei Tap auf "Ich komme vorbei" gefeuert — Map-Pfad sendet
    /// die Anfrage ohne Nachricht; den Compose-Flow gibt's nur einmal,
    /// im FeedView-JoinConfirmSheet (DropJoinSheet ist primär Info-Sheet).
    let onJoin: () -> Void

    @State private var joining = false
    @State private var resolvedAddress: String? = nil
    @State private var now = Date()
    @State private var showCancelAlert = false
    @State private var showCreatorProfile = false

    /// Live-Joiner (aus `dropins/{dropID}`) — damit auch Nicht-Mitglieder
    /// sehen wer schon dabei ist. Vorher: nur BLE-confirmed sichtbar
    /// = leer für Fremd-Drops ohne eigene BLE-Verbindung.
    struct LiveJoiner: Identifiable {
        let id: String
        let name: String
        let age: Int?
        let profileImageURL: String?
    }
    @State private var liveJoiners: [LiveJoiner] = []

    /// Admin-Flag: Tap auf Demo-Live-Runde → sofort beigetreten
    /// (ohne Pending). Nur für App-Store-Screenshots.
    @AppStorage("demoAutoJoin") private var demoAutoJoin: Bool = false

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// Nur BLE-bestätigte Teilnehmer (+ eigener Host-Token) anzeigen.
    private var confirmedParticipants: [DropParticipant] {
        let myToken = String(store.currentUser.id.uuidString
            .replacingOccurrences(of: "-", with: "").prefix(8))
        return item.participants.filter { p in
            p.token == myToken || store.bluetoothMeetup.confirmedTokens.contains(p.token)
        }
    }

    // Ist der Nutzer bereits in einem anderen Drop aktiv?
    private var blockedByOtherDrop: Bool {
        guard let active = store.activeJoinedDropID else { return false }
        return active != item.id
    }

    private var activeSince: String {
        let elapsed = Int(now.timeIntervalSince(item.createdAt) / 60)
        if elapsed < 1 { return tr("drop.just_started") }
        if elapsed < 60 { return tr("map.active_since_mins").replacingOccurrences(of: "{mins}", with: "\(elapsed)") }
        let h = elapsed / 60
        let m = elapsed % 60
        return m > 0
            ? tr("map.active_since_hm").replacingOccurrences(of: "{h}", with: "\(h)").replacingOccurrences(of: "{m}", with: "\(m)")
            : tr("map.active_since_h").replacingOccurrences(of: "{h}", with: "\(h)")
    }

    private var startTimeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "de_DE")
        return "Gestartet \(f.string(from: item.createdAt)) Uhr"
    }

    var accentColor: Color {
        switch item.type {
        case .myDrop:   return .accentOrange
        case .joiner:   return .onlineGreen
        case .stranger: return item.creatorAgeGroup?.color ?? Color.auroraCyan
        default:        return .brand
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Hero: 160pt hohe Mini-Map mit dickem Cream→Lavender-Fade
            // nach unten. Darauf: LIVE-Pill oben links, Share oben rechts,
            // und ein großer floating Icon-Puck mittig am unteren Rand,
            // der die Grenze zum Content überlappt (gleicher Look wie
            // Google-Maps-Place-Sheets).
            ZStack(alignment: .top) {
                MiniMapSnapshotFill(coordinate: item.effectiveCoordinate, metersSpan: 500)
                // Starker Fade unten, damit der Content-Übergang weich wird
                // und der Icon-Puck auf Lavender sitzt, nicht auf Karte.
                LinearGradient(
                    colors: [
                        Color.brandLavender.opacity(0.0),
                        Color.brandLavender.opacity(0.05),
                        Color.brandLavender.opacity(0.9),
                        Color.brandCream
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                HStack(alignment: .top) {
                    if !item.isGhost {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.accentOrange)
                                .frame(width: 6, height: 6)
                            Text("LIVE")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .tracking(1.0)
                                .foregroundColor(.brandNight)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.brandCream))
                        .shadow(color: Color.brandNight.opacity(0.10), radius: 4, y: 2)
                    }
                    Spacer()
                    DropShareButton(item: item)
                }
                .padding(.horizontal, 18).padding(.top, 14)
            }
            .frame(height: 160)
            .clipped()

            // Header: Icon-Puck + Content (Puck überlappt das Hero oben via
            // negativem Top-Padding).
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.brandCream)
                        .frame(width: 72, height: 72)
                        .overlay(Circle().stroke(Color.brandViolet, lineWidth: 3))
                        .shadow(color: Color.brandViolet.opacity(0.28), radius: 10, y: 4)
                    DazuActivityIcon(item.emoji.isEmpty ? "✨" : item.emoji, when: item.hasActivityEmoji)
                        .font(.system(size: 34))
                }
                .padding(.top, -44)  // Puck 44pt über die Hero-Grenze schieben

                VStack(alignment: .leading, spacing: 4) {
                    // Aktivität als Haupttitel — bei Fremden und Freunden.
                    // Violett + Orange-Punkt am Ende (wie der Name im Profil),
                    // damit's zur dazu-Markensprache passt.
                    let title = item.type == .myDrop ? item.activity : (item.isStranger ? item.activity : item.name)
                    (Text(title).foregroundColor(.brandViolet)
                     + Text(".").foregroundColor(.brandOrange))
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                    // Host + Alter + ETA + Distance alle in einer Zeile —
                    // kompakter als die alte 2-Zeilen-Trennung. Host-Teil
                    // bleibt tappbar (öffnet Mini-Profil).
                    if item.type != .myDrop {
                        HStack(spacing: 8) {
                            Button { showCreatorProfile = true } label: {
                                HStack(spacing: 5) {
                                    (Text(item.name).foregroundColor(.brandViolet)
                                     + Text(".").foregroundColor(.brandOrange))
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                    if let age = item.creatorAge {
                                        Text("\(age)")
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                            .foregroundColor(.brandNight.opacity(0.55))
                                    }
                                }
                            }
                            .dropsPressable()

                            Text("·")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.brandNight.opacity(0.3))

                            HStack(spacing: 4) {
                                DazuIcon("figure.walk")
                                    .font(.system(size: 11, weight: .bold))
                                Text(store.etaString(to: item.effectiveCoordinate))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.brandViolet)

                            Text("·")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.brandNight.opacity(0.3))

                            Text(store.distanceString(to: item.effectiveCoordinate))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.brandNight.opacity(0.6))
                        }
                    } else {
                        Label { Text(tr("drop.my_drop")) } icon: { DazuIcon("star.fill") }
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.brandOrange)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 18)

            // Live-Joiner (aus `dropins/{dropID}`) — sichtbar auch wenn ich
            // noch nicht gejoined bin. Vorher: nur BLE-confirmed, also leer
            // für Fremd-Drops. Zeigt kleine Avatar-Row + "X kommen" Zeile.
            if confirmedParticipants.isEmpty && !liveJoiners.isEmpty {
                HStack(spacing: 10) {
                    HStack(spacing: -8) {
                        ForEach(liveJoiners.prefix(4)) { j in
                            Group {
                                if let url = j.profileImageURL, !url.isEmpty {
                                    RemoteProfileImage(url: url,
                                                       fallbackEmoji: "",
                                                       size: 32,
                                                       strokeColor: Color.brandCream)
                                } else {
                                    Circle()
                                        .fill(Color.brandLavender)
                                        .frame(width: 32, height: 32)
                                        .overlay(DazuPersonIcon().font(.system(size: 14)))
                                }
                            }
                            .overlay(Circle().stroke(Color.brandCream, lineWidth: 2))
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if liveJoiners.count == 1, let p = liveJoiners.first {
                            (Text(p.name).foregroundColor(.brandViolet)
                             + Text(".").foregroundColor(.brandOrange))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Text(tr("drop.on_the_way"))
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                        } else {
                            let names = liveJoiners.prefix(2).map { $0.name }.joined(separator: " & ")
                            let extra = liveJoiners.count > 2 ? " +\(liveJoiners.count - 2)" : ""
                            (Text(names + extra).foregroundColor(.brandViolet)
                             + Text(".").foregroundColor(.brandOrange))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Text(tr("drop.on_the_way"))
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }

            // Teilnehmer-Avatare — nur BLE-bestätigte (physisch vor Ort)
            if !confirmedParticipants.isEmpty {
                HStack(spacing: 10) {
                    ParticipantAvatars(participants: confirmedParticipants)
                    VStack(alignment: .leading, spacing: 2) {
                        // Single-Participant-Fall: Name + Alter inline,
                        // Verified-Check, Beta-Badge (nur wenn Self),
                        // dann Tier-Badge + "Ist bereits vor Ort" darunter.
                        if confirmedParticipants.count == 1, let p = confirmedParticipants.first {
                            HStack(spacing: 5) {
                                Text(nameWithAge(p))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(1)
                                if isSelfParticipant(p) && store.qualifiesForBetaBadge {
                                    BetaBadge()
                                }
                            }
                            HStack(spacing: 5) {
                                if ReliabilityScore.isTrusted(forPoints: p.reliabilityScore) {
                                    DazuIcon("checkmark.seal.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.brandViolet)
                                    Circle()
                                        .fill(Color.textTertiary)
                                        .frame(width: 2, height: 2)
                                }
                                Text(tr("map.already_on_site"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.textSecondary)
                            }
                        } else {
                            Text(participantNamesLabel(confirmedParticipants))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                            Text(tr("map.are_already_on_site"))
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            // Unterwegs-Anzeige: Beitritt aber noch nicht per BLE bestätigt.
            // Beim eigenen Drop ist der Host selbst in `participants` enthalten
            // und per Definition vor Ort — darf nicht als "unterwegs" zählen.
            let hostIsSelf = (item.hostUID ?? "") == (store.currentUser.firebaseUID ?? "none")
            let baseline = hostIsSelf ? max(item.participants.count - 1, 0)
                                      : item.participants.count
            let onTheWayCount = max(baseline - confirmedParticipants.count, 0)
            if onTheWayCount > 0 {
                HStack(spacing: 6) {
                    DazuIcon("figure.walk", accent: false)
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                    Text(onTheWayCount == 1
                         ? tr("map.one_on_way")
                         : tr("map.x_on_way").replacingOccurrences(of: "{count}", with: "\(onTheWayCount)"))
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 18)
                .padding(.top, onTheWayCount > 0 && confirmedParticipants.isEmpty ? 12 : 4)
            }

            // Adresse / Fuzzy-Hinweis
            if item.isFuzzy {
                // Kein Reverse-Geocoding bei Fuzzy-Drops — die fuzzy Koordinate
                // liefert eine falsche Adresse, die echte würde den Host verraten.
                // Stattdessen: Hinweis dass der Drop näher ist als auf der Karte.
                HStack(spacing: 8) {
                    DazuIcon("location.slash.fill")
                        .font(.system(size: 12))
                        .foregroundColor(accentColor.opacity(0.75))
                    Text(tr("map.fuzzy_pos_info"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            } else if let address = resolvedAddress {
                HStack(spacing: 8) {
                    DazuIcon("mappin.and.ellipse", accent: false)
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                    Text(address)
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            }

            // Aktiv-Dauer-Chip (Lavendel + orangener Dot)
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.brandOrange)
                    .frame(width: 7, height: 7)
                Text(activeSince)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.brandNight)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color.brandLavender))
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .onReceive(timer) { _ in now = Date() }

            // Optionale Zusatzinfos (Uhrzeit nur bei geplanten Drops, nicht bei "Jetzt")
            let showTimeTile = item.scheduledTime != nil && item.scheduledTime != "Jetzt"
            if showTimeTile || item.dropDescription != nil {
                VStack(spacing: 8) {
                    if showTimeTile, let time = item.scheduledTime {
                        HStack(spacing: 8) {
                            DazuIcon("clock.fill")
                                .font(.system(size: 12)).foregroundColor(.brand)
                            Text(trScheduledTime(time)).font(.system(size: 13, weight: .medium)).foregroundColor(.textPrimary)
                            Spacer()
                        }
                    }
                    if let desc = item.dropDescription, !desc.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            DazuIcon("text.bubble.fill")
                                .font(.system(size: 12)).foregroundColor(.textSecondary)
                            Text(desc).font(.system(size: 13)).foregroundColor(.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                    }
                }
                .padding(14)
                .liquidGlass(cornerRadius: 14)
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }

            Spacer(minLength: 0)

            // Bottom
            if item.type == .myDrop {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        DazuIcon("clock.badge.checkmark.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.brandOrange)
                        Text(tr("drop.waiting_for_joiners"))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.7))
                    }


                    Button {
                        showCancelAlert = true
                    } label: {
                        HStack(spacing: 8) {
                            DazuIcon("flag.checkered").font(.system(size: 14, weight: .bold))
                            Text(tr("drop.end_drop"))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.brandNight.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Color.brandLavender.opacity(0.6)))
                    }
                    .dropsPressable()
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 24)
                .sheet(isPresented: $showCancelAlert) {
                    EndDropSheet(
                        activityEmoji: item.emoji,
                        activityName: item.activity,
                        participantCount: item.participants.count,
                        elapsedSeconds: Date().timeIntervalSince(item.createdAt)
                    ) {
                        store.cancelDrop(id: item.id)
                        showCancelAlert = false
                        dismiss()
                    } onCancel: {
                        showCancelAlert = false
                    }
                    // Sheet kompakter — vorher 0.82 (zu groß auf normalen
                    // iPhones, viel Leerraum). 0.62 reicht für das straffere
                    // Layout (kleineres Hero-Visual, engere Spacings) ohne
                    // zu scrollen.
                    .presentationDetents([.fraction(0.62)])
                    // Drop-Beenden-Warnung darf nicht versehentlich
                    // weggewischt werden — User muss bewusst Beenden
                    // oder Abbrechen tippen.
                    .presentationDragIndicator(.hidden)
                    .interactiveDismissDisabled()
                    .sheetBackground()
                }
                .alert(tr("map.live_activity_disabled"), isPresented: $store.showLiveActivitySettingsHint) {
                    Button(tr("map.open_settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(tr("map.live_activities_info"))
                }
            } else if blockedByOtherDrop {
                // Bereits in einem anderen Drop aktiv
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        DazuIcon("lock.circle.fill", accent: false)
                            .font(.system(size: 15))
                            .foregroundColor(.textTertiary)
                        Text(tr("drop.already_active"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    Text(tr("drop.leave_active_first"))
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            } else {
                // Map-Pfad: schickt direkt ohne Compose-UI. Wer eine
                // Nachricht mitgeben will, geht über den Umgebungs-Tab
                // (FeedView → JoinConfirmSheet mit Quick-Chips + freier
                // Eingabe). Doppelte Compose-UI verwirrt nur.
                //
                // TimelineView refresht den Cooldown-Countdown sekündlich
                // — sonst zeigt der Button "X Min" stale bis das nächste
                // Sheet-Update kommt. Wichtig: nach Verlassen muss der User
                // sehen wie der Cooldown abläuft, sonst probiert er es
                // wieder und wieder.
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let cooldown = store.joinCooldownRemaining(dropID: item.id)
                    let inCooldown = cooldown > 0 && !isJoined
                    Button {
                        guard !isJoined && !joining && !inCooldown else { return }
                        // Demo-Autojoin: Pending überspringen, direkt dropin
                        // schreiben + sheet schließen → sofortiger „bereits
                        // dabei"-State für App-Store-Screenshots.
                        if demoAutoJoin,
                           let fbid = item.firebaseDropID,
                           fbid.hasPrefix("demolive_") {
                            let myUID = FirebaseAuth.Auth.auth().currentUser?.uid ?? "demo_self"
                            let payload: [String: Any] = [
                                "name": store.currentUser.name,
                                "emoji": store.currentUser.emoji,
                                "lat": store.currentUser.coordinate.latitude,
                                "lng": store.currentUser.coordinate.longitude,
                                "locTime": Date().timeIntervalSince1970 * 1000,
                                "timestamp": Date().timeIntervalSince1970 * 1000,
                                "profileImageURL": store.profileImageURL ?? ""
                            ]
                            Database.database().reference()
                                .child("dropins").child(fbid).child(myUID)
                                .setValue(payload)
                            // Store-State setzen damit dazu-Tab in die Live-
                            // Ansicht springt (nutzt activeJoinedDropID +
                            // activeDropAnnotation für die Content-View).
                            // 2h-Dauer + createdAt=jetzt überschreiben → Timer
                            // sinnvoll statt 12h-Default.
                            store.activeJoinedDropID = item.id
                            var liveItem = item
                            liveItem.durationMinutes = 120
                            liveItem.createdAt = Date()
                            store.activeDropAnnotation = liveItem
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                store.selectedTab = .create
                            }
                            return
                        }
                        joining = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            joining = false
                            onJoin()
                            dismiss()
                            // Sofort auf den Aktiv-Tab wechseln
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                store.selectedTab = .create
                            }
                        }
                    } label: {
                        let isPending = store.myJoinRequestStatus == "pending" && isJoined
                        let isDeclined = store.myJoinRequestStatus == "declined" && isJoined
                        ZStack {
                            if inCooldown {
                                let mins = Int(cooldown / 60) + 1
                                HStack(spacing: 8) {
                                    DazuIcon("clock.fill").font(.system(size: 15))
                                    Text(tr("map.cooldown_mins").replacingOccurrences(of: "{mins}", with: "\(mins)"))
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(.white.opacity(0.9))
                            } else if joining || isPending {
                                HStack(spacing: 8) {
                                    DazuLoader().tint(.white)
                                    Text(isPending ? tr("map.waiting_confirmation") : "")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            } else if isDeclined {
                                HStack(spacing: 8) {
                                    DazuIcon("xmark.circle.fill").font(.system(size: 17))
                                    Text(tr("map.not_confirmed")).font(.system(size: 16, weight: .bold))
                                }
                                .foregroundColor(.white)
                            } else if isJoined {
                                HStack(spacing: 8) {
                                    DazuIcon("checkmark.circle.fill").font(.system(size: 17))
                                    Text(tr("drop.im_in")).font(.system(size: 16, weight: .bold))
                                }
                                .foregroundColor(.white)
                            } else {
                                HStack(spacing: 8) {
                                    DazuIcon("figure.walk.arrival", accent: false).font(.system(size: 17))
                                    Text(tr("drop.coming_by")).font(.system(size: 16, weight: .bold))
                                }
                                .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            Capsule().fill(
                                inCooldown ? Color.brandNight.opacity(0.25)
                              : isDeclined ? Color.brandOrange
                              : isJoined   ? Color.brandViolet
                              : joining    ? Color.brandViolet.opacity(0.6)
                                           : Color.brandViolet
                            )
                        )
                    }
                    .dropsPressable()
                    .disabled(isJoined || joining || inCooldown)
                    .animation(.spring(response: 0.3), value: isJoined)
                    .animation(.spring(response: 0.3), value: joining)
                    .animation(.spring(response: 0.3), value: inCooldown)
                    let _ = ctx.date  // hält die TimelineView am Tickern
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandCream.ignoresSafeArea())
        .onAppear {
            geocodeAddress()
            // Drop-View für Drops+ „wer hat geschaut" erfassen
            store.viewDrop(item)
            fetchLiveJoiners()
        }
        .sheet(isPresented: $showCreatorProfile) {
            // Fallback auf item-Felder wenn participants leer (Fuzzy/Stranger-Drops
            // aus Firebase haben keine participants-Liste befüllt — nur hostUID/name/emoji).
            let creator = item.participants.first
            let profileName  = creator?.name           ?? item.name
            let profileEmoji = creator?.emoji          ?? item.emoji
            let profileUID   = creator?.firebaseUID    ?? item.hostUID
            let profileScore = creator?.reliabilityScore ?? item.hostReliabilityPoints ?? ReliabilityScore.startingPoints
            let profileImgURL = creator?.profileImageURL ?? item.hostProfileImageURL
            if #available(iOS 16.4, *) {
                MiniProfileSheet(
                    name: profileName,
                    emoji: profileEmoji,
                    selfie: creator?.selfie,
                    profileImageURL: profileImgURL,
                    reliabilityScore: profileScore,
                    accentColor: accentColor,
                    userUID: profileUID,
                    canBlock: true
                ) { dismiss() }
                .environmentObject(store)
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.hidden)
                .sheetBackground()
            } else {
                MiniProfileSheet(
                    name: profileName,
                    emoji: profileEmoji,
                    selfie: creator?.selfie,
                    profileImageURL: profileImgURL,
                    reliabilityScore: profileScore,
                    accentColor: accentColor,
                    userUID: profileUID,
                    canBlock: true
                ) { dismiss() }
                .environmentObject(store)
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.hidden)
            }
        }
    }

    // MARK: - Teilnehmer-Namen

    private func participantNamesLabel(_ participants: [DropParticipant]) -> String {
        let names = participants.map { $0.name }
        switch names.count {
        case 1: return names[0]
        case 2: return "\(names[0]) & \(names[1])"
        case 3: return "\(names[0]), \(names[1]) & \(names[2])"
        default:
            let visible = names.prefix(2).joined(separator: ", ")
            return tr("map.and_more").replacingOccurrences(of: "{names}", with: visible).replacingOccurrences(of: "{count}", with: "\(names.count - 2)")
        }
    }

    /// Name mit Alter im Format "Dennis, 30" wenn vorhanden, sonst nur Name.
    private func nameWithAge(_ p: DropParticipant) -> String {
        if let age = p.age { return "\(p.name), \(age)" }
        return p.name
    }

    /// Vergleicht ob der Teilnehmer der eigene User ist — Vergleich
    /// primär über firebaseUID, Fallback Name (z.B. wenn als Host
    /// registriert ohne explizite UID).
    private func isSelfParticipant(_ p: DropParticipant) -> Bool {
        let myUID = FirebaseAuth.Auth.auth().currentUser?.uid
        return (p.firebaseUID != nil && p.firebaseUID == myUID)
            || (p.firebaseUID == nil && p.name == store.currentUser.name)
    }

    // MARK: - Reverse Geocoding

    /// Lädt die aktuellen Dropins (= bereits beigetretene User) aus Firebase
    /// und zeigt sie als Live-Joiner-Row. Vorher sahen Nicht-Mitglieder gar
    /// nicht wer schon dabei ist — jetzt werden Avatare + Namen sichtbar.
    private func fetchLiveJoiners() {
        guard let firebaseID = item.firebaseDropID else { return }
        Database.database().reference()
            .child("dropins").child(firebaseID)
            .observeSingleEvent(of: .value) { snap in
                var list: [LiveJoiner] = []
                for case let child as DataSnapshot in snap.children {
                    guard let dict = child.value as? [String: Any],
                          let name = dict["name"] as? String else { continue }
                    list.append(LiveJoiner(
                        id: child.key,
                        name: name,
                        age: dict["age"] as? Int,
                        profileImageURL: dict["profileImageURL"] as? String
                    ))
                }
                DispatchQueue.main.async { self.liveJoiners = list }
            }
    }

    private func geocodeAddress() {
        // Fuzzy-Drops: kein Geocoding.
        // • fuzzy coord → liefert falsche Adresse (800-1000m daneben)
        // • real  coord → würde den Host-Standort verraten
        // Der Fuzzy-Hinweis-Row ersetzt die Adresszeile im UI.
        guard !item.isFuzzy else { return }
        let geocoder = CLGeocoder()
        let loc = CLLocation(latitude: item.coordinate.latitude, longitude: item.coordinate.longitude)
        geocoder.reverseGeocodeLocation(loc) { placemarks, _ in
            guard let p = placemarks?.first else { return }
            let street = [p.thoroughfare, p.subThoroughfare]
                .compactMap { $0 }.joined(separator: " ")
            let city = p.locality ?? ""
            DispatchQueue.main.async {
                resolvedAddress = [street, city].filter { !$0.isEmpty }.joined(separator: ", ")
            }
        }
    }
}

// MARK: - In-App Route Sheet

struct InAppRouteSheet: View {
    @AppStorage("appLanguage") private var appLanguage = "de"
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let destination: CLLocationCoordinate2D
    let destinationName: String
    let accentColor: Color

    @State private var route: MKRoute? = nil
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Topbar
            HStack {
                Button(tr("common.close")) { dismiss() }
                    .font(.system(size: 15)).foregroundColor(accentColor)
                Spacer()
                Text(tr("map.route"))
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(.textPrimary)
                Spacer()
                Text(tr("common.close")).foregroundColor(.clear) // balance
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(Color.bgPrimary)

            Divider()

            // Karte mit Route
            ZStack {
                RouteMapView(
                    userCoordinate: store.currentUser.coordinate,
                    destination: destination,
                    route: route
                )
                if isLoading {
                    Color.black.opacity(0.08)
                    VStack(spacing: 10) {
                        DazuLoader().tint(.brand)
                        Text(tr("map.calculating_route"))
                            .font(.system(size: 13)).foregroundColor(.textSecondary)
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Color.white.opacity(0.85)))
                }
            }
            .frame(maxHeight: .infinity)
            .ignoresSafeArea(edges: .horizontal)

            // Info + Button
            VStack(spacing: 14) {
                // Reisezeit + Distanz
                if let route = route {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("map.walking"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textSecondary)
                                .textCase(.uppercase)
                            Text(tr("map.walk_minutes").replacingOccurrences(of: "{mins}", with: "\(max(1, Int(route.expectedTravelTime / 60)))"))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.textPrimary)
                        }
                        Spacer()
                        Divider().frame(height: 44)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(tr("map.distance"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textSecondary)
                                .textCase(.uppercase)
                            Text(route.distance < 1000
                                 ? "\(Int(route.distance)) m"
                                 : String(format: "%.1f km", route.distance / 1000))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.textPrimary)
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // Ziel-Adresse
                HStack(spacing: 6) {
                    DazuIcon("mappin.circle.fill")
                        .foregroundColor(accentColor).font(.system(size: 14))
                    Text(destinationName)
                        .font(.system(size: 14, weight: .medium)).foregroundColor(.textPrimary)
                    Spacer()
                }

                // Schließen-Button (Hauptaktion)
                Button { dismiss() } label: {
                    Text(tr("common.close"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.lg))
                }
                .dropsPressable()

                // Sekundär: Turn-by-Turn in Apple Maps
                Button {
                    let placemark = MKPlacemark(coordinate: destination)
                    let mapItem = MKMapItem(placemark: placemark)
                    mapItem.name = destinationName
                    mapItem.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
                    ])
                } label: {
                    Label { Text(tr("map.open_in_maps")) } icon: { DazuIcon("arrow.triangle.turn.up.right.circle", accent: false) }
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                .dropsPressable()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 28)
            .background(Color.bgPrimary)
        }
        .background(Color.bgPrimary)
        .onAppear { calculateRoute() }
    }

    private func calculateRoute() {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            placemark: MKPlacemark(coordinate: store.currentUser.coordinate)
        )
        request.destination = MKMapItem(
            placemark: MKPlacemark(coordinate: destination)
        )
        request.transportType = .walking
        MKDirections(request: request).calculate { response, _ in
            DispatchQueue.main.async {
                isLoading = false
                route = response?.routes.first
            }
        }
    }
}

// MARK: - Route Map View (UIViewRepresentable)

struct RouteMapView: UIViewRepresentable {
    let userCoordinate: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
    let route: MKRoute?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })

        // Ziel-Pin
        let pin = MKPointAnnotation()
        pin.coordinate = destination
        map.addAnnotation(pin)

        if let route = route {
            map.addOverlay(route.polyline, level: .aboveRoads)
            // Sichtbereich an Route anpassen
            let rect = route.polyline.boundingMapRect
            let padded = rect.insetBy(dx: -rect.size.width * 0.25,
                                      dy: -rect.size.height * 0.25)
            map.setVisibleMapRect(padded,
                edgePadding: UIEdgeInsets(top: 60, left: 24, bottom: 60, right: 24),
                animated: true)
        } else {
            // Fallback: beide Punkte zeigen
            let coords = [userCoordinate, destination]
            let points = coords.map { MKMapPoint($0) }
            var rect = MKMapRect.null
            for p in points {
                let r = MKMapRect(x: p.x - 500, y: p.y - 500, width: 1000, height: 1000)
                rect = rect.union(r)
            }
            map.setVisibleMapRect(rect,
                edgePadding: UIEdgeInsets(top: 60, left: 24, bottom: 60, right: 24),
                animated: false)
        }
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemGreen
            renderer.lineWidth = 5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let id = "DropPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            if let marker = view as? MKMarkerAnnotationView {
                marker.markerTintColor = UIColor.systemGreen
                marker.glyphImage = UIImage(systemName: "mappin.circle.fill")
            }
            return view
        }
    }
}

// MARK: - Active Drop Tab View

struct ActiveDropTabView: View {
    @EnvironmentObject var store: AppStore
    let item: MapAnnotationItem
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("appLanguage") private var appLanguage = "de"

    /// Eigene LocationManager-Instanz — für GPS-basierte Ankunfts-Erkennung.
    @StateObject private var locationManager = LocationManager()
    @State private var route: MKRoute? = nil
    @State private var isLoadingRoute = true
    @State private var resolvedAddress: String? = nil
    @State private var showCancelAlert = false
    @State private var showLeaveConfirm = false
    @State private var showExtendSheet = false
    @State private var now = Date()
    @State private var arrivedAnimated = false
    @State private var showShareSheet = false
    @State private var showRouteSheet = false
    @State private var lastExtendedAt: Date? = nil
    @State private var lastExtendCooldownSecs: Int = 0  // Hälfte der gewählten Verlängerung
    /// Sheet-State im Parent — überlebt Firebase-Updates ohne zu resetten.
    @State private var selectedProfileParticipant: DropParticipant? = nil
    /// Host-Standort-Änderung — öffnet Pin-Picker, bestätigter Pin wird nach
    /// Firebase geschrieben und triggert eine Benachrichtigung an alle Joiner.
    @State private var showChangeLocationSheet = false
    /// Dropins aus Firebase (für Demo-Live-Drops wo item.participants leer
    /// ist aber dropins/{fbid} echte Mock-Joiner enthält). Als Pseudo-
    /// DropParticipants gerendert damit die Live-Teilnehmer-Row voll ist.
    @State private var demoJoiners: [DropParticipant] = []
    @State private var pendingNewCoord: CLLocationCoordinate2D? = nil

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Adaptive Farben

    var isOwnDrop: Bool { item.type == .myDrop }

    /// Eigener Token (8-stellig)
    /// Konsistent mit AppStore.myBLEToken (firebaseUID-prefix). Vorher nutzte
    /// dies die lokale UUID — das hat NICHT mit den BLE-confirmedTokens
    /// gematched, weil Joiner ihren BLE-Token aus firebaseUID ableiten.
    /// Folge: UI-Filter wie `p.token == myToken` sahen nie eine
    /// Übereinstimmung → Joiner blieb auf "Unterwegs", obwohl BLE bestätigt
    /// hatte.
    var myToken: String {
        store.myBLEToken
    }

    /// Schwelle in Metern, ab der GPS-Nähe als „vor Ort" gilt.
    /// Eng gesetzt (< 20 m) damit der Host erst wirklich am Ziel ankommt — nicht
    /// schon beim Vorbeifahren auf „angekommen" springt.
    private static let gpsArrivalThresholdMeters: Double = 20

    /// Prüft ob GPS-Position nahe genug am Drop-Ort ist.
    private var isNearDropByGPS: Bool {
        guard let dist = liveDistanceMeters else { return false }
        return dist <= Self.gpsArrivalThresholdMeters
    }

    /// Live Luftlinien-Distanz zum Drop in Metern. Re-berechnet sich bei jedem
    /// GPS-Update (locationManager.userLocation ist @Published), daher updated
    /// die Anzeige im Aktiv-Tab **live** während man läuft — statt nur beim
    /// Tab-Switch wie vorher mit der statischen Route-Distanz.
    private var liveDistanceMeters: Double? {
        guard let user = locationManager.userLocation else { return nil }
        let userLoc = CLLocation(latitude: user.latitude, longitude: user.longitude)
        let dropLoc = CLLocation(latitude: item.coordinate.latitude, longitude: item.coordinate.longitude)
        return userLoc.distance(from: dropLoc)
    }

    /// Geschätzte Gehzeit basierend auf liveDistanceMeters (~1.25 m/s = 75 m/min
    /// Fußgänger-Durchschnitt in der Stadt).
    private var liveWalkMinutes: Int? {
        guard let dist = liveDistanceMeters else { return nil }
        return max(1, Int(dist / 75))
    }

    /// Host ist „angekommen" sobald eine dieser Bedingungen zutrifft:
    ///   1. Drop wurde am aktuellen Standort erstellt (`dropLocationType == .current`)
    ///   2. GPS-Position ist ≤ 100 m vom Drop-Koordinaten entfernt
    ///   3. Mindestens eine BLE-Bestätigung mit einem anderen Teilnehmer
    /// Joiner: ebenfalls via GPS oder BLE.
    var isArrived: Bool {
        // Früher: `isOwnDrop && dropLocationType == .current` → der Host war
        // automatisch "vor Ort" sobald die Runde lief, egal ob er sich
        // seitdem wegbewegt hat. Jetzt: auch der Host muss GPS-nah oder
        // BLE-bestätigt sein. Verhindert "falsch vor Ort angezeigt" wenn
        // der Host zwischendrin weggegangen ist.
        return isNearDropByGPS
            || !store.bluetoothMeetup.confirmedTokens.isEmpty
    }

    /// Synthetischer Host-Teilnehmer für fremde Drops (Firebase liefert keine Participants).
    private var syntheticHost: DropParticipant {
        DropParticipant(name: item.name, emoji: item.emoji, token: "__host__")
    }

    /// Physisch bestätigte Teilnehmer (BLE-bestätigt ODER der Host bei
    /// fremden Drops, wenn der Joiner noch keine participants-Liste hat).
    /// Self (das eigene Token) zählt nur als „vor Ort", wenn `isArrived`
    /// wirklich greift — sonst stand der Host bei einem Pin-Drop oder
    /// der Joiner kurz nach Beitritt fälschlich auf „vor Ort", obwohl
    /// er noch unterwegs war.
    var confirmedHere: [DropParticipant] {
        var result: [DropParticipant]
        if item.participants.isEmpty && !isOwnDrop {
            // Host ist immer vor Ort — ggf. weitere BLE-bestätigte einfügen
            result = [syntheticHost]
            let bleConfirmed = store.bluetoothMeetup.confirmedTokens
            if !bleConfirmed.isEmpty {
                let extra = bleConfirmed.map { token in
                    DropParticipant(name: "", emoji: item.emoji, token: token)
                }
                result.append(contentsOf: extra)
            }
        } else {
            result = item.participants.filter { p in
                // Self: nur wenn physisch angekommen (GPS ≤ 20 m oder BLE).
                // Andere Teilnehmer: nur wenn BLE bestätigt hat.
                if p.token == myToken { return isArrived }
                return store.bluetoothMeetup.confirmedTokens.contains(p.token)
            }
        }

        // Fail-safe: wenn User im aktiven Drop ist UND als „vor Ort" gilt
        // (isArrived) aber Self fehlt in der Liste (Firebase-Sync-Lag o.ä.),
        // dann Self explizit anhängen. Sonst sieht der User sich selbst nicht
        // in seinem eigenen Drop — extrem irritierend.
        if isArrived && store.isInActiveDrop
           && !result.contains(where: { $0.token == myToken }) {
            result.append(DropParticipant(
                name: store.currentUser.name,
                emoji: store.currentUser.emoji,
                reliabilityScore: store.reliabilityScore.points,
                reliabilityCommits: store.reliabilityScore.totalCommits,
                age: store.userAge,
                token: myToken,
                profileImageURL: store.profileImageURL
            ))
        }

        return result
    }

    /// Unterwegs (beigetreten, aber noch nicht per BLE bestätigt).
    /// Self landet hier solange `isArrived` false ist — auch der Host,
    /// wenn er einen Pin-Drop fern vom aktuellen Standort erstellt hat.
    var onTheWay: [DropParticipant] {
        var result: [DropParticipant]
        if item.participants.isEmpty && !isOwnDrop {
            // Aktueller User ist unterwegs bis BLE bestätigt
            guard !isArrived else { return [] }
            return [DropParticipant(name: store.currentUser.name,
                                    emoji: store.currentUser.emoji,
                                    token: myToken)]
        } else {
            result = item.participants.filter { p in
                // Self: in „Unterwegs" wenn noch nicht angekommen.
                // Andere: in „Unterwegs" wenn BLE noch nicht bestätigt hat.
                if p.token == myToken { return !isArrived }
                return !store.bluetoothMeetup.confirmedTokens.contains(p.token)
            }
        }

        // Fail-safe: wenn User im aktiven Drop ist UND noch nicht „vor Ort"
        // ist (isArrived == false) UND Self fehlt in der Liste, Self in
        // „Unterwegs" anzeigen — sonst landet der Joiner zwischen den Stühlen
        // (weder in Vor Ort noch Unterwegs sichtbar).
        if !isArrived && store.isInActiveDrop
           && !result.contains(where: { $0.token == myToken }) {
            result.append(DropParticipant(
                name: store.currentUser.name,
                emoji: store.currentUser.emoji,
                reliabilityScore: store.reliabilityScore.points,
                reliabilityCommits: store.reliabilityScore.totalCommits,
                age: store.userAge,
                token: myToken,
                profileImageURL: store.profileImageURL
            ))
        }

        return result
    }

    var accentColor: Color {
        switch item.type {
        case .myDrop:   return .brandOrange
        case .joiner:   return .brandViolet
        case .stranger: return .brandViolet
        default:        return .brandViolet
        }
    }

    var activeSince: String {
        let e = Int(now.timeIntervalSince(item.createdAt) / 60)
        if e < 1 { return tr("drop.just_started") }
        if e < 60 { return tr("map.since_mins").replacingOccurrences(of: "{mins}", with: "\(e)") }
        let h = e / 60; let m = e % 60
        return m > 0
            ? tr("map.since_hm").replacingOccurrences(of: "{h}", with: "\(h)").replacingOccurrences(of: "{m}", with: "\(m)")
            : tr("map.since_h").replacingOccurrences(of: "{h}", with: "\(h)")
    }

    // Kompakter Header-Emoji: kleiner wenn Unterwegs-Personen da sind
    private var headerEmojiSize: CGFloat {
        onTheWay.count > 0 ? 160 : 220
    }

    @ViewBuilder
    private var activeDropBackground: some View {
        // Standard-Cream-Aurora wie Rest der App — kein dunkles Scrim,
        // kein Drop-Farben-Glow mehr. Alles einheitlich im dazu-Look.
        AppAuroraBackground()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandCream.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    v1LiveView
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                }
            }
        }
        .onAppear {
            calculateRoute()
            geocodeAddress()
            if isArrived { arrivedAnimated = true }
        }
        .onReceive(timer) { _ in now = Date() }
        .onChange(of: isArrived) { _, arrived in
            if arrived { withAnimation(.spring(response: 0.5)) { arrivedAnimated = true } }
        }
        .sheet(isPresented: $showCancelAlert) {
            EndDropSheet(
                activityEmoji: item.emoji,
                activityName: item.activity,
                participantCount: item.participants.count,
                elapsedSeconds: Date().timeIntervalSince(item.createdAt)
            ) {
                store.cancelDrop(id: item.id)
                showCancelAlert = false
            } onCancel: {
                showCancelAlert = false
            }
            // Sheet kompakter — vorher 0.82 (zu groß auf normalen
            // iPhones, viel Leerraum). 0.62 passt zum strafferen Layout.
            .presentationDetents([.fraction(0.62)])
            // Drop-Beenden-Warnung darf nicht versehentlich
            // weggewischt werden — User muss bewusst Beenden oder
            // Abbrechen tippen.
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
            .sheetBackground()
        }
        // In-App-Route-Sheet — wird vom Joiner-Navigation-Button und
        // vom Host-Banner getriggert. Zeigt eine MKMapView mit
        // Walking-Polyline statt Apple Maps zu öffnen.
        .sheet(isPresented: $showRouteSheet) {
            InAppRouteSheet(
                destination: item.coordinate,
                destinationName: item.locationTitle.isEmpty ? item.activity : item.locationTitle,
                accentColor: accentColor
            )
            .environmentObject(store)
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Shared Header + Card Helper

    @ViewBuilder
    private var dropHeader: some View {
        // ── Abgelaufen-Banner (Drop unsichtbar für neue User, aber noch aktiv) ──
        if isOwnDrop && item.isTimeExpired {
            HStack(spacing: 10) {
                DazuIcon("clock.badge.xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.brandViolet)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.brandLavender))
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("map.drop_no_longer_visible"))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.brandNight)
                    Text(tr("map.no_new_joiners"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.6))
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .liquidGlass(cornerRadius: 18)
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }

        // Rondesignlab-Headline: Status als Caps-Lead, dann großer Aktivitäts-
        // Name mit Emoji-Dot, darunter Live-Chip + Teilnehmer-Infos als Chips.
        VStack(alignment: .leading, spacing: 14) {
            Text((isOwnDrop ? tr("drop.my_drop_active") : (isArrived ? tr("drop.arrived") : tr("drop.on_the_way"))).uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.brandViolet.opacity(0.75))

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.activity)
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundColor(.brandNight)
                DazuActivityIcon(item.emoji, when: item.hasActivityEmoji)
                    .font(.system(size: 32))
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                // Live-seit-Chip
                HStack(spacing: 6) {
                    Circle().fill(Color.brandOrange).frame(width: 7, height: 7)
                    Text(activeSince)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.brandNight)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.brandLavender))

                // Teilnehmer-Chip
                let joined = isOwnDrop
                    ? item.participants.count
                    : max(1, confirmedHere.count + (isArrived ? 0 : 1))
                let maxP = item.maxParticipants
                HStack(spacing: 5) {
                    DazuIcon("person.2.fill").font(.system(size: 10, weight: .bold))
                    Text(tr("map.participants")
                        .replacingOccurrences(of: "{joined}", with: "\(joined)")
                        .replacingOccurrences(of: "{max}", with: "\(maxP)"))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    if joined >= maxP {
                        Text("· \(tr("map.full"))")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(.brandOrange)
                    }
                }
                .foregroundColor(.brandViolet)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.brandLavender))

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(14)
        .liquidGlass(cornerRadius: 20)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - Unterwegs-Ansicht

    @ViewBuilder
    private var onTheWayContent: some View {
        // Header
        dropHeader

        // Route-Info Card
        sectionCard {
            if isLoadingRoute {
                HStack(spacing: 10) {
                    DazuLoader().tint(.brand).scaleEffect(0.9)
                    Text(tr("map.calculating_route"))
                        .font(.system(size: 14)).foregroundColor(Color.textSecondary)
                }
            } else if let r = route {
                // Gehzeit kommt aus MKRoute (einmal berechnet, genauer weil
                // Gebäude-Umrundung), aber Distanz kommt LIVE aus dem GPS:
                // updated während man geht, nicht nur beim Tab-Switch.
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("map.walking_minutes").replacingOccurrences(of: "{mins}", with: "\(liveWalkMinutes ?? max(1, Int(r.expectedTravelTime / 60)))"))
                            .font(.system(size: 17, weight: .bold)).foregroundColor(Color.textPrimary)
                        Text({
                            let dist = liveDistanceMeters ?? r.distance
                            return dist < 1000
                                ? "\(Int(dist)) m entfernt"
                                : String(format: "%.1f km entfernt", dist / 1000)
                        }())
                            .font(.system(size: 13)).foregroundColor(Color.textSecondary)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.3), value: liveDistanceMeters)
                        if let addr = resolvedAddress {
                            HStack(spacing: 3) {
                                DazuIcon("mappin", accent: false).font(.system(size: 9)).foregroundColor(Color.textTertiary)
                                Text(addr).font(.system(size: 11)).foregroundColor(Color.textTertiary).lineLimit(1)
                            }
                        }
                    }
                    Spacer()
                    Button {
                        // In-App-Route statt Apple Maps öffnen — siehe
                        // .sheet(isPresented: $showRouteSheet) am body.
                        showRouteSheet = true
                    } label: {
                        Label { Text(tr("map.navigation")) } icon: { DazuIcon("arrow.triangle.turn.up.right.circle.fill") }
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(accentColor)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(accentColor.opacity(0.12), in: Capsule())
                    }
                    .dropsPressable()
                }
            }
        }

        // Host-Vorschau (immer sichtbar für den Joiner — damit man weiß zu wem man geht)
        sectionCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.brand.opacity(0.14)).frame(width: 44, height: 44)
                    DazuActivityIcon(item.emoji, when: item.hasActivityEmoji).font(.system(size: 22))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(item.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.textPrimary)
                        if let age = item.creatorAge {
                            Text("\(age)")
                                .font(.system(size: 15))
                                .foregroundColor(Color.textSecondary)
                        }
                    }
                    Text(tr("map.your_host"))
                        .font(.system(size: 11))
                        .foregroundColor(Color.textTertiary)
                }
                Spacer()
                DazuIcon("person.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Color.brand)
            }
        }

        // Gesperrte Teilnehmer-Vorschau
        sectionCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.textTertiary.opacity(0.18)).frame(width: 40, height: 40)
                    DazuIcon("lock.fill", accent: false)
                        .font(.system(size: 15)).foregroundColor(Color.textTertiary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("drop.details_locked"))
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(Color.textPrimary)
                    Text(tr("drop.arrive_for_unlock"))
                        .font(.system(size: 11)).foregroundColor(Color.textTertiary)
                }
                Spacer()
            }
            if !confirmedHere.isEmpty || !onTheWay.isEmpty {
                HStack(spacing: 16) {
                    if !confirmedHere.isEmpty {
                        Label { Text("\(confirmedHere.count) vor Ort") } icon: { DazuIcon("checkmark.circle.fill") }
                            .font(.system(size: 12, weight: .medium)).foregroundColor(.onlineGreen)
                    }
                    if !onTheWay.isEmpty {
                        HStack(spacing: 4) {
                            PulsingLiveDot()
                            Text(tr("map.on_the_way_count").replacingOccurrences(of: "{count}", with: "\(onTheWay.count)"))
                                .font(.system(size: 12, weight: .medium)).foregroundColor(Color.textTertiary)
                        }
                    }
                    Spacer()
                }
                .padding(.top, 10)
            }
        }

        VStack(spacing: 8) {
            extendButton
            leaveButton
        }
        .padding(.top, 16).padding(.bottom, 32)
    }

    // MARK: - Host-Unterwegs-Banner

    /// Banner für den Host, wenn er einen Drop an einem Pin-Ort erstellt
    /// hat und selbst noch nicht physisch dort ist (`isArrived == false`
    /// und `isOwnDrop`). Zeigt Distanz, Gehzeit und einen Maps-Button —
    /// damit man sofort sieht „aha, ich muss noch hin".
    @ViewBuilder
    private var hostOnTheWayBanner: some View {
        sectionCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentOrange.opacity(0.15))
                        .frame(width: 40, height: 40)
                    PulsingLiveDot()
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("map.you_on_the_way"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.textPrimary)
                    HStack(spacing: 6) {
                        if let dist = liveDistanceMeters {
                            Text(dist < 1000
                                 ? tr("map.meters_away").replacingOccurrences(of: "{meters}", with: "\(Int(dist))")
                                 : tr("map.km_away").replacingOccurrences(of: "{km}", with: String(format: "%.1f", dist / 1000)))
                                .font(.system(size: 12))
                                .foregroundColor(Color.textSecondary)
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.3), value: liveDistanceMeters)
                        }
                        if let mins = liveWalkMinutes {
                            Text("· ~\(mins) \(tr("map.min_short"))")
                                .font(.system(size: 12))
                                .foregroundColor(Color.textTertiary)
                        }
                    }
                }
                Spacer()
                Button {
                    // In-App-Route statt Apple Maps öffnen
                    showRouteSheet = true
                } label: {
                    DazuIcon("arrow.triangle.turn.up.right.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.accentOrange)
                }
                .dropsPressable()
            }
        }
    }

    // MARK: - V1 Live-View (neues dazu-Design)

    @ViewBuilder
    private var v1LiveView: some View {
        VStack(spacing: 14) {
            v1HeroCard
            // Spacer schafft klare Trennung zwischen Hero/Chips (gehört zur
            // Runde selbst) und der "Wer kommt"-Card (Teilnehmerliste). Sonst
            // kleben die zwei Blöcke zu dicht aufeinander.
            v1ParticipantsCard
                .padding(.top, 6)
            if isOwnDrop {
                v1HostActions
            } else {
                v1JoinerActions
            }
        }
        .sheet(isPresented: $showChangeLocationSheet) {
            v1ChangeLocationSheet
        }
    }

    // MARK: Hero-Card

    @ViewBuilder private var v1HeroCard: some View {
        VStack(spacing: 14) {
            // Activity + Icon oben zentriert — dazu-Asset-Icon statt Emoji-
            // Fallback (sonst taucht bei fehlendem Emoji ein Sparkle auf).
            VStack(spacing: 8) {
                DazuActivityIcon(item.emoji, when: item.hasActivityEmoji)
                    .font(.system(size: 40))
                    .frame(width: 56, height: 56)
                Text(item.activity)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.brandNight)
                    .multilineTextAlignment(.center)
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.brandViolet)
                    Text(resolvedAddress ?? item.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .padding(.top, 10)

            // Mini-Karten-Band — zeigt wo der Drop stattfindet. 108pt Höhe
            // = schlank, nimmt dem Progress-Ring nicht die Aufmerksamkeit.
            // Rechteck mit cornerRadius 16, Fill-Variante füllt die Breite.
            MiniMapSnapshotFill(coordinate: item.coordinate, metersSpan: 350)
                .frame(height: 108)
                .overlay(
                    Circle()
                        .fill(Color.brandOrange)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 20)

            // Progress-Ring mit Rest-Zeit
            v1ProgressRing
                .padding(.vertical, 4)

            // Meta-Chips (1/10, vor Ort, Entfernung …) — gehören zum
            // Hero-Block, damit die "Wer kommt"-Card darunter als klar
            // getrennter Teilnehmer-Bereich wirkt.
            v1MetaChips
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .liquidGlass(cornerRadius: 24)
    }

    // MARK: Progress Ring (Rest-Zeit)

    @ViewBuilder private var v1ProgressRing: some View {
        let startRef = item.startsAt
        let endRef = item.expiresAt
        let total = max(endRef.timeIntervalSince(startRef), 60)
        let elapsed = max(0, now.timeIntervalSince(startRef))
        let progress = min(1.0, elapsed / total)
        let remaining = max(0, endRef.timeIntervalSince(now))
        let remainingLabel: String = {
            if remaining <= 0 { return "zu Ende" }
            let m = Int(remaining / 60)
            if m < 60 { return "\(m) Min" }
            let h = m / 60
            let mm = m % 60
            return mm == 0 ? "\(h) Std" : "\(h) Std \(mm) Min"
        }()
        ZStack {
            Circle()
                .stroke(Color.brandLavender, lineWidth: 10)
                .frame(width: 140, height: 140)
            Circle()
                .trim(from: 0, to: 1.0 - progress)
                .stroke(Color.brandOrangeFixed,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 140, height: 140)
                .animation(.linear(duration: 1), value: progress)
            VStack(spacing: 2) {
                Text(tr("live.still_remaining"))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.5))
                Text(remainingLabel)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.brandNight)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    // MARK: Meta Chips Row

    @ViewBuilder private var v1MetaChips: some View {
        HStack(spacing: 8) {
            v1MetaChip(icon: "person.2.fill",
                       text: "\(item.participants.count)/\(item.maxParticipants)")
            if let dist = liveDistanceMeters, !isOwnDrop {
                let kmLabel = dist >= 1000
                    ? String(format: "%.1f km", dist / 1000)
                    : "\(Int(dist)) m"
                v1MetaChip(icon: "figure.walk", text: kmLabel)
            }
            if let eta = liveWalkMinutes, !isOwnDrop {
                v1MetaChip(icon: "clock.fill", text: "~\(eta) Min")
            }
            if isArrived {
                v1MetaChip(icon: "checkmark.circle.fill", text: "vor Ort", tint: .onlineGreen)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func v1MetaChip(icon: String, text: String, tint: Color = .brandViolet) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text).font(.system(size: 12, weight: .heavy, design: .rounded))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.15)))
    }

    // MARK: Teilnehmer-Card mit ETA

    @ViewBuilder private var v1ParticipantsCard: some View {
        // Für Demo-Live-Drops (fehlende item.participants) nutzen wir die
        // live aus `dropins/{fbid}` geladenen Pseudo-Participants.
        let all = item.participants.isEmpty ? demoJoiners : item.participants
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.brandViolet)
                Text(tr("live.who_coming"))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(.brandNight)
                Spacer()
            }
            if all.isEmpty {
                Text(tr("live.alone_waiting"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(all, id: \.id) { p in
                        v1ParticipantRow(p)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .liquidGlass(cornerRadius: 20)
        .onAppear { fetchDemoJoinersIfNeeded() }
    }

    /// Lädt die Dropins für den aktuellen (Demo-)Drop und baut sie als
    /// Pseudo-DropParticipants. Nur für Demo-Live-Drops. Nutzt observe(.value)
    /// damit neue Mock-Joiner (asynchron von seedLiveDemoDrops geschrieben)
    /// automatisch nachrutschen — vorher sah der User nur sich selbst.
    private func fetchDemoJoinersIfNeeded() {
        guard let fbid = item.firebaseDropID,
              fbid.hasPrefix("demolive_") else { return }
        Database.database().reference()
            .child("dropins").child(fbid)
            .observe(.value) { snap in
                var list: [DropParticipant] = []
                for case let child as DataSnapshot in snap.children {
                    guard let dict = child.value as? [String: Any] else { continue }
                    var p = DropParticipant(
                        name: dict["name"] as? String ?? "?",
                        emoji: dict["emoji"] as? String ?? "",
                        reliabilityScore: dict["reliabilityPoints"] as? Int ?? 85,
                        reliabilityCommits: 0
                    )
                    p.age = dict["age"] as? Int
                    p.profileImageURL = dict["profileImageURL"] as? String
                    list.append(p)
                }
                DispatchQueue.main.async { self.demoJoiners = list }
            }
    }

    @ViewBuilder
    private func v1ParticipantRow(_ p: DropParticipant) -> some View {
        let isSelf = p.token == myToken
        let isHere = confirmedHere.contains(where: { $0.token == p.token })
        HStack(spacing: 12) {
            // Avatar
            Group {
                if let url = p.profileImageURL, !url.isEmpty {
                    RemoteProfileImage(url: url, fallbackEmoji: p.emoji,
                                       size: 40, strokeColor: .clear)
                } else {
                    ZStack {
                        Circle().fill(Color.brandLavender).frame(width: 40, height: 40)
                        DazuProfileIcon(size: 24)
                    }
                }
            }
            .overlay(Circle().stroke(isHere ? Color.onlineGreen : Color.brandLavender, lineWidth: 2))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(isSelf ? "Du" : (p.name.isEmpty ? "Teilnehmer" : p.name))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.brandNight)
                        .lineLimit(1)
                    if p.token == "__host__" || (isSelf && isOwnDrop) {
                        Text("· Host")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.brandOrange)
                    }
                }
                Text(isHere ? "vor Ort" : "unterwegs")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(isHere ? .onlineGreen : .brandNight.opacity(0.5))
            }
            Spacer()
            // Status-Dot
            Circle()
                .fill(isHere ? Color.onlineGreen : Color.brandOrange)
                .frame(width: 10, height: 10)
        }
    }

    // MARK: Host Actions

    @ViewBuilder private var v1HostActions: some View {
        VStack(spacing: 10) {
            Button {
                showChangeLocationSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 14, weight: .bold))
                    Text(tr("live.change_location"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundColor(.brandViolet)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Capsule().fill(Color.brandLavender))
            }
            .dropsPressable()

            Button {
                showExtendSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 14, weight: .bold))
                    Text(tr("live.extend"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundColor(.brandViolet)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Capsule().fill(Color.brandLavender))
            }
            .dropsPressable()

            Button {
                showCancelAlert = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(tr("live.end_round"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Capsule().fill(Color.accentRed))
            }
            .dropsPressable()
        }
    }

    // MARK: Joiner Actions

    @ViewBuilder private var v1JoinerActions: some View {
        VStack(spacing: 10) {
            Button {
                showRouteSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(tr("live.open_route"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Capsule().fill(Color.brandVioletFixed))
            }
            .dropsPressable()

            Button {
                showLeaveConfirm = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(tr("live.leave_round"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundColor(.accentRed)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Capsule().fill(Color.accentRed.opacity(0.12)))
            }
            .dropsPressable()
        }
    }

    // MARK: Change Location Sheet

    @ViewBuilder private var v1ChangeLocationSheet: some View {
        NavigationStack {
            ZStack {
                Color.brandCream.ignoresSafeArea()
                VStack(spacing: 12) {
                    Text(tr("live.new_meetup_pin"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.brandNight)
                        .padding(.top, 14)
                    Text(tr("live.long_press_hint"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    // Interaktive Karte mit tap-to-pin.
                    v1PinPickerMap
                        .frame(height: 320)
                        .cornerRadius(18)
                        .padding(.horizontal, 16)

                    if let coord = pendingNewCoord {
                        Text(String(format: "Pin: %.4f, %.4f", coord.latitude, coord.longitude))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.6))
                            .monospacedDigit()
                    }

                    Button {
                        let coord = pendingNewCoord ?? locationManager.userLocation
                        if let coord = coord { applyNewHostLocation(coord) }
                    } label: {
                        Text(pendingNewCoord == nil
                             ? "Aktuelle Position verwenden"
                             : "Hier treffen & alle informieren")
                            .dropsPrimaryButton()
                    }
                    .dropsPressable()
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    Button {
                        showChangeLocationSheet = false
                        pendingNewCoord = nil
                    } label: {
                        Text(tr("common.cancel"))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.55))
                            .padding(.vertical, 6)
                    }
                    .padding(.bottom, 18)
                }
            }
            .presentationDetents([.large])
        }
    }

    /// Interaktive MKMapView mit Long-Press-Pin-Picker. Setzt
    /// `pendingNewCoord` beim Long-Press. Zeigt den aktuellen Drop-Pin
    /// orange und den neuen Pin violett.
    @ViewBuilder private var v1PinPickerMap: some View {
        PinPickerMap(
            initialCenter: item.coordinate,
            existingPin: item.coordinate,
            selectedCoord: $pendingNewCoord
        )
    }

    /// Schreibt die neue Host-Koordinate nach Firebase und sendet Push an alle
    /// Joiner. Lokaler Toast bestätigt die Änderung.
    private func applyNewHostLocation(_ coord: CLLocationCoordinate2D) {
        let dropID = item.id.uuidString
        RealtimeDBManager.shared.updateDropLocation(dropID: dropID, coord: coord)
        // Push an alle Joiner — nutzt die bestehende Push-API falls vorhanden,
        // sonst nur lokaler Toast. Lokaler Toast immer.
        store.showInfoToast("Neuer Treffpunkt gesetzt. Alle werden informiert.",
                            icon: "mappin.and.ellipse")
        showChangeLocationSheet = false
    }

    // MARK: - Vor-Ort-Ansicht (freigeschaltet)

    @ViewBuilder
    private var arrivedContent: some View {
        VStack(spacing: 0) {
            dropHeader

            // Host ist physisch noch nicht am Drop (Pin-Drop fern vom
            // aktuellen Standort) — prominent zeigen „du bist unterwegs"
            // mit Distanz + Apple-Maps-Button. Sobald er ≤ 20 m ist,
            // schaltet `isArrived` um und dieser Banner verschwindet.
            if isOwnDrop && !isArrived {
                hostOnTheWayBanner
            }

            if isOwnDrop {
                // ── Standort + Beschreibung ───────────────────────────
                locationDescriptionCard

                // ── Plätze-Balken ─────────────────────────────────────
                spotsCard

                // ── „Wer hat deinen Drop gesehen" (Drops+ Feature) ─────
                dropViewersCard

                // ── Einladungslink (immer sichtbar) ───────────────────
                shareButtonCard

                // ── Vor Ort ───────────────────────────────────────────
                if !confirmedHere.isEmpty {
                    sectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label { Text(tr("drop.arrived")) } icon: { DazuIcon("checkmark.circle.fill") }
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(.onlineGreen)
                                Spacer()
                                Text("\(confirmedHere.count) Person\(confirmedHere.count == 1 ? "" : "en")")
                                    .font(.system(size: 11)).foregroundColor(Color.textTertiary)
                            }
                            ForEach(confirmedHere) { p in
                                ParticipantDetailRow(participant: p, isArrived: true,
                                                    dropCoordinate: item.coordinate,
                                                    onTapProfile: { selectedProfileParticipant = $0 })
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .opacity))
                            }
                        }
                    }
                    .animation(.spring(response: 0.45), value: confirmedHere.count)
                }

                // ── Unterwegs ─────────────────────────────────────────
                if !onTheWay.isEmpty {
                    sectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                PulsingLiveDot()
                                Text(tr("drop.on_the_way"))
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(Color.textSecondary)
                                Text("· \(tr("map.live"))").font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color.auroraBlue)
                                Spacer()
                                Text("\(onTheWay.count) Person\(onTheWay.count == 1 ? "" : "en")")
                                    .font(.system(size: 11)).foregroundColor(Color.textTertiary)
                            }
                            ForEach(onTheWay) { p in
                                ParticipantDetailRow(participant: p, isArrived: false,
                                                    dropCoordinate: item.coordinate,
                                                    onTapProfile: { selectedProfileParticipant = $0 })
                            }
                        }
                    }
                }

                // ── Restzeit-Balken ───────────────────────────────────
                if item.durationMinutes > 0 { timeBarCard }

                // ── Verlängern + Beenden ──────────────────────────────
                VStack(spacing: 8) {
                    extendButton
                    leaveButton
                }
                .padding(.top, 12).padding(.bottom, 32)

            } else {
                // Joiner-Ansicht (vor Ort, nicht eigener Drop)
                inviteCard

                if !confirmedHere.isEmpty {
                    sectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label { Text(tr("drop.arrived")) } icon: { DazuIcon("checkmark.circle.fill") }
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(.onlineGreen)
                                Spacer()
                                Text("\(confirmedHere.count) Person\(confirmedHere.count == 1 ? "" : "en")")
                                    .font(.system(size: 11)).foregroundColor(Color.textTertiary)
                            }
                            ForEach(confirmedHere) { p in
                                ParticipantDetailRow(participant: p, isArrived: true,
                                                    dropCoordinate: item.coordinate,
                                                    onTapProfile: { selectedProfileParticipant = $0 })
                            }
                        }
                    }
                }

                if !onTheWay.isEmpty {
                    sectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                PulsingLiveDot()
                                Text(tr("drop.on_the_way"))
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(Color.textSecondary)
                                Spacer()
                            }
                            ForEach(onTheWay) { p in
                                ParticipantDetailRow(participant: p, isArrived: false,
                                                    dropCoordinate: item.coordinate,
                                                    onTapProfile: { selectedProfileParticipant = $0 })
                            }
                        }
                    }
                }

                VStack(spacing: 8) {
                    extendButton
                    leaveButton
                }
                .padding(.top, 16).padding(.bottom, 32)
            }
        }
    }

    // MARK: - Standort + Beschreibung

    @ViewBuilder
    private var locationDescriptionCard: some View {
        let address = resolvedAddress ?? (item.locationTitle.isEmpty ? nil : item.locationTitle)
        let hasDesc = ((item.dropDescription?.isEmpty) == nil)
        if address != nil || hasDesc {
            sectionCard {
                VStack(alignment: .leading, spacing: hasDesc && address != nil ? 10 : 0) {
                    if let addr = address {
                        HStack(spacing: 6) {
                            DazuIcon("mappin.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(accentColor)
                            Text(addr)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.textPrimary)
                                .lineLimit(2)
                            Spacer()
                        }
                    }
                    if hasDesc {
                        if address != nil {
                            Divider().opacity(0.4)
                        }
                        Text(item.dropDescription ?? "")
                            .font(.system(size: 13))
                            .foregroundColor(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Plätze-Balken

    private var spotsCard: some View {
        let used  = item.participants.count
        let total = max(1, item.maxParticipants)
        let free  = max(0, total - used)
        let ratio = Double(used) / Double(total)
        return sectionCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        DazuIcon("person.2.fill", accent: false)
                            .font(.system(size: 11)).foregroundColor(Color.textTertiary)
                        Text(tr("map.x_of_y_participants").replacingOccurrences(of: "{used}", with: "\(used)").replacingOccurrences(of: "{total}", with: "\(total)"))
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(Color.textPrimary)
                    }
                    Spacer()
                    Text(free == 0 ? tr("map.full_red") : (free == 1 ? tr("map.spots_free_singular") : tr("map.spots_free_plural")).replacingOccurrences(of: "{count}", with: "\(free)"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(free == 0 ? .accentOrange : .onlineGreen)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(free == 0 ? Color.accentOrange : accentColor)
                            .frame(width: geo.size.width * ratio, height: 6)
                            .animation(.spring(response: 0.5), value: used)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - „Wer hat deinen Drop gesehen" — Drops+ Feature

    /// Zeigt die Anzahl der Viewer. Free-User sehen nur die Zahl + CTA zur Paywall.
    /// Drops+ Mitglieder sehen zusätzlich Avatare + Namen.
    @ViewBuilder
    private var dropViewersCard: some View {
        // "Wer hat geschaut" ist eine Drops+ Feature → für den Launch komplett aus.
        let viewers = FeatureFlags.dropsPlusEnabled
            ? (store.dropViewersByDropID[item.id.uuidString] ?? [])
            : []
        if !viewers.isEmpty {
            sectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        DazuIcon("eye.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color.auroraAmber)
                        Text("\(viewers.count) \(viewers.count == 1 ? "Person hat" : "Personen haben") geschaut")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color.textPrimary)
                        Spacer()
                        if !store.isDropsPlusActive {
                            DazuIcon("lock.fill", accent: false)
                                .font(.system(size: 10))
                                .foregroundColor(Color.textTertiary)
                        }
                    }

                    if store.isDropsPlusActive {
                        // Plus: Avatare + Namen
                        VStack(spacing: 8) {
                            ForEach(viewers.prefix(8)) { viewer in
                                HStack(spacing: 10) {
                                    RemoteProfileImage(
                                        url: viewer.profileImageURL,
                                        fallbackEmoji: viewer.emoji,
                                        size: 34,
                                        strokeColor: Color.white.opacity(0.12)
                                    )
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 4) {
                                            Text(viewer.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(Color.textPrimary)
                                            if let age = viewer.age {
                                                Text(", \(age)")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(Color.textSecondary)
                                            }
                                        }
                                        Text(relativeTimeLabel(viewer.viewedAt))
                                            .font(.system(size: 11))
                                            .foregroundColor(Color.textTertiary)
                                    }
                                    Spacer()
                                }
                            }
                            if viewers.count > 8 {
                                Text(tr("map.more_count").replacingOccurrences(of: "{count}", with: "\(viewers.count - 8)"))
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.textTertiary)
                            }
                        }
                    } else {
                        // Free: verschwommene Avatare + Upgrade-Prompt
                        HStack(spacing: -10) {
                            ForEach(viewers.prefix(5)) { viewer in
                                RemoteProfileImage(
                                    url: viewer.profileImageURL,
                                    fallbackEmoji: viewer.emoji,
                                    size: 36,
                                    strokeColor: Color.white.opacity(0.15)
                                )
                                .blur(radius: 6)
                                .overlay(Circle().fill(Color.black.opacity(0.12)))
                            }
                            Spacer()
                        }
                        .frame(height: 40)

                        Button {
                            store.showDropsPlusPaywall = true
                        } label: {
                            HStack(spacing: 6) {
                                DazuIcon("bolt.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(tr("map.unlock_with_plus"))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [Color.auroraAmber, Color.auroraAmber],
                                    startPoint: .leading, endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: Radius.md)
                            )
                        }
                        .dropsPressable()
                    }
                }
            }
        }
    }

    private func relativeTimeLabel(_ date: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(date))
        if elapsed < 60 { return tr("map.just_now") }
        if elapsed < 3600 { return tr("map.ago_mins").replacingOccurrences(of: "{mins}", with: "\(elapsed / 60)") }
        if elapsed < 86400 { return tr("map.ago_hours").replacingOccurrences(of: "{hours}", with: "\(elapsed / 3600)") }
        return tr("map.ago_days").replacingOccurrences(of: "{days}", with: "\(elapsed / 86400)")
    }

    // MARK: - Einladungs-Button (immer sichtbar)

    private var shareButtonCard: some View {
        sectionCard {
            Button { showShareSheet = true } label: {
                HStack(spacing: 10) {
                    DazuIcon("square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                    Text(tr("map.invite_friends"))
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    DazuIcon("chevron.right")
                        .font(.system(size: 12)).opacity(0.4)
                }
                .foregroundColor(accentColor)
            }
            .dropsPressable()
        }
        .sheet(isPresented: $showShareSheet) {
            // Wichtig: www-Subdomain nutzen weil drops-app.de → www.drops-app.de
            // mit 307 redirected wird. Apple Universal Links akzeptieren keine
            // Redirects — der Link würde sonst im Browser statt in der App
            // öffnen. Beide Hosts sind in den Entitlements als applinks
            // registriert, also gleich autoritativ.
            let dropLink = URL(string: AppLinks.dropShareURL(dropID: item.id.uuidString))!
            let location = item.locationTitle.isEmpty ? "" : " · \(item.locationTitle)"
            let subject = "\(item.activity)\(location) — komm vorbei."
            ShareSheet(items: [dropLink], subject: subject)
        }
    }

    // MARK: - Restzeit-Balken

    private var timeBarCard: some View {
        let total   = Double(item.durationMinutes) * 60
        let elapsed = now.timeIntervalSince(item.createdAt)
        let ratio   = min(1, max(0, elapsed / total))
        return sectionCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        DazuIcon("clock")
                            .font(.system(size: 11)).foregroundColor(Color.textTertiary)
                        Text(tr("map.time_left"))
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(Color.textPrimary)
                    }
                    Spacer()
                    Text(item.timeRemainingString)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ratio > 0.85 ? .accentOrange : Color.textSecondary)
                        .contentTransition(.numericText())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(ratio > 0.85 ? Color.accentOrange : accentColor)
                            .frame(width: geo.size.width * ratio, height: 6)
                            .animation(.linear(duration: 1), value: ratio)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - Invite Card (Joiner-Ansicht, oder wenn keine Teilnehmer)

    @ViewBuilder
    private var inviteCard: some View {
        if item.participants.count <= 1 {
            sectionCard {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(accentColor.opacity(0.18)).frame(width: 40, height: 40)
                        DazuIcon("person.wave.2.fill")
                            .font(.system(size: 17)).foregroundColor(accentColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("drop.waiting_title"))
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(Color.textPrimary)
                        Text(tr("drop.waiting_description"))
                            .font(.system(size: 11)).foregroundColor(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Extend Button (nur Host)

    /// Verbleibende Cooldown-Sekunden nach dem letzten Verlängern (nil = bereit).
    /// Drops+ Bypass ist als Feature angekündigt aber noch nicht aktiv.
    private var extendCooldownRemaining: Int? {
        guard let last = lastExtendedAt, lastExtendCooldownSecs > 0 else { return nil }
        let elapsed = Int(now.timeIntervalSince(last))
        let remaining = lastExtendCooldownSecs - elapsed
        return remaining > 0 ? remaining : nil
    }

    private func formatCooldown(_ secs: Int) -> String {
        if secs < 60 { return tr("map.cooldown_s").replacingOccurrences(of: "{s}", with: "\(secs)") }
        let m = secs / 60
        let s = secs % 60
        return s > 0
            ? tr("map.cooldown_ms").replacingOccurrences(of: "{m}", with: "\(m)").replacingOccurrences(of: "{s}", with: "\(s)")
            : tr("map.cooldown_m").replacingOccurrences(of: "{m}", with: "\(m)")
    }

    @ViewBuilder
    private var extendButton: some View {
        if isOwnDrop && item.durationMinutes > 0 {
            let onCooldown = extendCooldownRemaining != nil
            Button {
                guard !onCooldown else { return }
                showExtendSheet = true
            } label: {
                HStack(spacing: 7) {
                    DazuIcon(onCooldown ? "clock" : "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .bold))
                    if let secs = extendCooldownRemaining {
                        Text(tr("map.extend_cooldown").replacingOccurrences(of: "{time}", with: formatCooldown(secs)))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                    } else {
                        Text(tr("map.extend"))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                }
                .foregroundColor(onCooldown ? .brandNight.opacity(0.4) : .brandViolet)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.brandLavender.opacity(onCooldown ? 0.45 : 0.9)))
            }
            .dropsPressable()
            .disabled(onCooldown)
            .padding(.horizontal, 18)
            .sheet(isPresented: $showExtendSheet) {
                ExtendDropSheet(dropID: item.id, onExtended: { chosenMinutes in
                    lastExtendedAt = Date()
                    lastExtendCooldownSecs = (chosenMinutes / 2) * 60
                })
                .environmentObject(store)
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Shared Leave Button

    private var leaveButton: some View {
        VStack(spacing: 0) {
            Button {
                if isOwnDrop { showCancelAlert = true }
                else { showLeaveConfirm = true }
            } label: {
                HStack(spacing: 8) {
                    DazuIcon(isOwnDrop ? "flag.checkered" : "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14, weight: .bold))
                    Text(isOwnDrop ? tr("drop.end_drop") : tr("drop.leave_drop"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundColor(.brandNight.opacity(0.65))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.brandLavender.opacity(0.5)))
            }
            .dropsPressable()
            .padding(.horizontal, 18)

            // Info: wann der Drop automatisch endet (nur bei gesetzter Dauer)
            if item.durationMinutes > 0 && !item.timeRemainingString.isEmpty {
                HStack(spacing: 4) {
                    DazuIcon("clock").font(.system(size: 10, weight: .bold))
                    Text(item.timeRemainingString)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.brandNight.opacity(0.5))
                .padding(.top, 6)
            }
        }
        .sheet(isPresented: $showLeaveConfirm) {
            // Elapsed seconds aus dem joinRequest des Stores — bei pending
            // Requests = 0 (kein Score-Risiko), bei akzeptierten 12+ min
            // löst die Score-Warnung aus.
            let elapsed: TimeInterval = {
                if let req = store.joinRequests.first(where: { $0.dropID == item.id }) {
                    return Date().timeIntervalSince(req.createdAt)
                }
                return 0
            }()
            LeaveDropSheet(
                activityEmoji: item.emoji,
                activityName: item.activity,
                elapsedSeconds: elapsed
            ) {
                store.leaveDropJoin(dropID: item.id)
                showLeaveConfirm = false
            } onCancel: {
                showLeaveConfirm = false
            }
            .presentationDetents([.fraction(0.65)])
            // Verlassen-Warnung darf nicht versehentlich weggewischt
            // werden — User muss bewusst Verlassen oder Abbrechen tippen.
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
            .sheetBackground()
        }
        // ── MiniProfile für Teilnehmer — im Parent damit Firebase-Updates
        // den @State in ParticipantDetailRow nicht resetten.
        .sheet(item: $selectedProfileParticipant) { p in
            let agePart = p.age.map { ", \($0)" } ?? ""
            let subtitle = p.statusMessage.isEmpty
                ? "\(tr("map.drops_user"))\(agePart)"
                : "\(p.statusMessage)\(agePart)"
            MiniProfileSheet(
                name: p.name,
                emoji: p.emoji,
                selfie: p.selfie,
                profileImageURL: p.profileImageURL,
                reliabilityScore: p.reliabilityScore,
                totalCommits: p.reliabilityCommits,
                subtitle: subtitle,
                accentColor: ReliabilityScore.color(forPoints: p.reliabilityScore),
                userUID: p.firebaseUID,
                canBlock: true,
                onBlock: {}
            )
            .environmentObject(store)
            .presentationDetents([.fraction(0.5)])
        }
    }

    // MARK: - Helpers

    private func geocodeAddress() {
        let loc = CLLocation(latitude: item.coordinate.latitude, longitude: item.coordinate.longitude)
        CLGeocoder().reverseGeocodeLocation(loc) { placemarks, _ in
            guard let p = placemarks?.first else { return }
            let street = [p.thoroughfare, p.subThoroughfare].compactMap { $0 }.joined(separator: " ")
            DispatchQueue.main.async {
                resolvedAddress = [street, p.locality].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            }
        }
    }

    private func calculateRoute() {
        let req = MKDirections.Request()
        req.source      = MKMapItem(placemark: MKPlacemark(coordinate: store.currentUser.coordinate))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: item.coordinate))
        req.transportType = .walking
        MKDirections(request: req).calculate { response, _ in
            DispatchQueue.main.async {
                isLoadingRoute = false
                route = response?.routes.first
            }
        }
    }
}

// MARK: - Participant Detail Row

struct ParticipantDetailRow: View {
    let participant: DropParticipant
    let isArrived: Bool
    /// Standort des Drops — für die Live-Karte der unterwegs-Person
    let dropCoordinate: CLLocationCoordinate2D
    /// Callback zum Parent — Sheet wird dort verwaltet, damit Firebase-Updates
    /// den @State nicht zurücksetzen und das Sheet nicht schließen.
    var onTapProfile: ((DropParticipant) -> Void)? = nil
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var colorScheme
    @State private var showLiveLocation = false

    private var avatarBg: Color { colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06) }
    private var avatarStroke: Color { colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.10) }

    // MARK: Helpers

    /// Direkte Display-Werte aus der echten Punktzahl. Frühere Rekonstruktion
    /// via showUps führte bei Punkten >100 dazu, dass `displayText` falsche
    /// Werte zeigte und die Progress-Bar überlief (Strikethrough-Effekt).
    private var displayPoints: Int { participant.reliabilityScore }
    private var displayColor: Color  { ReliabilityScore.color(forPoints: displayPoints) }
    private var displayBadge: String { ReliabilityScore.badge(forPoints: displayPoints) }
    private var displayBadgeIcon: String { ReliabilityScore.badgeIcon(forPoints: displayPoints) }
    /// Bar-Füllung: Fortschritt innerhalb des aktuellen Tiers (0–1).
    private var displayBarFill: Double {
        ReliabilityScore.tierProgress(forPoints: displayPoints)
    }

    /// Beta-Badge nur wenn der Teilnehmer der eigene User ist (für andere
    /// Teilnehmer ist `createdAt` aktuell nicht im DropParticipant-Schema
    /// propagiert). Vergleich über firebaseUID, Fallback Name.
    private var participantQualifiesForBetaBadge: Bool {
        let myUID = FirebaseAuth.Auth.auth().currentUser?.uid
        let isMe = (participant.firebaseUID != nil && participant.firebaseUID == myUID)
            || (participant.firebaseUID == nil && participant.name == store.currentUser.name)
        guard isMe else { return false }
        return store.qualifiesForBetaBadge
    }

    /// Gehgeschwindigkeit ~5 km/h = 83 m/min
    private var etaMinutes: Int? {
        guard let dist = participant.simulatedDistance else { return nil }
        return max(1, Int(dist / 83.0))
    }

    private var etaClockString: String? {
        guard let mins = etaMinutes,
              let arrival = Calendar.current.date(byAdding: .minute, value: mins, to: Date())
        else { return nil }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: arrival)
    }

    private var distanceLabel: String? {
        guard let dist = participant.simulatedDistance else { return nil }
        return dist < 1000
            ? "~\(Int(dist)) m"
            : String(format: "~%.1f km", dist / 1000)
    }

    private var nameLabel: String {
        if let age = participant.age { return "\(participant.name), \(age)" }
        return participant.name
    }

    // MARK: Body

    var body: some View {
        Button {
            if !isArrived && participant.liveCoordinate != nil {
                showLiveLocation = true
            } else {
                onTapProfile?(participant)
            }
        } label: {
            if isArrived {
                // ── Vor Ort: volle Darstellung ────────────────────────
                HStack(spacing: 13) {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let img = participant.selfie {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 50, height: 50).clipShape(Circle())
                            } else {
                                RemoteProfileImage(
                                    url: participant.profileImageURL,
                                    fallbackEmoji: participant.emoji,
                                    size: 50,
                                    strokeColor: Color.onlineGreen.opacity(0.55)
                                )
                            }
                        }
                        .overlay(Circle().stroke(Color.onlineGreen.opacity(0.55), lineWidth: 2))

                        Circle().fill(Color.onlineGreen).frame(width: 17, height: 17)
                            .overlay(DazuIcon("checkmark")
                                .font(.system(size: 8, weight: .bold)).foregroundColor(.white))
                            .offset(x: 2, y: 2)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(nameLabel)
                                .font(.system(size: 14, weight: .semibold)).foregroundColor(Color.textPrimary).lineLimit(1)
                            if participantQualifiesForBetaBadge {
                                BetaBadge()
                            }
                        }
                        // Trust-Badge nur anzeigen wenn verlässlich.
                        if ReliabilityScore.isTrusted(forPoints: displayPoints) {
                            HStack(spacing: 4) {
                                DazuIcon("checkmark.seal.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.brandViolet)
                                Text(tr("tier.trusted"))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.brandViolet)
                            }
                        }
                    }

                    Spacer(minLength: 6)
                    HStack(spacing: 3) {
                        Circle().fill(Color.onlineGreen).frame(width: 5, height: 5)
                        Text(tr("drop.arrived")).font(.system(size: 11, weight: .semibold)).foregroundColor(.onlineGreen)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.bgSecondary))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.onlineGreen.opacity(0.30), lineWidth: 1))

            } else {
                // ── Unterwegs: kompakte einzeilige Darstellung ────────
                HStack(spacing: 10) {
                    // Kleiner Avatar
                    Group {
                        if let img = participant.selfie {
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(width: 36, height: 36).clipShape(Circle())
                        } else if participant.profileImageURL != nil {
                            RemoteProfileImage(
                                url: participant.profileImageURL,
                                fallbackEmoji: participant.emoji,
                                size: 36,
                                strokeColor: Color.clear
                            )
                        } else {
                            ZStack {
                                Circle().fill(avatarBg)
                                DazuPersonIcon().font(.system(size: 16))
                            }
                        }
                    }
                    .frame(width: 36, height: 36).clipShape(Circle())
                    .overlay(Circle().stroke(avatarStroke, lineWidth: 1))
                    .opacity(0.8)

                    // Name
                    Text(nameLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    // Distanz + ETA kompakt
                    HStack(spacing: 6) {
                        if let dist = distanceLabel {
                            HStack(spacing: 3) {
                                DazuIcon("figure.walk").font(.system(size: 9, weight: .medium))
                                Text(dist).font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Color.textSecondary)
                        }
                        if let mins = etaMinutes {
                            HStack(spacing: 3) {
                                DazuIcon("clock").font(.system(size: 9))
                                Text(tr("map.walk_minutes").replacingOccurrences(of: "{mins}", with: "\(mins)")).font(.system(size: 11))
                            }
                            .foregroundColor(Color.textSecondary)
                        } else if distanceLabel == nil {
                            Text(tr("drop.on_the_way")).font(.system(size: 11)).foregroundColor(Color.textSecondary)
                        }
                    }

                    DazuIcon("chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color.textSecondary.opacity(0.5))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: Radius.md).fill(Color.bgSecondary))
            }
        }
        .dropsPressable()
        // Live-Standort-Sheet für Unterwegs-Personen
        .sheet(isPresented: $showLiveLocation) {
            ParticipantLiveLocationSheet(
                participant: participant,
                dropCoordinate: dropCoordinate
            )
            .presentationDetents([.height(480)])
            .presentationDragIndicator(.hidden)
        }
    }
}

// MARK: - Participant Live Location Sheet

struct ParticipantLiveLocationSheet: View {
    @AppStorage("appLanguage") private var appLanguage = "de"
    let participant: DropParticipant
    let dropCoordinate: CLLocationCoordinate2D
    @Environment(\.dismiss) private var dismiss

    @State private var route: MKRoute? = nil
    @State private var targetRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48.1371, longitude: 11.5754),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )

    private var liveCoord: CLLocationCoordinate2D {
        participant.liveCoordinate ?? dropCoordinate
    }

    private var etaMinutes: Int? {
        guard let dist = participant.simulatedDistance else { return nil }
        return max(1, Int(dist / 83.0))
    }

    private var etaClockString: String? {
        guard let mins = etaMinutes,
              let arrival = Calendar.current.date(byAdding: .minute, value: mins, to: Date())
        else { return nil }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: arrival)
    }

    private var distanceLabel: String? {
        guard let dist = participant.simulatedDistance else { return nil }
        return dist < 1000 ? "~\(Int(dist)) m" : String(format: "~%.1f km", dist / 1000)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Handle ────────────────────────────────────────────────
            Capsule().fill(Color(UIColor.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 10).padding(.bottom, 16)

            // ── Header ────────────────────────────────────────────────
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.brandLavender)
                        .frame(width: 46, height: 46)
                    DazuPersonIcon().font(.system(size: 22))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(participant.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.textPrimary)
                        if let age = participant.age {
                            Text("\(age)")
                                .font(.system(size: 13))
                                .foregroundColor(.textTertiary)
                        }
                    }
                    Label { Text(tr("drop.heading_to_drop")) } icon: { DazuIcon("figure.walk") }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.brand)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    DazuIcon("xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(UIColor.systemGray3))
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 14)

            // ── Karte ─────────────────────────────────────────────────
            ZStack(alignment: .bottom) {
                Map(initialPosition: .region(fitRegion(from: liveCoord, to: dropCoordinate))) {
                    ForEach(mapAnnotations) { ann in
                        Annotation("", coordinate: ann.coordinate) {
                            if ann.isPersonPin {
                                // Joiner-Pin
                                ZStack {
                                    Circle()
                                        .fill(Color.brand.opacity(0.18))
                                        .frame(width: 44, height: 44)
                                    Circle()
                                        .stroke(Color.brand.opacity(0.6), lineWidth: 2)
                                        .frame(width: 44, height: 44)
                                    DazuPersonIcon()
                                        .font(.system(size: 20))
                                }
                                .shadow(color: Color.brand.opacity(0.4), radius: 8)
                            } else {
                                // Drop-Pin
                                ZStack {
                                    Circle()
                                        .fill(Color.accentOrange.opacity(0.18))
                                        .frame(width: 34, height: 34)
                                    Circle()
                                        .stroke(Color.accentOrange.opacity(0.6), lineWidth: 2)
                                        .frame(width: 34, height: 34)
                                    DazuIcon("mappin.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.accentOrange)
                                }
                            }
                        }
                    }
                }
                .frame(height: 240)
                .cornerRadius(20)
                .padding(.horizontal, 16)

                // Distanz-Overlay unten auf der Karte
                if let dist = distanceLabel {
                    HStack(spacing: 5) {
                        DazuIcon("figure.walk", accent: false)
                            .font(.system(size: 11))
                        Text(dist + " entfernt")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.75)))
                    .padding(.bottom, 10)
                }
            }
            .padding(.bottom, 14)

            // ── ETA-Karte ─────────────────────────────────────────────
            HStack(spacing: 0) {
                // ETA
                VStack(spacing: 4) {
                    if let mins = etaMinutes {
                        Text(tr("map.mins").replacingOccurrences(of: "{mins}", with: "\(mins)"))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text(tr("map.arrival_approx"))
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    } else {
                        Text("–")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 36)

                // Uhrzeit
                VStack(spacing: 4) {
                    if let clock = etaClockString {
                        Text(clock + tr("map.oclock_suffix"))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text(tr("map.expected"))
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    } else {
                        Text("–")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 36)

                // Score
                VStack(spacing: 4) {
                    Text(tr("map.points_abbrev").replacingOccurrences(of: "{points}", with: "\(participant.reliabilityScore)"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(scoreColor)
                    Text(tr("profile.reliability"))
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 16)
            .liquidGlass(cornerRadius: 18)
            .padding(.horizontal, 16)

            Spacer(minLength: 20)
        }
        .background(Color.white.opacity(0.75))
    }

    // MARK: - Helpers

    private var scoreColor: Color {
        switch participant.reliabilityScore {
        case 200...: return .onlineGreen
        case 50..<200: return .accentOrange
        default:       return .accentRed
        }
    }

    private struct MapPin: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
        let isPersonPin: Bool
    }

    private var mapAnnotations: [MapPin] {
        [MapPin(coordinate: liveCoord, isPersonPin: true),
         MapPin(coordinate: dropCoordinate, isPersonPin: false)]
    }

    private func fitRegion(from: CLLocationCoordinate2D,
                           to: CLLocationCoordinate2D) -> MKCoordinateRegion {
        let minLat = min(from.latitude,  to.latitude)
        let maxLat = max(from.latitude,  to.latitude)
        let minLon = min(from.longitude, to.longitude)
        let maxLon = max(from.longitude, to.longitude)
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let spanLat = max(0.008, (maxLat - minLat) * 1.6)
        let spanLon = max(0.008, (maxLon - minLon) * 1.6)
        return MKCoordinateRegion(center: center,
                                  span: MKCoordinateSpan(latitudeDelta: spanLat,
                                                         longitudeDelta: spanLon))
    }
}

// MARK: - Rounded Corners Helper

private extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

private struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                                cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// MARK: - Participant Avatars (überlappende Kreise)

struct ParticipantAvatars: View {
    let participants: [DropParticipant]
    private let maxVisible = 4
    private let size: CGFloat = 32
    private let border: CGFloat = 2

    private var visible: [DropParticipant] { Array(participants.prefix(maxVisible)) }
    private var extra: Int { max(0, participants.count - maxVisible) }

    var body: some View {
        HStack(spacing: -(size * 0.35)) {
            ForEach(Array(visible.enumerated()), id: \.offset) { i, p in
                avatarCircle(for: p)
                    .zIndex(Double(maxVisible - i))
            }
            if extra > 0 {
                ZStack {
                    Circle()
                        .fill(Color.brandLavender)
                        .frame(width: size, height: size)
                        .overlay(Circle().stroke(Color.bgPrimary, lineWidth: border))
                    Text("+\(extra)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textPrimary)
                }
                .zIndex(0)
            }
        }
    }

    @ViewBuilder
    private func avatarCircle(for participant: DropParticipant) -> some View {
        ZStack {
            Circle()
                .fill(Color.bgPrimary)
                .frame(width: size + border * 2, height: size + border * 2)

            if let img = participant.selfie {
                // Echtes Selfie-Foto
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if participant.profileImageURL != nil {
                // Remote-Profilbild über RemoteProfileImage (mit Cache)
                RemoteProfileImage(
                    url: participant.profileImageURL,
                    fallbackEmoji: participant.emoji,
                    size: size,
                    strokeColor: Color.clear
                )
            } else {
                // Emoji-Fallback
                Circle()
                    .fill(Color.brand.opacity(0.1))
                    .frame(width: size, height: size)
                    .overlay(
                        DazuPersonIcon()
                            .font(.system(size: size * 0.5))
                    )
            }
        }
    }
}

// MARK: - Mini Profile Sheet (Freunde & Fremde)

struct MiniProfileSheet: View {
    @AppStorage("appLanguage") private var appLanguage = "de"
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let name: String
    let emoji: String
    var selfie: UIImage? = nil
    var profileImageURL: String? = nil
    var reliabilityScore: Int = 85
    var totalCommits: Int = 0
    var subtitle: String = ""
    var accentColor: Color = Color.auroraCyan
    var isPlus: Bool = false
    /// Wenn gesetzt, wird der Drops+ Status live aus Firebase nachgezogen — dadurch
    /// zeigt das Sheet auch bei Freunden / Teilnehmern korrekt das Plus-Badge.
    var userUID: String? = nil
    /// Optionales Alter — wird im Subtitle angezeigt. Wenn nil, wird's via userUID aus
    /// `users/{uid}/birthdate` nachgezogen.
    var userAge: Int? = nil
    var canBlock: Bool = true
    /// True wenn dieser User in deiner Freundesliste ist → zeigt
    /// "Freund entfernen"-Button statt Block/Melden.
    var isFriend: Bool = false
    let onBlock: () -> Void

    @State private var showBlockAlert = false
    @State private var showReportSheet = false
    @State private var showRemoveFriendAlert = false
    @State private var fetchedPlus: Bool = false
    @State private var inviteSent: Bool = false
    /// Aus Firebase nachgezogen — für Beta-Badge-Cutoff und Alter im Subtitle.
    @State private var fetchedCreatedAt: Date? = nil
    /// Letzter Online-Heartbeat des Users — nil wenn noch nicht geladen.
    /// Daraus wird „Online jetzt" oder „Zuletzt online vor X Min" abgeleitet.
    @State private var fetchedLastActive: Date? = nil
    @State private var fetchedAge: Int? = nil
    /// Hero-Gradient des anderen Users — aus Firestore geladen.
    @State private var fetchedHeroTemplate: ProfileHeroTemplate = .aurora

    /// Online-Status-String — "Online jetzt" wenn der letzte Heartbeat
    /// unter 5 Min alt ist, sonst "Zuletzt online vor X Min / vor X Std /
    /// vor X Tagen". Fallback auf den statischen Subtitle wenn noch keine
    /// Daten geladen sind.
    private var onlineStatusLabel: String {
        guard let la = fetchedLastActive else { return subtitle }
        let delta = Date().timeIntervalSince(la)
        if delta < 5 * 60 { return tr("mini.online_now") }
        if delta < 60 * 60 {
            let m = Int(delta / 60)
            return tr("mini.last_online_min").replacingOccurrences(of: "{n}", with: "\(m)")
        }
        if delta < 24 * 60 * 60 {
            let h = Int(delta / 3600)
            return tr("mini.last_online_hours").replacingOccurrences(of: "{n}", with: "\(h)")
        }
        let d = Int(delta / 86400)
        return tr("mini.last_online_days").replacingOccurrences(of: "{n}", with: "\(d)")
    }

    /// Beta-Badge-Cutoff: Nutzer ab 04.05.2026 (Europe/Berlin) bekommen kein Badge mehr.
    /// Frühere Nutzer (Early Adopter) behalten den Badge dauerhaft. Wenn createdAt
    /// nicht ermittelbar ist, wird der Badge zur Sicherheit NICHT gezeigt.
    private var qualifiesForBetaBadge: Bool {
        guard let created = fetchedCreatedAt else { return false }
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 4
        c.hour = 0; c.minute = 0; c.second = 0
        c.timeZone = TimeZone(identifier: "Europe/Berlin")
        let cutoff = Calendar(identifier: .gregorian).date(from: c) ?? Date()
        return created < cutoff
    }

    /// Effektives Alter — übergeben oder aus Firebase nachgezogen.
    private var displayAge: Int? { userAge ?? fetchedAge }

    // Tier aus Punktzahl direkt — unabhängig von Event-Historie.
    private var tierLabel: String { ReliabilityScore.badge(forPoints: reliabilityScore) }
    private var tierIcon:  String { ReliabilityScore.badgeIcon(forPoints: reliabilityScore) }
    private var tierColor: Color  { ReliabilityScore.color(forPoints: reliabilityScore) }
    private var tierProgress: Double { ReliabilityScore.tierProgress(forPoints: reliabilityScore) }

    /// Anzahl früherer bestätigter Begegnungen mit diesem Nutzer (aus lokalen Daten).
    private var priorEncountersCount: Int {
        store.encounters.filter { $0.friendName == name && $0.confirmed }.count
    }

    /// „Dabei seit 3 Monaten" / „Neu dabei" — leitet Drops-Member-Status
    /// aus dem in Firebase gespeicherten `createdAt` ab (geladen in
    /// onAppear via `fetchUserMeta`). nil, wenn noch nicht geladen.
    private var memberSinceLabel: String? {
        guard let created = fetchedCreatedAt else { return nil }
        let now = Date()
        let comps = Calendar.current.dateComponents([.year, .month, .day],
                                                     from: created, to: now)
        let years = comps.year ?? 0
        let months = comps.month ?? 0
        let days = comps.day ?? 0
        if years >= 1 {
            return years == 1 ? tr("map.member_since_1y") : tr("map.member_since_y").replacingOccurrences(of: "{years}", with: "\(years)")
        }
        if months >= 1 {
            return months == 1 ? tr("map.member_since_1m") : tr("map.member_since_m").replacingOccurrences(of: "{months}", with: "\(months)")
        }
        if days >= 1 {
            return days == 1 ? tr("map.member_since_yesterday") : tr("map.member_since_d").replacingOccurrences(of: "{days}", with: "\(days)")
        }
        return tr("map.member_today")
    }

    /// Grid-Übersicht aller Badges die ein User haben könnte (außer Founder):
    /// Verifiziert, Verlässlich, PLUS, BETA, Gastgeber. Erfüllt = Farbe,
    /// nicht erfüllt = ausgegraut mit kurzem Hinweis wie man ihn erreicht.
    @ViewBuilder
    private var allBadgesRow: some View {
        let hasHost = store.pastDrops.contains { $0.wasHost }
        let isTrusted = ReliabilityScore.isTrusted(forPoints: reliabilityScore)
        let items: [(name: String, icon: String, color: Color, achieved: Bool, hint: String)] = [
            (tr("badge.verified"), "checkmark.shield.fill", Color.brandViolet,
             priorEncountersCount > 0,
             tr("badge.verified_hint")),
            (tr("badge.trusted"), "checkmark.seal.fill", Color.brandViolet,
             isTrusted,
             tr("badge.trusted_hint")),
            (tr("badge.beta"), "sparkle", Color.brandViolet,
             qualifiesForBetaBadge,
             tr("badge.beta_hint")),
            (tr("badge.host"), "star.fill", Color.brandOrange,
             hasHost,
             tr("badge.host_hint"))
        ]
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 8) {
                    Image(systemName: item.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(item.achieved ? item.color : .brandNight.opacity(0.3))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(
                            item.achieved ? item.color.opacity(0.15) : Color.brandNight.opacity(0.06)
                        ))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(item.achieved ? item.color : .brandNight.opacity(0.55))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if !item.achieved {
                            Text(item.hint)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(.brandNight.opacity(0.4))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(item.achieved
                          ? item.color.opacity(0.08)
                          : Color.brandNight.opacity(0.04)))
            }
        }
    }

    /// Chip-Badge für die Header-Chip-Row (Verlässlich, PLUS, Verifiziert …).
    /// Lavendel-Tint mit tintfarbenem Icon + Label, konsistent zum Profil-
    /// Header im Haupt-Tab.
    @ViewBuilder
    private func miniChip(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            DazuIcon(icon).font(.system(size: 9, weight: .bold))
            Text(text).font(.system(size: 10, weight: .heavy, design: .rounded))
        }
        .foregroundColor(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }

    /// Kompakte Info-Zeile innerhalb der Stats-Card.
    @ViewBuilder
    private func miniInfoRow(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 28, height: 28)
                DazuIcon(icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tint)
            }
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Clean dazu-Hintergrund — Creme/Nacht (adaptive) statt
            // Hero-Gradient. Kein Emoji-Scatter mehr.
            Color.brandCream.ignoresSafeArea()

        VStack(spacing: 0) {
            // ── Clean Header ───────────────────────────────────────────
            VStack(spacing: 12) {
                Capsule().fill(Color.brandNight.opacity(0.18))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)

                // Avatar — gleicher Stil wie der Profil-Tab-Header-Avatar:
                // 96px Kreis mit 3px Lavendel-Border, Foto wenn vorhanden,
                // sonst der zwei-ton dazu-Profil-Icon-Fallback.
                Group {
                    if let img = selfie {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                    } else if let urlStr = profileImageURL, !urlStr.isEmpty {
                        RemoteProfileImage(url: urlStr, fallbackEmoji: emoji, size: 96,
                                           strokeColor: .clear)
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.brandLavender)
                                .frame(width: 96, height: 96)
                            DazuProfileIcon(size: 54)
                        }
                    }
                }
                // Violetter Ring wie der Dennis-Avatar im Profil-Tab —
                // ersetzt den dezenten Lavender-Ring.
                .overlay(Circle().stroke(Color.brandViolet, lineWidth: 3.5))
                .shadow(color: Color.brandViolet.opacity(0.25), radius: 10, y: 4)
                .padding(.top, 4)
            }

            // ── Name + Alter + Badges ──────────────────────────────────
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // Namen-Stil wie das Profil: violett + oranger Punkt.
                    (Text(name).foregroundColor(.brandViolet)
                     + Text(".").foregroundColor(.brandOrange))
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                    if let age = displayAge {
                        Text("\(age)")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.5))
                    }
                }

                // Online-Status — nur zeigen wenn tatsächlich bekannt
                // (vorher Fallback "Dazu-Nutzer", das wirkte wie Platzhalter).
                if !onlineStatusLabel.isEmpty {
                    Text(onlineStatusLabel)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.6))
                }

                // Badge-Übersicht: alle Badges die der User haben könnte,
                // ausgegraut wenn noch nicht erreicht, mit kurzem Unlock-Hinweis.
                allBadgesRow
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }
            .padding(.top, 14)
            .padding(.bottom, 20)

            // ── Info-Card: Member-Seit + Treffen-Zähler ────────────────
            // Trust-Badge wurde in die Chip-Zeile oben verschoben; hier
            // nur noch sekundäre Infos (seit wann dabei, wie oft getroffen).
            VStack(spacing: 0) {
                if let memberSince = memberSinceLabel {
                    miniInfoRow(
                        icon: "sparkle",
                        tint: Color.brandViolet,
                        text: memberSince
                    )
                }
                if priorEncountersCount > 0 {
                    Divider().padding(.leading, 52)
                    miniInfoRow(
                        icon: "person.2.wave.2.fill",
                        tint: Color.auroraOrange,
                        text: tr("map.met_count").replacingOccurrences(of: "{count}", with: "\(priorEncountersCount)")
                    )
                }
            }
            .liquidGlass(cornerRadius: 18)
            .padding(.horizontal, 20)

            Spacer()

            // Bei Freunden: "Freund entfernen" — bei Fremden: Melden + Blockieren.
            // Keine Aktionen auf sich selbst.
            if name != store.currentUser.name {
                // Einladen-Button — nur sichtbar wenn ich gerade hoste UND
                // der User ein Freund mit bekannter UID ist. Sonst hat der
                // Button keinen Adressaten oder Drop, zu dem eingeladen
                // werden könnte.
                if isFriend, !store.activeDrops.isEmpty,
                   let targetUID = userUID, !targetUID.isEmpty {
                    // Flacher dazu-Primary (violett), konsistent zum Rest
                    // der App statt eigener Sunset-Gradient.
                    Button {
                        store.inviteFriendToDrop(friendUID: targetUID)
                        withAnimation(.spring(response: 0.3)) { inviteSent = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
                    } label: {
                        HStack(spacing: 8) {
                            DazuIcon(inviteSent ? "checkmark.circle.fill" : "paperplane.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text(inviteSent ? tr("map.invitation_sent") : tr("map.invite_to_my_drop"))
                        }
                        .dropsPrimaryButton()
                    }
                    .dropsPressable()
                    .disabled(inviteSent)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }
                if isFriend {
                    Button { showRemoveFriendAlert = true } label: {
                        HStack(spacing: 6) {
                            DazuIcon("person.badge.minus", accent: false)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tr("map.remove_friend"))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.accentRed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(Color.accentRed.opacity(0.10)))
                    }
                    .dropsPressable()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                } else if canBlock {
                    HStack(spacing: 10) {
                        Button { showReportSheet = true } label: {
                            HStack(spacing: 6) {
                                DazuIcon("flag.fill").font(.system(size: 13, weight: .semibold))
                                Text(tr("map.report")).font(.system(size: 14, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.accentOrange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(Color.accentOrange.opacity(0.10)))
                        }
                        .dropsPressable()

                        Button { showBlockAlert = true } label: {
                            HStack(spacing: 6) {
                                DazuIcon("hand.raised.fill", accent: false).font(.system(size: 13, weight: .semibold))
                                Text(tr("map.block")).font(.system(size: 14, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.accentRed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(Color.accentRed.opacity(0.10)))
                        }
                        .dropsPressable()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                } else {
                    Spacer(minLength: 20)
                }
            } else {
                Spacer(minLength: 20)
            }
        }           // VStack body
        }           // ZStack fullscreen Cream
        .alert(tr("profile.confirm_block_title"), isPresented: $showBlockAlert) {
            Button(tr("common.cancel"), role: .cancel) {}
            Button(tr("map.block"), role: .destructive) {
                store.blockUser(name: name)
                dismiss()
                onBlock()
            }
        } message: {
            Text(tr("profile.block_message").replacingOccurrences(of: "{name}", with: name))
        }
        .alert(tr("map.remove_friend_q"), isPresented: $showRemoveFriendAlert) {
            Button(tr("common.cancel"), role: .cancel) {}
            Button(tr("map.remove"), role: .destructive) {
                if let uid = userUID, !uid.isEmpty {
                    store.removeFriend(theirUID: uid)
                }
                dismiss()
            }
        } message: {
            Text(tr("map.unfriend_message").replacingOccurrences(of: "{name}", with: name))
        }
        .sheet(isPresented: $showReportSheet) {
            ReportUserSheet(reportedName: name, reportedUID: userUID) {
                showReportSheet = false
            }
        }
        .onAppear {
            // Plus-Status aus Firebase ziehen, falls nicht schon übergeben und UID vorhanden
            if !isPlus, let uid = userUID, !uid.isEmpty {
                RealtimeDBManager.shared.fetchPlusStatus(uid: uid) { plus in
                    fetchedPlus = plus
                }
            }
            // Letzter Online-Heartbeat für Status-Label „Zuletzt online …".
            if let uid = userUID, !uid.isEmpty {
                RealtimeDBManager.shared.fetchLastActive(uid: uid) { lastActive in
                    fetchedLastActive = lastActive
                }
            }
            // createdAt + birthdate für Beta-Badge & Alter laden
            if let uid = userUID, !uid.isEmpty {
                RealtimeDBManager.shared.fetchUserMeta(uid: uid) { created, birthdate in
                    fetchedCreatedAt = created
                    if let bd = birthdate, userAge == nil {
                        let comps = Calendar.current.dateComponents([.year], from: bd, to: Date())
                        if let years = comps.year, years > 0, years < 120 {
                            fetchedAge = years
                        }
                    }
                }
            }
            // Hero-Gradient aus Firestore laden
            if let uid = userUID, !uid.isEmpty {
                Firestore.firestore().collection("users").document(uid)
                    .getDocument { snap, _ in
                        guard let raw = snap?.data()?["heroTemplate"] as? String,
                              let tpl = ProfileHeroTemplate(rawValue: raw) else { return }
                        DispatchQueue.main.async { fetchedHeroTemplate = tpl }
                    }
            }
        }
    }
}

// MARK: - Munich Zone Overlay (Aurora-Grenze + Ausgrauung)

/// Weiche Aurora-Grenzlinie — vollständig jitter-frei.
///
/// Geometrie (pts) kommt von außen (LiveMapView via onMapCameraChange) und
/// wird synchron mit MapKit aktualisiert. Der Canvas berührt proxy.convert
/// NICHT mehr → keine Frame-Versätze möglich.
/// Farb-Loop: 20 s (langsam und ruhig).
struct MunichZoneOverlay: View {
    /// Vorkonvertierte Bildschirmpunkte — von LiveMapView bereitgestellt.
    let pts: [CGPoint]

    // HSB-Hue-Stützpunkte (geschlossen): cyan → grün → violet → pink → amber → cyan
    private static let hueStops: [Double] = [0.530, 0.370, 0.720, 0.920, 0.100, 0.530]

    /// Farbe für eine Bogenlängen-Position (0–1) + laufende Phase.
    private func hue(at arcPos: Double, phase: Double) -> Color {
        let t = (arcPos + phase).truncatingRemainder(dividingBy: 1.0)
        let stops = Self.hueStops
        let scaled = t * Double(stops.count - 1)
        let i = min(Int(scaled), stops.count - 2)
        let f = scaled - Double(i)
        let h = stops[i] + (stops[i + 1] - stops[i]) * f
        return Color(hue: h, saturation: 0.78, brightness: 0.92)
    }

    /// Vorberechnete normalisierte Positionen (0..1) je Punkt um das Polygon
    /// — basiert auf dem **Punkt-Index**, nicht auf Screen-Distanz, damit
    /// wir das nicht pro Frame neu rechnen müssen. Der Farbverlauf wandert
    /// gleichmäßig entlang der Punkt-Reihenfolge — für 161-Punkte-Polygon
    /// mit halbwegs gleichmäßiger Punktdichte sieht das gleichwertig aus.
    private var normalizedPositions: [Double] {
        let n = pts.count
        guard n > 1 else { return [] }
        return (0..<n).map { Double($0) / Double(n - 1) }
    }

    var body: some View {
        // 12 fps für Farbwechsel — 20s-Loop, sehr langsam, halbierte CPU-Last
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: false)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 20.0) / 20.0

            Canvas { ctx, size in
                guard pts.count > 3 else { return }

                // ── Zone-Path bauen (wird 2× gebraucht) ─────────────────
                var zonePath = Path()
                zonePath.move(to: pts[0])
                for pt in pts.dropFirst() { zonePath.addLine(to: pt) }
                zonePath.closeSubpath()

                // ── Ausgrauung außerhalb (Even-Odd-Loch) ──────────────
                var outerPath = Path()
                outerPath.addRect(CGRect(x: -600, y: -600,
                                        width: size.width + 1200,
                                        height: size.height + 1200))
                outerPath.addPath(zonePath)
                ctx.fill(outerPath,
                         with: .color(.primary.opacity(0.12)),
                         style: FillStyle(eoFill: true))

                // ── Index-basierte Farbpositionen (keine Arc-Length-
                //     Berechnung pro Frame mehr!) ────────────────────
                let n = pts.count
                let positions = normalizedPositions

                // ── Breiter Glow-Layer ──────────────────────────────
                // Jeder Segment bekommt eine Mischfarbe aus Start und Ende —
                // sieht flüssiger aus als harte Segment-Grenzen.
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 8))
                    for i in 0..<(n - 1) {
                        let col = hue(at: positions[i], phase: phase)
                        var seg = Path()
                        seg.move(to: pts[i])
                        seg.addLine(to: pts[i + 1])
                        layer.stroke(seg,
                                     with: .color(col.opacity(0.48)),
                                     style: StrokeStyle(lineWidth: 10,
                                                        lineCap: .round,
                                                        lineJoin: .round))
                    }
                }

                // ── Feine Mittellinie ──────────────────────────────
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 1.0))
                    for i in 0..<(n - 1) {
                        let col = hue(at: positions[i], phase: phase)
                        var seg = Path()
                        seg.move(to: pts[i])
                        seg.addLine(to: pts[i + 1])
                        layer.stroke(seg,
                                     with: .color(col.opacity(0.42)),
                                     style: StrokeStyle(lineWidth: 1.5,
                                                        lineCap: .round,
                                                        lineJoin: .round))
                    }
                }
            }
        }
        .transaction { $0.animation = nil }
    }
}

// MARK: - Multi-Zone Overlay (alle 5 Launch-Städte gleichzeitig)

/// Zeichnet mehrere Service-Zones (Polygone) mit Aurora-Borders und
/// einer gemeinsamen Ausgrauung außerhalb aller Zonen. Even-Odd-Fill mit
/// N+1 Subpaths (Außen-Rechteck + N Polygone) erzeugt N Löcher im Grau.
struct MultiZoneOverlay: View {
    /// Liefert die aktuellen Screen-Pixel-Polygone. Wird in jedem TimelineView-
    /// Tick (12 fps) aufgerufen, holt sich also direkt aus dem aktuellen
    /// MapProxy die frisch projizierten Punkte. Dadurch: kein @State auf
    /// LiveMapView, kein parent-Re-Render, Pins bleiben stabil.
    let polygonsProvider: () -> [[CGPoint]]

    // Violett (#5B3DF5, hue≈0.694) ↔ Mint (#4DEBBE, hue≈0.453) — App-Farben
    private static let hueStops: [Double] = [0.694, 0.573, 0.453, 0.573, 0.694]

    private func hue(at arcPos: Double, phase: Double) -> Color {
        let t = (arcPos + phase).truncatingRemainder(dividingBy: 1.0)
        let stops = Self.hueStops
        let scaled = t * Double(stops.count - 1)
        let i = min(Int(scaled), stops.count - 2)
        let f = scaled - Double(i)
        let h = stops[i] + (stops[i + 1] - stops[i]) * f
        return Color(hue: h, saturation: 0.90, brightness: 0.96)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 20.0) / 20.0
            // Polygone auf jedem Display-Frame frisch aus dem MKMapView holen —
            // Aurora folgt der Kamera ohne Drift (kein minimumInterval-Cap).
            let polygons = polygonsProvider()

            Canvas { ctx, size in
                guard !polygons.isEmpty else { return }

                // ── Ausgrauung: Außen-Rechteck + jede Zone als Loch (even-odd) ──
                var outerPath = Path()
                outerPath.addRect(CGRect(x: -600, y: -600,
                                        width: size.width + 1200,
                                        height: size.height + 1200))
                for pts in polygons where pts.count > 2 {
                    var zone = Path()
                    zone.move(to: pts[0])
                    for pt in pts.dropFirst() { zone.addLine(to: pt) }
                    zone.closeSubpath()
                    outerPath.addPath(zone)
                }
                ctx.fill(outerPath,
                         with: .color(.primary.opacity(0.12)),
                         style: FillStyle(eoFill: true))

                // ── Aurora-Border pro Zone ───────────────────────────
                for pts in polygons where pts.count > 2 {
                    let n = pts.count
                    // Index-basierte Farbpositionen (performant)
                    let positions = (0..<n).map { Double($0) / Double(n - 1) }

                    // Breiter Glow
                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 8))
                        for i in 0..<(n - 1) {
                            let col = hue(at: positions[i], phase: phase)
                            var seg = Path()
                            seg.move(to: pts[i])
                            seg.addLine(to: pts[i + 1])
                            layer.stroke(seg,
                                         with: .color(col.opacity(0.48)),
                                         style: StrokeStyle(lineWidth: 10,
                                                            lineCap: .round,
                                                            lineJoin: .round))
                        }
                    }

                    // Feine Mittellinie
                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 1.0))
                        for i in 0..<(n - 1) {
                            let col = hue(at: positions[i], phase: phase)
                            var seg = Path()
                            seg.move(to: pts[i])
                            seg.addLine(to: pts[i + 1])
                            layer.stroke(seg,
                                         with: .color(col.opacity(0.42)),
                                         style: StrokeStyle(lineWidth: 1.5,
                                                            lineCap: .round,
                                                            lineJoin: .round))
                        }
                    }
                }
            }
        }
        .transaction { $0.animation = nil }
    }
}

// MARK: - Pulsierender Live-Dot (Unterwegs-Anzeige)

struct PulsingLiveDot: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.auroraBlue.opacity(0.25))
                .frame(width: 12, height: 12)
                .scaleEffect(pulsing ? 1.8 : 1.0)
                .opacity(pulsing ? 0 : 0.6)
            Circle()
                .fill(Color.auroraBlue)
                .frame(width: 7, height: 7)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

// MARK: - UIKit ShareSheet Wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var subject: String = ""
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if !subject.isEmpty { vc.setValue(subject, forKey: "subject") }
        return vc
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Drag-Damping Helper

/// Liquid-Glass-Style Drag-Damping: Drag nach unten passiert weich,
/// nach Schwellwert wird's elastisch gebremst (rubber-band). Drag nach oben
/// (negativer Wert) wird stark gedämpft → fühlt sich „klebrig" an wie bei
/// Apple's Tab-Bar-Pull.
fileprivate func dampedDragOffset(_ raw: CGFloat) -> CGFloat {
    if raw <= 0 {
        // Drag nach oben → starke Resistance
        return raw * 0.25
    }
    let threshold: CGFloat = 80
    if raw <= threshold { return raw }
    // Über Schwellwert: zunehmender Widerstand (rubber-band)
    let extra = raw - threshold
    return threshold + extra * (1 / (1 + extra / 220))
}

// MARK: - Map Boost Card
//
// Schwebt überm Recenter-Button wenn Boost-Phase aktiv ist (<5 Drops in
// Reichweite). Drag-Handle oben, Bolt-Icon mit Gradient links, Text rechts.
// Bei Drag → folgt rubber-band-mäßig dem Finger; bei Loslassen >60pt tropft
// die Karte zur kleinen Pille links neben dem Recenter-Button (matchedGeometryEffect).
struct MapBoostCard: View {
    var onCollapse: (() -> Void)? = nil

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 8) {
            // Drag-Handle + Collapse-Chevron
            HStack {
                Spacer()
                Capsule()
                    .fill(Color.textPrimary.opacity(0.20))
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                if onCollapse != nil {
                    Button {
                        onCollapse?()
                    } label: {
                        DazuIcon("chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.textPrimary.opacity(0.45))
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .dropsPressable()
                    .accessibilityLabel("Einklappen")
                }
            }
            .padding(.top, -2)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentOrange, Color.brand],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                        .shadow(
                            color: Color.accentOrange.opacity(pulse ? 0.55 : 0.25),
                            radius: pulse ? 14 : 6
                        )
                    DazuIcon("bolt.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("map.boost_phase_active"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(tr("map.boost_phase_msg"))
                        .font(.system(size: 11.5))
                        .foregroundColor(.textPrimary.opacity(0.72))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .liquidGlass(cornerRadius: 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Extend Drop Sheet

private struct ExtendDropSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let dropID: UUID
    let onExtended: (Int) -> Void  // übergibt die gewählten Minuten

    var body: some View {
        ZStack {
            Color.brandCream.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: -2) {
                    Text(tr("live.round"))
                        .foregroundColor(.brandNight)
                    Text(tr("live.extend_dot"))
                        .foregroundColor(.brandViolet)
                }
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Text(tr("map.extend_drop_msg"))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)

                let options: [(String, Int)] = [
                    (tr("map.extend_30min"), 30), (tr("map.extend_1h"), 60),
                    (tr("map.extend_2h"), 120), (tr("map.extend_4h"), 240)
                ]
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(options, id: \.1) { label, minutes in
                        Button {
                            store.extendDrop(id: dropID, byMinutes: minutes)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onExtended(minutes)
                            dismiss()
                        } label: {
                            Text(label)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.brandNight)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.brandLavender.opacity(0.9))
                                )
                        }
                        .dropsPressable()
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                Button(tr("map.cancel")) { dismiss() }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 22)
            }
        }
    }
}

// MARK: - Report User Sheet
// Ermöglicht Nutzern, andere Profile wegen Verstoßes zu melden.
// Schreibt einen Eintrag unter `reports/{autoID}` → wird im Admin-Panel geprüft.
// Pflicht für App Review (Guideline 1.2 — UGC-Apps).

struct ReportUserSheet: View {
    let reportedName: String
    let reportedUID: String?
    let onDismiss: () -> Void

    init(reportedName: String, reportedUID: String? = nil, onDismiss: @escaping () -> Void) {
        self.reportedName = reportedName
        self.reportedUID = reportedUID
        self.onDismiss = onDismiss
    }

    @State private var selectedReason: String = ""
    @State private var details: String = ""
    @State private var submitted: Bool = false
    @Environment(\.dismiss) private var dismiss

    private var reasons: [String] {
        [
            tr("map.report_reason_harassment"),
            tr("map.report_reason_fake"),
            tr("map.report_reason_spam"),
            tr("map.report_reason_offensive"),
            tr("map.report_reason_minor"),
            tr("map.report_reason_misc")
        ]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        DazuIcon("flag.fill")
                            .foregroundColor(.accentOrange)
                        Text(reportedName).font(.system(size: 15, weight: .semibold))
                    }
                } header: {
                    Text(tr("map.reported_user"))
                }

                if submitted {
                    Section {
                        HStack(spacing: 10) {
                            DazuIcon("checkmark.seal.fill")
                                .foregroundColor(.brand)
                            Text(tr("map.report_received"))
                                .font(.system(size: 14))
                        }
                    }
                } else {
                    Section {
                        ForEach(reasons, id: \.self) { reason in
                            Button {
                                selectedReason = reason
                            } label: {
                                HStack {
                                    Text(reason).foregroundColor(.textPrimary)
                                    Spacer()
                                    if selectedReason == reason {
                                        DazuIcon("checkmark").foregroundColor(.brand)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(tr("map.reason"))
                    }

                    Section {
                        TextField(tr("map.optional_more_info"), text: $details, axis: .vertical)
                            .lineLimit(3...6)
                    } header: {
                        Text(tr("map.details_optional"))
                    }
                }
            }
            .navigationTitle(tr("map.report_user"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("map.cancel")) { dismiss(); onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if submitted {
                        Button(tr("map.done")) { dismiss(); onDismiss() }
                            .fontWeight(.semibold)
                    } else {
                        Button(tr("map.send")) {
                            RealtimeDBManager.shared.submitReport(
                                reportedUID: reportedUID,
                                reportedName: reportedName,
                                reason: selectedReason,
                                details: details
                            )
                            withAnimation { submitted = true }
                        }
                        .fontWeight(.semibold)
                        .disabled(selectedReason.isEmpty)
                    }
                }
            }
        }
    }
}

// MARK: - JoinerLiveInfoSheet
// Kompakte Info-Ansicht wenn der Host auf einen Joiner-Pin auf seiner
// Karte tippt. KEIN "Ich komme vorbei"-Button (der Joiner kommt ja zu
// uns, nicht andersrum). Zeigt Avatar, Name, Alter, Reliability-Tier
// und — wenn GPS bekannt — Distanz / ETA zum eigenen Drop.
struct JoinerLiveInfoSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let item: MapAnnotationItem

    /// Live-Info aus joinerLiveInfos via stableUUID-Match. item.id ist
    /// die hash-basierte UUID — wir suchen die UID rückwärts indem wir
    /// gegen alle bekannten Joiner-UIDs vergleichen.
    private var joinerInfo: JoinerLiveInfo? {
        for (uid, info) in store.joinerLiveInfos
        where AppStore.stableUUID(from: uid) == item.id {
            return info
        }
        return nil
    }

    /// Distanz zum eigenen Drop in km — Joiner ist unterwegs ZU uns.
    private var distanceKm: Double? {
        guard let info = joinerInfo,
              let myDrop = store.activeDrops.first else { return nil }
        let joiner = CLLocation(latitude: info.lat, longitude: info.lng)
        let drop = CLLocation(latitude: myDrop.location.coordinate.latitude,
                              longitude: myDrop.location.coordinate.longitude)
        return joiner.distance(from: drop) / 1000.0
    }

    /// ETA in Minuten — grobe Walking-Speed-Annahme (5 km/h).
    private var etaMinutes: Int? {
        guard let km = distanceKm else { return nil }
        return Int((km / 5.0) * 60.0)
    }

    private var reliabilityTier: String {
        guard let pts = joinerInfo?.reliabilityPoints else { return "" }
        return ReliabilityScore.badge(forPoints: pts)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Avatar + Name (+ Age) + "ist auf dem Weg"-Label
            HStack(spacing: 14) {
                ZStack {
                    if let url = joinerInfo?.profileImageURL, !url.isEmpty {
                        RemoteProfileImage(
                            url: url,
                            fallbackEmoji: item.emoji,
                            size: 60,
                            strokeColor: .clear
                        )
                    } else {
                        Circle()
                            .fill(Color.onlineGreen.opacity(0.14))
                            .frame(width: 60, height: 60)
                        DazuPersonIcon()
                            .font(.system(size: 30))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.textPrimary)
                        if let age = joinerInfo?.age {
                            Text("· \(age)")
                                .font(.system(size: 15))
                                .foregroundColor(.textSecondary)
                        }
                    }
                    HStack(spacing: 5) {
                        PulsingLiveDot()
                        Text(tr("map.on_the_way_to_drop"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                    if !reliabilityTier.isEmpty {
                        Text(reliabilityTier)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.brand)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.brand.opacity(0.12), in: Capsule())
                            .padding(.top, 2)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 18)

            Divider().padding(.horizontal, 20)

            // Live-Stats: Distanz + ETA
            if let km = distanceKm, let eta = etaMinutes {
                HStack(spacing: 0) {
                    statBlock(
                        icon: "figure.walk",
                        value: tr("map.mins_short").replacingOccurrences(of: "{mins}", with: "\(eta)"),
                        label: tr("map.way"),
                        color: .brand
                    )
                    Divider().frame(height: 36)
                    statBlock(
                        icon: "location.fill",
                        value: String(format: "%.1f km", km),
                        label: tr("map.distance_short"),
                        color: .onlineGreen
                    )
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }

            Spacer(minLength: 12)

            // Schließen-Button — kein CTA, weil keine Aktion nötig ist.
            // Der Host beobachtet einfach wie der Joiner näher kommt.
            Button { dismiss() } label: {
                Text(tr("map.close"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.75))
    }

    @ViewBuilder
    private func statBlock(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            DazuIcon(icon)
                .font(.system(size: 16))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Ghost Drop Info Sheet

/// Read-only Info-Karte für bereits beendete Drops. Kein Join-Button —
/// der Drop ist vorbei. Zeigt Activity, Host, Teilnehmer-Namen (Chips,
/// keine Bilder) und Zeit-Status.
// MARK: - Demo Drop CTA Sheet

struct DemoDropCTASheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let item: MapAnnotationItem

    @State private var resolvedAddress: String? = nil

    private static let demoNamePool = [
        "Lena", "Max", "Sophie", "Tim", "Anna", "Jonas", "Lisa", "Felix",
        "Marie", "Paul", "Hannah", "Leon", "Emma", "Noah", "Mia", "Ben",
        "Sarah", "Luca", "Lara", "Erik",
    ]

    private var participantCount: Int { item.effectiveParticipantCount }

    private var participantNames: [String] {
        guard participantCount > 0 else { return [] }
        var result: [String] = []
        let hostName = item.name.trimmingCharacters(in: .whitespaces)
        if !hostName.isEmpty { result.append(hostName) }
        let seed = item.id.uuidString.hashValue
        var rng = SeededRNG(seed: UInt64(bitPattern: Int64(seed)))
        var pool = Self.demoNamePool.filter { $0 != hostName }
        while result.count < participantCount && !pool.isEmpty {
            let idx = Int(rng.next() % UInt64(pool.count))
            result.append(pool.remove(at: idx))
        }
        return result
    }

    private var countLabel: String {
        if participantCount == 1 { return tr("ghost.were_there_one") }
        return tr("ghost.were_there_many").replacingOccurrences(of: "{n}", with: "\(participantCount)")
    }

    private var endedLabel: String {
        guard let endedAt = item.endedAt else { return "" }
        let minutes = Int(Date().timeIntervalSince(endedAt) / 60)
        if minutes < 60 {
            return tr("ghost.ended_ago_min").replacingOccurrences(of: "{n}", with: "\(max(1, minutes))")
        }
        return tr("ghost.ended_ago_hr").replacingOccurrences(of: "{n}", with: "\(max(1, minutes / 60))")
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(UIColor.tertiarySystemFill))
                        .frame(width: 52, height: 52)
                    DazuActivityIcon(item.emoji.isEmpty ? "👻" : item.emoji, when: item.hasActivityEmoji)
                        .font(.system(size: 24))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.activity)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.textPrimary)
                    if !item.locationTitle.isEmpty {
                        Text(item.locationTitle)
                            .font(.system(size: 13))
                            .foregroundColor(.brand)
                    } else if let addr = resolvedAddress {
                        Text(addr)
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }
                    if !endedLabel.isEmpty {
                        Text(endedLabel)
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                            .padding(.top, 1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 18)
            .task(id: item.id) {
                // Nur geocoden wenn kein Venue-Name vorhanden (sonst Adresse oft ungenau)
                guard item.locationTitle.isEmpty else { return }
                let loc = CLLocation(latitude: item.coordinate.latitude, longitude: item.coordinate.longitude)
                CLGeocoder().reverseGeocodeLocation(loc) { placemarks, _ in
                    guard let p = placemarks?.first else { return }
                    let street = [p.thoroughfare, p.subThoroughfare]
                        .compactMap { $0 }.joined(separator: " ")
                    guard !street.isEmpty else { return }
                    DispatchQueue.main.async { resolvedAddress = street }
                }
            }

            // ── Teilnehmer-Chips ──────────────────────────────────────────
            if !participantNames.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(countLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .padding(.horizontal, 20)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(participantNames.enumerated()), id: \.offset) { _, name in
                                Text(name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(Color(UIColor.secondarySystemFill)))
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }

            // ── CTA-Bereich ───────────────────────────────────────────────
            VStack(spacing: 6) {
                DazuIcon("leaf.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.brandViolet)
                    .padding(.top, 20)
                Text(tr("live.community_headline"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                Text(tr("live.community_body"))
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)

            // ── Buttons ───────────────────────────────────────────────────
            HStack(spacing: 10) {
                ShareLink(
                    item: URL(string: "https://apps.apple.com/de/app/drops-triff-leute/id6762097493")!,
                    subject: Text(tr("live.share_subject")),
                    message: Text(tr("live.share_message"))
                ) {
                    HStack(spacing: 6) {
                        DazuIcon("square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                        Text(tr("live.share"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.brand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().strokeBorder(Color.brand.opacity(0.6), lineWidth: 1.5))
                }
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        store.selectedTab = .create
                    }
                } label: {
                    HStack(spacing: 6) {
                        DazuIcon("plus.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(tr("live.start_plan"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.brand))
                }
                .dropsPressable()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Ghost Drop Info Sheet

struct GhostDropInfoSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let item: MapAnnotationItem

    /// Pool deutscher Vornamen für deterministisch erzeugte Demo-Teilnehmer.
    /// Selber drop.id-Seed → selbe Namen-Auswahl bei jedem Sheet-Open.
    private static let demoNamePool = [
        "Lena", "Max", "Sophie", "Tim", "Anna", "Jonas", "Lisa", "Felix",
        "Marie", "Paul", "Hannah", "Leon", "Emma", "Noah", "Mia", "Ben",
        "Sarah", "Luca", "Lara", "Erik",
    ]

    private var participantCount: Int {
        item.effectiveParticipantCount
    }

    /// Deterministische Namensliste aus drop.id-Seed. Host (`item.name`)
    /// kommt zuerst, dann weitere Namen aus dem Pool — alle unique.
    private var participantNames: [String] {
        guard participantCount > 0 else { return [] }
        var result: [String] = []
        let hostName = item.name.trimmingCharacters(in: .whitespaces)
        if !hostName.isEmpty { result.append(hostName) }

        // Deterministischer Seed aus UUID — gleicher Drop → gleiche Reihenfolge.
        let seed = item.id.uuidString.hashValue
        var rng = SeededRNG(seed: UInt64(bitPattern: Int64(seed)))
        var pool = Self.demoNamePool.filter { $0 != hostName }
        while result.count < participantCount && !pool.isEmpty {
            let idx = Int(rng.next() % UInt64(pool.count))
            result.append(pool.remove(at: idx))
        }
        return result
    }

    private var countLabel: String {
        if participantCount == 1 { return tr("ghost.were_there_one") }
        return tr("ghost.were_there_many").replacingOccurrences(of: "{n}", with: "\(participantCount)")
    }

    private var endedLabel: String {
        guard let endedAt = item.endedAt else { return "" }
        let minutes = Int(Date().timeIntervalSince(endedAt) / 60)
        if minutes < 60 {
            return tr("ghost.ended_ago_min").replacingOccurrences(of: "{n}", with: "\(max(1, minutes))")
        }
        let hours = max(1, minutes / 60)
        return tr("ghost.ended_ago_hr").replacingOccurrences(of: "{n}", with: "\(hours)")
    }

    var body: some View {
        VStack(spacing: 14) {
            // Activity-Header
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.textTertiary.opacity(0.12))
                        .frame(width: 60, height: 60)
                    DazuActivityIcon(item.emoji, when: item.hasActivityEmoji)
                        .font(.system(size: 30))
                        .saturation(0.7)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.activity)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.textPrimary)
                    if !item.locationTitle.isEmpty {
                        Text(item.locationTitle)
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                    }
                    if !item.name.isEmpty {
                        Text(tr("ghost.host_was").replacingOccurrences(of: "{name}", with: item.name))
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            // Namen-Chips + Count
            if !participantNames.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(countLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textSecondary)
                    // FlowLayout-Style: einfaches HStack das umbricht
                    // wenn zu viele Namen — mit ScrollView horizontal
                    // als Fallback (selten >5 Teilnehmer).
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(participantNames.enumerated()), id: \.offset) { _, name in
                                Text(name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.textPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.textTertiary.opacity(0.12)))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
            }

            // Status-Label
            VStack(spacing: 4) {
                Text(tr("ghost.title"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                if !endedLabel.isEmpty {
                    Text(endedLabel)
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                }
                Text(tr("ghost.subtitle"))
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 22)
            }
            .padding(.top, 4)

            Spacer(minLength: 0)

            // Schließen-Button
            Button(action: { dismiss() }) {
                Text(tr("common.close"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Color.brand))
            }
            .dropsPressable()
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Mini-RNG für deterministische Demo-Daten. Linear Congruential Generator —
/// reicht völlig für "selber Seed → selbe Sequenz" bei Demo-Inhalten.
private struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - Stable Cluster Key

/// Hash der sortierten Member-UUIDs als stabile View-Identität für
/// Cluster-Gruppen. Gleiche Mitglieder → gleicher Key → SwiftUI behält
/// die Annotation-Identität bei Cluster-Recompute, kein Re-Render-Flash.
extension Array where Element == MapAnnotationItem {
    var stableClusterKey: String {
        map { $0.id.uuidString }.sorted().joined(separator: "|")
    }
}

// MARK: - MKMapView UIKit-Wrapper (Phase 1: Drop-Pins)
//
// Hintergrund: SwiftUI Map re-rendert ihren Body bei jedem Pan-Event (mapPosition-
// Binding). Annotations werden dabei pro Frame re-evaluiert → subtiles Wobble der
// Pins. MKMapView verwaltet Annotations nativ; Pan/Zoom triggert keine SwiftUI-
// Re-Renders → Pins stehen pixelgenau still.
//
// Diese Phase: nur Drop-Pins (active + ghost) via MKAnnotation. Andere
// Map-Inhalte (Aurora-Overlay, Joiner-Pins, Communities, GPS-Ring, Suggested
// Spots) bleiben vorerst auf SwiftUI-Seite oder werden temporär ausgeblendet.

/// Custom MKAnnotation, hält Referenz auf das MapAnnotationItem.
final class MapKitDropAnnotation: NSObject, MKAnnotation {
    var item: MapAnnotationItem
    /// `coordinate` ist via KVO observierbar — MKMapView nutzt das wenn wir die
    /// Position aktualisieren. Stabile Identität gibt's via `item.id`.
    var coordinate: CLLocationCoordinate2D { item.coordinate }
    /// Cache des letzten Render-Keys → wenn unverändert: skip re-configure.
    /// Verhindert Flashing alle 5-10s wenn LiveMapView wegen Location-Updates
    /// rendered und updateUIView() durchläuft.
    var lastRenderKey: String = ""
    init(item: MapAnnotationItem) {
        self.item = item
        super.init()
    }
}

/// Render-Key für eine Annotation. Wenn der String unverändert ist, muss die
/// View nicht neu konfiguriert werden — alle render-relevanten Felder sind drin.
fileprivate func annotationRenderKey(_ item: MapAnnotationItem, isJoined: Bool) -> String {
    let parts: [String] = [
        item.emoji,
        item.activity,
        item.name,
        item.isGhost ? "G" : "_",
        item.isFuzzy ? "F" : "_",
        "\(item.maxParticipants)",
        "\(item.liveParticipantCount ?? -1)",
        "\(item.participants.count)",
        isJoined ? "J" : "_",
        "\(item.type)",
        "\(item.clusterGroup?.count ?? 0)"
    ]
    return parts.joined(separator: "|")
}

/// Custom MKAnnotationView die unsere existierende `DropMapPin` SwiftUI-View via
/// UIHostingController rendert. Damit behalten wir das ganze Pin-Design ohne
/// es in UIView neu zu schreiben.
final class MapKitDropAnnotationView: MKAnnotationView {
    static let reuseID = "MapKitDropAnnotationView"

    private var host: UIHostingController<AnyView>?
    var onTap: (() -> Void)?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        // Eigener Tap-Handler — Standard-MKAnnotationView öffnet sonst Callout.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        backgroundColor = .clear
        // Core-Animation implicit animations deaktivieren — MapKit triggert
        // sonst alle paar Sekunden Fade/Position-Animationen auf den Annotation-
        // Views (z.B. bei Location-Updates), was als Blinken sichtbar wird.
        layer.actions = [
            "opacity":   NSNull(),
            "position":  NSNull(),
            "bounds":    NSNull(),
            "transform": NSNull(),
            "contents":  NSNull(),
        ]
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleTap() { onTap?() }

    /// SwiftUI-Pin (re-)konfigurieren. Wird bei dequeue + bei Updates aufgerufen.
    func configure(item: MapAnnotationItem,
                   isJoined: Bool,
                   myToken: String,
                   confirmedTokens: Set<String>,
                   onTap: @escaping () -> Void) {
        self.onTap = onTap

        let rootView: AnyView
        switch item.type {
        case .cluster:
            let group = item.clusterGroup ?? []
            rootView = AnyView(DropClusterPin(group: group, onTap: onTap))
            isUserInteractionEnabled = true
        case .suggested:
            let spot = item.suggestedSpot ?? AppStore.SuggestedSpot(
                id: item.id.uuidString, coordinate: item.coordinate,
                activityEmoji: item.emoji, activityName: item.activity,
                occurrences: 1, lastSeen: Date())
            rootView = AnyView(SuggestedSpotPin(spot: spot))
            isUserInteractionEnabled = false
        case .community:
            if let community = item.communityRef {
                rootView = AnyView(CommunityMapPin(community: community, action: onTap))
            } else {
                rootView = AnyView(EmptyView())
            }
            isUserInteractionEnabled = true
        default:
            rootView = AnyView(DropMapPin(
                item: item,
                isJoined: isJoined,
                onTap: onTap,
                myToken: myToken,
                confirmedTokens: confirmedTokens
            ))
            isUserInteractionEnabled = true
        }

        if let h = host {
            // SwiftUI-Update ohne UIKit-Animation-Wrapper damit kein Flash entsteht
            // wenn MapKit zwischen Frames refresht.
            UIView.performWithoutAnimation {
                h.rootView = rootView
            }
        } else {
            let h = UIHostingController(rootView: rootView)
            h.view.backgroundColor = .clear
            h.view.translatesAutoresizingMaskIntoConstraints = false
            // Implicit Animation auch am Hosting-Layer deaktivieren
            h.view.layer.actions = [
                "opacity":   NSNull(),
                "position":  NSNull(),
                "bounds":    NSNull(),
                "transform": NSNull(),
                "contents":  NSNull(),
            ]
            addSubview(h.view)
            NSLayoutConstraint.activate([
                h.view.centerXAnchor.constraint(equalTo: centerXAnchor),
                h.view.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            host = h
        }

        // SwiftUI-View kann selbst-sized werden — eigene Frame-Größe daraus ableiten
        // damit MKMapView den Touch-Hitbox-Bereich richtig setzt.
        // layoutIfNeeded() reicht NICHT wenn die View noch nicht im Window-Hierarchy
        // ist (z.B. beim ersten viewFor-annotation-Aufruf) → size wäre .zero → kein
        // Tap-Bereich. Daher: sofort versuchen, bei .zero auf nächsten Run-Loop warten.
        host?.view.layoutIfNeeded()
        let immediateSize = host?.view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            ?? CGSize(width: 60, height: 60)
        if immediateSize.width > 4 && immediateSize.height > 4 {
            bounds = CGRect(origin: .zero, size: immediateSize)
        } else {
            // Noch nicht gemessen — nächsten Run-Loop abwarten
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let h = self.host else { return }
                h.view.layoutIfNeeded()
                let size = h.view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
                if size.width > 4 && size.height > 4 {
                    self.bounds = CGRect(origin: .zero, size: size)
                }
            }
        }
        centerOffset = CGPoint(x: 0, y: 0)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onTap = nil
    }
}

/// Referenz-Box die die echte MKMapView hält. Damit kann der polygonsProvider-
/// Closure des Aurora-Overlays bei jedem 12fps-Tick convert() direkt aufrufen
/// statt einen statischen Snapshot zu nutzen — Overlay folgt der Kamera live.
final class MapViewBox {
    weak var mapView: MKMapView?
}

/// SwiftUI-Wrapper um MKMapView. Drop-Pins werden nativ verwaltet — kein Wobble
/// beim Pannen.
struct MapKitMapView: UIViewRepresentable {
    /// Einweg-Intent: non-nil → Kamera dorthin bewegen, danach auto-clear.
    /// Nil → Map frei scrollbar ohne SwiftUI-Interference.
    @Binding var targetRegion: MKCoordinateRegion?
    let annotations: [MapAnnotationItem]
    let myToken: String
    let confirmedTokens: Set<String>
    let isJoinedProvider: (UUID) -> Bool
    let onTapAnnotation: (MapAnnotationItem) -> Void
    let onCameraChange: ((MKMapView) -> Void)?
    let preferredColorScheme: ColorScheme?
    /// Wird in makeUIView befüllt — ermöglicht Live-Koordinaten-Konvertierung
    /// außerhalb von updateUIView (z.B. polygonsProvider im Aurora-Overlay).
    let mapViewBox: MapViewBox

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        mapViewBox.mapView = map
        map.showsUserLocation = true
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        // POI-Filter analog zur SwiftUI-Map: kuratierte Hangout-Spots
        map.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .cafe, .restaurant, .bakery, .brewery, .winery,
            .nightlife, .museum, .park, .beach, .amusementPark,
        ])
        map.register(MapKitDropAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: MapKitDropAnnotationView.reuseID)
        // Initialer Zoom kommt via targetRegion (userLocation-onAppear).
        // Default: München-Mitte als Fallback bis GPS verfügbar.
        let defaultRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.1371, longitude: 11.5754),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
        map.setRegion(targetRegion ?? defaultRegion, animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self

        // ── Programmatischer Kamera-Intent ──
        // targetRegion ist nur non-nil wenn jemand die Kamera explizit bewegen
        // will (Initial-Zoom, focusedDrop, Cluster-Zoom). Einmalig konsumieren
        // und sofort clearen — kein Feedback-Loop, kein Überschreiben von Gesten.
        if let target = targetRegion {
            map.setRegion(target, animated: true)
            DispatchQueue.main.async { self.targetRegion = nil }
        }

        // ── Annotation-Diff ──
        let current = map.annotations.compactMap { $0 as? MapKitDropAnnotation }
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.item.id, $0) })
        let newIDs = Set(annotations.map { $0.id })

        // Entfernen was nicht mehr da ist
        let toRemove = current.filter { !newIDs.contains($0.item.id) }
        if !toRemove.isEmpty { map.removeAnnotations(toRemove) }

        // Hinzufügen neue
        let toAdd = annotations.compactMap { item -> MapKitDropAnnotation? in
            currentByID[item.id] == nil ? MapKitDropAnnotation(item: item) : nil
        }
        if !toAdd.isEmpty { map.addAnnotations(toAdd) }

        // Update existierende — aber NUR wenn sich render-relevante Felder
        // geändert haben. updateUIView läuft sonst alle paar Sekunden durch
        // (Location-Updates), und ein blindes view.configure() würde alle
        // Pins kurz aufblitzen lassen.
        for item in annotations {
            if let anno = currentByID[item.id] {
                // Koord-Änderung? Über willChangeValue für KVO (MapKit observed).
                let oldCoord = anno.coordinate
                if abs(oldCoord.latitude - item.coordinate.latitude) > 0.00001
                || abs(oldCoord.longitude - item.coordinate.longitude) > 0.00001 {
                    anno.willChangeValue(forKey: "coordinate")
                    anno.item = item
                    anno.didChangeValue(forKey: "coordinate")
                } else {
                    anno.item = item
                }
                let isJoined = isJoinedProvider(item.id)
                let key = annotationRenderKey(item, isJoined: isJoined)
                if key != anno.lastRenderKey {
                    if let view = map.view(for: anno) as? MapKitDropAnnotationView {
                        view.configure(
                            item: item,
                            isJoined: isJoined,
                            myToken: myToken,
                            confirmedTokens: confirmedTokens,
                            onTap: { onTapAnnotation(item) }
                        )
                    }
                    anno.lastRenderKey = key
                }
            }
        }

        // Dark/Light Mode — nur setzen wenn anders als aktuell, sonst triggert
        // jeder updateUIView ein UIKit-Layout-Pass auf der MapView.
        let targetStyle: UIUserInterfaceStyle = preferredColorScheme.map {
            $0 == .dark ? .dark : .light
        } ?? .unspecified
        if map.overrideUserInterfaceStyle != targetStyle {
            map.overrideUserInterfaceStyle = targetStyle
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapKitMapView
        /// Debounce: Cluster-Recompute 150ms nach letztem regionDidChange.
        /// Verhindert O(n²)-Arbeit auf jedem Pan-Frame.
        private var pendingClusterWork: DispatchWorkItem?

        init(_ parent: MapKitMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Kein Region-Sync zurück zu SwiftUI — targetRegion ist ein
            // Einweg-Intent, nicht ein Two-Way-Binding. Dadurch: null Re-Renders
            // während des Pannens, kein Kamera-Sprung durch stale State.
            pendingClusterWork?.cancel()
            let work = DispatchWorkItem { [weak self, weak mapView] in
                guard let self = self, let mapView = mapView else { return }
                self.parent.onCameraChange?(mapView)
            }
            pendingClusterWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // User-Location: Blue Dot bleibt, aber Callout aus — sonst öffnet
            // sich beim Tap ein grauer Placeholder-Bubble über dem Avatar-Pin,
            // der mit der Runde nichts zu tun hat.
            if let userLoc = annotation as? MKUserLocation {
                let id = "userLocation"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKUserLocationView(annotation: userLoc, reuseIdentifier: id)
                v.canShowCallout = false
                v.isEnabled = false
                return v
            }
            guard let drop = annotation as? MapKitDropAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: MapKitDropAnnotationView.reuseID, for: drop
            ) as? MapKitDropAnnotationView
            let isJoined = parent.isJoinedProvider(drop.item.id)
            view?.configure(
                item: drop.item,
                isJoined: isJoined,
                myToken: parent.myToken,
                confirmedTokens: parent.confirmedTokens,
                onTap: { [weak self] in self?.parent.onTapAnnotation(drop.item) }
            )
            drop.lastRenderKey = annotationRenderKey(drop.item, isJoined: isJoined)
            return view
        }
    }
}

// MARK: - Pin Picker Map (V1 Live-View)

/// MKMapView-Wrapper mit Long-Press-Gesture zum Setzen eines neuen Pins.
/// Zeigt den bestehenden Drop-Pin orange und den neu gewählten Pin violett.
struct PinPickerMap: UIViewRepresentable {
    let initialCenter: CLLocationCoordinate2D
    let existingPin: CLLocationCoordinate2D
    @Binding var selectedCoord: CLLocationCoordinate2D?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.showsUserLocation = true
        let region = MKCoordinateRegion(
            center: initialCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        )
        map.setRegion(region, animated: false)
        map.delegate = context.coordinator

        let existing = PinAnnotation(coordinate: existingPin, isNew: false)
        map.addAnnotation(existing)

        let lp = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        lp.minimumPressDuration = 0.3
        map.addGestureRecognizer(lp)
        context.coordinator.map = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let newPins = map.annotations.compactMap { $0 as? PinAnnotation }.filter { $0.isNew }
        map.removeAnnotations(newPins)
        if let coord = selectedCoord {
            let pin = PinAnnotation(coordinate: coord, isNew: true)
            map.addAnnotation(pin)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: PinPickerMap
        weak var map: MKMapView?
        init(_ parent: PinPickerMap) { self.parent = parent }

        @objc func handleLongPress(_ gr: UILongPressGestureRecognizer) {
            guard gr.state == .began, let map = map else { return }
            let point = gr.location(in: map)
            let coord = map.convert(point, toCoordinateFrom: map)
            parent.selectedCoord = coord
            Haptic.selection()
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? PinAnnotation else { return nil }
            let id = pin.isNew ? "newPin" : "existingPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: pin, reuseIdentifier: id)
            view.annotation = pin
            let color: UIColor = pin.isNew
                ? UIColor(red: 0.357, green: 0.239, blue: 0.961, alpha: 1.0)
                : UIColor(red: 1.000, green: 0.627, blue: 0.180, alpha: 1.0)
            let size: CGFloat = pin.isNew ? 28 : 22
            let container = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
            container.backgroundColor = color
            container.layer.cornerRadius = size / 2
            container.layer.borderWidth = 3
            container.layer.borderColor = UIColor.white.cgColor
            container.layer.shadowColor = color.cgColor
            container.layer.shadowOpacity = 0.5
            container.layer.shadowRadius = 6
            container.layer.shadowOffset = CGSize(width: 0, height: 2)
            view.subviews.forEach { $0.removeFromSuperview() }
            view.frame = container.frame
            view.addSubview(container)
            view.centerOffset = CGPoint(x: 0, y: -size / 2)
            return view
        }
    }

    final class PinAnnotation: NSObject, MKAnnotation {
        let coordinate: CLLocationCoordinate2D
        let isNew: Bool
        init(coordinate: CLLocationCoordinate2D, isNew: Bool) {
            self.coordinate = coordinate
            self.isNew = isNew
        }
    }
}
