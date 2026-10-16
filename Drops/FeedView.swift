import SwiftUI
import CoreLocation
import MapKit
import FirebaseDatabase
import FirebaseAuth

// MARK: - Feed Status

enum FeedStatus {
    case justArrived, active, starting

    var label: String {
        switch self {
        case .justArrived: return tr("feed.just_arrived")
        case .active:      return tr("feed.active")
        case .starting:    return tr("feed.starting_soon")
        }
    }

    var icon: String {
        switch self {
        case .justArrived: return "circle.fill"
        case .active:      return "flame.fill"
        case .starting:    return "clock.fill"
        }
    }

    var color: Color {
        switch self {
        case .justArrived: return .onlineGreen
        case .active:      return Color(UIColor.systemOrange)
        case .starting:    return Color(UIColor.systemYellow)
        }
    }
}

// MARK: - Feed View

struct FeedView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("appLanguage") private var appLanguage = "de"

    // Mini-Profil State
    @State private var profileParticipant: DropParticipant? = nil
    @State private var profileCanBlock = false
    @State private var profileSubtitle = ""
    @State private var profileAccent: Color = Color.auroraViolet
    @State private var auroraAnimate = false
    @State private var selectedCommunityFromFeed: Community? = nil
    /// Persistiert: hat User die First-Time-Hint-Card schon dismisst?
    /// Nach erstem Tap wird das auf true gesetzt → erscheint nicht wieder.
    @AppStorage("ud_feedFirstTimeHintDismissed") private var feedHintDismissed = false
    /// Globaler Tageszähler „heute passiert" aus /stats/dropsToday/{YYYY-MM-DD}.
    /// Wird on-appear subscribed; Cloud-Function `onDropEndedCount` incrementiert
    /// bei abgeschlossenen Runden die Spam-Gate (≥10 Min + ≥1 Joiner) bestehen.
    @State private var globalTodayCount: Int = 0
    @State private var globalTodayHandle: DatabaseHandle? = nil
    /// Scroll-adaptiv: true, sobald die Hero-Headline aus dem sichtbaren
    /// Bereich gescrollt ist. Treibt den kompakten dazu-Chip oben.
    @State private var feedIsScrolled = false
    @AppStorage("ud_profileHeroTemplate") private var profileHeroTemplateRaw = ProfileHeroTemplate.aurora.rawValue
    private var profileHeroTemplate: ProfileHeroTemplate {
        ProfileHeroTemplate(rawValue: profileHeroTemplateRaw) ?? .aurora
    }

    /// Sichtbar nur für echte Erstnutzer: noch keinen Drop erstellt UND
    /// keinen aktiven Drop laufen. Solange Filter-Treffer vorhanden sind
    /// (also was im Feed steht zum Antippen), zeigen wir den Hint —
    /// sonst greift schon der DropsEmptyState weiter unten.
    private var showFirstTimeHint: Bool {
        guard !feedHintDismissed else { return false }
        guard store.pastDrops.isEmpty else { return false }
        guard store.activeDrops.isEmpty else { return false }
        guard !strangerAnnotations.isEmpty || !sortedFriendDrops.isEmpty else { return false }
        return true
    }

    /// Onboarding-Hint für Erstnutzer — erklärt in einem Satz den Haupt-
    /// flow ("Tap → vorbeikommen") und ist persistent dismissable.
    @ViewBuilder
    private var firstTimeHintCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.auroraOrange, Color.auroraGreen],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                DazuIcon("hand.wave.fill", accent: false)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(tr("feed.new_here"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(tr("feed.new_here_body"))
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    feedHintDismissed = true
                }
            } label: {
                DazuIcon("xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .dropsPressable()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Color.auroraOrange.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func showStrangerProfile(_ item: MapAnnotationItem) {
        let creator = item.participants.first ?? DropParticipant(name: item.name, emoji: item.emoji)
        profileParticipant = creator
        profileCanBlock = true
        // Statischer "Dazu-Nutzer"-Subtitle entfernt — Sheet zeigt stattdessen
        // den dynamischen Online-Status (oder nichts, wenn unbekannt).
        profileSubtitle = ""
        profileAccent = Color.auroraViolet
    }

    private func showFriendProfile(_ friend: User) {
        profileParticipant = DropParticipant(name: friend.name, emoji: friend.emoji,
                                             reliabilityScore: friend.reliabilityPoints,
                                             profileImageURL: friend.profileImageURL,
                                             firebaseUID: friend.firebaseUID)
        profileCanBlock = false
        profileSubtitle = friend.isAvailable ? tr("feed.available_now") : (friend.statusMessage.isEmpty ? tr("feed.unavailable") : friend.statusMessage)
        profileAccent = Color.brand
    }

    /// Prüft ob ein Drop in die aktuell gewählte Kategorie passt.
    private func matchesActivityFilter(_ item: MapAnnotationItem) -> Bool {
        ActivityCategory.matches(filter: store.activityCategoryFilter,
                                 emoji: item.emoji, activity: item.activity)
    }

    /// Match für den „Heute Abend"-Filter. Greift wenn entweder das
    /// scheduledTime explizit „Abend" enthält oder der Drop heute erstellt
    /// wurde und nach 17 Uhr aktiv wird.
    private func matchesTonight(_ item: MapAnnotationItem) -> Bool {
        if let st = item.scheduledTime, st.localizedCaseInsensitiveContains("abend") {
            return true
        }
        let cal = Calendar.current
        guard cal.isDateInToday(item.createdAt) else { return false }
        let hour = cal.component(.hour, from: Date())
        return hour >= 17
    }

    // Öffentliche Drops — Drops+ Boost zuerst, dann nach Interessen-Match priorisiert.
    // Distanz-Filter: `.nearby`/`.quarter` schränken auf Radius vom User-Standort
    // ein, `.city` zeigt die ganze aktuelle Stadt (Verhalten wie vorher).
    // „Nur weiblich"-Filter blendet alle Nicht-weiblich-Hosts aus (nur für weibliche Userinnen).
    // Aktivitäts-Filter blendet Drops raus deren Kategorie nicht gewählt ist.
    private var strangerAnnotations: [MapAnnotationItem] {
            var base = store.allMapAnnotations.filter { $0.isStranger && !$0.isGhost }
        let userCoord = store.currentUser.coordinate
        // Drop dem der User aktuell beigetreten ist NIEMALS rausfiltern —
        // egal welche Distance/Gender/Activity-Filter aktiv sind. Sonst
        // verschwindet ein gejointer Drop aus dem Umgebungstab obwohl man
        // ihn auf der Karte sieht (Bug-Report).
        let joinedDropID = store.activeJoinedDropID?.uuidString
        let isJoinedDrop: (MapAnnotationItem) -> Bool = { drop in
            joinedDropID != nil && drop.id.uuidString == joinedDropID
        }
        if let myCity = ServiceCities.city(for: userCoord) {
            base = base.filter { isJoinedDrop($0) || myCity.contains($0.coordinate) }
        } else if let myCityNear = ServiceCities.cityNear(userCoord) {
            base = base.filter { isJoinedDrop($0) || myCityNear.contains($0.coordinate) }
        }
        if store.genderFilterEnabled && store.userGender == "weiblich" {
            base = base.filter { isJoinedDrop($0) || ($0.hostGender?.lowercased() ?? "") == "weiblich" }
        }
        base = base.filter { isJoinedDrop($0) || matchesActivityFilter($0) }
        return base.sorted { a, b in
            // Sortierung nach Interessen-Match (falls Interessen gesetzt sind)
            if !store.userInterests.isEmpty {
                let scoreA = interestScore(for: a)
                let scoreB = interestScore(for: b)
                if scoreA != scoreB { return scoreA > scoreB }
            }
            return false
        }
    }

    /// Vergangene Drops — selbe Distanz- und Aktivitäts-Filter wie strangerAnnotations.
    private var ghostAnnotations: [MapAnnotationItem] {
        let userCoord = store.currentUser.coordinate
        var base = store.allMapAnnotations.filter { $0.isGhost && $0.isStranger }
        if let myCity = ServiceCities.city(for: userCoord) {
            base = base.filter { myCity.contains($0.coordinate) }
        } else if let myCityNear = ServiceCities.cityNear(userCoord) {
            base = base.filter { myCityNear.contains($0.coordinate) }
        }
        base = base.filter { matchesActivityFilter($0) }
        return base
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
            .prefix(6)
            .map { $0 }
    }

    /// Horizontaler Strip mit allen Communities in der Nähe — fixiert auf
    /// dem Bezirks-Zentrum. Tap öffnet das Join-Sheet.
    private var communitiesNearbyStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                DazuIcon("person.3.fill", accent: false)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.cleroGreen)
                Text(tr("feed.communities_nearby"))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundColor(.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.nearbyCommunities) { community in
                        Button { selectedCommunityFromFeed = community } label: {
                            communityCard(community)
                        }
                        .dropsPressable()
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .sheet(item: $selectedCommunityFromFeed) { community in
            CommunityJoinSheet(community: community)
                .environmentObject(store)
                .presentationDetents([.fraction(0.45)])
                .presentationDragIndicator(.visible)
                .sheetBackground()
        }
    }

    private func communityCard(_ c: Community) -> some View {
        let isMember = c.creatorUID == store.currentUser.firebaseUID
                    || store.myCommunityMemberships.contains(c.id)
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.cleroGreen, Color.brand],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 38, height: 38)
                DazuIcon(c.icon, accent: false)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(c.displayName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    if isMember {
                        DazuIcon("checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.cleroGreen)
                    }
                }
                Text("\(c.district) · \(c.memberCount)")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .liquidGlass(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.cleroGreen.opacity(0.25), lineWidth: 1)
        )
    }

    /// Segmented Control: Drop-Radius (1km / 3km / Stadt) + „Heute Abend"-Toggle.
    /// Sichtbarer Label-Header macht klar, dass es um den Suchradius geht.
    private var distanceTimeFilterBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                DazuIcon("scope")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.brand)
                Text(tr("feed.drop_radius"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text("· \(store.feedDistanceFilter.detailLabel)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16)

            HStack(spacing: 8) {
                ForEach(FeedDistanceFilter.allCases, id: \.self) { dist in
                    segmentChip(
                        title: dist.label,
                        selected: store.feedDistanceFilter == dist
                    ) {
                        store.feedDistanceFilter = dist
                        store.saveAll()
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func segmentChip(title: String, icon: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { action() }
        } label: {
            HStack(spacing: 5) {
                if let icon = icon {
                    DazuIcon(icon, accent: false)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(selected ? .white : .brand)
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
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

    /// „Nur weiblich"-Toggle im App-Stil.
    // MARK: - Puls der Stadt

    /// Kompakte Stat-Card mit zwei Zahlen: wie viele Runden gerade live sind
    /// und wie viele heute insgesamt stattgefunden haben. Zeigt dem User
    /// auch bei leerem Feed dass die App lebt.
    @ViewBuilder
    private var cityPulseCard: some View {
        // Aktive Runden hier: öffentliche + eigene aktive
        let liveCount = strangerAnnotations.count + store.activeDrops.count
        // „Heute passiert" = globaler Tageszähler aus RTDB (Cloud-Function
        // zählt nur Runden mit ≥10 Min Dauer UND ≥1 Joiner).
        let todayCount = globalTodayCount

        HStack(spacing: 10) {
            pulseStat(
                big: "\(liveCount)",
                small: liveCount == 1 ? tr("feed.rounds_live_singular") : tr("feed.rounds_live_plural"),
                icon: "runde",
                tint: .brandViolet
            )
            pulseStat(
                big: "\(todayCount)",
                small: tr("feed.happened_today"),
                icon: "sparkles",
                tint: .brandViolet
            )
        }
        .onAppear { subscribeGlobalTodayCount() }
        .onDisappear { unsubscribeGlobalTodayCount() }
    }

    private var todayDayKey: String {
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "Europe/Berlin")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private func subscribeGlobalTodayCount() {
        guard globalTodayHandle == nil else { return }
        let ref = Database.database().reference()
            .child("stats").child("dropsToday").child(todayDayKey)
        globalTodayHandle = ref.observe(.value) { snap in
            globalTodayCount = (snap.value as? Int) ?? 0
        }
    }

    private func unsubscribeGlobalTodayCount() {
        guard let h = globalTodayHandle else { return }
        Database.database().reference()
            .child("stats").child("dropsToday").child(todayDayKey)
            .removeObserver(withHandle: h)
        globalTodayHandle = nil
    }

    @ViewBuilder
    private func pulseStat(big: String, small: String,
                           icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            DazuIcon(icon)
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.brandLavender))
            VStack(alignment: .leading, spacing: 1) {
                Text(big)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.brandNight)
                Text(small)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 16)
    }

    // MARK: - Freunde in Reichweite

    /// Horizontale Avatar-Row aller Freunde mit Online-Dot und Status-Label
    /// darunter. Tap öffnet das MiniProfileSheet via `showFriendProfile`.
    @ViewBuilder
    private var friendsInRangeStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("feed.your_friends"))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.brandNight)
                Spacer()
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(store.friends) { friend in
                        Button {
                            showFriendProfile(friend)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack(alignment: .bottomTrailing) {
                                    Group {
                                        if let url = friend.profileImageURL,
                                           !url.isEmpty {
                                            RemoteProfileImage(url: url,
                                                               fallbackEmoji: friend.emoji,
                                                               size: 56,
                                                               strokeColor: .clear)
                                        } else {
                                            ZStack {
                                                Circle().fill(Color.brandLavender)
                                                    .frame(width: 56, height: 56)
                                                DazuProfileIcon(size: 34)
                                            }
                                        }
                                    }
                                    .overlay(Circle().stroke(Color.brandLavender, lineWidth: 2))
                                    // Online-/Offline-Dot — beide opak,
                                    // sonst scheint das Profilbild durch.
                                    Circle()
                                        .fill(friend.isAvailable
                                              ? Color.onlineGreen
                                              : Color(red: 0.60, green: 0.60, blue: 0.65))
                                        .frame(width: 14, height: 14)
                                        .overlay(Circle().stroke(Color.brandCream, lineWidth: 2))
                                }
                                Text(friend.name)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.brandNight)
                                    .lineLimit(1)
                                    .frame(width: 64)
                            }
                        }
                        .dropsPressable()
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var femaleOnlyFilterBar: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                store.genderFilterEnabled.toggle()
                store.saveAll()
            }
        } label: {
            HStack(spacing: 10) {
                DazuIcon("line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(store.genderFilterEnabled ? .white : .brand)
                Text(tr("feed.female_only"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(store.genderFilterEnabled ? .white : .textPrimary)
                Spacer(minLength: 0)
                if store.genderFilterEnabled {
                    DazuIcon("checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(
                        store.genderFilterEnabled
                            ? Color.brand
                            : Color.bgCard
                    )
            )
            .shadow(color: store.genderFilterEnabled ? Color.brand.opacity(0.28) : .clear, radius: 8, y: 3)
        }
        .dropsPressable()
    }

    // Freunde-Drops — nach Interessen-Match priorisiert
    private var sortedFriendDrops: [(name: String, emoji: String, status: String,
                                     activity: String, place: String, eta: String, dist: String)] {
        let base = store.nearbyDropsForFeed
        guard !store.userInterests.isEmpty else { return base }
        return base.sorted { a, b in
            friendInterestScore(for: a) > friendInterestScore(for: b)
        }
    }

    /// Keywords pro Interesse-Key — für Matching gegen Activity-Strings
    private let interestKeywords: [String: [String]] = [
        "interest.coffee":  ["kaffee", "coffee", "café", "cafe"],
        "interest.food":    ["essen", "food", "lunch", "dinner", "pizza", "burger", "restaurant", "brunch"],
        "interest.sport":   ["sport", "fitness", "gym", "laufen", "run", "fußball", "soccer", "tennis", "basketball"],
        "interest.music":   ["musik", "music", "konzert", "concert", "festival"],
        "interest.cinema":  ["kino", "film", "cinema", "movie", "serie"],
        "interest.gaming":  ["gaming", "game", "games", "zocken", "spielen"],
        "interest.shopping":["shopping", "einkaufen", "outlet", "markt"],
        "interest.outdoor": ["outdoor", "natur", "nature", "park", "wandern", "hike", "fahrrad", "bike"],
        "interest.travel":  ["reisen", "travel", "trip", "ausflug", "urlaub"],
        "interest.party":   ["ausgehen", "party", "bar", "drink", "drinks", "cocktail", "nachtleben", "club", "feiern"],
        "interest.photo":   ["foto", "fotos", "photo", "photos", "kamera", "camera", "shooting"],
        "interest.cooking": ["kochen", "cooking", "cook", "küche", "backen", "bake", "rezept"],
    ]

    /// 1 wenn Activity-String ein Interesse-Keyword enthält, sonst 0
    private func interestScore(for item: MapAnnotationItem) -> Int {
        let activity = item.activity.lowercased()
        return store.userInterests.contains { key in
            interestKeywords[key]?.contains(where: { activity.contains($0) }) ?? false
        } ? 1 : 0
    }

    private func friendInterestScore(for item: (name: String, emoji: String, status: String,
                                                 activity: String, place: String,
                                                 eta: String, dist: String)) -> Int {
        let activity = item.activity.lowercased()
        return store.userInterests.contains { key in
            interestKeywords[key]?.contains(where: { activity.contains($0) }) ?? false
        } ? 1 : 0
    }

    private func feedStatus(for index: Int) -> FeedStatus {
        [FeedStatus.justArrived, .active, .starting, .justArrived, .active, .starting][index % 6]
    }

    private func participantCount(for index: Int) -> Int {
        [2, 0, 3, 1, 2, 0][index % 6]
    }

    private func extraParticipantEmojis(for index: Int) -> [String] {
        let sets: [[String]] = [["🧔", "👩"], [], ["😎", "🧑", "👱"], ["👩"], ["🧔", "👩"], []]
        return sets[index % sets.count]
    }

    private func concreteStatus(for item: (name: String, emoji: String, status: String,
                                           activity: String, place: String,
                                           eta: String, dist: String), index: Int) -> String {
        let texts = [
            tr("feed.status_in_place").replacingOccurrences(of: "{place}", with: item.place),
            tr("feed.status_on_way"),
            tr("feed.status_already_there"),
            tr("feed.status_just_arrived"),
            tr("feed.status_starting_soon"),
            tr("feed.status_open_join")
        ]
        return texts[index % texts.count]
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppAuroraBackground()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {

                        // Rondesignlab-Style Top: Wortmarke inline + massive
                        // Hero-Headline. Logo liegt oben in-line (NICHT
                        // sticky) — beim Scrollen fliegt es weg und ein
                        // kompakter dazu-Chip klebt via scrollAdaptive-
                        // DazuHeader(isScrolled:) oben ein (iOS-Large→
                        // Compact-Pattern).
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                DazuWordmark(color: .brandNight, dotColor: .brandOrange)
                                    .frame(height: 24)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: -4) {
                                Text(tr("feed.what_running"))
                                    .foregroundColor(.brandNight)
                                (Text(tr("feed.with_you")).foregroundColor(.brandViolet)
                                 + Text("?").foregroundColor(.brandOrange))
                            }
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .lineSpacing(-2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                        // ── Puls der Stadt ──────────────────────────────────
                        // Lebenszeichen auch wenn gerade nichts live ist:
                        // Nutzer-Count im Umkreis + Runden heute.
                        cityPulseCard
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)

                        // ── Freunde in Reichweite ──────────────────────────
                        // Avatar-Row mit Online-Dot, Tap öffnet Mini-Profil.
                        if !store.friends.isEmpty {
                            friendsInRangeStrip
                                .padding(.bottom, 10)
                        }

                        // ── Filter (nur Frauen-Toggle) ────────────────────
                        if store.userGender == "weiblich" {
                            femaleOnlyFilterBar
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 8)
                        }

                        // ── Communities in der Nähe ──────────────────────
                        // Horizontale Liste aller genehmigten Communities.
                        // Tap auf Card öffnet das Join-Sheet. Nur sichtbar
                        // wenn mind. 1 Community existiert.
                        if FeatureFlags.communitiesEnabled && !store.nearbyCommunities.isEmpty {
                            communitiesNearbyStrip
                                .padding(.bottom, 8)
                        }

                        // Power-Hour-Pille entfernt (Feature deaktiviert).
                        EmptyView()

                        // ── Push-Permission-Banner ──
                        // Zeigt sich nur wenn Push deaktiviert + nicht
                        // dismissed. Tap → iOS-Settings öffnen. Wichtig weil
                        // ohne Push die ganze Reaktivität (Anfragen, Drop-
                        // Ende, Auto-Accept) silently broken ist.
                        PushPermissionBanner()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)

                        // ── First-Time-Hint für neue User ──
                        // Zeigt sich für User die noch keinen Drop erstellt
                        // ODER beigetreten sind, solange im Feed mindestens
                        // 1 Drop sichtbar ist. Verschwindet automatisch nach
                        // erster Aktion. Erklärt den Hauptpfad in 1 Satz +
                        // schließbar via X.
                        if showFirstTimeHint {
                            firstTimeHintCard
                                .padding(.horizontal, 16)
                                .padding(.bottom, 10)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // ── Eigener aktiver Drop ──
                        if let myDrop = store.activeDrops.first {
                            MyDropFeedCard(drop: myDrop, onCardTap: {
                                store.focusedDropCoordinate = myDrop.location.coordinate
                                withAnimation { store.selectedTab = .map }
                            })
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                        }

                        // ── Freunde in der Nähe (prominent) ──
                        if !sortedFriendDrops.isEmpty {
                            friendsSectionHeader(count: sortedFriendDrops.count)
                            ForEach(Array(sortedFriendDrops.enumerated()), id: \.offset) { i, item in
                                FriendDropCard(
                                    item: item,
                                    status: feedStatus(for: i),
                                    participantCount: participantCount(for: i),
                                    extraEmojis: extraParticipantEmojis(for: i),
                                    concreteStatus: concreteStatus(for: item, index: i),
                                    isFeatured: i == 0,
                                    profileImageURL: store.friends.first(where: { $0.name == item.name })?.profileImageURL,
                                    coordinate: store.friends.first(where: { $0.name == item.name })?.coordinate,
                                    onAvatarTap: {
                                        if let friend = store.friends.first(where: { $0.name == item.name }) {
                                            showFriendProfile(friend)
                                        }
                                    },
                                    onCardTap: {
                                        if let friend = store.friends.first(where: { $0.name == item.name }) {
                                            store.focusedDropCoordinate = friend.coordinate
                                        }
                                        withAnimation { store.selectedTab = .map }
                                    }
                                )
                            }
                        }

                        // ── Öffentliche Drops (schwächer) ──
                        if !strangerAnnotations.isEmpty {
                            strangerSectionHeader(count: strangerAnnotations.count)
                            ForEach(strangerAnnotations) { item in
                                StrangerDropFeedCard(item: item,
                                    onCreatorTap: { showStrangerProfile(item) },
                                    onCardTap: {
                                        store.focusedDropCoordinate = item.coordinate
                                        withAnimation { store.selectedTab = .map }
                                    })
                                    .opacity(0.95)
                                    // .id verhindert dass SwiftUI den View für
                                    // einen anderen Drop recycled → @State joined
                                    // bleibt nicht fälschlicherweise auf true.
                                    .id(item.id)
                            }
                        }

                        // ── Vergangene Drops in der Nähe ──
                        if !ghostAnnotations.isEmpty {
                            let noActive = sortedFriendDrops.isEmpty && strangerAnnotations.isEmpty
                            ghostSectionHeader(count: ghostAnnotations.count, noActive: noActive)
                            ForEach(ghostAnnotations) { item in
                                GhostDropFeedCard(item: item, onCardTap: {
                                    store.focusedDropCoordinate = item.coordinate
                                    withAnimation { store.selectedTab = .map }
                                })
                                .id(item.id)
                                .padding(.bottom, 8)
                            }
                        }

                        // ── Leer-State ──
                        // Boost-Bonus wird direkt im EmptyState als kleine
                        // Capsule angezeigt (statt früher separater
                        // BoostBanner-Sektion). So gibt es eine einzige,
                        // konsistente Botschaft: "Sei der erste — und du
                        // bekommst +15 Bonus dafür".
                        // Empty-State nicht zeigen wenn eine eigene Runde läuft —
                        // der Nutzer sieht seine Runde oben im Feed, zusätzlich
                        // "Hier ist noch nichts los" ist widersprüchlich.
                        if sortedFriendDrops.isEmpty && strangerAnnotations.isEmpty
                            && ghostAnnotations.isEmpty && store.activeDrops.isEmpty {
                            DropsEmptyState(
                                onCreateTap: { store.selectedTab = .create },
                                boostActive: store.isBoostPhaseActive,
                                boostBonus: store.currentBoostBonus
                            )
                                .padding(.top, 48)
                        }

                        // "Nicht verfügbar"-Sektion ist aus dem Umgebungs-Feed raus —
                        // offline Freunde sieht man im Freunde-Tab (dort dediziert).
                        // Im Feed geht's darum was JETZT passiert, daher irrelevant.

                        Spacer(minLength: 24)
                    }
                    .padding(.top, 8)
                }
                .onScrollGeometryChange(for: Bool.self) { geo in
                    // Chip faded ein, sobald das Inline-Logo weggescrollt
                    // ist (Logo-Höhe + top-Padding). Das iOS-Standard-
                    // Pattern bei UINavigationBar.scrollEdgeAppearance —
                    // kurzer Overlap mit der noch halb sichtbaren Hero
                    // ist OK, der Compact-Chip ist dezent genug.
                    geo.contentOffset.y > 50
                } action: { _, newValue in
                    feedIsScrolled = newValue
                }
                .scrollAdaptiveDazuHeader(isScrolled: feedIsScrolled)
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(item: $profileParticipant) { p in
                if #available(iOS 16.4, *) {
                    MiniProfileSheet(
                        name: p.name,
                        emoji: p.emoji,
                        selfie: p.selfie,
                        profileImageURL: p.profileImageURL,
                        reliabilityScore: p.reliabilityScore,
                        totalCommits: p.reliabilityCommits,
                        subtitle: profileSubtitle,
                        accentColor: profileAccent,
                        userUID: p.firebaseUID,
                        canBlock: profileCanBlock
                    ) {
                        // Alle abhängigen State-Vars zusammen zurücksetzen —
                        // sonst blieben subtitle/accent/canBlock vom vorherigen
                        // Sheet-User stehen wenn der nächste geöffnet wird.
                        profileParticipant = nil
                        profileSubtitle    = ""
                        profileAccent      = Color.auroraViolet
                        profileCanBlock    = false
                    }
                        .environmentObject(store)
                        .presentationDetents([.fraction(0.5)])
                        .presentationDragIndicator(.hidden)
                        .modifier(AvailabilityPresentationBackground())
                }
            }
        }
    }

    // MARK: - Section Headers

    @ViewBuilder
    private func friendsSectionHeader(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(tr("feed.friends_header_caps")) · \(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.brandViolet.opacity(0.65))
            HStack(alignment: .center) {
                Text(tr("feed.nearby"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.brandNight)
                Spacer()
                Text("≤ \(Int(store.radiusFilter))m")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.5))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.brandLavender.opacity(0.6)))
            }
        }
        .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 12)
    }

    @ViewBuilder
    private func strangerSectionHeader(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(tr("feed.public_header_caps")) · \(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.brandViolet.opacity(0.65))
            Text(tr("feed.all_rounds"))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.brandNight)
        }
        .padding(.horizontal, 24).padding(.top, 32).padding(.bottom, 12)
    }

    @ViewBuilder
    private func ghostSectionHeader(count: Int, noActive: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if noActive {
                // Info-Banner: keine aktiven Drops gerade
                HStack(alignment: .top, spacing: 12) {
                    DazuIcon("moon.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.brandViolet)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("feed.no_active_drops_title"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(tr("feed.no_active_drops_subtitle"))
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .liquidGlass(cornerRadius: 13)
                .padding(.horizontal, 14)
            }

            // Section-Label: "VERGANGENE DROPS · n"
            HStack(spacing: 5) {
                Text(tr("feed.past_drops").uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .tracking(0.5)
                Text("·")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 18)
        }
        .padding(.top, noActive ? 16 : 20)
        .padding(.bottom, 6)
    }

    private var offlineFriendsHeader: some View {
        HStack(spacing: 6) {
            DazuIcon("moon.fill", accent: false)
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
            Text(tr("feed.unavailable"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 6)
    }
}

private struct AvailabilityPresentationBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackground(.clear)
        } else {
            content
        }
    }
}

