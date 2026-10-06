import SwiftUI
import FirebaseAuth
import FirebaseDatabase

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
                                title: "Aktive Pläne",
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
                                    Image(systemName: "person.text.rectangle.fill")
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
                                                Image(systemName: "arrow.right")
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
                                            Image(systemName: "xmark.circle.fill")
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
                                            Image(systemName: "checkmark.circle.fill")
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
                                    Image(systemName: "flag.fill")
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
                                Image(systemName: "chevron.right")
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
                                    Image(systemName: "arrow.counterclockwise.circle.fill")
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
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                            }
                            .padding(12)
                            .liquidGlass(cornerRadius: 14)
                            .padding(.horizontal, 20)
                        }
                        .dropsPressable()

                        // Power-Hour Force-Toggle: zwingt Power-Hour permanent
                        // an, unabhängig von Wochentag/Uhrzeit. Praktisch zum
                        // Testen von Banner, Toast und Bonus-Logik ohne 18-Uhr
                        // abwarten zu müssen.
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .fill(Color.accentOrange.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.accentOrange)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Power-Hour erzwingen")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text(store.debugForcePowerHour
                                     ? "Aktiv — Bonus +25 immer"
                                     : "Aus — folgt dem Zeitplan")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $store.debugForcePowerHour)
                                .tint(.accentOrange)
                                .labelsHidden()
                        }
                        .padding(12)
                        .liquidGlass(cornerRadius: 14)
                        .padding(.horizontal, 20)

                        // Demo-Drops-Toggle: schreibt /config/demoDropsEnabled.
                        // Cloud Function seedDemoDrops liest den Flag bei jedem
                        // Cron-Run (stündlich). Off → keine neuen Demos mehr;
                        // bestehende werden via 4h-TTL natürlich ausgeräumt.
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .fill(Color.brand.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.brand)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Demo-Pläne")
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
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.brand)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Live-Monitor")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("Aktuelle Pläne anschauen & moderieren")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
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
                                    Image(systemName: "star.circle.fill")
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
                                Image(systemName: "chevron.right")
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
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.textTertiary)
                            .font(.system(size: 15))
                        TextField("Name, Telefon, E-Mail oder UID", text: $searchText)
                            .font(.system(size: 15))
                            .foregroundColor(.textPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.textTertiary)
                            }
                        }
                    }
                    .padding(12)
                    .liquidGlass(cornerRadius: 14)
                    .padding(.horizontal, 20)

                    // ── Sortier-Picker ────────────────────────────────────
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.arrow.down")
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
                            ProgressView().tint(.brand)
                            Text("Lade Daten…")
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else if filteredUsers.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.slash")
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
                                        Image(systemName: "mappin.circle.fill")
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
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.tertiary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation { isLoading = true }
                        loadData()
                    } label: {
                        Image(systemName: "arrow.clockwise")
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
}


// MARK: - User Detail Sheet

private struct AdminUserDetailSheet: View {
    let user: AdminUserEntry
    let onTogglePlus: () -> Void
    let onEndDrop: (() -> Void)?
    let onBan: () -> Void
    let onToggleAdmin: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Drops dieses Users in Firebase. Wird beim Sheet-Open einmalig
    /// geladen. Enthält nur Drops die noch in `drops/` liegen — vom
    /// Host gecancelte Drops sind weg (cancelDrop ruft removeValue).
    @State private var userDrops: [AdminUserDropEntry] = []
    @State private var loadingDrops = true

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
                        Image(systemName: "xmark.circle.fill")
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

    /// Section „Erstellte Drops" — listet alle Drops die noch in `drops/`
    /// liegen (live, abgelaufen, vom Admin beendet). Cancelled Drops
    /// (Host hat „Drop beenden" gedrückt) sind via removeValue gelöscht
    /// und tauchen hier NICHT auf — Hinweis-Footer macht das klar.
    @ViewBuilder
    private var userDropsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentOrange)
                    .frame(width: 18)
                Text("Erstellte Pläne")
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
                        ProgressView().tint(.brand)
                        Text("Lade Pläne…")
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                } else if userDrops.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "tray")
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
            Text(drop.emoji.isEmpty ? "📍" : drop.emoji)
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
            Image(systemName: icon).font(.system(size: 8, weight: .semibold))
            Text(label).font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
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
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
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
                    Image(systemName: icon)
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
                            Image(systemName: "star.fill")
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
                        Image(systemName: "mappin.circle.fill")
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
                    Image(systemName: "chevron.right")
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
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
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
                    ProgressView().tint(.brand)
                    Spacer()
                } else if filtered.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "flag.slash")
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
                        Image(systemName: "arrow.clockwise")
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
                Image(systemName: "clock").font(.system(size: 10))
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
                        Label("Erledigt", systemImage: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.brand)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.brand.opacity(0.12), in: Capsule())
                    }
                    .dropsPressable()

                    Button {
                        onSetStatus("dismissed")
                    } label: {
                        Label("Abweisen", systemImage: "xmark")
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
                            Label("Bannen", systemImage: "hand.raised.fill")
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
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
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
                    ProgressView().tint(.brand)
                    Spacer()
                } else if filtered.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "dot.radiowaves.left.and.right")
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
                        Image(systemName: "arrow.clockwise")
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
                        Text(drop.emoji).font(.system(size: 28))
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
                                    Image(systemName: reason.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(reason.color)
                                        .frame(width: 28)
                                    Text(reason.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    if selectedIndex == idx {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 17))
                                            .foregroundColor(reason.color)
                                    } else {
                                        Image(systemName: "circle")
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
                        Image(systemName: "trash.fill")
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
            Text(drop.emoji).font(.system(size: 28))
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
                    Label("\(drop.participants)", systemImage: "person.2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "clock").font(.system(size: 10))
                    Text("erstellt \(Self.df.string(from: drop.createdAt))")
                        .font(.system(size: 11))
                    Text("→ läuft bis \(Self.df.string(from: drop.expiresAt))")
                        .font(.system(size: 11))
                }
                .foregroundColor(.textTertiary)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
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
