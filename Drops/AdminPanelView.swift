import SwiftUI
import FirebaseAuth
import FirebaseDatabase
import FirebaseStorage
import UserNotifications

// MARK: - Admin Panel

struct AdminPanelView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var users: [AdminUserEntry] = []
    @State private var stats: AdminStats? = nil
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var activeFilter: UserFilter = .all
    @State private var sortMode: SortMode = .createdAt
    @State private var confirmAction: ConfirmAction? = nil
    @State private var selectedUser: AdminUserEntry? = nil
    @State private var auroraAnimate = false
    @State private var showReports = false
    @State private var showDropsMonitor = false
    @State private var showCommunityRequests = false
    @State private var pendingCommunityCount = 0
    @State private var debugResetToast: String? = nil
    @State private var isWipingPastDrops = false
    @State private var nameChangeRequests: [RealtimeDBManager.NameChangeRequest] = []
    // Demo-Drops Toggle: spiegelt /config/demoDropsEnabled in RTDB.
    // Schreibt direkt zurück bei Toggle-Änderung (admin-only via security rule).
    @State private var demoDropsEnabled: Bool = true
    @State private var demoDropsConfigLoaded: Bool = false

    enum UserFilter { case all, banned, active, plus }
    enum SortMode: String, CaseIterable, Identifiable {
        case createdAt   // Neueste zuerst (Default)
        case city        // A→Z nach Stadt, dann name
        case name        // A→Z nach Name
        var id: String { rawValue }
        var label: String {
            switch self {
            case .createdAt: return "Neueste"
            case .city:      return "Stadt"
            case .name:      return "Name"
            }
        }
    }

    /// UserDefaults-Keys, die beim Debug-Reset zurückgesetzt werden.
    private static let debugResetKeys: [String] = [
        "ud_pushReaskShown",
        "ud_firstDrop_created",
        "ud_firstDrop_joined",
        "hasSeenWelcome",
    ]

    private var debugResetSubtitle: String {
        if let toast = debugResetToast { return toast }
        return "Konfetti, Push-Reask, Welcome neu auslösen"
    }

    private func resetOnboardingFlags() {
        let ud = UserDefaults.standard
        Self.debugResetKeys.forEach { ud.removeObject(forKey: $0) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        debugResetToast = "Zurückgesetzt ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            debugResetToast = nil
        }
    }

    struct ConfirmAction: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let destructive: Bool
        let action: () -> Void
    }

    var filteredUsers: [AdminUserEntry] {
        var base = users
        switch activeFilter {
        case .all:    break
        case .banned: base = base.filter { $0.isBanned }
        case .active: base = base.filter { $0.hasActiveDrop }
        case .plus:   base = base.filter { $0.isPlusUser }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            base = base.filter {
                $0.name.lowercased().contains(q) ||
                $0.email.lowercased().contains(q) ||
                $0.phoneNumber.lowercased().contains(q) ||
                $0.id.lowercased().hasPrefix(q)        // UID-Prefix-Match
            }
        }
        switch sortMode {
        case .createdAt:
            base.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .city:
            // Stadt A→Z, "—" (keine Stadt) ans Ende; Tiebreaker = Name
            base.sort { lhs, rhs in
                let l = lhs.cityName ?? "zzz_unknown"
                let r = rhs.cityName ?? "zzz_unknown"
                if l == r { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
                return l.localizedCaseInsensitiveCompare(r) == .orderedAscending
            }
        case .name:
            base.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return base
    }

    /// Nach Stadt gruppierte Nutzer für den Sort-Modus `.city`. Reihenfolge:
    /// Städte alphabetisch (A→Z), Section „Ohne Stadt" (key == nil) immer
    /// ans Ende. Innerhalb einer Stadt sind die User nach Name sortiert.
    /// Verwendet `filteredUsers` als Quelle, damit Such-/Filter-Chips
    /// auch innerhalb der Gruppen wirken.
    private struct CityGroup {
        let key: String?
        let users: [AdminUserEntry]
    }
    private var groupedByCity: [CityGroup] {
        var buckets: [String?: [AdminUserEntry]] = [:]
        for u in filteredUsers {
            buckets[u.cityName, default: []].append(u)
        }
        let withCity = buckets
            .compactMap { (key, users) -> CityGroup? in
                guard let k = key else { return nil }
                let sorted = users.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return CityGroup(key: k, users: sorted)
            }
            .sorted { ($0.key ?? "") .localizedCaseInsensitiveCompare($1.key ?? "") == .orderedAscending }

        var result = withCity
        if let noCity = buckets[nil], !noCity.isEmpty {
            let sorted = noCity.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            result.append(CityGroup(key: nil, users: sorted))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // ── Stat-Kacheln ──────────────────────────────────────
                    if let s = stats {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 12
                        ) {
                            AdminStatCard(
                                title: "Nutzer gesamt",
                                value: "\(s.totalUsers)",
                                icon: "person.3.fill",
                                color: .blue,
                                isActive: activeFilter == .all
                            ) {
                                withAnimation(.spring(response: 0.3)) { activeFilter = .all }
                            }
                            AdminStatCard(
                                title: "Aktive Runden",
                                value: "\(s.activeDrops)",
                                icon: "dot.radiowaves.left.and.right",
                                color: .green,
                                isActive: activeFilter == .active
                            ) {
                                withAnimation(.spring(response: 0.3)) { activeFilter = .active }
                            }
                            AdminStatCard(
                                title: "Gesperrt",
                                value: "\(s.bannedUsers)",
                                icon: "xmark.shield.fill",
                                color: .red,
                                isActive: activeFilter == .banned
                            ) {
                                withAnimation(.spring(response: 0.3)) { activeFilter = .banned }
                            }
                            AdminStatCard(
                                title: "dazu+",
                                value: "\(users.filter { $0.isPlusUser }.count)",
                                icon: "star.fill",
                                color: .yellow,
                                isActive: activeFilter == .plus
                            ) {
                                withAnimation(.spring(response: 0.3)) { activeFilter = .plus }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Namensänderungsanfragen
                        if !nameChangeRequests.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    DazuIcon("person.text.rectangle.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.brand)
                                    Text("Namensänderungen")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("\(nameChangeRequests.count)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.brand))
                                }
                                .padding(.horizontal, 16).padding(.top, 14)

                                ForEach(nameChangeRequests) { req in
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(req.oldName)
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.textSecondary)
                                                DazuIcon("arrow.right")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.textTertiary)
                                                Text(req.newName)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(.textPrimary)
                                            }
                                            Text(req.uid.prefix(12) + "…")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.textTertiary)
                                        }
                                        Spacer()
                                        // Ablehnen
                                        Button {
                                            RealtimeDBManager.shared.denyNameChange(uid: req.uid) {
                                                DispatchQueue.main.async {
                                                    nameChangeRequests.removeAll { $0.uid == req.uid }
                                                }
                                            }
                                        } label: {
                                            DazuIcon("xmark.circle.fill")
                                                .font(.system(size: 22))
                                                .foregroundColor(.accentRed.opacity(0.8))
                                        }
                                        // Genehmigen
                                        Button {
                                            RealtimeDBManager.shared.approveNameChange(uid: req.uid, newName: req.newName) {
                                                DispatchQueue.main.async {
                                                    nameChangeRequests.removeAll { $0.uid == req.uid }
                                                    // Falls eigener Account → lokal auch updaten
                                                    if req.uid == FirebaseAuth.Auth.auth().currentUser?.uid {
                                                        store.currentUser.name = req.newName.capitalizedFirst
                                                        store.pendingNameChange = nil
                                                        store.saveAll()
                                                    }
                                                }
                                            }
                                        } label: {
                                            DazuIcon("checkmark.circle.fill")
                                                .font(.system(size: 22))
                                                .foregroundColor(.onlineGreen)
                                        }
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                    .background(Color.bgCard,
                                                in: RoundedRectangle(cornerRadius: 12))
                                    .padding(.horizontal, 16)
                                }
                                .padding(.bottom, 8)
                            }
                            .background(Color.bgGrouped,
                                        in: RoundedRectangle(cornerRadius: Radius.lg))
                            .padding(.horizontal, 20)
                        }

                        // Meldungen — öffnet separates Sheet
                        Button {
                            showReports = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .fill(Color.accentOrange.opacity(0.15))
                                        .frame(width: 40, height: 40)
                                    DazuIcon("flag.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.accentOrange)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("Meldungen")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.textPrimary)
                                        if s.openReports > 0 {
                                            Text("\(s.openReports)")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 7).padding(.vertical, 2)
                                                .background(Capsule().fill(Color.accentRed))
                                        }
                                    }
                                    Text(s.openReports == 0 ? "Keine offenen Meldungen" : "\(s.openReports) offen")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                                DazuIcon("chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                            }
                            .padding(12)
                            .liquidGlass(cornerRadius: 14)
                            .padding(.horizontal, 20)
                        }
                        .dropsPressable()

                        // Debug: Onboarding-Flags zurücksetzen — für Demo/Testing.
                        // Setzt alle einmaligen Trigger zurück (Konfetti, Push-Reask, Welcome).
                        Button {
                            resetOnboardingFlags()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .fill(Color.purple.opacity(0.15))
                                        .frame(width: 40, height: 40)
                                    DazuIcon("arrow.counterclockwise.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.purple)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Debug — Onboarding zurücksetzen")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                    Text(debugResetSubtitle)
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                                DazuIcon("chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                            }
                            .padding(12)
                            .liquidGlass(cornerRadius: 14)
                            .padding(.horizontal, 20)
                        }
                        .dropsPressable()

                        // Power-Hour-Toggle entfernt — Feature wurde eingestampft.

                        // Demo-Drops-Toggle: schreibt /config/demoDropsEnabled.
                        // Cloud Function seedDemoDrops liest den Flag bei jedem
                        // Cron-Run (stündlich). Off → keine neuen Demos mehr;
                        // bestehende werden via 4h-TTL natürlich ausgeräumt.
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .fill(Color.brand.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                DazuIcon("sparkles")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.brand)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Demo-Runden")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text(demoDropsEnabled
                                     ? "Aktiv — stündlich ~15-25 Ghosts in 5 Städten"
                                     : "Aus — keine neuen Demos werden generiert")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { demoDropsEnabled },
                                set: { newVal in
                                    demoDropsEnabled = newVal
                                    // Nicht schreiben bevor der Initial-Load fertig ist
                                    // (sonst überschreibt der Default-true den Server-Wert).
                                    guard demoDropsConfigLoaded else { return }
                                    Database.database()
                                        .reference()
                                        .child("config")
                                        .child("demoDropsEnabled")
                                        .setValue(newVal)
                                }
                            ))
                            .tint(.brand)
                            .labelsHidden()
                            .disabled(!demoDropsConfigLoaded)
                        }
                        .padding(12)
                        .liquidGlass(cornerRadius: 14)
                        .padding(.horizontal, 20)
                        .onAppear {
                            // Aktuellen Server-Wert holen (default true falls Knoten fehlt).
                            Database.database()
                                .reference()
                                .child("config")
                                .child("demoDropsEnabled")
                                .observeSingleEvent(of: .value) { snap in
                                    let raw = snap.value
                                    if let b = raw as? Bool { demoDropsEnabled = b }
                                    else { demoDropsEnabled = true }
                                    demoDropsConfigLoaded = true
                                }
                        }


                        // Live Drops Monitor — öffnet Sheet
                        Button {
                            showDropsMonitor = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .fill(Color.brand.opacity(0.15))
                                        .frame(width: 40, height: 40)
                                    DazuIcon("dot.radiowaves.left.and.right")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.brand)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Live-Monitor")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("Aktuelle Runden anschauen & moderieren")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                                DazuIcon("chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                            }
                            .padding(12)
                            .liquidGlass(cornerRadius: 14)
                            .padding(.horizontal, 20)
                        }
                        .dropsPressable()

                        // Meine eigenen vergangenen Runden löschen — Firebase
                        // (`users/{myUID}/pastDrops`) + lokaler UserDefaults-
                        // Cache, damit Profil, Stats und Suggested-Spots
                        // auf der Karte sofort leer sind. Nur eigenes Konto,
                        // andere User nicht betroffen (dafür: Admin → User-Detail).
                        Button {
                            confirmAction = ConfirmAction(
                                title: "Meine vergangenen Runden löschen?",
                                message: "Löscht deine Historie aus Firebase und dem lokalen Cache. Nicht rückgängig machbar.",
                                destructive: true,
                                action: {
                                    guard let myUID = Auth.auth().currentUser?.uid else { return }
                                    isWipingPastDrops = true
                                    RealtimeDBManager.shared.wipePastDrops(forUID: myUID) { ok in
                                        store.pastDrops.removeAll()
                                        UserDefaults.standard.removeObject(forKey: "ud_pastDrops")
                                        isWipingPastDrops = false
                                        debugResetToast = ok ? "Deine Historie gelöscht" : "Fehler beim Löschen in Firebase"
                                    }
                                }
                            )
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .fill(Color.red.opacity(0.15))
                                        .frame(width: 40, height: 40)
                                    if isWipingPastDrops {
                                        ProgressView()
                                            .scaleEffect(0.75)
                                            .tint(.red)
                                    } else {
                                        DazuIcon("trash.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.red)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Meine vergangenen Runden löschen")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("Firebase + lokaler Cache — nur dein Konto")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                                DazuIcon("chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                            }
                            .padding(12)
                            .liquidGlass(cornerRadius: 14)
                            .padding(.horizontal, 20)
                        }
                        .dropsPressable()
                        .disabled(isWipingPastDrops)

                        // Demo-Daten seeden: 11 Mock-Freunde + 12 pastDrops
                        // für App-Store-Screenshots. Lädt Avatar-URLs aus
                        // Firebase Storage (demo/avatars/avatar_01-11.jpg)
                        // und baut Freundschaftsbeziehungen + Historie auf.
                        Button {
                            seedDemoData()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .fill(Color.brandViolet.opacity(0.18))
                                        .frame(width: 40, height: 40)
                                    DazuIcon("wand.and.stars")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.brandViolet)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Demo-Daten seeden")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("11 Mock-Freunde + 12 vergangene Runden")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                DazuIcon("chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                            }
                            .padding(12)
                            .liquidGlass(cornerRadius: 14)
                            .padding(.horizontal, 20)
                        }
                        .dropsPressable()

                        // Aktive Demo-Runden auf der Karte + Umgebung: 6 Pins
                        // mit Mock-Freunden als Hosts, verteilt auf München.
                        // Werden als isDemo=true markiert, laufen 4h.
                        Button {
                            seedLiveDemoDrops()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .fill(Color.accentOrange.opacity(0.18))
                                        .frame(width: 40, height: 40)
                                    DazuIcon("mappin.and.ellipse")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.accentOrange)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Live-Runden auf Karte seeden")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("6 aktive Runden, Mock-Freunde als Hosts, 4h TTL")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                DazuIcon("chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                            }
                            .padding(12)
                            .liquidGlass(cornerRadius: 14)
                            .padding(.horizontal, 20)
                        }
                        .dropsPressable()

                        // Räumt alle Demo-Drops (isDemo:true) sofort aus RTDB.
                        // Nutzt die existierende `purgeDemoDrops` Cloud Function.
                        Button {
                            purgeDemoDrops()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .fill(Color.red.opacity(0.15))
                                        .frame(width: 40, height: 40)
                                    DazuIcon("trash.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.red)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Demo-Drops auf Karte löschen")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("Räumt alle isDemo:true-Pins sofort")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                DazuIcon("chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                            }
                            .padding(12)
                            .liquidGlass(cornerRadius: 14)
                            .padding(.horizontal, 20)
                        }
                        .dropsPressable()

                        // Push-Debug: triggert mit 3-5s Delay echte iOS-
                        // Notifications. Zum Testen App zuklappen oder Handy
                        // sperren — Push erscheint als Banner, Dynamic Island
                        // oder auf dem Sperrbildschirm. Jeder Tap = andere Variante.
                        Button {
                            sendTestPush()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .fill(Color.brandOrange.opacity(0.18))
                                        .frame(width: 40, height: 40)
                                    DazuIcon("bell.badge.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.brandOrange)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Test-Push senden")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("5s Delay — App schließen, erscheint als iOS-Push")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                DazuIcon("chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                            }
                            .padding(12)
                            .liquidGlass(cornerRadius: 14)
                            .padding(.horizontal, 20)
                        }
                        .dropsPressable()

                        // Community-Anträge — Creator-Bewerbungen genehmigen/ablehnen
                        if FeatureFlags.communitiesEnabled {
                        Button {
                            showCommunityRequests = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .fill(Color.brand.opacity(0.15))
                                        .frame(width: 40, height: 40)
                                    DazuIcon("star.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.brand)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("Community-Anträge")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.textPrimary)
                                        if pendingCommunityCount > 0 {
                                            Text("\(pendingCommunityCount)")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 7).padding(.vertical, 2)
                                                .background(Capsule().fill(Color.brand))
                                        }
                                    }
                                    Text(pendingCommunityCount == 0
                                         ? "Keine offenen Anträge"
                                         : "\(pendingCommunityCount) offen")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                                DazuIcon("chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                            }
                            .padding(12)
                            .liquidGlass(cornerRadius: 14)
                            .padding(.horizontal, 20)
                        }
                        .dropsPressable()
                        }
                    }

                    // ── Suchfeld ──────────────────────────────────────────
                    HStack(spacing: 10) {
                        DazuIcon("magnifyingglass")
                            .foregroundColor(.textTertiary)
                            .font(.system(size: 15))
                        TextField("Name, Telefon, E-Mail oder UID", text: $searchText)
                            .font(.system(size: 15))
                            .foregroundColor(.textPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                DazuIcon("xmark.circle.fill")
                                    .foregroundColor(.textTertiary)
                            }
                        }
                    }
                    .padding(12)
                    .liquidGlass(cornerRadius: 14)
                    .padding(.horizontal, 20)

                    // ── Sortier-Picker ────────────────────────────────────
                    HStack(spacing: 8) {
                        DazuIcon("arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textSecondary)
                        Text("Sortieren:")
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                        Picker("Sortierung", selection: $sortMode) {
                            ForEach(SortMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal, 20)

                    // ── Nutzerliste ───────────────────────────────────────
                    if isLoading {
                        VStack(spacing: 12) {
                            DazuLoader().tint(.brand)
                            Text("Lade Daten…")
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else if filteredUsers.isEmpty {
                        VStack(spacing: 12) {
                            DazuIcon("person.slash")
                                .font(.system(size: 36))
                                .foregroundColor(.textTertiary)
                            Text(searchText.isEmpty ? "Keine Nutzer" : "Keine Treffer")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else if sortMode == .city {
                        // Stadt-Modus: nach Stadt gruppieren, jede Gruppe
                        // mit eigener Header-Zeile (Stadtname + Anzahl).
                        // Innerhalb einer Gruppe nach Name sortiert. Nutzer
                        // ohne Stadt landen in der Section „Ohne Stadt"
                        // ganz am Ende.
                        LazyVStack(spacing: 18) {
                            ForEach(groupedByCity, id: \.key) { group in
                                VStack(spacing: 10) {
                                    HStack(spacing: 8) {
                                        DazuIcon("mappin.circle.fill", accent: false)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(group.key == nil ? .textTertiary : .blue)
                                        Text(group.key ?? "Ohne Stadt")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(.textPrimary)
                                        Text("\(group.users.count)")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.textSecondary)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(Color.primary.opacity(0.08), in: Capsule())
                                        Spacer()
                                    }
                                    .padding(.horizontal, 4)

                                    LazyVStack(spacing: 10) {
                                        ForEach(group.users) { user in
                                            AdminUserCard(user: user) {
                                                selectedUser = user
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredUsers) { user in
                                AdminUserCard(user: user) {
                                    selectedUser = user
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, 12)
            }
            .background(
                ZStack {
                    Color.bgPrimary
                    // Aurora — im Hintergrund, beeinflusst Layout nicht
                    ZStack {
                        Circle()
                            .fill(Color.brand.opacity(0.18))
                            .frame(width: 300, height: 300)
                            .blur(radius: 80)
                            .offset(x: auroraAnimate ? 60 : -20, y: auroraAnimate ? -60 : -100)
                        Circle()
                            .fill(Color.accentOrange.opacity(0.10))
                            .frame(width: 220, height: 220)
                            .blur(radius: 60)
                            .offset(x: auroraAnimate ? -50 : 30, y: auroraAnimate ? -20 : -80)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea()
            )
            .navigationTitle("Admin Panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        DazuIcon("xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.tertiary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation { isLoading = true }
                        loadData()
                    } label: {
                        DazuIcon("arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.brand)
                    }
                }
            }
            .confirmationDialog(
                confirmAction?.title ?? "",
                isPresented: Binding(
                    get: { confirmAction != nil },
                    set: { if !$0 { confirmAction = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let ca = confirmAction {
                    Button(ca.title, role: ca.destructive ? .destructive : .none) { ca.action() }
                    Button("Abbrechen", role: .cancel) { confirmAction = nil }
                }
            } message: {
                Text(confirmAction?.message ?? "")
            }
            .sheet(item: $selectedUser) { user in
                AdminUserDetailSheet(
                    user: user,
                    onTogglePlus: {
                        selectedUser = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            confirmAction = ConfirmAction(
                                title: user.isPlusUser ? "dazu+ entziehen" : "dazu+ freischalten",
                                message: user.isPlusUser
                                    ? "\(user.name) den Plus-Zugang entziehen?"
                                    : "\(user.name) dazu+ kostenlos freischalten?",
                                destructive: user.isPlusUser,
                                action: {
                                    let newPlus = !user.isPlusUser
                                    RealtimeDBManager.shared.adminSetPlus(uid: user.id, isPlus: newPlus) { loadData() }
                                    // Wenn der Admin sich selbst freischaltet/entzieht: lokalen State sofort updaten
                                    if user.id == Auth.auth().currentUser?.uid {
                                        store.isPlusUser = newPlus
                                        // Success-Popup nur bei Aktivierung — Admin-Panel schließen, dann anzeigen
                                        if newPlus {
                                            dismiss()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                                store.showDropsPlusSuccess = true
                                            }
                                        }
                                    }
                                }
                            )
                        }
                    },
                    onEndDrop: user.activeDropID == nil ? nil : {
                        selectedUser = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            confirmAction = ConfirmAction(
                                title: "Plan beenden",
                                message: "Den aktiven Plan von \(user.name) sofort beenden?",
                                destructive: true,
                                action: {
                                    guard let dropID = user.activeDropID else { return }
                                    RealtimeDBManager.shared.adminEndDrop(dropID: dropID) { loadData() }
                                }
                            )
                        }
                    },
                    onBan: {
                        selectedUser = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            confirmAction = ConfirmAction(
                                title: user.isBanned ? "Sperre aufheben" : "User sperren",
                                message: user.isBanned
                                    ? "\(user.name) wieder freischalten?"
                                    : "\(user.name) sperren? Kein Login mehr möglich.",
                                destructive: !user.isBanned,
                                action: {
                                    RealtimeDBManager.shared.adminSetBan(uid: user.id, banned: !user.isBanned) { loadData() }
                                }
                            )
                        }
                    },
                    onToggleAdmin: {
                        selectedUser = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            confirmAction = ConfirmAction(
                                title: user.isAdmin ? "Admin-Rechte entziehen" : "Zum Admin machen",
                                message: "\(user.name) \(user.isAdmin ? "Admin-Rechte entziehen" : "zum Admin ernennen")?",
                                destructive: false,
                                action: {
                                    RealtimeDBManager.shared.adminSetAdmin(uid: user.id, isAdmin: !user.isAdmin) { loadData() }
                                }
                            )
                        }
                    },
                    onDelete: {
                        selectedUser = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            confirmAction = ConfirmAction(
                                title: "Nutzer löschen",
                                message: "\(user.name) dauerhaft löschen? Nicht rückgängig machbar.",
                                destructive: true,
                                action: {
                                    RealtimeDBManager.shared.adminDeleteUser(uid: user.id) { loadData() }
                                }
                            )
                        }
                    },
                    onWipePastDrops: {
                        selectedUser = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            confirmAction = ConfirmAction(
                                title: "Vergangene Runden löschen",
                                message: "\(user.name): komplette Historie aus Firebase löschen? Nicht rückgängig machbar.",
                                destructive: true,
                                action: {
                                    RealtimeDBManager.shared.wipePastDrops(forUID: user.id) { ok in
                                        // Wenn der betroffene User man selbst ist: lokalen Cache gleich mitputzen
                                        if user.id == Auth.auth().currentUser?.uid {
                                            store.pastDrops.removeAll()
                                            UserDefaults.standard.removeObject(forKey: "ud_pastDrops")
                                        }
                                        debugResetToast = ok ? "Historie von \(user.name) gelöscht" : "Fehler beim Löschen"
                                    }
                                }
                            )
                        }
                    }
                )
            }
        }
        .onAppear {
            loadData()
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                auroraAnimate = true
            }
        }
        .sheet(isPresented: $showReports, onDismiss: { loadData() }) {
            AdminReportsSheet()
        }
        .sheet(isPresented: $showDropsMonitor, onDismiss: { loadData() }) {
            AdminDropsMonitorSheet()
        }
        .sheet(isPresented: $showCommunityRequests, onDismiss: { loadCommunityCount() }) {
            AdminCommunityRequestsSheet()
        }
    }

    // MARK: - Load

    private func loadData() {
        isLoading = true
        RealtimeDBManager.shared.adminFetchAllUsers { result in
            DispatchQueue.main.async {
                users = result
                withAnimation { isLoading = false }
            }
        }
        RealtimeDBManager.shared.adminFetchStats { result in
            DispatchQueue.main.async { stats = result }
        }
        RealtimeDBManager.shared.fetchNameChangeRequests { result in
            DispatchQueue.main.async { nameChangeRequests = result }
        }
        loadCommunityCount()
    }

    private func loadCommunityCount() {
        CommunityManager.shared.adminFetchRequests { reqs in
            pendingCommunityCount = reqs.filter { $0.status == "pending" }.count
        }
    }

    // MARK: - Demo-Daten Seed für App-Store-Screenshots

    /// Mock-Freunde + pastDrops in Dennis' Account seeden. Avatars werden
    /// aus Firebase Storage (`demo/avatars/avatar_01-11.jpg`) via downloadURL
    /// aufgelöst. Freundschaften werden in `friends/{myUID}/{mockUID}` +
    /// umgekehrt eingetragen; Mock-User-Nodes landen unter `users/mock_*`.
    /// Reversibel: Lösche `friends/{myUID}/mock_*` + `users/mock_*` von
    /// Hand in der Firebase Console, oder nutze den "Vergangene Runden
    /// löschen"-Button für die Historie.
    private func seedDemoData() {
        guard let myUID = Auth.auth().currentUser?.uid else {
            debugResetToast = "Nicht eingeloggt"
            return
        }

        struct Mock { let id: String; let name: String; let age: Int; let gender: String; let avatarPath: String }
        let mocks: [Mock] = [
            .init(id: "mock_max",    name: "Max",    age: 34, gender: "männlich",  avatarPath: "random-person.jpeg"),
            .init(id: "mock_lea",    name: "Lea",    age: 28, gender: "weiblich",  avatarPath: "random-person-2.jpeg"),
            .init(id: "mock_jana",   name: "Jana",   age: 26, gender: "weiblich",  avatarPath: "random-person-9.jpeg"),
            .init(id: "mock_mia",    name: "Mia",    age: 25, gender: "weiblich",  avatarPath: "random-person-8.jpeg"),
            .init(id: "mock_leo",    name: "Leo",    age: 28, gender: "männlich",  avatarPath: "random-person-5.jpeg"),
            .init(id: "mock_sophie", name: "Sophie", age: 27, gender: "weiblich",  avatarPath: "random-person-6.jpeg"),
            .init(id: "mock_finn",   name: "Finn",   age: 25, gender: "männlich",  avatarPath: "random-person-7.jpeg"),
            .init(id: "mock_tim",    name: "Tim",    age: 30, gender: "männlich",  avatarPath: "random-person-4.jpeg"),
            .init(id: "mock_jonas",  name: "Jonas",  age: 27, gender: "männlich",  avatarPath: "random-person-3.jpeg"),
            .init(id: "mock_lisa",   name: "Lisa",   age: 24, gender: "weiblich",  avatarPath: "random-person-10.jpeg"),
            .init(id: "mock_felix",  name: "Felix",  age: 36, gender: "männlich",  avatarPath: "random-person-11.jpeg"),
        ]

        let db = Database.database().reference()
        let group = DispatchGroup()
        var urls: [String: String] = [:]   // mockID → avatarURL

        // Monogramm-Avatare (keine KI-Portraits mehr) nach
        // demoavatars/mono_<mockID>.png rendern und uploaden.
        for m in mocks {
            group.enter()
            MonogramAvatar.generateAndUpload(mockID: m.id, name: m.name) { url in
                if let s = url { urls[m.id] = s }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            // Mock-User-Nodes anlegen + Freundschaft beidseitig.
            // birthdate wird für die Alter-Anzeige in der Freundeliste
            // gebraucht (fetchUserMeta liest nicht `age`, sondern birthdate).
            // lastActiveAt als "letzter Online-Heartbeat" — gestreut 2–45 min
            // damit die Avatars glaubhaft "gerade / vor x Min online" wirken.
            let cal = Calendar.current
            let nowMs = Date().timeIntervalSince1970 * 1000
            for m in mocks {
                let avatar = urls[m.id] ?? ""
                let birthdate = cal.date(byAdding: .year, value: -m.age, to: Date()) ?? Date()
                let bdOffsetDays = Int.random(in: 0...364)
                let adjustedBirthdate = cal.date(byAdding: .day, value: -bdOffsetDays, to: birthdate) ?? birthdate
                let minutesAgo = Int.random(in: 2...45)
                let lastActiveMs = nowMs - Double(minutesAgo) * 60_000
                db.child("users").child(m.id).updateChildValues([
                    "name":            m.name,
                    "age":             m.age,
                    "gender":          m.gender,
                    "birthdate":       adjustedBirthdate.timeIntervalSince1970,
                    "profileImageURL": avatar,
                    "reliabilityPoints": Int.random(in: 180...480),
                    "lastActiveAt":    lastActiveMs,
                    "isMock":          true
                ])
                db.child("friends").child(myUID).child(m.id).setValue(true)
                db.child("friends").child(m.id).child(myUID).setValue(true)
            }

            // 12 PastDrops seeden — gemischt Host/Joiner, über 6 Wochen verteilt.
            let now = Date()
            let samples: [(String, String, String, Bool, Int)] = [
                ("☕️", "Kaffee",       "Café Katz & Maus",      true,  3),
                ("🏃", "Lauftreff",    "Englischer Garten",     false, 5),
                ("🍻", "Afterwork",    "Augustiner Keller",     false, 4),
                ("🧘", "Yoga",         "Luitpoldpark",          true,  4),
                ("🍕", "Pizza",        "L'Osteria Schwabing",   false, 3),
                ("🎾", "Padel",        "MTTC Iphitos",          true,  2),
                ("🚶", "Spaziergang",  "Isar-Ufer",             false, 4),
                ("🎬", "Kino",         "Mathäser Filmpalast",   false, 3),
                ("🧗", "Bouldern",     "Boulderwelt Ost",       true,  2),
                ("🥐", "Brunch",       "Rotkehlchen",           false, 5),
                ("🚴", "Fahrrad",      "Olympiapark",           true,  3),
                ("🍵", "Matcha",       "Man Versus Machine",    false, 2),
            ]
            let myName = store.currentUser.name.isEmpty ? "Du" : store.currentUser.name

            for (idx, s) in samples.enumerated() {
                let date = cal.date(byAdding: .day, value: -(idx * 3 + 1), to: now) ?? now
                let joinerCount = s.4 - 1
                let shuffled = mocks.shuffled().prefix(joinerCount)
                var parts: [[String: Any]] = []
                parts.append([
                    "name": myName,
                    "emoji": "🙂",
                    "reliabilityScore": 100,
                    "wasHost": s.3,
                    "didShowUp": true,
                    "profileImageURL": store.profileImageURL ?? ""
                ])
                for m in shuffled {
                    parts.append([
                        "name": m.name,
                        "emoji": "🙂",
                        "reliabilityScore": Int.random(in: 180...480),
                        "wasHost": false,
                        "didShowUp": true,
                        "profileImageURL": urls[m.id] ?? ""
                    ])
                }
                let dropID = UUID().uuidString
                db.child("users").child(myUID).child("pastDrops").child(dropID).setValue([
                    "activityEmoji":  s.0,
                    "activityName":   s.1,
                    "locationName":   s.2,
                    "date":           date.timeIntervalSince1970,
                    "wasHost":        s.3,
                    "participantCount": s.4,
                    "participantNames": parts.compactMap { $0["name"] as? String },
                    "participants":   parts,   // volle Dicts mit profileImageURL
                    "latitude":       48.137 + Double.random(in: -0.03...0.03),
                    "longitude":      11.575 + Double.random(in: -0.04...0.04)
                ]) { err, _ in
                    if let err = err {
                        print("[seed] ✗ pastDrop \(s.1): \(err.localizedDescription)")
                    } else {
                        print("[seed] ✓ pastDrop \(s.1) geschrieben")
                    }
                }
            }

            let avatarsOK = urls.count
            debugResetToast = "11 Freunde + 12 Runden geseedet (Avatars: \(avatarsOK)/11). App neu starten."
        }
    }

    /// Räumt alle Demo-Drops direkt in RTDB: alles mit `isDemo:true`
    /// (Seeder-Ghosts aus Cloud Function) ODER `isDemoLive:true` (Live-
    /// Mocks aus dem Live-Runden-Button hier). Lokaler Write statt
    /// HTTPS damit auch die neuen Live-Mocks mit erfasst werden.
    private func purgeDemoDrops() {
        let db = Database.database().reference()
        db.child("drops").observeSingleEvent(of: .value) { snap in
            var removed = 0
            for case let child as DataSnapshot in snap.children {
                guard let d = child.value as? [String: Any] else { continue }
                let isDemo     = (d["isDemo"]     as? Bool) ?? false
                let isDemoLive = (d["isDemoLive"] as? Bool) ?? false
                if isDemo || isDemoLive {
                    db.child("drops").child(child.key).removeValue()
                    removed += 1
                }
            }
            DispatchQueue.main.async {
                debugResetToast = "\(removed) Demo-Drops gelöscht"
            }
        }
    }

    /// 6 aktive Demo-Runden auf die Karte seeden — nutzt die 11 Mock-Freunde
    /// als Hosts. Pins sind isDemo=true, laufen 4h, danach räumt sie
    /// `purgeDemoDrops`-Function (oder manuell über Admin). Avatars werden
    /// aus Storage demoavatars/ geladen und als `hostProfileImageURL` eingefroren.
    private func seedLiveDemoDrops() {
        struct LiveMock {
            let userID: String   // mock_X → Freund, demo_live_X → anonymer Stranger
            let hostName: String; let hostAge: Int; let hostGender: String
            let avatarPath: String
            let emoji: String; let activity: String; let location: String
            let lat: Double; let lng: Double
            let currentParticipants: Int; let maxParticipants: Int
        }
        // 3 Drops sind von Mock-Freunden (werden als Freund + eigener Drop
        // auf der Karte angezeigt → "Live-Standorte online-Freunde"), 3
        // weitere Drops sind anonyme Stranger für Fülle.
        let liveMocks: [LiveMock] = [
            // ── 3 Freund-Drops ─────────────────────────────────────────────
            .init(userID: "mock_max",   hostName: "Max",    hostAge: 34, hostGender: "männlich", avatarPath: "random-person.jpeg",
                  emoji: "☕️", activity: "Kaffee", location: "Café Katz & Maus",
                  lat: 48.1446, lng: 11.5641, currentParticipants: 3, maxParticipants: 6),
            .init(userID: "mock_lea",   hostName: "Lea",    hostAge: 28, hostGender: "weiblich", avatarPath: "random-person-2.jpeg",
                  emoji: "🧘", activity: "Yoga", location: "Luitpoldpark",
                  lat: 48.1878, lng: 11.5681, currentParticipants: 4, maxParticipants: 8),
            .init(userID: "mock_lisa",  hostName: "Lisa",   hostAge: 24, hostGender: "weiblich", avatarPath: "random-person-10.jpeg",
                  emoji: "🍻", activity: "Afterwork", location: "Augustiner Keller",
                  lat: 48.1430, lng: 11.5540, currentParticipants: 4, maxParticipants: 10),
            // ── 3 Stranger-Drops ────────────────────────────────────────────
            .init(userID: "demo_live_jana",  hostName: "Jana",   hostAge: 26, hostGender: "weiblich", avatarPath: "random-person-9.jpeg",
                  emoji: "🥐", activity: "Brunch", location: "Rotkehlchen",
                  lat: 48.1659, lng: 11.5820, currentParticipants: 5, maxParticipants: 8),
            .init(userID: "demo_live_finn",  hostName: "Finn",   hostAge: 25, hostGender: "männlich", avatarPath: "random-person-7.jpeg",
                  emoji: "🏃", activity: "Lauftreff", location: "Englischer Garten",
                  lat: 48.1631, lng: 11.6050, currentParticipants: 6, maxParticipants: 12),
            .init(userID: "demo_live_tim",   hostName: "Tim",    hostAge: 30, hostGender: "männlich", avatarPath: "random-person-4.jpeg",
                  emoji: "🎾", activity: "Padel", location: "MTTC Iphitos",
                  lat: 48.1529, lng: 11.5420, currentParticipants: 2, maxParticipants: 4),
        ]

        let db = Database.database().reference()
        let group = DispatchGroup()
        var urls: [String: String] = [:]   // userID → avatarURL

        // Monogramm-Avatare (keine KI-Portraits mehr) – dieselbe Logik wie
        // in seedDemoData, aber unter demoavatars/mono_<userID>.png.
        for m in liveMocks {
            group.enter()
            MonogramAvatar.generateAndUpload(mockID: m.userID, name: m.hostName) { url in
                if let s = url { urls[m.userID] = s }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let now = Date()
            let expires = now.addingTimeInterval(4 * 3600)
            for (idx, m) in liveMocks.enumerated() {
                let dropID = "demolive_\(idx)_\(Int(now.timeIntervalSince1970))"
                // isDemo bewusst FALSE — isDemo-Pins werden matter/kleiner
                // gerendert ("Ghost-Look"). Für Marketing-Screenshots sollen
                // die Pins voll als Live-Runden erscheinen.
                // hostProfileImageURL bewusst NICHT setzen — dann rendert der
                // Pin das Activity-Icon (Kaffee-Tasse etc.) statt des Host-
                // Avatars → sieht wie das dazu-Logo aus, nicht wie Instagram.
                let payload: [String: Any] = [
                    "userID":                  m.userID,
                    "displayName":             m.hostName,
                    "emoji":                   m.emoji,
                    "activityName":            m.activity,
                    "locationTitle":           m.location,
                    "lat":                     m.lat,
                    "lng":                     m.lng,
                    "radius":                  500,
                    "timestamp":               now.timeIntervalSince1970 * 1000,
                    "createdAt":               now.timeIntervalSince1970 * 1000,
                    "expiresAt":               expires.timeIntervalSince1970,
                    "scheduledTime":           "Jetzt",
                    "startAt":                 now.timeIntervalSince1970,
                    "maxParticipants":         m.maxParticipants,
                    "currentParticipants":     m.currentParticipants,
                    "active":                  true,
                    "isDemoLive":              true,   // Marker für eigenen Purge
                    "hostGender":              m.hostGender,
                    "hostAge":                 m.hostAge,
                    "hostReliabilityPoints":   Int.random(in: 240...480)
                ]
                db.child("drops").child(dropID).setValue(payload) { err, _ in
                    if let err = err { print("[seedLive] ✗ \(m.activity): \(err.localizedDescription)") }
                    else { print("[seedLive] ✓ \(m.activity) @ \(m.location)") }
                }
            }
            debugResetToast = "6 Live-Runden auf Karte (Avatars: \(urls.count)/6)"
        }
    }

    /// Scheduled eine lokale Notification mit 5s Delay — iOS behandelt die
    /// wie einen echten Push (Banner, Lock-Screen, Dynamic Island), vorausgesetzt
    /// die App ist nicht im Vordergrund. Jeder Aufruf wählt zufällig einen
    /// Push-Typ aus den echten App-Events, damit du Styling + Dynamic-Island-
    /// Verhalten für jeden Fall siehst. Tipp: direkt nach Tap App zuklappen
    /// oder Side-Button drücken.
    private func sendTestPush() {
        let variants: [(type: String, title: String, body: String)] = [
            ("friend_request",      "Neue Freundschaftsanfrage", "Lisa möchte mit dir befreundet sein."),
            ("drop_nearby",         "Neu in deiner Nähe",        "Kaffee am Marienplatz — 5 Min zu Fuß."),
            ("drop_ended",          "Runde beendet",             "Deine Brunch-Runde ist zu Ende. 3 waren dabei."),
            ("drop_start_reminder", "In 15 Min geht's los",       "Dein Spaziergang startet gleich am Isar-Ufer."),
            ("community_push",      "Clero · Neue Runde",         "Max hostet eine Laufrunde im Englischen Garten."),
        ]
        let v = variants.randomElement()!
        let content = UNMutableNotificationContent()
        content.title = v.title
        content.body  = v.body
        content.sound = .default
        content.userInfo = ["type": v.type]
        let request = UNNotificationRequest(
            identifier: "testPush_\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { err in
            DispatchQueue.main.async {
                if let err = err {
                    debugResetToast = "Push-Fehler: \(err.localizedDescription)"
                } else {
                    debugResetToast = "Push kommt in 5s — App zuklappen"
                }
            }
        }
    }

}


// MARK: - User Detail Sheet

private struct AdminUserDetailSheet: View {
    let user: AdminUserEntry
    let onTogglePlus: () -> Void
    let onEndDrop: (() -> Void)?
    let onBan: () -> Void
    let onToggleAdmin: () -> Void
    let onDelete: () -> Void
    let onWipePastDrops: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Drops dieses Users in Firebase. Wird beim Sheet-Open einmalig
    /// geladen. Enthält nur Drops die noch in `drops/` liegen — vom
    /// Host gecancelte Drops sind weg (cancelDrop ruft removeValue).
    @State private var userDrops: [AdminUserDropEntry] = []
    @State private var loadingDrops = true

    /// Lokale Toggle-States für Badges — damit die UI nach dem Firebase-
    /// Write sofort flipped, auch ohne Refetch des User-Objekts.
    @State private var localBeta: Bool = false
    @State private var localTrusted: Bool = false
    @State private var localFounder: Bool = false
    @State private var localVerified: Bool = false
    @State private var localHost: Bool = false
    @State private var badgeStateInitialized = false

    private var initials: String { String(user.name.prefix(1)).uppercased() }
    private var avatarColor: Color {
        user.isBanned ? .red : user.isAdmin ? .orange : .blue
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // Avatar + Name
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(avatarColor.opacity(0.15))
                                .frame(width: 72, height: 72)
                            Text(initials)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundColor(avatarColor)
                        }

                        VStack(spacing: 4) {
                            Text(user.name)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.textPrimary)
                            if user.email != "–" {
                                Text(user.email)
                                    .font(.system(size: 14))
                                    .foregroundColor(.textSecondary)
                            }
                        }

                        HStack(spacing: 6) {
                            if let city = user.cityName {
                                AdminBadge(text: city, icon: "mappin.circle.fill", color: .blue)
                            }
                            if user.hasActiveDrop {
                                AdminBadge(text: user.activeDropActivity ?? "Plan aktiv",
                                           icon: "dot.radiowaves.left.and.right", color: .green)
                            }
                            if user.isPlusUser {
                                AdminBadge(text: "dazu+", icon: "star.fill", color: .yellow)
                            }
                            if user.isAdmin {
                                AdminBadge(text: "Admin", icon: "star.fill", color: .orange)
                            }
                            if user.isBanned {
                                AdminBadge(text: "Gesperrt", icon: "xmark.shield.fill", color: .red)
                            }
                        }
                    }
                    .padding(.top, 8)

                    // Info-Zeilen
                    VStack(spacing: 0) {
                        infoRow(icon: "person.text.rectangle", label: "UID",
                                value: String(user.id.prefix(16)) + "…")
                        if let date = user.createdAt {
                            Divider().padding(.leading, 44)
                            infoRow(icon: "calendar", label: "Registriert",
                                    value: date.formatted(.dateTime.day().month().year()))
                        }
                        if user.email != "–" {
                            Divider().padding(.leading, 44)
                            infoRow(icon: "envelope", label: "E-Mail", value: user.email)
                        }
                    }
                    .liquidGlass(cornerRadius: 18)
                    .padding(.horizontal, 20)

                    // Badge-Management (Admin-only)
                    adminBadgesSection

                    // Drops dieses Users (aktiv + in DB verbliebene)
                    userDropsSection

                    // Aktionen
                    VStack(spacing: 10) {
                        if let endDrop = onEndDrop {
                            DetailActionButton(
                                icon: "xmark.circle.fill",
                                label: "Plan beenden (\(user.activeDropActivity ?? "Aktiv"))",
                                color: .accentOrange,
                                action: endDrop
                            )
                        }
                        DetailActionButton(
                            icon: user.isPlusUser ? "star.slash.fill" : "star.fill",
                            label: user.isPlusUser ? "dazu+ entziehen" : "dazu+ freischalten",
                            color: .yellow,
                            action: onTogglePlus
                        )
                        DetailActionButton(
                            icon: user.isBanned ? "lock.open.fill" : "xmark.shield.fill",
                            label: user.isBanned ? "Sperre aufheben" : "Nutzer sperren",
                            color: user.isBanned ? .green : .red, action: onBan
                        )
                        DetailActionButton(
                            icon: "trash.circle.fill",
                            label: "Vergangene Runden löschen",
                            color: .red, action: onWipePastDrops
                        )
                        if user.id != Auth.auth().currentUser?.uid {
                            DetailActionButton(
                                icon: user.isAdmin ? "star.slash" : "star.fill",
                                label: user.isAdmin ? "Admin-Status entziehen" : "Zum Admin machen",
                                color: .orange, action: onToggleAdmin
                            )
                            DetailActionButton(
                                icon: "trash.fill",
                                label: "Nutzer löschen",
                                color: .red, action: onDelete
                            )
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 40)
                }
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle(user.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        DazuIcon("xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .onAppear { loadUserDrops() }
        }
    }

    private func loadUserDrops() {
        loadingDrops = true
        RealtimeDBManager.shared.adminFetchUserDrops(uid: user.id) { drops in
            userDrops = drops
            loadingDrops = false
        }
    }

    /// Section „Badges" — Admin kann BETA, Trust und Community-Creator
    /// manuell setzen/entziehen. Schreibt in Firestore unter
    /// `users/{uid}/badges`. Live-aktive Flags werden aus dem User-Doc
    /// nachgezogen und per Toggle sofort gesynct.
    @ViewBuilder
    private var adminBadgesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                DazuIcon("rosette")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.brandViolet)
                    .frame(width: 18)
                Text("Badges")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .kerning(0.4)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 20)

            VStack(spacing: 8) {
                badgeToggleRow(label: tr("badge.founder"), icon: "crown.fill",
                               field: "founder", binding: $localFounder)
                badgeToggleRow(label: tr("badge.verified"), icon: "checkmark.shield.fill",
                               field: "verified", binding: $localVerified)
                badgeToggleRow(label: tr("badge.trusted"), icon: "checkmark.seal.fill",
                               field: "trusted", binding: $localTrusted)
                badgeToggleRow(label: tr("badge.host"), icon: "star.fill",
                               field: "host", binding: $localHost)
                badgeToggleRow(label: tr("badge.beta"), icon: "sparkle",
                               field: "beta", binding: $localBeta)
            }
            .padding(.horizontal, 20)
            .onAppear {
                if !badgeStateInitialized {
                    localBeta     = user.hasBetaBadge
                    localTrusted  = user.hasTrustedBadge
                    localFounder  = user.hasFounderBadge
                    localVerified = user.hasVerifiedBadge
                    localHost     = user.hasHostBadge
                    badgeStateInitialized = true
                }
            }
        }
    }

    @ViewBuilder
    private func badgeToggleRow(label: String, icon: String, field: String,
                                 binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            DazuIcon(icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.brandViolet)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.brandLavender))
            Text(label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.textPrimary)
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(.brandOrange)
                .onChange(of: binding.wrappedValue) { _, newValue in
                    RealtimeDBManager.shared.adminSetBadge(uid: user.id,
                                                           field: field,
                                                           value: newValue,
                                                           completion: nil)
                }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .liquidGlass(cornerRadius: 16)
    }

    /// Section „Erstellte Drops" — listet alle Drops die noch in `drops/`
    /// liegen (live, abgelaufen, vom Admin beendet). Cancelled Drops
    /// (Host hat „Drop beenden" gedrückt) sind via removeValue gelöscht
    /// und tauchen hier NICHT auf — Hinweis-Footer macht das klar.
    @ViewBuilder
    private var userDropsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                DazuIcon("list.bullet.rectangle.portrait")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentOrange)
                    .frame(width: 18)
                Text("Erstellte Runden")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .kerning(0.4)
                    .textCase(.uppercase)
                Spacer()
                if !loadingDrops {
                    Text("\(userDrops.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 4)

            VStack(spacing: 0) {
                if loadingDrops {
                    HStack {
                        DazuLoader().tint(.brand)
                        Text("Lade Pläne…")
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                } else if userDrops.isEmpty {
                    HStack(spacing: 10) {
                        DazuIcon("tray")
                            .font(.system(size: 16))
                            .foregroundColor(.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keine Pläne in Firebase")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text("User hat entweder keinen erstellt oder alle wurden via Cancel gelöscht.")
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                } else {
                    ForEach(Array(userDrops.enumerated()), id: \.element.id) { idx, drop in
                        userDropRow(drop)
                        if idx < userDrops.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
            .liquidGlass(cornerRadius: 18)
            .padding(.horizontal, 20)

            // Footnote — Cancel-Drops sind weg, das soll klar sein.
            Text("Hinweis: vom Host beendete Pläne werden aus der DB gelöscht und erscheinen hier nicht.")
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 24).padding(.top, 4)
        }
    }

    @ViewBuilder
    private func userDropRow(_ drop: AdminUserDropEntry) -> some View {
        HStack(spacing: 12) {
            DazuActivityIcon(drop.emoji.isEmpty ? "📍" : drop.emoji)
                .font(.system(size: 22))
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.md))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(drop.activityName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    statusBadge(for: drop.status)
                }
                HStack(spacing: 6) {
                    if let created = drop.createdAt {
                        Text(created.formatted(.dateTime.day().month().year().hour().minute()))
                    } else {
                        Text("—")
                    }
                    if let city = drop.cityName {
                        Text("·"); Text(city)
                    }
                    Text("·")
                    Text("\(drop.currentParticipants) " + (drop.currentParticipants == 1 ? "Teiln." : "Teiln."))
                }
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder
    private func statusBadge(for status: AdminUserDropEntry.Status) -> some View {
        let (label, color, icon): (String, Color, String) = {
            switch status {
            case .live:    return ("Live",      .onlineGreen,  "dot.radiowaves.left.and.right")
            case .expired: return ("Abgelaufen", .textTertiary, "clock.badge.xmark")
            case .ended:   return ("Beendet",   .accentOrange, "xmark.circle.fill")
            }
        }()
        HStack(spacing: 3) {
            DazuIcon(icon).font(.system(size: 8, weight: .semibold))
            Text(label).font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            DazuIcon(icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.brand)
                .frame(width: 20)
                .padding(.leading, 16)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.trailing)
                .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
    }
}

private struct DetailActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                DazuIcon(icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                DazuIcon("chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .foregroundColor(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.card))
        }
        .dropsPressable()
    }
}

// MARK: - Stat Card

private struct AdminStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(isActive ? color.opacity(0.25) : color.opacity(0.13))
                        .frame(width: 40, height: 40)
                    DazuIcon(icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(color)
                }
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .liquidGlass(cornerRadius: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isActive ? color.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .dropsPressable()
    }
}

// MARK: - User Card (List Row)

private struct AdminUserCard: View {
    let user: AdminUserEntry
    let onTap: () -> Void

    private var initials: String { String(user.name.prefix(1)).uppercased() }
    private var avatarColor: Color {
        user.isBanned ? .red : user.isAdmin ? .orange : .blue
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(avatarColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Text(initials)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(avatarColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(user.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        if user.isAdmin {
                            DazuIcon("star.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                        }
                    }
                    if user.email != "–" {
                        Text(user.email)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }
                    // Stadt direkt sichtbar in der Listen-Zeile (vorher nur
                    // im Detail-Sheet) — ein Pin-Icon + Stadtname als
                    // Sub-Caption. Wenn keine Stadt gesetzt ist, "—" als
                    // Hinweis statt komplett verstecken, damit der Admin
                    // sieht "fehlt" statt "wo ist das Feld?".
                    HStack(spacing: 4) {
                        DazuIcon("mappin.circle.fill", accent: false)
                            .font(.system(size: 10))
                            .foregroundColor(user.cityName == nil ? .textTertiary : .blue)
                        Text(user.cityName ?? "Ohne Stadt")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(user.cityName == nil ? .textTertiary : .textSecondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if user.isBanned {
                        AdminBadge(text: "Gesperrt", icon: "xmark.shield.fill", color: .red)
                    } else if user.hasActiveDrop {
                        AdminBadge(text: "Aktiv", icon: "dot.radiowaves.left.and.right", color: .green)
                    }
                    DazuIcon("chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .liquidGlass(cornerRadius: 16)
        }
        .dropsPressable()
    }
}

// MARK: - Badge

private struct AdminBadge: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            DazuIcon(icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Admin Reports Sheet
// Listet alle Nutzer-Meldungen — neueste zuerst. Admin kann jeden Eintrag als
// erledigt / abgewiesen markieren. Bei "Nutzer bannen" wird direkt der Ban gesetzt.

struct AdminReportsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reports: [AdminReportEntry] = []
    @State private var isLoading = true
    @State private var filter: Filter = .open

    enum Filter: String, CaseIterable { case open = "Offen", all = "Alle", resolved = "Erledigt" }

    private var filtered: [AdminReportEntry] {
        switch filter {
        case .open:     return reports.filter { $0.status == "open" }
        case .resolved: return reports.filter { $0.status != "open" }
        case .all:      return reports
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 10)

                if isLoading {
                    Spacer()
                    DazuLoader().tint(.brand)
                    Spacer()
                } else if filtered.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        DazuIcon("flag.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.textTertiary)
                        Text(filter == .open ? "Keine offenen Meldungen" : "Keine Meldungen")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { report in
                                AdminReportCard(
                                    report: report,
                                    onSetStatus: { newStatus in
                                        RealtimeDBManager.shared.adminSetReportStatus(
                                            reportID: report.id, status: newStatus
                                        )
                                        if let idx = reports.firstIndex(where: { $0.id == report.id }) {
                                            let updated = reports[idx]
                                            reports[idx] = AdminReportEntry(
                                                id: updated.id,
                                                reporterUID: updated.reporterUID,
                                                reportedUID: updated.reportedUID,
                                                reportedName: updated.reportedName,
                                                reason: updated.reason,
                                                details: updated.details,
                                                createdAt: updated.createdAt,
                                                status: newStatus
                                            )
                                        }
                                    },
                                    onBanUser: {
                                        guard !report.reportedUID.isEmpty else { return }
                                        // Erst bannen, dann Report als resolved markieren
                                        RealtimeDBManager.shared.adminSetBan(uid: report.reportedUID, banned: true)
                                        RealtimeDBManager.shared.adminSetReportStatus(
                                            reportID: report.id, status: "resolved"
                                        )
                                        if let idx = reports.firstIndex(where: { $0.id == report.id }) {
                                            let updated = reports[idx]
                                            reports[idx] = AdminReportEntry(
                                                id: updated.id,
                                                reporterUID: updated.reporterUID,
                                                reportedUID: updated.reportedUID,
                                                reportedName: updated.reportedName,
                                                reason: updated.reason,
                                                details: updated.details,
                                                createdAt: updated.createdAt,
                                                status: "resolved"
                                            )
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Meldungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isLoading = true
                        loadReports()
                    } label: {
                        DazuIcon("arrow.clockwise")
                    }
                }
            }
        }
        .onAppear { loadReports() }
    }

    private func loadReports() {
        RealtimeDBManager.shared.adminFetchReports { result in
            reports = result
            isLoading = false
        }
    }
}

private struct AdminReportCard: View {
    let report: AdminReportEntry
    let onSetStatus: (String) -> Void
    let onBanUser: () -> Void
    @State private var showBanConfirm = false

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yy HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.reportedName.isEmpty ? "Unbekannt" : report.reportedName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(report.reason)
                        .font(.system(size: 13))
                        .foregroundColor(.accentOrange)
                }
                Spacer()
                statusBadge
            }

            if !report.details.isEmpty {
                Text(report.details)
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                DazuIcon("clock").font(.system(size: 10))
                Text(Self.df.string(from: report.createdAt)).font(.system(size: 11))
                Spacer()
                if !report.reportedUID.isEmpty {
                    Text("UID: \(String(report.reportedUID.prefix(8)))…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.textTertiary)
                }
            }
            .foregroundColor(.textTertiary)

            if report.status == "open" {
                HStack(spacing: 8) {
                    Button {
                        onSetStatus("resolved")
                    } label: {
                        Label { Text("Erledigt") } icon: { DazuIcon("checkmark") }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.brand)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.brand.opacity(0.12), in: Capsule())
                    }
                    .dropsPressable()

                    Button {
                        onSetStatus("dismissed")
                    } label: {
                        Label { Text("Abweisen") } icon: { DazuIcon("xmark") }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.textSecondary.opacity(0.12), in: Capsule())
                    }
                    .dropsPressable()

                    Spacer()

                    if !report.reportedUID.isEmpty {
                        Button {
                            showBanConfirm = true
                        } label: {
                            Label { Text("Bannen") } icon: { DazuIcon("hand.raised.fill", accent: false) }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.accentRed)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.accentRed.opacity(0.12), in: Capsule())
                        }
                        .dropsPressable()
                    }
                }
            }
        }
        .padding(14)
        .liquidGlass(cornerRadius: 14)
        .alert("Nutzer bannen?", isPresented: $showBanConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Bannen", role: .destructive) { onBanUser() }
        } message: {
            Text("\(report.reportedName.isEmpty ? "Dieser Nutzer" : report.reportedName) wird gesperrt. Die Meldung wird automatisch als erledigt markiert.")
        }
    }

    @ViewBuilder private var statusBadge: some View {
        switch report.status {
        case "resolved":
            label(text: "Erledigt", color: .brand, icon: "checkmark.seal.fill")
        case "dismissed":
            label(text: "Abgewiesen", color: .textTertiary, icon: "xmark.seal.fill")
        default:
            label(text: "Offen", color: .accentOrange, icon: "flag.fill")
        }
    }

    private func label(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            DazuIcon(icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Admin Live Drops Monitor Sheet
// Zeigt alle aktuell laufenden Drops mit Stadt-Filter + Lösch-Button für
// Content-Moderation. Drops werden beim Löschen auch aus dropins/joinRequests
// entfernt + es wird ein Admin-Notice unter users/{host}/adminNotices abgelegt
// (Cloud-Function-Hook für Push an Host mit dem Lösch-Grund).

struct AdminDropsMonitorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var drops: [AdminDropEntry] = []
    @State private var isLoading = true
    @State private var cityFilter: String = "Alle"
    @State private var pendingDelete: AdminDropEntry? = nil

    private var cities: [String] {
        ["Alle"] + ServiceCities.all.map { $0.name } + ["—"]
    }

    private var filtered: [AdminDropEntry] {
        if cityFilter == "Alle" { return drops }
        return drops.filter { $0.cityName == cityFilter }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Stadt-Filter (horizontal scrollable chips)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(cities, id: \.self) { city in
                            let active = cityFilter == city
                            Button(city) {
                                withAnimation(.spring(response: 0.25)) { cityFilter = city }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(active ? .white : .textPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(active ? Color.brand : Color(UIColor.systemGray5),
                                        in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }

                if isLoading {
                    Spacer()
                    DazuLoader().tint(.brand)
                    Spacer()
                } else if filtered.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        DazuIcon("dot.radiowaves.left.and.right", accent: false)
                            .font(.system(size: 36))
                            .foregroundColor(.textTertiary)
                        Text(cityFilter == "Alle"
                             ? "Keine aktiven Pläne"
                             : "Keine Pläne in \(cityFilter)")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { drop in
                                AdminDropCard(drop: drop) {
                                    pendingDelete = drop
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Live Pläne")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isLoading = true
                        loadDrops()
                    } label: {
                        DazuIcon("arrow.clockwise")
                    }
                }
            }
            // Reason-Picker-Sheet — vordefinierte Gründe als Chips +
            // optionales Custom-Feld. Der Host bekommt dieselbe Nachricht
            // beim nächsten App-Resume als Bestätigungs-Sheet.
            .sheet(item: $pendingDelete) { drop in
                AdminEndDropReasonSheet(drop: drop) { reason in
                    RealtimeDBManager.shared.adminDeleteDrop(
                        dropID: drop.id,
                        hostUID: drop.hostUID,
                        reason: reason
                    )
                    drops.removeAll { $0.id == drop.id }
                    pendingDelete = nil
                } onCancel: {
                    pendingDelete = nil
                }
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear { loadDrops() }
    }

    private func loadDrops() {
        RealtimeDBManager.shared.adminFetchActiveDrops { result in
            drops = result
            isLoading = false
        }
    }
}

// MARK: - Admin End-Drop Reason Sheet
//
// Vordefinierte Gründe + optional eigener Text — für den Live-Drops-
// Monitor. Der gewählte Grund wird mit dem Drop-Lösch-Aufruf an
// `adminDeleteDrop` durchgereicht und landet als `adminNotice` im
// Firebase-Pfad des Hosts. Der Host bekommt die Nachricht beim
// nächsten App-Resume als bestätigungspflichtiges Sheet.

private struct AdminEndDropReasonSheet: View {
    let drop: AdminDropEntry
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    /// Liste vordefinierter Gründe. Reihenfolge nach geschätzter
    /// Häufigkeit — die häufigsten oben, "Sonstiges" als Fallback.
    private static let presetReasons: [(icon: String, title: String, color: Color)] = [
        ("exclamationmark.triangle.fill", "Verstoß gegen Nutzungsbedingungen", .accentRed),
        ("eye.slash.fill",                "Unangemessener Inhalt",            .accentRed),
        ("person.crop.circle.badge.xmark","Belästigung gemeldet",              .accentRed),
        ("mappin.slash",                  "Falsche Standortangabe",            .accentOrange),
        ("megaphone.fill",                "Spam / Werbung",                    .accentOrange),
        ("arrow.uturn.backward",          "Wiederholtes Fehlverhalten",        .accentOrange),
        ("ellipsis.circle",               "Sonstiges (eigener Grund)",         .textSecondary),
    ]

    @State private var selectedIndex: Int? = nil
    @State private var customText: String = ""
    @Environment(\.dismiss) private var dismiss

    private var isCustom: Bool { selectedIndex == Self.presetReasons.count - 1 }
    private var canConfirm: Bool {
        guard let idx = selectedIndex else { return false }
        if idx == Self.presetReasons.count - 1 {
            return !customText.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }
    private var resolvedReason: String {
        guard let idx = selectedIndex else { return "" }
        if idx == Self.presetReasons.count - 1 {
            return customText.trimmingCharacters(in: .whitespaces)
        }
        return Self.presetReasons[idx].title
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Drop-Vorschau
                    HStack(spacing: 10) {
                        DazuActivityIcon(drop.emoji).font(.system(size: 28))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(drop.activityName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.textPrimary)
                            Text("von \(drop.hostName)")
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Radius.card))

                    Text("Grund auswählen")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .textCase(.uppercase)

                    // Reason-Liste
                    VStack(spacing: 8) {
                        ForEach(Array(Self.presetReasons.enumerated()), id: \.offset) { idx, reason in
                            Button {
                                withAnimation(.spring(response: 0.25)) {
                                    selectedIndex = idx
                                    if idx != Self.presetReasons.count - 1 {
                                        customText = ""
                                    }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    DazuIcon(reason.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(reason.color)
                                        .frame(width: 28)
                                    Text(reason.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    if selectedIndex == idx {
                                        DazuIcon("checkmark.circle.fill")
                                            .font(.system(size: 17))
                                            .foregroundColor(reason.color)
                                    } else {
                                        DazuIcon("circle")
                                            .font(.system(size: 17))
                                            .foregroundColor(.textTertiary.opacity(0.6))
                                    }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .fill(selectedIndex == idx
                                              ? reason.color.opacity(0.10)
                                              : Color.primary.opacity(0.04))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .stroke(selectedIndex == idx
                                                ? reason.color.opacity(0.5)
                                                : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .dropsPressable()
                        }
                    }

                    // Custom-Textfeld nur wenn „Sonstiges" gewählt
                    if isCustom {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Eigener Grund")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            TextField("z.B. Inhalt nicht regelkonform", text: $customText, axis: .vertical)
                                .lineLimit(2...4)
                                .font(.system(size: 14))
                                .padding(12)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Radius.md))
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 90) // Platz für Footer-Buttons
            }
            .navigationTitle("Plan entfernen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { onCancel() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onConfirm(resolvedReason)
                } label: {
                    HStack(spacing: 8) {
                        DazuIcon("trash.fill")
                        Text("Entfernen & Host benachrichtigen")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canConfirm ? Color.accentRed : Color.gray, in: Capsule())
                }
                .dropsPressable()
                .disabled(!canConfirm)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
                .background(Color.bgPrimary.opacity(0.92))
            }
        }
    }
}

private struct AdminDropCard: View {
    let drop: AdminDropEntry
    let onDelete: () -> Void

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM. HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DazuActivityIcon(drop.emoji).font(.system(size: 28))
                .frame(width: 44, height: 44)
                .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.md))

            VStack(alignment: .leading, spacing: 4) {
                Text(drop.activityName.isEmpty ? "Plan" : drop.activityName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(drop.hostName)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                    Text("·").foregroundColor(.textTertiary)
                    Text(drop.cityName)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                    Text("·").foregroundColor(.textTertiary)
                    Label { Text("\(drop.participants)") } icon: { DazuIcon("person.2.fill", accent: false) }
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                HStack(spacing: 8) {
                    DazuIcon("clock").font(.system(size: 10))
                    Text("erstellt \(Self.df.string(from: drop.createdAt))")
                        .font(.system(size: 11))
                    Text("→ läuft bis \(Self.df.string(from: drop.expiresAt))")
                        .font(.system(size: 11))
                }
                .foregroundColor(.textTertiary)
            }

            Spacer()

            Button(action: onDelete) {
                DazuIcon("trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentRed)
                    .frame(width: 36, height: 36)
                    .background(Color.accentRed.opacity(0.12), in: Circle())
            }
            .dropsPressable()
        }
        .padding(14)
        .liquidGlass(cornerRadius: 14)
    }
}

// MARK: - Monogramm-Avatar-Generator (für Demo-Daten)

/// Erzeugt kreisförmige Monogramm-PNGs für Demo-Avatare und lädt sie
/// nach Firebase Storage `demoavatars/mono_<mockID>.png`.
fileprivate enum MonogramAvatar {

    /// Deterministische Farbe pro Mock-ID (Hex ohne #). Palette strikt
    /// aus dazu-Spektrum: Violet → Pink → Coral → Orange (Analog-Harmonie
    /// um brandViolet #5B3DF5 und accentOrange).
    private static let paletteByID: [String: String] = [
        "mock_max":    "5B3DF5",  // brand violet (deep)
        "mock_lea":    "FF7A4A",  // warm coral
        "mock_jana":   "E85D9E",  // rose pink
        "mock_mia":    "C84FD4",  // orchid
        "mock_leo":    "7C5CFF",  // violet light
        "mock_sophie": "FF8E6D",  // soft coral
        "mock_finn":   "9B5BF0",  // purple
        "mock_tim":    "D14AB8",  // magenta
        "mock_jonas":  "4A2EC2",  // deep indigo-violet
        "mock_lisa":   "FF6B8A",  // pink
        "mock_felix":  "FF9A3D",  // orange
        "demo_live_jana": "E85D9E",
        "demo_live_finn": "9B5BF0",
        "demo_live_tim":  "D14AB8"
    ]

    /// 400×400 PNG mit solidem BG + weißem SF-Rounded-Monogramm.
    static func renderPNG(initial: String, colorHex: String, size: CGFloat = 400) -> Data? {
        let bg = hexColor(colorHex)
        let letter = String(initial.prefix(1)).uppercased()
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: fmt)
        let image = renderer.image { ctx in
            bg.setFill()
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: size, height: size))
            let fontSize = size * 0.46
            let base = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            let font: UIFont = {
                if let d = base.fontDescriptor.withDesign(.rounded) {
                    return UIFont(descriptor: d, size: fontSize)
                }
                return base
            }()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white
            ]
            let str = NSAttributedString(string: letter, attributes: attrs)
            let s = str.size()
            let x = (size - s.width) / 2
            let y = (size - s.height) / 2 - size * 0.015
            str.draw(at: CGPoint(x: x, y: y))
        }
        return image.pngData()
    }

    /// Lädt (bzw. überschreibt) `demoavatars/mono_<mockID>.png`.
    static func generateAndUpload(mockID: String, name: String, completion: @escaping (String?) -> Void) {
        guard
            let hex = paletteByID[mockID],
            let initial = name.first.map(String.init),
            let data = renderPNG(initial: initial, colorHex: hex)
        else {
            completion(nil); return
        }
        let ref = Storage.storage().reference().child("demoavatars/mono_\(mockID).png")
        let meta = StorageMetadata()
        meta.contentType = "image/png"
        ref.putData(data, metadata: meta) { _, err in
            if let err = err {
                print("[mono] upload ✗ \(mockID): \(err.localizedDescription)")
                completion(nil); return
            }
            ref.downloadURL { url, err in
                if let s = url?.absoluteString {
                    print("[mono] ✓ \(mockID) → \(s)")
                    completion(s)
                } else {
                    print("[mono] downloadURL ✗ \(mockID): \(err?.localizedDescription ?? "?")")
                    completion(nil)
                }
            }
        }
    }

    private static func hexColor(_ hex: String) -> UIColor {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >>  8) & 0xFF) / 255
        let b = CGFloat( v        & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }
}