// MARK: - Friend Drop Card

struct FriendDropCard: View {
    let item: (name: String, emoji: String, status: String,
               activity: String, place: String, eta: String, dist: String)
    let status: FeedStatus
    let participantCount: Int
    let extraEmojis: [String]
    let concreteStatus: String
    let isFeatured: Bool
    /// Profilbild-URL des Hosts, wenn vorhanden. Wird im großen Avatar oben
    /// rechts angezeigt; Fallback ist das dazu-Profil-Icon.
    var profileImageURL: String? = nil
    /// Koordinate des Freundes-Drops für das Mini-Karten-Tile. nil → kein
    /// Snapshot (zeigt dann nur die bestehenden Meta-Chips).
    var coordinate: CLLocationCoordinate2D? = nil
    var onAvatarTap: (() -> Void)? = nil
    var onCardTap: (() -> Void)? = nil

    @State private var joined = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ── Hero-Kopf: großer Avatar links + Name/Status + Aktivität ──
            HStack(alignment: .top, spacing: 14) {
                Button { onAvatarTap?() } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let url = profileImageURL, !url.isEmpty {
                                RemoteProfileImage(url: url, fallbackEmoji: item.emoji,
                                                   size: 64, strokeColor: .clear)
                            } else {
                                ZStack {
                                    Circle().fill(Color.brandLavender)
                                        .frame(width: 64, height: 64)
                                    DazuProfileIcon(size: 38)
                                }
                            }
                        }
                        .overlay(Circle().stroke(Color.brandLavender, lineWidth: 2))
                        // Live-Puls als kleiner Dot unten rechts.
                        Circle().fill(Color.brandOrange)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.brandCream, lineWidth: 2))
                    }
                }
                .dropsPressable()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.brandNight)
                            .lineLimit(1)
                        if isFeatured {
                            DazuIcon("flame.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.brandOrange)
                        }
                    }
                    // Aktivität als Hero-Headline — das ist, was den Nutzer
                    // dazu bringt zu tappen.
                    Text(item.activity)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundColor(.brandViolet)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let coord = coordinate {
                    MiniMapSnapshot(coordinate: coord,
                                    size: CGSize(width: 68, height: 68),
                                    cornerRadius: 14)
                }
            }

            // ── Meta-Row: Ort · ETA · Teilnehmer-Count ───────────────────
            HStack(spacing: 10) {
                metaChip(icon: "mappin.and.ellipse", text: item.place)
                metaChip(icon: "figure.walk", text: "\(item.eta) · \(item.dist)")
                if participantCount > 0 || !extraEmojis.isEmpty {
                    let count = max(participantCount, extraEmojis.count)
                    metaChip(icon: "person.2.fill",
                             text: count == 1 ? "1 dabei" : "\(count) dabei")
                }
            }

            // ── Großer flacher CTA ──────────────────────────────────────
            Button(action: { withAnimation(.spring(response: 0.3)) { joined = true } }) {
                HStack(spacing: 8) {
                    if joined {
                        DazuIcon("checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text(tr("feed.im_in"))
                    } else {
                        Text(tr("feed.come_join"))
                        DazuIcon("arrow.right")
                            .font(.system(size: 13, weight: .heavy))
                    }
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(joined ? .brandViolet : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    Capsule().fill(joined ? Color.brandLavender : Color.brandViolet)
                )
            }
            .dropsPressable()
            .disabled(joined)
        }
        .padding(18)
        .liquidGlass(cornerRadius: 24)
        .padding(.horizontal, 14).padding(.bottom, 10)
        .contentShape(Rectangle())
        .onTapGesture { onCardTap?() }
    }

    /// Kleiner Lavendel-Chip für Meta-Infos (Ort, ETA, Teilnehmer).
    @ViewBuilder
    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            DazuIcon(icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.brandViolet)
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.brandNight.opacity(0.75))
                .lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Color.brandLavender.opacity(0.6)))
    }
}

// MARK: - Stranger Drop Feed Card (Öffentliche Drops — schwächer)

struct StrangerDropFeedCard: View {
    let item: MapAnnotationItem
    @EnvironmentObject var store: AppStore
    @State private var joined = false
    @State private var showJoinConfirm = false
    @State private var showLeaveConfirm = false
    /// Admin-Flag: Tap auf Demo-Live-Runde → sofort beigetreten
    /// (ohne JoinConfirmSheet). Nur für App-Store-Screenshots.
    @AppStorage("demoAutoJoin") private var demoAutoJoin: Bool = false
    /// Live-Joiner (aus `dropins/{firebaseDropID}`) als kleine Avatar-Row
    /// in der Card — damit User auch ohne Pin-Tap sieht wer schon dabei ist.
    struct JoinerPreview: Identifiable {
        let id: String
        let name: String
        let url: String?
    }
    @State private var joinerPreviews: [JoinerPreview] = []
    var onCreatorTap: (() -> Void)? = nil
    var onCardTap: (() -> Void)? = nil

    // Aurora-Farbe: deterministisch aus Drop-ID → immer gleiche Farbe pro Drop
    private var accentColor: Color {
        let auroraColors: [Color] = [
            Color.auroraCyan, // cyan
            Color.onlineGreen, // grün
            Color.auroraAmber, // amber
            Color.auroraPink, // pink
            Color.auroraViolet, // violet
            Color.auroraTeal, // teal
        ]
        let index = abs(item.id.hashValue) % auroraColors.count
        return auroraColors[index]
    }
    private var alreadyJoined: Bool { store.hasJoinedDrop(dropID: item.id) }

    var body: some View {
        // Gleiches Layout wie MyDropFeedCard: Mini-Map füllt den ganzen
        // Hintergrund, ein Lavender-Gradient-Film links deckend blendet
        // nach rechts aus, damit der Pin auf der Karte sichtbar bleibt
        // und der Text trotzdem lesbar ist.
        let isPending = store.pendingJoinDropID == item.id
        let isJoined = (alreadyJoined || joined) && !isPending
        let cooldown = store.joinCooldownRemaining(dropID: item.id)
        let inCooldown = cooldown > 0 && !isJoined && !isPending
        // Blocked wenn der User bereits in einem anderen aktiven Drop ist
        // ODER eine andere pending-Anfrage offen hat — sonst könnte er
        // parallel bei mehreren Runden sitzen während die Hosts noch
        // bestätigen.
        let hasPendingElsewhere = store.pendingJoinDropID != nil
            && store.pendingJoinDropID != item.id
        let blockedByOther = (store.isInActiveDrop || hasPendingElsewhere)
            && !isJoined && !isPending
        let isFull = item.isFull && !isJoined && !isPending
        return ZStack {
            MiniMapSnapshotFill(coordinate: item.coordinate, metersSpan: 500)
            LinearGradient(
                colors: [
                    Color.brandLavender,
                    Color.brandLavender.opacity(0.9),
                    Color.brandLavender.opacity(0.15)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            HStack(alignment: .center, spacing: 12) {
                Button {
                    onCreatorTap?()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.brandCream.opacity(0.9))
                            .frame(width: 50, height: 50)
                        DazuActivityIcon(item.emoji.isEmpty ? "✨" : item.emoji, when: item.hasActivityEmoji)
                            .font(.system(size: 24))
                    }
                }
                .dropsPressable()

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        // Violett + Orange-Punkt — wie der Name im Profil.
                        (Text(item.activity).foregroundColor(.brandViolet)
                         + Text(".").foregroundColor(.brandOrange))
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        let timeLabel = item.scheduledTime ?? "Jetzt"
                        let timeLabelDisplay = trScheduledTime(timeLabel)
                        let isNow = timeLabel == "Jetzt"
                        // "Jetzt"-Badge in Orange (dazu-Signalfarbe für Live),
                        // alle anderen Zeiten in Violett.
                        let badgeFg: Color = isNow ? .accentOrange : .brandViolet
                        let badgeBg: Color = isNow ? Color.accentOrange.opacity(0.14) : Color.brandCream.opacity(0.75)
                        HStack(spacing: 3) {
                            DazuIcon(isNow ? "circle.fill" : "clock.fill")
                                .font(.system(size: 7, weight: .bold))
                            Text(timeLabelDisplay)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundColor(badgeFg)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(badgeBg)
                        .cornerRadius(5)
                        .fixedSize()
                    }
                    Button {
                        onCreatorTap?()
                    } label: {
                        HStack(spacing: 6) {
                            // Namen-Stil wie das Profil: Violett + oranger Punkt.
                            (Text(item.name).foregroundColor(.brandViolet)
                             + Text(".").foregroundColor(.brandOrange))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            if let age = item.creatorAge {
                                Text("\(age)")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.brandNight.opacity(0.55))
                            }
                            if FeatureFlags.communitiesEnabled,
                               let uid = item.hostUID,
                               store.communityForCreator(uid: uid) != nil {
                                CommunityCreatorBadge(community: nil, compact: true)
                            }
                            DazuIcon("chevron.right")
                                .font(.system(size: 9))
                                .foregroundColor(.brandNight.opacity(0.4))
                        }
                    }
                    .dropsPressable()
                    HStack(spacing: 5) {
                        DazuIcon("figure.walk")
                            .font(.system(size: 10)).foregroundColor(.brandNight.opacity(0.7))
                        Text(store.etaString(to: item.coordinate))
                            .font(.system(size: 12)).foregroundColor(.brandNight.opacity(0.75))
                        Text("·").foregroundColor(.brandNight.opacity(0.4)).font(.system(size: 12))
                        // Mini-Avatar-Stack der bereits beigetretenen Joiner
                        // (aus `dropins/{firebaseDropID}`) — statt dem
                        // generischen Personen-Icon.
                        if !joinerPreviews.isEmpty {
                            HStack(spacing: -6) {
                                ForEach(joinerPreviews.prefix(3)) { j in
                                    Group {
                                        if let u = j.url, !u.isEmpty {
                                            RemoteProfileImage(url: u, fallbackEmoji: "",
                                                               size: 20, strokeColor: Color.brandLavender)
                                        } else {
                                            // Fallback: Initialen-Monogramm wenn URL fehlt.
                                            let letter = String(j.name.prefix(1)).uppercased()
                                            ZStack {
                                                Circle().fill(Color.brandViolet.opacity(0.85))
                                                    .frame(width: 20, height: 20)
                                                Text(letter)
                                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                    }
                                    .overlay(Circle().stroke(Color.brandLavender, lineWidth: 1.5))
                                }
                            }
                        } else {
                            DazuIcon("person.2.fill")
                                .font(.system(size: 10)).foregroundColor(.brandNight.opacity(0.7))
                        }
                        Text("\(item.effectiveParticipantCount) / \(item.maxParticipants)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(item.isFull ? .accentRed : .brandNight.opacity(0.75))
                    }
                }

                Spacer(minLength: 6)

                Button(action: {
                        // Statt silent-fail bei deaktiviertem Button:
                        // erklärenden Toast zeigen. User hatte vorher kein
                        // Feedback warum der Tap nichts macht.
                        if isFull {
                            store.showInfoToast(
                                tr("feed.drop_full_toast").replacingOccurrences(of: "{max}", with: "\(item.maxParticipants)"),
                                icon: "person.fill.xmark"
                            )
                            return
                        }
                        if blockedByOther {
                            store.showInfoToast(
                                tr("feed.in_other_drop_toast"),
                                icon: "lock.fill"
                            )
                            return
                        }
                        if inCooldown {
                            let mins = Int(cooldown / 60) + 1
                            store.showInfoToast(
                                tr("feed.cooldown_toast").replacingOccurrences(of: "{mins}", with: "\(mins)"),
                                icon: "clock.arrow.circlepath"
                            )
                            return
                        }
                        if isPending {
                            // Pending-Tap: Anfrage zurückziehen
                            store.leaveDropJoin(dropID: item.id)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { joined = false }
                        } else if isJoined {
                            // Bereits dabei → Verlassen bestätigen
                            showLeaveConfirm = true
                        } else if demoAutoJoin,
                                  let fbid = item.firebaseDropID,
                                  fbid.hasPrefix("demolive_") {
                            // Demo-Autojoin für App-Store-Screenshots: Compose-
                            // Sheet + Pending-State komplett überspringen.
                            // Schreibt direkt den dropin in Firebase, setzt den
                            // visuellen Status auf „bereits dabei".
                            let myUID = Auth.auth().currentUser?.uid ?? "demo_self"
                            let payload: [String: Any] = [
                                "name": store.currentUser.name,
                                "emoji": store.currentUser.emoji,
                                "lat": store.currentUser.coordinate.latitude,
                                "lng": store.currentUser.coordinate.longitude,
                                "locTime": Date().timeIntervalSince1970 * 1000,
                                "timestamp": Date().timeIntervalSince1970 * 1000,
                                "profileImageURL": store.profileImageURL ?? ""
                            ]
                            let ref = Database.database().reference()
                                .child("dropins").child(fbid)
                            ref.child(myUID).setValue(payload)

                            // Für Demo-Screenshots garantiert ein paar Mock-
                            // Joiner mitschreiben falls die seedLive-Dropins
                            // fehlen. Idempotent — überschreibt pro Mock-ID.
                            let mockFallback: [(id: String, name: String, age: Int)] = [
                                ("mock_sophie", "Sophie", 27),
                                ("mock_leo",    "Leo",    28),
                                ("mock_jana",   "Jana",   26)
                            ]
                            let baseLat = item.coordinate.latitude
                            let baseLng = item.coordinate.longitude
                            for (idx, m) in mockFallback.enumerated() {
                                let p: [String: Any] = [
                                    "name":  m.name,
                                    "emoji": "🙂",
                                    "age":   m.age,
                                    "lat":   baseLat + Double.random(in: -0.002...0.002),
                                    "lng":   baseLng + Double.random(in: -0.002...0.002),
                                    "timestamp": Date().timeIntervalSince1970 * 1000 - Double(idx * 90_000),
                                    "profileImageURL": "",
                                    "reliabilityPoints": Int.random(in: 200...400)
                                ]
                                ref.child(m.id).setValue(p)
                            }

                            store.activeJoinedDropID = item.id
                            // Für die Live-Ansicht: Mock-Joiners direkt in
                            // item.participants reinschreiben (statt zu
                            // hoffen dass Firebase-Observe sie liefert).
                            // Plus Dauer-Override auf 2 Std.
                            var liveItem = item
                            liveItem.durationMinutes = 120
                            liveItem.createdAt = Date()
                            liveItem.participants = [
                                DropParticipant(name: "Sophie", emoji: "", reliabilityScore: 320, reliabilityCommits: 0),
                                DropParticipant(name: "Leo",    emoji: "", reliabilityScore: 265, reliabilityCommits: 0),
                                DropParticipant(name: "Jana",   emoji: "", reliabilityScore: 410, reliabilityCommits: 0)
                            ]
                            store.activeDropAnnotation = liveItem
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { joined = true }
                            store.selectedTab = .create
                        } else {
                            // ÖFFNET das Compose-Sheet — schickt NICHT direkt.
                            showJoinConfirm = true
                        }
                    }) {
                        let colors = feedJoinButtonColors(
                            blockedByOther: blockedByOther,
                            inCooldown: inCooldown,
                            isPending: isPending,
                            isJoined: isJoined,
                            isFull: isFull
                        )
                        feedJoinButtonLabel(
                            blockedByOther: blockedByOther,
                            inCooldown: inCooldown,
                            cooldownMin: Int(cooldown / 60) + 1,
                            isPending: isPending,
                            isJoined: isJoined,
                            isFull: isFull
                        )
                        .foregroundColor(colors.fg)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(colors.bg)
                        .cornerRadius(Radius.md)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(colors.stroke, lineWidth: 0.8))
                    }
                    .dropsPressable()
                    // Kein `.disabled(...)` mehr — wir wollen den Tap
                    // bewusst durchlassen, um im Action-Closure einen
                    // erklärenden Toast zu zeigen (Cooldown / Voll /
                    // Bereits-in-Drop). Visuell wirkt der Button durch
                    // die grauen Farben aus feedJoinButtonColors weiter
                    // wie „nicht aktiv".
                    .sheet(isPresented: $showLeaveConfirm) {
                        // Lokales Sekunden-Delta anhand der hostessen joinRequest
                        // (createdAt). Bei pending Requests sind 0 sekunden okay,
                        // bei akzeptierten kann das 12+ min sein → Sheet zeigt
                        // dann die Score-Risiko-Warnung.
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
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { joined = false }
                            showLeaveConfirm = false
                        } onCancel: {
                            showLeaveConfirm = false
                        }
                        .presentationDetents([.fraction(0.65)])
                        // Verlassen-Warnung darf nicht versehentlich
                        // weggewischt werden — User muss bewusst Verlassen
                        // oder Abbrechen tippen.
                        .presentationDragIndicator(.hidden)
                        .interactiveDismissDisabled()
                        .sheetBackground()
                    }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .frame(minHeight: 92)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.brand.opacity(0.22), lineWidth: 1)
        )
        .padding(.horizontal, 14).padding(.bottom, 10)
        .contentShape(Rectangle())
        .onTapGesture { onCardTap?() }
        .onAppear {
            // Live-Joiner (Name + optional URL) aus `dropins/{fbid}`.
            // Avatar fällt auf Initialen-Monogramm zurück wenn URL fehlt.
            guard joinerPreviews.isEmpty,
                  let fbid = item.firebaseDropID else { return }
            Database.database().reference()
                .child("dropins").child(fbid)
                .observeSingleEvent(of: .value) { snap in
                    var list: [JoinerPreview] = []
                    for case let child as DataSnapshot in snap.children {
                        guard let dict = child.value as? [String: Any] else { continue }
                        let name = dict["name"] as? String ?? "?"
                        let url  = dict["profileImageURL"] as? String
                        list.append(JoinerPreview(id: child.key, name: name, url: url))
                    }
                    DispatchQueue.main.async { self.joinerPreviews = list }
                }
        }
        // Beitritts-Compose + Bestätigung
        .sheet(isPresented: $showJoinConfirm) {
            JoinConfirmSheet(item: item) {
                // Wird vom Sheet aufgerufen wenn die Anfrage tatsächlich
                // rausgegangen ist — erst dann den Card-State auf "Bin dabei"
                // setzen, sonst flackert der Status falls der User abbricht.
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { joined = true }
            }
                .environmentObject(store)
                .presentationDetents([.fraction(0.55)])
                .presentationDragIndicator(.hidden)
                .sheetBackground()
        }
    }

    /// Farbpalette für den Join-Button — als Tuple ausgelagert weil
    /// inline-Ternäres-Cascading den Compiler überfordert.
    private func feedJoinButtonColors(
        blockedByOther: Bool, inCooldown: Bool,
        isPending: Bool, isJoined: Bool, isFull: Bool
    ) -> (fg: Color, bg: Color, stroke: Color) {
        // Vorher: alle Buttons mit opacity(0.10) als BG — auf dem neuen
        // Lavender-Film-Kartenlayout kaum lesbar. Jetzt solide Buttons mit
        // weißem/dunklem Text für klaren Kontrast.
        if isFull {
            return (.white, Color.accentRed, Color.clear)
        }
        if blockedByOther {
            return (.brandNight.opacity(0.6), Color.brandCream.opacity(0.9), Color.brandNight.opacity(0.12))
        }
        if inCooldown {
            return (.brandNight.opacity(0.6), Color.brandCream.opacity(0.9), Color.brandNight.opacity(0.12))
        }
        if isPending {
            return (.white, Color.accentOrange, Color.clear)
        }
        if isJoined {
            return (.white, Color.onlineGreen, Color.clear)
        }
        return (Color.brandCream, Color.brandViolet, Color.clear)
    }

    /// Label für den Join-Button — extrahiert damit der SwiftUI-Compiler
    /// den verschachtelten if/else-Branch nicht type-check-timeoutet.
    @ViewBuilder
    private func feedJoinButtonLabel(blockedByOther: Bool,
                                     inCooldown: Bool,
                                     cooldownMin: Int,
                                     isPending: Bool,
                                     isJoined: Bool,
                                     isFull: Bool) -> some View {
        HStack(spacing: 4) {
            if isFull {
                DazuIcon("person.fill.xmark", accent: false).font(.system(size: 10, weight: .medium))
                Text(tr("feed.full"))
                    .font(.system(size: 12, weight: .semibold))
            } else if blockedByOther {
                DazuIcon("lock.fill", accent: false).font(.system(size: 10))
                Text(tr("feed.in_drop"))
                    .font(.system(size: 12, weight: .semibold))
            } else if inCooldown {
                DazuIcon("clock").font(.system(size: 10, weight: .medium))
                Text("\(cooldownMin) \(tr("map.min_short"))")
                    .font(.system(size: 12, weight: .semibold))
            } else if isPending {
                DazuIcon("hourglass").font(.system(size: 10, weight: .medium))
                Text(tr("feed.pending"))
                    .font(.system(size: 12, weight: .semibold))
            } else if isJoined {
                DazuIcon("checkmark").font(.system(size: 10, weight: .bold))
                Text(tr("feed.im_in"))
                    .font(.system(size: 12, weight: .semibold))
            } else {
                Text(tr("feed.im_coming"))
                    .font(.system(size: 12, weight: .semibold))
            }
        }
    }
}

// MARK: - My Drop Feed Card

struct MyDropFeedCard: View {
    let drop: DropEvent
    var onCardTap: (() -> Void)? = nil

    private var timeRemainingText: String {
        let remaining = drop.expiresAt.timeIntervalSinceNow
        guard remaining > 0 else { return tr("feed.mydrop_ended") }
        let mins = Int(remaining / 60)
        if mins < 60 { return "\(mins) min" }
        return "\(mins / 60)h \(mins % 60)m"
    }

    private var joinedCount: Int { drop.participants.count }

    var body: some View {
        Button { onCardTap?() } label: {
            // Map-Hintergrund füllt die ganze Card; Content liegt mit
            // Lavendel-Gradient-Film drüber damit alles lesbar bleibt.
            ZStack {
                MiniMapSnapshotFill(coordinate: drop.location.coordinate,
                                    metersSpan: 500)
                // Links-nach-rechts Lavendel-Film: links deckend für den
                // Text, rechts fast transparent damit die Karte sichtbar
                // bleibt und der Pin durchkommt.
                LinearGradient(
                    colors: [
                        Color.brandLavender,
                        Color.brandLavender.opacity(0.85),
                        Color.brandLavender.opacity(0.05)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.brandCream.opacity(0.9))
                            .frame(width: 50, height: 50)
                        DazuActivityIcon(drop.activity.emoji)
                            .font(.system(size: 24))
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            // Violett + Orange-Punkt — Profil-Namensstil.
                            (Text(drop.activity.name).foregroundColor(.brandViolet)
                             + Text(".").foregroundColor(.brandOrange))
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .lineLimit(1)
                            Text(tr("feed.mydrop_badge"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.brandViolet)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.brandCream.opacity(0.75))
                                .cornerRadius(5)
                        }
                        HStack(spacing: 5) {
                            DazuIcon("person.2.fill")
                                .font(.system(size: 10)).foregroundColor(.brandNight.opacity(0.7))
                            Text("\(joinedCount) / \(drop.maxParticipants)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.brandNight.opacity(0.75))
                            Text("·").foregroundColor(.brandNight.opacity(0.4)).font(.system(size: 12))
                            DazuIcon("clock.fill")
                                .font(.system(size: 10)).foregroundColor(.brandNight.opacity(0.7))
                            Text(timeRemainingText)
                                .font(.system(size: 12)).foregroundColor(.brandNight.opacity(0.75))
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .frame(height: 86)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.brand.opacity(0.25), lineWidth: 1)
            )
        }
        .dropsPressable()
    }
}

// MARK: - Ghost Drop Feed Card

struct GhostDropFeedCard: View {
    let item: MapAnnotationItem
    @EnvironmentObject var store: AppStore
    var onCardTap: (() -> Void)? = nil

    @State private var resolvedAddress: String? = nil

    private var endedAgoText: String {
        guard let ended = item.endedAt else { return "" }
        let minutes = Int(-ended.timeIntervalSinceNow / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    var body: some View {
        Button { onCardTap?() } label: {
            HStack(alignment: .center, spacing: 14) {
                // Emoji-Kreis — Lavendel statt Grau, matcht Dazu-Palette
                ZStack {
                    Circle()
                        .fill(Color.brandLavender.opacity(0.6))
                        .frame(width: 54, height: 54)
                    DazuActivityIcon(item.emoji.isEmpty ? "👻" : item.emoji, when: item.hasActivityEmoji)
                        .font(.system(size: 26))
                        .opacity(0.85)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.activity)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.brandNight)

                    // Host-Name + Alter (immer sichtbar)
                    HStack(spacing: 4) {
                        Text(item.name)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.6))
                            .lineLimit(1)
                        if let age = item.creatorAge {
                            Text("·")
                                .font(.system(size: 12))
                                .foregroundColor(.brandNight.opacity(0.4))
                            Text("\(age)")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.brandNight.opacity(0.5))
                        }
                    }

                    // Venue oder Adresse + Distanz
                    HStack(spacing: 4) {
                        if !item.locationTitle.isEmpty {
                            DazuIcon("mappin", accent: false)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.textTertiary)
                            Text(item.locationTitle)
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                                .lineLimit(1)
                        } else if let addr = resolvedAddress {
                            Text(addr)
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                                .lineLimit(1)
                        }
                        if !item.locationTitle.isEmpty || resolvedAddress != nil {
                            Text("·")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                        }
                        Text(store.distanceString(to: item.coordinate))
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }
                }

                Spacer()

                // Zeitstempel rechts
                if !endedAgoText.isEmpty {
                    VStack(spacing: 2) {
                        DazuIcon("clock")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                        Text(endedAgoText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .liquidGlass(cornerRadius: 14)
            .padding(.horizontal, 14)
        }
        .dropsPressable()
        .task(id: item.id) {
            let loc = CLLocation(latitude: item.coordinate.latitude, longitude: item.coordinate.longitude)
            CLGeocoder().reverseGeocodeLocation(loc) { placemarks, _ in
                guard let p = placemarks?.first else { return }
                let street = [p.thoroughfare, p.subThoroughfare]
                    .compactMap { $0 }.joined(separator: " ")
                guard !street.isEmpty else { return }
                DispatchQueue.main.async { resolvedAddress = street }
            }
        }
    }
}

// MARK: - Join Confirm Sheet

struct JoinConfirmSheet: View {
    let item: MapAnnotationItem
    /// Wird gerufen wenn die Anfrage tatsächlich gesendet wurde — die
    /// FeedView setzt darauf hin den `joined`-State. Vorher fehlte das,
    /// dadurch flackerte die Card wenn der User das Sheet zumachte ohne
    /// "Senden" zu drücken.
    let onSent: () -> Void
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "de"

    /// Tatsächlich rausgehende Nachricht — befüllt durch Quick-Chip-Tap
    /// oder freie Eingabe im TextField. nil = keine Nachricht senden.
    @State private var composedMessage: String = ""
    @State private var sending = false
    @State private var sent = false

    /// Activity-bezogene Quick-Messages — passende Vorschläge je nach
    /// Drop-Typ. WICHTIG: nur Statements, keine Fragen — der Host sieht
    /// die Nachricht nur einmal in der Beitrittsanfrage und kann nicht
    /// darauf antworten. Fragen wie "Welche Bar?" laufen also ins Leere.
    /// Substring-Match damit Varianten wie "Bier", "Bierchen", "Drink"
    /// dasselbe Set treffen.
    private var quickMessages: [String] {
        let activity = item.activity.lowercased()
        // Drinks / Bar
        if activity.contains("bier") || activity.contains("drink")
            || activity.contains("bar") || activity.contains("cocktail")
            || activity.contains("party") {
            return ["Bin in 10 Min da",
                    "Erste Runde geht auf mich!",
                    "Hab Bock auf den Abend",
                    "Freu mich!"]
        }
        // Kaffee / Café / Brunch
        if activity.contains("kaffee") || activity.contains("brunch")
            || activity.contains("café") || activity.contains("cafe") {
            return [tr("feed.preset.coffee.1"),
                    tr("feed.preset.coffee.2"),
                    tr("feed.preset.coffee.3"),
                    tr("feed.preset.coffee.4")]
        }
        // Essen / Restaurant
        if activity.contains("essen") || activity.contains("food")
            || activity.contains("dinner") || activity.contains("lunch")
            || activity.contains("pizza") || activity.contains("burger") {
            return [tr("feed.preset.food.1"),
                    tr("feed.preset.food.2"),
                    tr("feed.preset.food.3"),
                    tr("feed.preset.food.4")]
        }
        // Sport / Workout / Laufen
        if activity.contains("sport") || activity.contains("workout")
            || activity.contains("lauf") || activity.contains("yoga")
            || activity.contains("gym") || activity.contains("fitness")
            || activity.contains("foto-walk") || activity.contains("walk")
            || activity.contains("spazier") {
            return [tr("feed.preset.sport.1"),
                    tr("feed.preset.sport.2"),
                    tr("feed.preset.sport.3"),
                    tr("feed.preset.sport.4")]
        }
        // Konzert / Musik / Festival
        if activity.contains("konzert") || activity.contains("musik")
            || activity.contains("festival") || activity.contains("club")
            || activity.contains("dj") {
            return [tr("feed.preset.music.1"),
                    tr("feed.preset.music.2"),
                    tr("feed.preset.music.3"),
                    tr("feed.preset.music.4")]
        }
        // Kino / Film
        if activity.contains("kino") || activity.contains("film")
            || activity.contains("movie") {
            return [tr("feed.preset.movie.1"),
                    tr("feed.preset.movie.2"),
                    tr("feed.preset.movie.3"),
                    tr("feed.preset.movie.4")]
        }
        // Gaming / Zocken
        if activity.contains("zock") || activity.contains("gaming")
            || activity.contains("game") {
            return [tr("feed.preset.gaming.1"),
                    tr("feed.preset.gaming.2"),
                    tr("feed.preset.gaming.3"),
                    tr("feed.preset.gaming.4")]
        }
        // Park / Outdoor / Hangout
        if activity.contains("park") || activity.contains("outdoor")
            || activity.contains("strand") || activity.contains("see") {
            return [tr("feed.preset.outdoor.1"),
                    tr("feed.preset.outdoor.2"),
                    tr("feed.preset.outdoor.3"),
                    tr("feed.preset.outdoor.4")]
        }
        // Shopping / Bummeln
        if activity.contains("shop") || activity.contains("bummel")
            || activity.contains("einkauf") {
            return [tr("feed.preset.shopping.1"),
                    tr("feed.preset.shopping.2"),
                    tr("feed.preset.shopping.3"),
                    tr("feed.preset.shopping.4")]
        }
        // Generischer Fallback
        return [tr("feed.preset.fallback.1"),
                tr("feed.preset.fallback.2"),
                tr("feed.preset.fallback.3"),
                tr("feed.preset.fallback.4")]
    }

    var body: some View {
        VStack(spacing: 16) {
            // Handle
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            // Icon
            ZStack {
                Circle()
                    .fill(Color.auroraViolet.opacity(0.12))
                    .frame(width: 64, height: 64)
                DazuActivityIcon(item.emoji, when: item.hasActivityEmoji)
                    .font(.system(size: 30))
            }

            VStack(spacing: 4) {
                Text(sent ? tr("feed.waiting_for_confirm") : tr("feed.send_request_to").replacingOccurrences(of: "{name}", with: item.name))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                if !sent {
                    Text(tr("feed.optional_message"))
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            if !sent {
                // Quick-Nachrichten — Chip befüllt das TextField, User kann's
                // dann noch editieren oder einfach so absenden.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickMessages, id: \.self) { msg in
                            Button {
                                composedMessage = msg
                            } label: {
                                Text(msg)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(composedMessage == msg
                                                     ? .white
                                                     : Color.auroraViolet)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(
                                        composedMessage == msg
                                        ? Color.auroraViolet
                                        : Color.auroraViolet.opacity(0.12)
                                    )
                                    .cornerRadius(20)
                            }
                            .dropsPressable()
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Freie Texteingabe entfernt — nur Quick-Chips (oben).
                // Custom-Nachrichten führten zu Spam-Risiko + erforderten
                // mehr Modering. Quick-Chips reichen für „kurzer Kontext"-Use-Case.
            } else {
                // Wartezustand nach Senden — zeigt klar dass der Host
                // erst noch bestätigen muss. Pulsierender Indicator gibt
                // visuelles Feedback dass die App aktiv "wartet" und kein
                // dead-end ist.
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        DazuLoader().tint(.brand).scaleEffect(0.9)
                            .tint(Color.auroraViolet)
                            .scaleEffect(0.9)
                        Text(tr("feed.notified").replacingOccurrences(of: "{name}", with: item.name))
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .fill(Color.white.opacity(0.75))
                    )
                    Text(tr("feed.close_window_msg").replacingOccurrences(of: "{name}", with: item.name))
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 20)
            }

            Spacer(minLength: 0)

            // Senden / Schließen
            HStack(spacing: 10) {
                if !sent {
                    Button { dismiss() } label: {
                        Text(tr("feed.cancel"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    .dropsPressable()

                    Button { sendRequest() } label: {
                        HStack(spacing: 6) {
                            if sending {
                                DazuLoader().tint(.white)
                            } else {
                                DazuIcon("paperplane.fill")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            Text(sending ? tr("feed.sending") : tr("feed.send"))
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            Capsule().fill(Color.auroraViolet)
                                .shadow(color: Color.auroraViolet.opacity(0.35),
                                        radius: 10, y: 3)
                        )
                    }
                    .dropsPressable()
                    .disabled(sending)
                } else {
                    // Sheet bleibt offen bis User selber schließt — sonst
                    // sieht's so aus als wäre die Anfrage angenommen, was
                    // sie noch nicht ist. User entscheidet wann fertig.
                    Button { dismiss() } label: {
                        Text(tr("feed.wait_in_background"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    .dropsPressable()
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sendRequest() {
        guard !sending && !sent else { return }
        sending = true
        let trimmed = composedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: String? = trimmed.isEmpty ? nil : trimmed
        store.sendJoinRequest(to: item, message: payload)
        onSent()
        // Sheet sofort schließen — der Wartestatus ist global sichtbar
        // über die Pending-Pill oben in der App (PendingJoinRequestPill).
        // User muss nicht mehr im Sheet sitzen während er auf Antwort wartet.
        dismiss()
    }
}

// MARK: - Boost Banner
//
// Erscheint im Umgebungs-Tab unten wenn weniger als `AppStore.boostThreshold`
// Drops in Reichweite sind. Reine Info-Karte — der „Drop erstellen"-Button
// ist im DropsEmptyState bzw. in der Tab-Bar; doppelt wäre verwirrend.
// Der eigentliche Bonus wird in AppStore.applyBoostBonusIfActive vergeben
// (createDrop / confirmEncounter / recordHostSuccess).
struct BoostBanner: View {
    @State private var pulse = false

    var body: some View {
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
                    .shadow(color: Color.accentOrange.opacity(pulse ? 0.55 : 0.25), radius: pulse ? 14 : 6)
                DazuIcon("bolt.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tr("feed.boost_phase_active"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(tr("feed.boost_phase_explainer"))
                    .font(.system(size: 12))
                    .foregroundColor(.textPrimary.opacity(0.72))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentOrange.opacity(0.10),
                            Color.brand.opacity(0.10),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .stroke(Color.accentOrange.opacity(0.35), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Mini-Map-Snapshot

/// Kleines Karten-Tile für Feed-Rows: zeigt via `MKMapSnapshotter` einen
/// Satellit-/Standard-Ausschnitt um die Drop-Koordinate, mit orangenem Pin
/// in der Mitte. Snapshotter rendert einmal, Ergebnis wird in `MiniMapCache`
/// gecacht — kein lebendes `MKMapView` pro Row (teuer, Battery).
struct MiniMapSnapshot: View {
    let coordinate: CLLocationCoordinate2D
    var size: CGSize = CGSize(width: 62, height: 62)
    var cornerRadius: CGFloat = 14
    /// Zoom-Breite in Metern (quadratisch). 400m ≈ gut lesbarer Nahbereich.
    var metersSpan: CLLocationDistance = 500

    @State private var image: UIImage? = nil
    /// Wenn `false`, wird kein Pin über den Snapshot gelegt (für Card-Fills,
    /// wo ein großer Pin die Karte überdeckt).
    var showsPin: Bool = true

    private var cacheKey: String {
        // Grid auf ~11m (4 Nachkommastellen) damit minimale GPS-Jitter
        // nicht zu Dauer-Rerenders führen.
        let lat = (coordinate.latitude  * 10_000).rounded() / 10_000
        let lng = (coordinate.longitude * 10_000).rounded() / 10_000
        return "\(lat)_\(lng)_\(Int(size.width))_\(Int(metersSpan))"
    }

    /// Pin-Durchmesser: klein auf großen Flächen (sonst wird aus 26% ein
    /// 80pt-Blob der die halbe Karte verdeckt). Max 18pt, min 10pt.
    private var pinDiameter: CGFloat {
        min(max(size.width * 0.22, 10), 18)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.brandLavender)
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            }
            if showsPin {
                ZStack {
                    Circle()
                        .fill(Color.brandOrange)
                        .frame(width: pinDiameter, height: pinDiameter)
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: pinDiameter, height: pinDiameter)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.brandNight.opacity(0.08), lineWidth: 1)
        )
        .task(id: cacheKey) { await generate() }
    }

    private func generate() async {
        if let cached = MiniMapCache.shared.image(forKey: cacheKey) {
            self.image = cached
            return
        }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate,
                                            latitudinalMeters: metersSpan,
                                            longitudinalMeters: metersSpan)
        options.size = size
        options.scale = UIScreen.main.scale
        options.showsBuildings = false
        if #available(iOS 16.0, *) {
            options.preferredConfiguration = MKStandardMapConfiguration(
                elevationStyle: .flat, emphasisStyle: .muted)
        }
        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snap = try await snapshotter.start()
            await MainActor.run {
                MiniMapCache.shared.set(snap.image, forKey: cacheKey)
                self.image = snap.image
            }
        } catch {
            // Snapshotter kann z.B. offline fehlschlagen — Lavendel-Fallback
            // bleibt sichtbar.
        }
    }
}

/// Füllt die ganze Elternfläche mit einem Karten-Snapshot — für Card-
/// Hintergründe. Nutzt denselben Cache und Snapshot-Mechanismus wie
/// `MiniMapSnapshot`. Pin ist dezenter (nicht overlay-dominant) weil der
/// darüberliegende Content eh das Hauptsujet ist.
struct MiniMapSnapshotFill: View {
    let coordinate: CLLocationCoordinate2D
    var metersSpan: CLLocationDistance = 500

    var body: some View {
        GeometryReader { geo in
            MiniMapSnapshot(coordinate: coordinate,
                            size: CGSize(width: max(geo.size.width, 1),
                                         height: max(geo.size.height, 1)),
                            cornerRadius: 0,
                            metersSpan: metersSpan,
                            showsPin: false)
        }
    }
}

/// Prozess-weiter In-Memory-Cache für die Mini-Map-Snapshots. NSCache räumt
/// unter Memory-Druck selbst auf.
private final class MiniMapCache {
    static let shared = MiniMapCache()
    private let cache = NSCache<NSString, UIImage>()
    init() { cache.countLimit = 128 }
    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }
    func set(_ img: UIImage, forKey key: String) {
        cache.setObject(img, forKey: key as NSString)
    }
}

