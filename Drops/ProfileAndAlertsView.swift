import SwiftUI
import MapKit
import AVFoundation
import FirebaseAuth
import FirebaseFirestore
@preconcurrency import Contacts

// MARK: - Freunde View

// Encounter-Modell ist in Models.swift definiert

struct FreundeView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("appLanguage") private var appLanguage = "de"
    @StateObject private var contactsVM = ContactsViewModel()
    @State private var showAddSheet = false
    @State private var showPhoneLinkSheet = false

    /// Öffnet UIActivityViewController mit dem Drops-Invite-Link. Wird vom
    /// FreundeEmptyState getriggert wenn der User dort "Einladungslink
    /// teilen" tappt — gleicher Inhalt wie das bestehende ShareLink im
    /// addFriendCard, nur programmatisch ansprechbar.
    private func presentInviteShareSheet() {
        let uid = FirebaseAuth.Auth.auth().currentUser?.uid ?? ""
        let url = URL(string: "https://apps.apple.com/de/app/drops-triff-leute/id6762097493?ref=invite_\(uid)")!
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        av.excludedActivityTypes = [.assignToContact, .saveToCameraRoll, .print]
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            var top = root
            while let presented = top.presentedViewController { top = presented }
            top.present(av, animated: true)
        }
    }
    @State private var addedContactUIDs: Set<String> = []
    @State private var profileParticipant: DropParticipant? = nil
    @State private var justConfirmedEncounterId: UUID? = nil
    @State private var auroraAnimate = false
    /// Scroll-adaptiv: true, sobald die Hero-Headline weggescrollt ist.
    /// Treibt den kompakten dazu-Chip oben (iOS Large→Compact-Pattern).
    @State private var friendsIsScrolled = false
    @State private var showImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var showImageSourceSheet = false
    /// Zwischenzustand damit das Picker-Sheet erst öffnet NACHDEM das
    /// Quellen-Sheet komplett dismissed ist — iOS kann nicht zwei Sheets
    /// parallel präsentieren, direktes Umschalten führte dazu dass die
    /// Kamera gar nicht aufging.
    @State private var pendingImageSource: UIImagePickerController.SourceType? = nil
    @State private var showEmojiPicker = false
    @State private var showScoreInfo = false
    @State private var showHeroPicker = false
    @State private var showNameChangeSheet = false
    @State private var nameChangeInput = ""
    /// Welches Stat-Tile ist aktuell im Detail-Sheet geöffnet?
    @State private var activeStatDetail: StatDetailKind? = nil
    /// Persistierter Profil-Hero-Hintergrund. Default: aurora.
    @AppStorage("ud_profileHeroTemplate") private var profileHeroTemplateRaw = ProfileHeroTemplate.aurora.rawValue
    /// Beta-Badge sichtbar wenn: Early-Adopter-Cutoff greift ODER Admin hat
    /// den Badge manuell gesetzt (Admin-Panel → Nutzer-Detail → BETA).
    private var qualifiesForBetaBadge: Bool {
        store.qualifiesForBetaBadge || store.hasAdminBetaBadge
    }

    /// Verifiziert durch ein bestätigtes Treffen — sobald mindestens eine
    /// Begegnung confirmed ist ODER ein vergangener Drop mit anderen
    /// Teilnehmern existiert, gilt der User als „in der echten Welt gesehen".
    /// Admin-Override (`hasAdminVerifiedBadge`) wird separat geprüft.
    private var hasVerifiedByMeeting: Bool {
        if store.encounters.contains(where: { $0.confirmed }) { return true }
        if store.pastDrops.contains(where: { $0.participants.count > 1 }) { return true }
        return false
    }

    /// Badge-Zeile unter dem Hero-Row im Profil-Header. Als eigener ViewBuilder
    /// extrahiert, weil die if-Kette inline den Swift-Compiler sprengt.
    /// Nutzt einen horizontalen ScrollView damit viele Badges nicht umbrechen
    /// oder abgeschnitten werden.
    @ViewBuilder
    private var profileBadgesRow: some View {
        let showVerified = store.hasAdminVerifiedBadge || hasVerifiedByMeeting
        let showTrusted  = store.hasAdminTrustedBadge
            || ReliabilityScore.isTrusted(forPoints: store.reliabilityScore.points)
        let showPlus     = FeatureFlags.dropsPlusEnabled && store.isDropsPlusActive
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if store.hasAdminFounderBadge { miniBadge(tr("badge.founder"), icon: "crown.fill", color: .brandOrange) }
                if showVerified               { miniBadge(tr("badge.verified"), icon: "checkmark.shield.fill", color: .brandViolet) }
                if store.hasAdminHostBadge    { miniBadge(tr("badge.host"), icon: "star.fill", color: .brandOrange) }
                if qualifiesForBetaBadge      { BetaBadge() }
                if showPlus                   { miniBadge(tr("badge.plus"), icon: "bolt.fill", color: .brandOrange) }
                if showTrusted                { miniBadge(tr("tier.trusted"), icon: "checkmark.seal.fill", color: .brandViolet) }
            }
        }
    }

    /// Konsistente Mini-Badge-Pille für Profil-Header.
    @ViewBuilder
    private func miniBadge(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            DazuIcon(icon, solid: true)
                .font(.system(size: 9, weight: .bold))
            Text(text.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .kerning(0.4)
        }
        .foregroundColor(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }

    private var profileHeroTemplate: ProfileHeroTemplate {
        ProfileHeroTemplate(rawValue: profileHeroTemplateRaw) ?? .aurora
    }

    private var onlineFriends: [User]  { store.friends.filter { $0.isAvailable } }
    private var offlineFriends: [User] { store.friends.filter { !$0.isAvailable } }

    /// Kontaktvorschläge: nur Leute die noch keine Freunde sind.
    /// Vergleich über `firebaseUID` (nicht `id.uuidString` — das ist nur die lokale UUID).
    /// Sortierung A→Z nach Name (case-insensitive, locale-aware).
    private var contactSuggestions: [RealtimeDBManager.ContactMatchResult] {
        let friendUIDs = Set(store.friends.compactMap { $0.firebaseUID })
        return contactsVM.matches
            .filter { !friendUIDs.contains($0.uid) && !addedContactUIDs.contains($0.uid) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppAuroraBackground()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {

                        // Klarer Hero mit großem Avatar links + Headline-Block
                        // rechts (Headline + Name/Alter). Alles in EINER
                        // Horizontal-Zeile mit klarer Baseline-Alignment,
                        // Badges-Row darunter.
                        VStack(alignment: .leading, spacing: 16) {
                            // Inline-Logo in der Hero (NICHT sticky). Beim
                            // Scrollen fadet oben ein kompakter dazu-Chip
                            // via scrollAdaptiveDazuHeader ein.
                            HStack {
                                DazuWordmark(color: .brandNight, dotColor: .brandOrange)
                                    .frame(height: 24)
                                Spacer()
                            }

                            HStack(alignment: .center, spacing: 16) {
                                // Avatar links, groß und ruhig.
                                Button(action: { showImageSourceSheet = true }) {
                                    ZStack(alignment: .bottom) {
                                        // Offener dazu-Logo-Ring in Orange —
                                        // Lücke oben rechts (zwischen 12 und
                                        // 3 Uhr), genau wie beim dazu-Logo
                                        // wo in der Lücke der Dot sitzt.
                                        // Trim 0→0.75 = 270° Pfad clockwise
                                        // ab 3 Uhr: 3→6→9→12 Uhr. Lücke
                                        // zwischen 12 Uhr und 3 Uhr.
                                        ZStack {
                                            Circle()
                                                .trim(from: 0.0, to: 0.75)
                                                .stroke(Color.brandOrangeFixed,
                                                        style: StrokeStyle(lineWidth: 4,
                                                                           lineCap: .round))
                                                .frame(width: 84, height: 84)

                                            Group {
                                                if let img = store.selfieImage {
                                                    Image(uiImage: img).resizable().scaledToFill()
                                                        .frame(width: 72, height: 72).clipShape(Circle())
                                                } else {
                                                    RemoteProfileImage(url: store.profileImageURL,
                                                                       fallbackEmoji: store.currentUser.emoji,
                                                                       size: 72, strokeColor: .clear)
                                                }
                                            }
                                        }

                                        // Kamera-Button mittig unten überlappend.
                                        ZStack {
                                            Circle().fill(Color.brandViolet).frame(width: 24, height: 24)
                                            DazuIcon("camera.fill", accent: false)
                                                .font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                                        }
                                        .overlay(Circle().stroke(Color.brandCream, lineWidth: 2))
                                        .offset(y: 4)
                                    }
                                    .frame(width: 86, height: 86)
                                }
                                .dropsPressable()

                                VStack(alignment: .leading, spacing: 4) {
                                    (Text(store.pendingNameChange ?? store.currentUser.name)
                                        .foregroundColor(.brandViolet)
                                     + Text(".").foregroundColor(.brandOrange))
                                        .font(.system(size: 34, weight: .bold, design: .rounded))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)

                                    if let age = store.userAge {
                                        Text("\(age) \(tr("profile.years_short"))")
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundColor(.brandNight.opacity(0.55))
                                    }
                                }
                                Spacer(minLength: 0)
                            }

                            profileBadgesRow
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                        // Drop-Statistiken
                        dropStatsSection

                        // „Letzte Begegnungen" entfernt — bestätigte Treffen
                        // triggern jetzt automatisch das Verifiziert-Badge
                        // oben, Freundesliste bleibt der primäre People-Hub.

                        // ── Eingehende Freundschaftsanfragen
                        if !store.incomingFriendRequests.isEmpty {
                            friendRequestsSection
                        }

                        // Online-Freunde
                        if !onlineFriends.isEmpty {
                            friendSection(
                                title: tr("profile.online_nearby"),
                                badge: "\(onlineFriends.count)",
                                friends: onlineFriends,
                                isOnline: true
                            )
                        }

                        // Offline-Section entfernt — Freunde-Stat-Kachel oben
                        // zeigt alle (online + offline) in einem Sheet.

                        // Freundesvorschläge (nach bestätigten Begegnungen)
                        if !store.friendSuggestions.isEmpty {
                            friendSuggestionsSection
                        }

                        // Kontakt-Vorschläge: Leute aus Adressbuch die auf Drops sind
                        if !contactSuggestions.isEmpty {
                            contactSuggestionsSection
                        }

                        // Drop-Verlauf
                        pastDropsSection

                        // Empty-State ODER Freund-hinzufügen-Card — niemals
                        // beide gleichzeitig, sonst stehen "Aus Kontakten
                        // hinzufügen" + "Einladungslink teilen" doppelt da.
                        // Empty-State hat die CTA-Buttons schon eingebaut.
                        if store.friends.isEmpty && store.pendingEncounters.isEmpty && store.friendSuggestions.isEmpty {
                            FreundeEmptyState(
                                onAddFromContacts: { showAddSheet = true },
                                onShareInvite: { presentInviteShareSheet() }
                            )
                            .padding(.top, 32)
                        } else {
                            addFriendCard
                        }

                        Spacer(minLength: 32)
                    }
                    .padding(.top, 8)
                }
                .onScrollGeometryChange(for: Bool.self) { geo in
                    // Chip faded ein, sobald das Inline-Logo weggescrollt
                    // ist (iOS Large→Compact-Übergang).
                    geo.contentOffset.y > 50
                } action: { _, newValue in
                    friendsIsScrolled = newValue
                }
                .scrollAdaptiveDazuHeader(isScrolled: friendsIsScrolled)
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(image: $store.selfieImage,
                                isPresented: $showImagePicker,
                                sourceType: imagePickerSource)
            }
            .sheet(isPresented: $showImageSourceSheet, onDismiss: {
                // Erst JETZT (nach Sheet-Dismiss-Animation) den eigentlichen
                // Picker öffnen. Direktes `showImagePicker = true` während
                // das Quellen-Sheet noch im Transition ist führt bei iOS
                // dazu dass der Picker gar nicht erscheint.
                if let src = pendingImageSource {
                    pendingImageSource = nil
                    imagePickerSource = src
                    showImagePicker = true
                }
            }) {
                VStack(spacing: 0) {
                    Capsule().fill(Color.brandNight.opacity(0.18))
                        .frame(width: 36, height: 4)
                        .padding(.top, 10)
                    Text(tr("profile.change_picture"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.brandNight)
                        .padding(.top, 18)
                        .padding(.bottom, 20)
                    VStack(spacing: 10) {
                        Button {
                            // Permission erst anfragen; wenn gewährt, pending
                            // merken und Sheet schließen → onDismiss öffnet
                            // den Picker. Simulator hat keine Kamera —
                            // Fallback auf .photoLibrary damit der Button
                            // dort nicht silent nix tut.
                            #if targetEnvironment(simulator)
                            let hasCamera = false
                            #else
                            let hasCamera = UIImagePickerController.isSourceTypeAvailable(.camera)
                            #endif
                            guard hasCamera else {
                                pendingImageSource = .photoLibrary
                                showImageSourceSheet = false
                                return
                            }
                            AVCaptureDevice.requestAccess(for: .video) { granted in
                                DispatchQueue.main.async {
                                    guard granted else {
                                        showImageSourceSheet = false
                                        return
                                    }
                                    pendingImageSource = .camera
                                    showImageSourceSheet = false
                                }
                            }
                        } label: {
                            Text(tr("profile.take_photo"))
                                .dropsPrimaryButton()
                        }
                        .dropsPressable()
                        Button {
                            pendingImageSource = .photoLibrary
                            showImageSourceSheet = false
                        } label: {
                            HStack {
                                Text(tr("profile.pick_from_library"))
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(.brandViolet)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Capsule().fill(Color.brandLavender))
                        }
                        .dropsPressable()
                        Button(role: .cancel) {
                            showImageSourceSheet = false
                        } label: {
                            Text(tr("profile.cancel"))
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(.brandNight.opacity(0.55))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .background(Color.brandCream.ignoresSafeArea())
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $showEmojiPicker) {
                EmojiPickerSheet(selected: store.currentUser.emoji) { emoji in
                    store.currentUser.emoji = emoji
                    store.saveAll()
                    // Emoji-Auswahl auch nach Firebase pushen — sonst geht
                    // sie beim Re-Login auf einem anderen Gerät verloren.
                    let email = (FirebaseAuth.Auth.auth().currentUser?.email
                                 ?? UserDefaults.standard.string(forKey: "ud_appleEmail"))
                    RealtimeDBManager.shared.saveUserProfile(
                        name:  store.currentUser.name,
                        emoji: emoji,
                        email: email
                    )
                }
                .presentationDetents([.height(460)])
                .presentationDragIndicator(.hidden)
                .sheetBackground()
            }
            .onChange(of: store.selfieImage) { _, img in
                guard img != nil else { return }
                store.saveAll()
                store.saveSelfie()   // Upload zu Firebase Storage → für andere Nutzer sichtbar
            }
            .task {
                // Sicherstellen dass createdAt geladen ist (idempotent)
                store.loadOwnCreatedAtIfNeeded()
            }
            .sheet(isPresented: $showScoreInfo) {
                ReliabilityInfoSheet(score: store.reliabilityScore)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                // Kontakte nur laden wenn Berechtigung bereits erteilt — kein Dialog beim Tab-Wechsel
                let status = CNContactStore.authorizationStatus(for: .contacts)
                if status == .authorized || status == .limited {
                    contactsVM.load()
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddFromContactsSheet().environmentObject(store)
            }
            // Gegenseitige Bestätigung: zeigt Freunde-Vorschläge der bestätigten Person
            .sheet(isPresented: Binding(
                get: { justConfirmedEncounterId != nil },
                set: { if !$0 { justConfirmedEncounterId = nil } }
            )) {
                if let eid = justConfirmedEncounterId,
                   let encounter = store.encounters.first(where: { $0.id == eid }) {
                    MutualConfirmationSheet(encounter: encounter)
                        .environmentObject(store)
                        .presentationDetents([.fraction(0.5)])
                        .presentationDragIndicator(.hidden)
                        .sheetBackground()
                }
            }
            .sheet(isPresented: Binding(
                get: { profileParticipant != nil },
                set: { if !$0 { profileParticipant = nil } }
            )) {
                if let p = profileParticipant {
                    // Match gegen die Freundesliste über Firebase-UID — wenn der
                    // User ein Freund ist, zeigt das Sheet "Freund entfernen"
                    // statt Block/Melden.
                    let isFriend: Bool = {
                        guard let uid = p.firebaseUID, !uid.isEmpty else { return false }
                        return store.friends.contains(where: { $0.firebaseUID == uid })
                    }()

                    if #available(iOS 16.4, *) {
                        MiniProfileSheet(
                            name: p.name,
                            emoji: p.emoji,
                            selfie: p.selfie,
                            profileImageURL: p.profileImageURL,
                            reliabilityScore: p.reliabilityScore,
                            subtitle: tr("profile.your_friend"),
                            accentColor: .brand,
                            userUID: p.firebaseUID,
                            canBlock: false,
                            isFriend: isFriend
                        ) { profileParticipant = nil }
                        .environmentObject(store)
                        .presentationDetents([.height(460)])
                        .presentationDragIndicator(.hidden)
                        .presentationBackground(.clear)
                    } else {
                        MiniProfileSheet(
                            name: p.name,
                            emoji: p.emoji,
                            selfie: p.selfie,
                            profileImageURL: p.profileImageURL,
                            reliabilityScore: p.reliabilityScore,
                            subtitle: tr("profile.your_friend"),
                            accentColor: .brand,
                            userUID: p.firebaseUID,
                            canBlock: false,
                            isFriend: isFriend
                        ) { profileParticipant = nil }
                        .environmentObject(store)
                        .presentationDetents([.height(460)])
                        .presentationDragIndicator(.hidden)
                    }
                }
            }
        }
    }

    // MARK: Eigener Status (Profil-Karte)

    private var myStatusCard: some View {
        // Clean Lavendel-Card im dazu-Design — kein bunter Hero-Gradient,
        // kein Emoji-Scatter mehr. Minimalistisch wie die Settings-Rows.
        myStatusCardContent
            .padding(.vertical, 4)
            .liquidGlass(cornerRadius: 20)
            .padding(.horizontal, 16)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: store.currentUser.isAvailable)
        .sheet(isPresented: $showHeroPicker) {
            ProfileHeroPickerSheet(selection: Binding(
                get: { profileHeroTemplate },
                set: {
                    profileHeroTemplateRaw = $0.rawValue
                    // In Firestore schreiben damit andere User es im MiniProfileSheet sehen
                    if let uid = Auth.auth().currentUser?.uid {
                        Firestore.firestore().collection("users").document(uid)
                            .setData(["heroTemplate": $0.rawValue], merge: true)
                    }
                }
            ))
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNameChangeSheet) {
            NameChangeSheet(
                currentName: store.currentUser.name,
                pendingName: store.pendingNameChange,
                cooldownDays: store.daysUntilNextNameChange,
                input: $nameChangeInput,
                onSubmit: { store.requestNameChange(to: nameChangeInput) },
                onCancel: { store.cancelNameChangeRequest() }
            )
            .environmentObject(store)
            .presentationDetents([.height(400)])
            .presentationDragIndicator(.visible)
        }
    }

    /// Innere Profil-Karte: Name/Badges links groß, Avatar oben rechts klein.
    /// Name ist nicht editierbar — Änderungen gehen nur über Support.
    private var myStatusCardContent: some View {
        HStack(alignment: .top, spacing: 16) {
            // Name + Alter + Badges + Trust-Marker — alles links, lesbar.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(store.pendingNameChange ?? store.currentUser.name)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(.brandNight)
                        .lineLimit(1)
                    if let age = store.userAge {
                        Text("· \(age)")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.5))
                    }
                }

                // Badges-Reihe (BETA / Plus / Community-Creator / Trust).
                HStack(spacing: 6) {
                    if qualifiesForBetaBadge {
                        BetaBadge()
                    }
                    if FeatureFlags.dropsPlusEnabled && store.isDropsPlusActive {
                        HStack(spacing: 3) {
                            DazuIcon("bolt.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("PLUS")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .kerning(0.4)
                        }
                        .foregroundColor(.brandOrange)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.brandOrange.opacity(0.14)))
                    }
                    if FeatureFlags.communitiesEnabled && store.isCommunityCreator {
                        CommunityCreatorBadge(community: store.myCommunity, compact: true)
                    }
                    if (store.hasAdminTrustedBadge || ReliabilityScore.isTrusted(forPoints: store.reliabilityScore.points)) {
                        HStack(spacing: 3) {
                            DazuIcon("checkmark.seal.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(tr("tier.trusted"))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.brandViolet)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.brandLavender))
                    }
                    Spacer(minLength: 0)
                }
            }

            // Avatar oben rechts — kompakter, Kamera-Badge zum Profilbild-Wechsel.
            Button(action: { showImageSourceSheet = true }) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let img = store.selfieImage {
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(width: 64, height: 64).clipShape(Circle())
                        } else {
                            RemoteProfileImage(url: store.profileImageURL,
                                               fallbackEmoji: store.currentUser.emoji,
                                               size: 64, strokeColor: .clear)
                        }
                    }
                    .overlay(Circle().stroke(Color.brandLavender, lineWidth: 3))

                    ZStack {
                        Circle().fill(Color.brandViolet).frame(width: 22, height: 22)
                        DazuIcon("camera.fill", accent: false)
                            .font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                    }
                }
            }
            .dropsPressable()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: Freundesvorschläge

    // MARK: Kontakt-Vorschläge aus Adressbuch

    private var contactSuggestionsSection: some View {
        VStack(spacing: 0) {
            HStack {
                DazuIcon("person.crop.circle.badge.checkmark")
                    .font(.system(size: 11))
                    .foregroundColor(.brand)
                Text(tr("profile.from_contacts"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .padding(.leading, 2)
                Spacer()
            }
            .padding(.leading, 20).padding(.bottom, 10)

            VStack(spacing: 0) {
                ForEach(Array(contactSuggestions.enumerated()), id: \.element.id) { idx, match in
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color.brand.opacity(0.12))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text(String(match.name.prefix(1)))
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.brand)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text(tr("profile.on_drops"))
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Button(action: {
                            // Schickt eine Anfrage — der Empfänger muss annehmen.
                            // Der Eintrag erscheint erst nach Accept in store.friends.
                            store.sendFriendRequest(to: match.uid)
                            addedContactUIDs.insert(match.uid)
                        }) {
                            Text(tr("profile.requests"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Color.brand)
                                .cornerRadius(20)
                        }
                        .dropsPressable()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)

                    if idx < contactSuggestions.count - 1 {
                        Divider().padding(.leading, 76)
                    }
                }
            }
            .liquidGlass(cornerRadius: Radius.xl)
            .padding(.horizontal, 16)
        }
    }

    // MARK: Freundesvorschläge (nach bestätigten Begegnungen)

    private var friendSuggestionsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tr("profile.maybe_know"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .padding(.leading, 4)
                DazuIcon("sparkles")
                    .font(.system(size: 11))
                    .foregroundColor(.brand)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.friendSuggestions) { suggestion in
                        VStack(spacing: 10) {
                            ZStack(alignment: .topTrailing) {
                                Circle()
                                    .fill(Color.bgSecondary)
                                    .frame(width: 64, height: 64)
                                    .overlay(DazuPersonIcon().font(.system(size: 32)))
                                    .overlay(Circle().stroke(Color.brand.opacity(0.2), lineWidth: 1.5))
                                // Dismiss-X
                                Button {
                                    withAnimation(.spring(response: 0.3)) {
                                        store.dismissSuggestion(id: suggestion.id)
                                    }
                                } label: {
                                    DazuIcon("xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.textTertiary)
                                        .background(Color.bgPrimary.clipShape(Circle()))
                                }
                                .accessibilityLabel(tr("profile.remove_suggestion"))
                                .offset(x: 4, y: -4)
                            }

                            VStack(spacing: 2) {
                                Text(suggestion.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text(suggestion.mutualFriend)
                                    .font(.system(size: 10))
                                    .foregroundColor(.textTertiary)
                                    .multilineTextAlignment(.center)
                            }

                            Button {
                                // Demo: Vorschlag zu Freunden hinzufügen
                                store.friends.append(User(
                                    name: suggestion.name,
                                    emoji: suggestion.emoji,
                                    isAvailable: false,
                                    statusMessage: tr("profile.newly_added")
                                ))
                                withAnimation(.spring(response: 0.3)) {
                                    store.dismissSuggestion(id: suggestion.id)
                                }
                            } label: {
                                Text(tr("profile.add"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.brandInverse)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.brand)
                                    .cornerRadius(20)
                            }
                            .dropsPressable()
                        }
                        .frame(width: 100)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 8)
                        .liquidGlass(cornerRadius: Radius.lg)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.horizontal, 0)
    }

    // MARK: Freundschaftsanfragen (eingehend)

    @ViewBuilder
    private var friendRequestsSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                DazuIcon("person.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.brand)
                Text(tr("profile.friend_requests"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary)
                Text("\(store.incomingFriendRequests.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.brandInverse)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.brand).cornerRadius(20)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(store.incomingFriendRequests) { req in
                    HStack(spacing: 12) {
                        // Avatar
                        if let url = req.fromImageURL, !url.isEmpty {
                            RemoteProfileImage(url: url,
                                               fallbackEmoji: "👋",
                                               size: 44)
                        } else {
                            Circle()
                                .fill(Color.brand.opacity(0.15))
                                .frame(width: 44, height: 44)
                                .overlay(DazuPersonIcon().font(.system(size: 22)))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(req.fromName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text(tr("profile.wants_to_be_friends"))
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()

                        // Ablehnen
                        Button(action: {
                            store.rejectFriendRequest(fromUID: req.fromUID)
                        }) {
                            DazuIcon("xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.textSecondary)
                                .frame(width: 36, height: 36)
                                .background(Color(UIColor.systemGray5), in: Circle())
                        }
                        .dropsPressable()

                        // Annehmen
                        Button(action: {
                            store.acceptFriendRequest(fromUID: req.fromUID)
                        }) {
                            DazuIcon("checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.brand, in: Circle())
                        }
                        .dropsPressable()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)

                    if req.id != store.incomingFriendRequests.last?.id {
                        Divider().padding(.leading, 70).padding(.trailing, 16)
                    }
                }
            }
            .liquidGlass(cornerRadius: Radius.xl)
            .padding(.horizontal, 16)
        }
    }

    // MARK: Freunde Sektion

    @ViewBuilder
    private func friendSection(title: String, badge: String?, friends: [User], isOnline: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .padding(.leading, 4)
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.brandInverse)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.brand).cornerRadius(20)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(friends) { friend in
                    FreundRow(friend: friend, isOnline: isOnline) {
                        profileParticipant = DropParticipant(
                            name: friend.name,
                            emoji: friend.emoji,
                            selfie: nil,
                            reliabilityScore: friend.reliabilityPoints,
                            profileImageURL: friend.profileImageURL,
                            firebaseUID: friend.firebaseUID
                        )
                    }
                    if friend.id != friends.last?.id {
                        Divider().padding(.leading, 70).padding(.trailing, 16)
                    }
                }
            }
            .liquidGlass(cornerRadius: Radius.xl)
            .padding(.horizontal, 16)
        }
    }

    // MARK: Wer kommt zu meinem Drop

    @ViewBuilder private var joinNotificationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                DazuIcon("figure.walk.arrival")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.brand)
                Text(tr("profile.coming_to_drop"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("\(store.activeJoinNotifications.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.brand)
                    .cornerRadius(Radius.md)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(Array(store.activeJoinNotifications.enumerated()), id: \.element.id) { i, note in
                    JoinNotificationRow(note: note)
                        .environmentObject(store)
                    if i < store.activeJoinNotifications.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .liquidGlass(cornerRadius: Radius.lg)
            .padding(.horizontal, 16)
        }
    }

    // MARK: Letzte Begegnungen

    @ViewBuilder private var encountersSection: some View {
        // Pending immer oben, dann bestätigte/abgelehnte nach Datum sortiert.
        // `visibleEncounters` blendet Pre-Encounter aus, deren Drop noch
        // läuft — die sollen erst nach Drop-Ende in „Letzte Begegnungen"
        // auftauchen.
        let sorted = store.visibleEncounters.sorted { a, b in
            let aPending = !a.confirmed && !a.denied && !a.isExpired
            let bPending = !b.confirmed && !b.denied && !b.isExpired
            if aPending != bPending { return aPending }
            return a.createdAt > b.createdAt
        }

        VStack(spacing: 0) {
            HStack {
                Text(tr("profile.recent_encounters"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .padding(.leading, 4)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.bottom, 8)
            .onAppear { store.markEncountersSeen() }

            VStack(spacing: 0) {
                if sorted.isEmpty {
                    // Inline-Empty-State — vorher renderte die Card komplett
                    // leer, was wie ein Layout-Bug aussah. Jetzt klarer
                    // Hint, wie Begegnungen entstehen.
                    // Minimalistischer Empty-State — nur zentrierter Text,
                    // kein Icon-Row. Fügt sich ruhig ins Rondesignlab-Design.
                    VStack(spacing: 6) {
                        Text(tr("profile.no_encounters_yet"))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.brandNight)
                        Text(tr("profile.no_encounters_sub"))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
                } else {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { i, encounter in
                        EncounterRow(encounter: encounter)
                        if i < sorted.count - 1 {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
            }
            .liquidGlass(cornerRadius: Radius.lg)
            .padding(.horizontal, 16)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: store.visibleEncounters.map { $0.confirmed || $0.denied })
    }

    // MARK: Drop-Statistiken

    /// Anzahl aufeinanderfolgender ISO-Wochen mit mindestens einem Drop,
    /// rückwärts gerechnet ab aktueller (oder letzter) Woche.
    private var weeklyStreak: Int {
        let cal = Calendar(identifier: .iso8601)
        let today = cal.startOfDay(for: Date())
        guard let currentWeekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        ) else { return 0 }
        let dropWeeks = Set(store.pastDrops.compactMap { drop -> Date? in
            cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: drop.date))
        })
        var probe = currentWeekStart
        if !dropWeeks.contains(probe) {
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: probe),
                  dropWeeks.contains(prev) else { return 0 }
            probe = prev
        }
        var streak = 0
        while dropWeeks.contains(probe) {
            streak += 1
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: probe) else { break }
            probe = prev
        }
        return streak
    }

    @ViewBuilder private var dropStatsSection: some View {
        // Stats reflektieren nur BEENDETE Drops (pastDrops). Laufende Drops
        // werden NICHT mitgezählt — sonst springt der Counter hoch sobald
        // jemand joint, was suggeriert dass der Drop „erfolgreich" war
        // obwohl er noch läuft und ggf. abgebrochen wird oder No-Shows hat.
        // Konsistent zur cancelDrop-Logik wo Drops erst nach Beendigung
        // mit Erfolg im Verlauf landen.
        let total   = store.pastDrops.count
        let hosted  = store.pastDrops.filter { $0.wasHost }.count
        let joined  = total - hosted
        let streak  = weeklyStreak
        // Stats werden IMMER gezeigt — auch bei 0 Drops/Commits, damit der
        // User sieht was er sammeln kann (Demo-Look auch beim Erst-Onboarding).
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(tr("profile.stats"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                if streak > 0 {
                    HStack(spacing: 4) {
                        DazuIcon("flame.fill").font(.system(size: 11)).foregroundColor(.accentOrange)
                        Text("\(streak) Woche\(streak == 1 ? "" : "n") aktiv")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accentOrange)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentOrange.opacity(0.12), in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 2)

            // Stat-Tiles: 3er-Row statt 2x2. „Treffen" (BLE-Showups) raus
            // weil Semantik unklar war und sich mit „Beigetreten" überlappt.
            HStack(spacing: 12) {
                StatTile(value: "\(total)",
                         label: tr("profile.drops_total"),
                         icon: "runde",
                         color: Color.brandViolet,
                         onTap: { activeStatDetail = .roundsCreated })
                    .modifier(DazuStatCardStyle())
                StatTile(value: "\(joined)",
                         label: tr("profile.joined"),
                         icon: "person.fill.badge.plus",
                         color: Color.brandViolet,
                         onTap: { activeStatDetail = .roundsJoined })
                    .modifier(DazuStatCardStyle())
                StatTile(value: "\(store.friends.count)",
                         label: tr("profile.friends"),
                         icon: "person.2.fill",
                         color: Color.brandViolet,
                         onTap: { activeStatDetail = .friends })
                    .modifier(DazuStatCardStyle())
            }
            .padding(.vertical, 2)
            .sheet(item: $activeStatDetail) { kind in
                StatDetailSheet(kind: kind)
                    .environmentObject(store)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }

            // ── Interessen-Chips (Aktivitäts-Häufigkeit) ─────────────
            // Zeigt die Top-6 Aktivitäten des Users nach Häufigkeit, als
            // horizontale Chip-Row. Ersetzt die alte „Lieblings-Aktivität"
            // (zeigte nur Einzel-Favorit) → macht die Persönlichkeit
            // sichtbar wenn jemand z.B. „Kaffee × 12 · Yoga × 8" häufig
            // mischt. Nur wenn ≥1 Drop existiert.
            if total > 0 {
                let chips = topActivityChips(from: store.pastDrops, limit: 6)
                if !chips.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("profile.interests"))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.textTertiary)
                            .kerning(0.6)
                            .textCase(.uppercase)
                            .padding(.horizontal, 2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(chips, id: \.name) { chip in
                                    HStack(spacing: 6) {
                                        DazuActivityIcon(chip.emoji,
                                                         tint: .brandVioletFixed,
                                                         dotColor: .brandOrangeFixed)
                                            .font(.system(size: 14))
                                        Text(chip.name)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundColor(.textPrimary)
                                        Text("×\(chip.count)")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundColor(.brandViolet)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(Capsule().fill(Color.brandLavender.opacity(0.55)))
                                    .overlay(Capsule().stroke(Color.brandViolet.opacity(0.15), lineWidth: 0.5))
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                    .padding(.top, 4)
                }

                // ── Hotspot-Map: alle vergangenen Drop-Locations auf einen Blick
                ProfileHotspotMap(drops: store.pastDrops)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // Drop-Verlauf wird jetzt im StatDetailSheet (.roundsCreated/.roundsJoined)
    // beim Tap auf die Runden-Kachel gezeigt — kein eigener Block im Profil mehr.
    @ViewBuilder private var pastDropsSection: some View { EmptyView() }

    // MARK: Freund hinzufügen

    private var addFriendCard: some View {
        // Gleicher Stil wie FreundeEmptyState (Sunset-Gradient-Pill für die
        // Primary-Action „Aus Kontakten hinzufügen", Brand-Outline-Pill für
        // „Einladungslink teilen") — vorher hatte diese Card noch das alte
        // Row-Layout mit Icon-Quadraten und Chevrons, was inkonsistent zum
        // Empty-State aussah. Jetzt einheitlich.
        VStack(spacing: 8) {
            // Hinweis-Banner wenn der eigene Account noch keine Phone-
            // Nummer verknüpft hat — ohne Nummer finden einen Freunde
            // nicht via Kontakt-Abgleich.
            let hasPhone = (Auth.auth().currentUser?.phoneNumber != nil)
                || (Auth.auth().currentUser?.providerData.contains { $0.providerID == "phone" } ?? false)
            if !hasPhone {
                Button(action: { showPhoneLinkSheet = true }) {
                    HStack(spacing: 8) {
                        DazuIcon("phone.badge.plus")
                            .font(.system(size: 13, weight: .bold))
                        Text(tr("profile.link_phone_hint"))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        DazuIcon("chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.brandViolet)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.brandLavender.opacity(0.55)))
                }
                .dropsPressable()
                .padding(.bottom, 4)
            }

            Button(action: { showAddSheet = true }) {
                HStack(spacing: 8) {
                    DazuIcon("person.crop.circle.badge.plus", accent: false)
                        .font(.system(size: 15, weight: .semibold))
                    Text(tr("profile.add_from_contacts"))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18).padding(.vertical, 11)
                .background(Capsule().fill(Color.brandVioletFixed))
            }
            .dropsPressable()

            // App-Store-Link mit User-UID als Tracking-Parameter (`ref`).
            // Funktioniert für jeden Empfänger:
            //   - App nicht installiert → App Store öffnet, User installiert
            //   - App installiert → "Öffnen"-Button im Store, App startet
            // Vorher Universal-Link auf drops-app.de/invite/{UID} — der ging
            // ins Leere weil die Web-Seite 404 lieferte und Apex-Redirect
            // den AASA-Fetch von Apple verhindert hat.
            ShareLink(item: URL(string: "https://apps.apple.com/de/app/drops-triff-leute/id6762097493?ref=invite_\(FirebaseAuth.Auth.auth().currentUser?.uid ?? "")")!) {
                HStack(spacing: 6) {
                    DazuIcon("square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                    Text(tr("profile.share_invite_link"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.brand)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(Color.brand.opacity(0.10)))
            }
            .dropsPressable()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .sheet(isPresented: $showAddSheet) {
            AddFromContactsSheet().environmentObject(store)
        }
        .sheet(isPresented: $showPhoneLinkSheet) {
            PhoneLinkSheet().environmentObject(store)
        }
    }
}

// MARK: - Drop Summary Sheet

struct DropSummarySheet: View {
    let drop: PastDrop
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var confirmDelete = false

    private var showUps: [PastDropParticipant]   { drop.participants.filter { $0.didShowUp } }
    private var noShows: [PastDropParticipant]    { drop.participants.filter { !$0.didShowUp } }
    private var reliabilityColor: Color {
        switch drop.avgReliability {
        case 85...: return .onlineGreen
        case 65..<85: return .accentOrange
        default: return .red
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Header ────────────────────────────────────────────
                    VStack(spacing: 10) {
                        DazuActivityIcon(drop.activityEmoji)
                            .font(.system(size: 52))
                            .frame(width: 84, height: 84)
                            .background(Color.brand.opacity(0.08), in: Circle())

                        Text(drop.activityName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.textPrimary)

                        HStack(spacing: 6) {
                            DazuIcon("mappin.circle.fill", accent: false)
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                            Text(drop.locationName)
                                .font(.system(size: 14))
                                .foregroundColor(.textSecondary)
                            Text("·")
                                .foregroundColor(.textTertiary)
                            Text(drop.dateLabel + " " + drop.timeLabel)
                                .font(.system(size: 14))
                                .foregroundColor(.textSecondary)
                        }

                        if drop.wasHost {
                            HStack(spacing: 4) {
                                DazuIcon("crown.fill")
                                    .font(.system(size: 10))
                                Text(tr("profile.was_host"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.accentOrange)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.accentOrange.opacity(0.1), in: Capsule())
                        }
                    }
                    .padding(.top, 8)

                    // ── Stat-Kacheln ──────────────────────────────────────
                    HStack(spacing: 12) {
                        statTile(value: "\(drop.participantCount)",
                                 label: tr("drop_summary.there"),
                                 icon: "person.2.fill",
                                 color: .brand)
                        statTile(value: "\(drop.avgReliability)%",
                                 label: tr("drop_summary.reliability"),
                                 icon: "checkmark.seal.fill",
                                 color: reliabilityColor)
                        statTile(value: "\(showUps.count)/\(drop.participantCount)",
                                 label: tr("drop_summary.appeared"),
                                 icon: "figure.walk.arrival",
                                 color: .onlineGreen)
                    }
                    .padding(.horizontal, 16)

                    // ── Teilnehmer ─────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tr("profile.participants"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .padding(.horizontal, 20).padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(Array(drop.participants.enumerated()), id: \.element.id) { i, p in
                                HStack(spacing: 14) {
                                    // Profilbild wenn vorhanden, sonst Emoji-Fallback.
                                    // Border bleibt rot bei No-Show — Visual-Cue gleich
                                    // wie vorher.
                                    Group {
                                        if let url = p.profileImageURL, !url.isEmpty {
                                            RemoteProfileImage(
                                                url: url,
                                                fallbackEmoji: p.emoji,
                                                size: 38,
                                                strokeColor: p.didShowUp ? Color.clear : Color.accentRed.opacity(0.2)
                                            )
                                        } else {
                                            DazuPersonIcon()
                                                .font(.system(size: 22))
                                                .frame(width: 38, height: 38)
                                                .background(p.didShowUp ? Color.brand.opacity(0.07) : Color.accentRed.opacity(0.06),
                                                            in: Circle())
                                                .overlay(
                                                    Circle().stroke(p.didShowUp ? Color.clear : Color.accentRed.opacity(0.2), lineWidth: 1)
                                                )
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(p.name)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(.textPrimary)
                                            if p.wasHost {
                                                DazuIcon("crown.fill")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.accentOrange)
                                            }
                                        }
                                        if !p.didShowUp {
                                            Text(tr("profile.not_shown"))
                                                .font(.system(size: 11))
                                                .foregroundColor(.red.opacity(0.7))
                                        }
                                    }

                                    Spacer()

                                    // Reliability-Score in % anzeigen — cappen auf 100
                                    // damit Roh-Punktestände (z.B. 202) nicht als
                                    // "202%" erscheinen.
                                    let cappedScore = min(p.reliabilityScore, 100)
                                    let scoreColor: Color = {
                                        switch cappedScore {
                                        case 85...: return .onlineGreen
                                        case 65..<85: return .accentOrange
                                        default: return .red
                                        }
                                    }()
                                    VStack(spacing: 3) {
                                        Text("\(cappedScore)%")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(scoreColor)
                                        // Mini-Balken
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(Color.primary.opacity(0.07))
                                                    .frame(height: 3)
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(scoreColor)
                                                    .frame(width: geo.size.width * CGFloat(cappedScore) / 100, height: 3)
                                            }
                                        }
                                        .frame(width: 44, height: 3)
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 11)

                                if i < drop.participants.count - 1 {
                                    Divider().padding(.leading, 68)
                                }
                            }
                        }
                        .liquidGlass(cornerRadius: Radius.lg)
                        .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 32)
                }
            }
            .navigationTitle(tr("drop_summary.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Links: Löschen (destruktiv) — vor allem für Test-Runden
                // damit die „Dabei gewesen"-Liste sauber bleibt.
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.red)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("common.done")) { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.brand)
                }
            }
            .confirmationDialog("Vergangene Runde löschen?",
                                isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    store.deletePastDrop(id: drop.id)
                    dismiss()
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text(tr("profile.delete_past_warning")
                    .replacingOccurrences(of: "{name}", with: "\u{201E}\(drop.activityName)\u{201C}"))
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private func statTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            DazuIcon(icon)
                .font(.system(size: 18))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: Radius.card))
    }
}

// MARK: - Encounter Row

struct EncounterRow: View {
    let encounter: Encounter
    @EnvironmentObject var store: AppStore
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var requestSent = false

    /// User ist bereits Freund? Dann „Hinzufügen"-Button ausblenden.
    private var isAlreadyFriend: Bool {
        guard let uid = encounter.friendUID else { return false }
        return store.friends.contains(where: { $0.firebaseUID == uid })
    }

    // Local-only state für „Angefragt"-Feedback nach Tap. Echte Server-
    // seitige Pending-Request-Liste pflegen wir nicht — wäre extra Round-
    // trip ohne klaren Mehrwert (User dismisst die Encounter eh nach Add).

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // Avatar — Profilbild wenn vorhanden, sonst Emoji-Fallback.
                if let url = encounter.friendProfileImageURL, !url.isEmpty {
                    RemoteProfileImage(
                        url: url,
                        fallbackEmoji: encounter.friendEmoji,
                        size: 48,
                        strokeColor: .clear
                    )
                } else {
                    ZStack {
                        Circle().fill(Color.brand.opacity(0.1)).frame(width: 48, height: 48)
                        DazuPersonIcon().font(.system(size: 24))
                    }
                }

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(encounter.activityEmoji + " " + encounter.activityName + " mit " + encounter.friendName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(encounter.timeAgoLabel)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }
                }

                Spacer()

                // Status-Badge / Aktionen
                if encounter.confirmed {
                    if isAlreadyFriend {
                        // Schon befreundet → einfaches Häkchen
                        HStack(spacing: 4) {
                            DazuIcon("checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.onlineGreen)
                            Text(tr("profile.friended"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.onlineGreen)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.onlineGreen.opacity(0.1), in: Capsule())
                    } else if requestSent {
                        // Request schon raus → wartet auf Antwort
                        HStack(spacing: 4) {
                            DazuIcon("hourglass")
                                .font(.system(size: 11))
                            Text(tr("profile.requested"))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.accentOrange)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.accentOrange.opacity(0.10), in: Capsule())
                    } else if let uid = encounter.friendUID {
                        // Hauptpfad: Add-Friend-Button (CTA in Brand-Sunset-Gradient)
                        Button {
                            store.sendFriendRequest(to: uid)
                            withAnimation(.spring(response: 0.3)) { requestSent = true }
                        } label: {
                            HStack(spacing: 4) {
                                DazuIcon("person.badge.plus", accent: false)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(tr("profile.add_friend"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [Color.auroraOrange, Color.auroraGreen],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                            )
                            .shadow(color: Color.auroraOrange.opacity(0.30), radius: 5, y: 1)
                        }
                        .dropsPressable()
                    } else {
                        // Confirmed aber keine UID — Legacy-Fallback
                        HStack(spacing: 4) {
                            DazuIcon("checkmark.circle.fill")
                                .font(.system(size: 14))
                            Text(tr("profile.confirmed"))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.onlineGreen)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.onlineGreen.opacity(0.1), in: Capsule())
                    }
                } else if encounter.denied || encounter.isExpired {
                    Text(encounter.isExpired && !encounter.denied ? tr("profile.expired") : tr("profile.not_met"))
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(UIColor.systemGray5), in: Capsule())
                } else {
                    // BLE-Bestätigung läuft automatisch im Hintergrund
                    HStack(spacing: 4) {
                        DazuIcon("antenna.radiowaves.left.and.right")
                            .font(.system(size: 11))
                            .foregroundColor(.brand)
                        Text(tr("profile.detecting"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.brand)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.brand.opacity(0.08), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .opacity(encounter.denied || encounter.isExpired ? 0.45 : 1)
    }
}

// MARK: - Join Notification Row (kein Accept/Decline — direkt dabei)

struct JoinNotificationRow: View {
    let note: JoinRequest
    @EnvironmentObject var store: AppStore
    @AppStorage("appLanguage") private var appLanguage = "de"

    /// Entfernung des Joiners vom Drop (simuliert)
    private var distanceLabel: String? {
        guard let joinerCoord = note.simulatedCoordinate,
              let dropCoord = note.dropCoordinate else { return nil }
        let joiner = CLLocation(latitude: joinerCoord.latitude, longitude: joinerCoord.longitude)
        let drop   = CLLocation(latitude: dropCoord.latitude, longitude: dropCoord.longitude)
        let m = joiner.distance(from: drop)
        let walkMins = max(1, Int(m / 80))
        let distStr = m < 1000 ? "\(Int(m))m" : String(format: "%.1fkm", m / 1000)
        return "~\(walkMins) Min · \(distStr) vom Plan"
    }

    var body: some View {
        HStack(spacing: 14) {
            // Emoji-Avatar mit Lauf-Animation
            ZStack {
                Circle()
                    .fill(Color.onlineGreen.opacity(0.12))
                    .frame(width: 44, height: 44)
                DazuPersonIcon()
                    .font(.system(size: 20))
                // Kleiner grüner Punkt: online / unterwegs
                Circle()
                    .fill(Color.onlineGreen)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color.bgPrimary, lineWidth: 1.5))
                    .offset(x: 14, y: 14)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(note.requesterName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(tr("profile.coming"))
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                }
                if let dist = distanceLabel {
                    HStack(spacing: 4) {
                        DazuIcon("figure.walk")
                            .font(.system(size: 10))
                            .foregroundColor(.onlineGreen)
                        Text(dist)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.onlineGreen)
                    }
                } else {
                    Text("\(note.dropActivity) · \(note.timeAgoLabel)")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            DazuIcon("figure.walk.arrival")
                .font(.system(size: 14))
                .foregroundColor(.onlineGreen)
                .padding(9)
                .background(Color.onlineGreen.opacity(0.10), in: Circle())
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

// MARK: - Mutual Confirmation Sheet

struct MutualConfirmationSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let encounter: Encounter
    @AppStorage("appLanguage") private var appLanguage = "de"

    /// Vorschläge die durch diese Begegnung generiert wurden
    private var suggestions: [FriendSuggestion] {
        store.friendSuggestions.filter {
            $0.mutualFriend == tr("profile.met_via").replacingOccurrences(of: "{name}", with: encounter.friendName)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(UIColor.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 12).padding(.bottom, 20)

            // Header
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.onlineGreen.opacity(0.12)).frame(width: 52, height: 52)
                    DazuPersonIcon().font(.system(size: 26))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        DazuIcon("checkmark.circle.fill")
                            .font(.system(size: 13)).foregroundColor(.onlineGreen)
                        Text(tr("profile.also_confirmed").replacingOccurrences(of: "{name}", with: encounter.friendName))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.textPrimary)
                    }
                    Text(tr("profile.maybe_know_more").replacingOccurrences(of: "{name}", with: encounter.friendName))
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            if suggestions.isEmpty {
                VStack(spacing: 10) {
                    DazuIcon("person.2.fill", accent: false)
                        .font(.system(size: 32)).foregroundColor(.textTertiary)
                    Text(tr("profile.no_suggestions"))
                        .font(.system(size: 14)).foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(suggestions) { s in
                            VStack(spacing: 10) {
                                Circle()
                                    .fill(Color.white.opacity(0.75))
                                    .frame(width: 60, height: 60)
                                    .overlay(DazuPersonIcon().font(.system(size: 28)))
                                    .overlay(Circle().stroke(Color.brand.opacity(0.2), lineWidth: 1.5))
                                VStack(spacing: 2) {
                                    Text(s.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                    Text(tr("profile.about_x").replacingOccurrences(of: "{name}", with: encounter.friendName))
                                        .font(.system(size: 10)).foregroundColor(.textTertiary)
                                        .multilineTextAlignment(.center)
                                }
                                Button {
                                    store.friends.append(User(
                                        name: s.name, emoji: s.emoji,
                                        isAvailable: false, statusMessage: tr("profile.newly_added")
                                    ))
                                    store.dismissSuggestion(id: s.id)
                                } label: {
                                    Text(tr("profile.add"))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.brandInverse)
                                        .padding(.horizontal, 14).padding(.vertical, 6)
                                        .background(Color.brand, in: Capsule())
                                }
                                .dropsPressable()
                            }
                            .frame(width: 100)
                            .padding(.vertical, 14).padding(.horizontal, 8)
                            .liquidGlass(cornerRadius: Radius.lg)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 16)
            }

            Spacer()

            Button(tr("common.done")) { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.brand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .liquidGlass(cornerRadius: 16)
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
        }
    }
}

// MARK: - Contacts View Model

/// Klassen-basiertes ViewModel für den Kontakt-Import.
/// Durch @StateObject bleibt die CNContactStore-Instanz sicher am Leben —
/// kein ARC-Problem und keine SwiftUI-Struct-Kopier-Falle.
@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var matches: [RealtimeDBManager.ContactMatchResult] = []
    @Published var isLoading = false
    @Published var permissionDenied = false

    /// Einzige Instanz — wird nie neu erstellt solange die Sheet-View lebt.
    private let contactStore = CNContactStore()

    func load() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized, .limited:
            fetchContacts()
        case .notDetermined:
            isLoading = true
            contactStore.requestAccess(for: .contacts) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.fetchContacts()
                    } else {
                        self.isLoading = false
                        self.permissionDenied = true
                    }
                }
            }
        default:
            permissionDenied = true
        }
    }

    func retry() {
        permissionDenied = false
        load()
    }

    private func fetchContacts() {
        isLoading = true
        let cs = contactStore
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let keys = [CNContactPhoneNumbersKey,
                        CNContactEmailAddressesKey] as [CNKeyDescriptor]
            var phones: [String] = []
            var emails: [String] = []
            let request = CNContactFetchRequest(keysToFetch: keys)
            try? cs.enumerateContacts(with: request) { contact, _ in
                for ph in contact.phoneNumbers {
                    phones.append(ph.value.stringValue)
                }
                for em in contact.emailAddresses {
                    emails.append(em.value as String)
                }
            }
            // RealtimeDBManager ist @MainActor — Aufruf zurück auf den Main-Thread.
            DispatchQueue.main.async {
                RealtimeDBManager.shared.lookupContactsOnDrops(phones: phones, emails: emails) { [weak self] results in
                    DispatchQueue.main.async {
                        self?.isLoading = false
                        self?.matches = results
                    }
                }
            }
        }
    }
}

// MARK: - Add From Contacts Sheet

struct AddFromContactsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLanguage") private var appLanguage = "de"
    @StateObject private var vm = ContactsViewModel()
    @State private var searchText = ""
    @State private var addedUIDs: Set<String> = []

    private var filtered: [RealtimeDBManager.ContactMatchResult] {
        // Bereits hinzugefügte Freunde ausblenden — sowohl aus der lokalen store.friends-Liste
        // (Firebase-UID-Match) als auch aus `addedUIDs` (gerade im Sheet getappt).
        let friendUIDs = Set(store.friends.compactMap { $0.firebaseUID })
        let base = vm.matches.filter {
            !friendUIDs.contains($0.uid) && !addedUIDs.contains($0.uid)
        }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Suchleiste
                HStack(spacing: 10) {
                    DazuIcon("magnifyingglass").foregroundColor(.textTertiary)
                    TextField(tr("profile.search_name"), text: $searchText)
                        .font(.system(size: 15)).foregroundColor(.textPrimary)
                }
                .padding(12)
                .liquidGlass(cornerRadius: 14)
                .padding(.horizontal, 16).padding(.vertical, 12)

                if vm.isLoading {
                    Spacer()
                    DazuLoader().tint(.brand).scaleEffect(0.9)
                        .tint(.brand)
                    Text(tr("profile.searching_contacts"))
                        .font(.system(size: 13)).foregroundColor(.textSecondary)
                        .padding(.top, 10)
                    Spacer()
                } else if vm.permissionDenied {
                    Spacer()
                    VStack(spacing: 12) {
                        DazuIcon("person.crop.circle.badge.xmark", accent: false)
                            .font(.system(size: 40)).foregroundColor(.textTertiary)
                        Text(tr("profile.no_contact_access"))
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(.textPrimary)
                        Text(tr("profile.allow_contact_access"))
                            .font(.system(size: 13)).foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                        Button(tr("profile.open_settings")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.brand)
                    }
                    Spacer()
                } else if vm.matches.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        DazuIcon("person.2.slash")
                            .font(.system(size: 40)).foregroundColor(.textTertiary)
                        Text(tr("profile.no_contacts_on_drops"))
                            .font(.system(size: 14)).foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                    }
                    Spacer()
                } else {
                    // Treffer
                    HStack(spacing: 8) {
                        DazuIcon("person.2.fill")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.brand)
                        Text((vm.matches.count == 1 ? tr("contacts.on_dazu_singular") : tr("contacts.on_dazu_plural"))
                            .replacingOccurrences(of: "{n}", with: "\(vm.matches.count)"))
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.textTertiary)
                            .kerning(0.4)
                        Spacer()
                    }
                    .padding(.horizontal, 20).padding(.bottom, 8)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, match in
                                ContactMatchRow(match: match, isAdded: addedUIDs.contains(match.uid)) {
                                    // Anfrage schicken — kein direkter Add mehr.
                                    // Der Empfänger muss die Anfrage annehmen.
                                    store.sendFriendRequest(to: match.uid)
                                    addedUIDs.insert(match.uid)
                                }
                                if idx < filtered.count - 1 {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                        .liquidGlass(cornerRadius: Radius.xl)
                        .padding(.horizontal, 16)
                    }
                }

                // Einladen Button — App-Store-Link (vorher fälschlich auf
                // drops.app/invite, das ist eine fremde Domain). Der echte
                // App-Store-Link funktioniert in beide Richtungen: Empfänger
                // ohne App landet im Store + installiert; Empfänger mit App
                // sieht "Öffnen" und startet die App direkt aus dem Store.
                ShareLink(item: URL(string: "https://apps.apple.com/de/app/drops-triff-leute/id6762097493")!) {
                    HStack(spacing: 8) {
                        DazuIcon("square.and.arrow.up")
                        Text(tr("profile.invite_others"))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.brand)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .liquidGlass(cornerRadius: 16)
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
            }
            .background(Color.bgGrouped.ignoresSafeArea())
            .navigationTitle(tr("profile.add_friends"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(tr("profile.done")) { dismiss() }.foregroundColor(.brand)
                }
            }
            .onAppear {
                // Kleiner Delay damit die Sheet-Animation fertig ist bevor der System-Dialog erscheint
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { vm.load() }
            }
            .onChange(of: scenePhase) { _, phase in
                // Wenn User aus iOS-Einstellungen zurückkommt → Zugriff erneut prüfen
                if phase == .active && vm.permissionDenied {
                    vm.retry()
                }
            }
        }
    }
}

private struct ContactMatchRow: View {
    let match: RealtimeDBManager.ContactMatchResult
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.brand.opacity(0.1))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(match.name.prefix(1)))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.brand)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(match.name)
                    .font(.system(size: 15, weight: .medium)).foregroundColor(.textPrimary)
                Text(tr("profile.uses_drops_label"))
                    .font(.system(size: 12)).foregroundColor(.textSecondary)
            }
            Spacer()
            Button(action: onAdd) {
                Text(isAdded ? tr("profile.added_check") : tr("profile.add"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isAdded ? .onlineGreen : .brandInverse)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(isAdded ? Color.onlineGreen.opacity(0.15) : Color.brand, in: Capsule())
            }
            .dropsPressable()
            .disabled(isAdded)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isAdded)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

struct SuggestionRow: View {
    let name: String
    let emoji: String
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var added = false
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.brandLavender).frame(width: 44, height: 44)
                DazuProfileIcon(size: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 15, weight: .medium)).foregroundColor(.textPrimary)
                Text(tr("profile.uses_drops")).font(.system(size: 12)).foregroundColor(.textSecondary)
            }
            Spacer()
            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { added = true } }) {
                Text(added ? "✓" : tr("profile.add"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(added ? .onlineGreen : .brandInverse)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(added ? Color.onlineGreen.opacity(0.15) : Color.brand, in: Capsule())
            }
            .dropsPressable()
            .disabled(added)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: - Freund Row

struct FreundRow: View {
    @EnvironmentObject var store: AppStore
    let friend: User
    let isOnline: Bool
    var onProfileTap: (() -> Void)? = nil
    @AppStorage("appLanguage") private var appLanguage = "de"
    @State private var invited = false

    var body: some View {
        Button { onProfileTap?() } label: {
            HStack(spacing: 14) {
                // Profilbild mit Online-Dot
                ZStack {
                    if let url = friend.profileImageURL, !url.isEmpty {
                        RemoteProfileImage(
                            url: url,
                            fallbackEmoji: friend.emoji,
                            size: 44,
                            strokeColor: .clear
                        )
                    } else {
                        AvatarBadge(emoji: friend.emoji, size: 44, isAvailable: false)
                    }
                    // Online-Dot
                    if isOnline {
                        Circle()
                            .fill(Color.onlineGreen)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.bgPrimary, lineWidth: 1.5))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(2)
                    }
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(friend.name)
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.textPrimary)
                    Text(friend.statusMessage)
                        .font(.system(size: 13)).foregroundColor(.textSecondary).lineLimit(1)
                    if isOnline {
                        Text(store.distanceString(to: friend.coordinate))
                            .font(.system(size: 11, weight: .medium)).foregroundColor(.brand)
                    }
                }

                Spacer()

                if isOnline {
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) { invited = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { invited = false }
                        }
                    }) {
                        Text(invited ? "✓" : tr("profile.invite"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(invited ? .onlineGreen : .brandInverse)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(invited ? Color.onlineGreen.opacity(0.15) : Color.brand, in: Capsule())
                    }
                    .dropsPressable()
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: invited)
                } else {
                    DazuIcon("chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .dropsPressable()
    }
}

// MARK: - Profile View

private struct HomePin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct ProfileView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("mapStyleMode") private var mapStyleModeRaw: String = MapStyleMode.auto.rawValue
    @AppStorage("appLanguage") private var appLanguage: String = "de"
    @AppStorage("ud_profileHeroTemplate") private var profileHeroTemplateRaw = ProfileHeroTemplate.aurora.rawValue
    private var profileHeroTemplate: ProfileHeroTemplate {
        ProfileHeroTemplate(rawValue: profileHeroTemplateRaw) ?? .aurora
    }
    @AppStorage("settingNotificationsOn") private var notificationsOn = true
    @AppStorage("ud_presenceShareEnabled") private var presenceSharing = false
    @State private var showPresenceOptInSheet = false
    @State private var showDeleteAlert = false
    @State private var isDeletingAccount = false
    @State private var deleteErrorMessage: String? = nil
    @State private var showDeleteError = false
    @State private var auroraAnimate = false
    @State private var showTeensLockedInfo = false
    /// Einziger Sheet-State — verhindert "mehrere .sheet auf selber View"-Bug
    /// (SwiftUI zeigt nur den letzten Modifier, alle anderen werden ignoriert).
    @State private var activeSettingsSheet: SettingsSheet? = nil
    @State private var settingsAtTop = true
    /// Scroll-adaptiv: true, sobald die Hero-Headline weggescrollt ist.
    /// Treibt den kompakten dazu-Chip oben (iOS Large→Compact-Pattern).
    @State private var settingsIsScrolled = false
    /// Dashboard-Sheet für die eigene Community (separater State weil
    /// .sheet(item:) eine Community als Identifier braucht).
    @State private var dashboardCommunity: Community? = nil

    enum SettingsSheet: String, Identifiable {
        case admin, blockedList, privacy, terms, dropsPlus, communityCreator, phoneLink
        var id: String { rawValue }
    }

    // Lokale Buffer für Altersslider — Store-Update nur beim Loslassen
    @State private var localAgeMin: Int = 18
    @State private var localAgeMax: Int = 99
    // Lokaler Buffer für Heimzone-Slider — Store/Karte nur beim Loslassen updaten
    @State private var localHomeZoneIndex: Double = 0
    // Kamera-Position für Heimzone-Karte — Binding statt .id()-Trick (kein Scroll-Reset)
    @State private var mapCameraPosition: MapCameraPosition = .automatic

    // Mein Profil — editierbare Felder
    @State private var editedName: String = ""   // unused after onboarding, kept for compiler
    @State private var editedPhone: String = ""
    @FocusState private var phoneFocused: Bool
    @State private var editedBirthdate: Date = Date()

    /// Direkt-Check per gespeicherter Telefonnummer / Apple-Relay-E-Mail —
    /// Fallback falls store.isAdmin nach Neustart noch nicht asynchron gesetzt wurde.
    private var isAdminByCredentials: Bool {
        let storedApple = (UserDefaults.standard.string(forKey: "ud_appleEmail") ?? "").lowercased()
        let savedPhone  = (UserDefaults.standard.string(forKey: "savedPhoneDialCode") ?? "")
                        + (UserDefaults.standard.string(forKey: "savedPhoneNumber") ?? "")
        return AdminConfig.isBootstrapAdmin(storedAppleEmail: storedApple, savedPhone: savedPhone)
    }

    var radiusOptions: [(label: String, subtitle: String, value: Double)] {
        [
            ("500m", tr("profile.radius_6min"), 500),
            ("800m", tr("profile.radius_10min"), 800),
            ("1.5km", tr("profile.radius_18min"), 1500),
            ("3km", tr("profile.radius_37min"), 3000),
            (tr("profile.radius_unlimited"), tr("profile.radius_all_drops"), 99999)
        ]
    }

    var body: some View {
        // Wie in FeedView (Umgebung) und FreundeView (Profil): NavigationStack
        // mit Large-Title. Liefert automatisch den korrekten Sticky-Header-Look
        // beim Scrollen, identisch zu den anderen Tabs.
        NavigationStack {
        ZStack(alignment: .top) {
            AppAuroraBackground()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {

                        // Rondesignlab-Style Hero mit Inline-Wordmark.
                        // Beim Scrollen fadet oben ein kompakter dazu-Chip
                        // via scrollAdaptiveDazuHeader ein.
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                DazuWordmark(color: .brandNight, dotColor: .brandOrange)
                                    .frame(height: 24)
                                Spacer()
                            }
                            (Text(tr("settings.headline")).foregroundColor(.brandViolet)
                             + Text(".").foregroundColor(.brandOrange))
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                        // ── Drops+ Banner ────────────────────────────────
                        // Aus für den initialen Launch — wieder einschalten
                        // via `FeatureFlags.dropsPlusEnabled = true` in Models.swift.
                        if FeatureFlags.dropsPlusEnabled {
                            Button { activeSettingsSheet = .dropsPlus } label: {
                                HStack(spacing: 14) {
                                    DazuIcon("bolt.fill")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(Color.auroraAmber)
                                        .frame(width: 44, height: 44)
                                        .background(Color.auroraAmber.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text("dazu+")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: [Color.auroraAmber, Color.auroraAmber],
                                                        startPoint: .leading, endPoint: .trailing
                                                    )
                                                )
                                            if store.isPlusUser {
                                                Text(tr("profile.active_badge"))
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(.black)
                                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(Color.auroraAmber, in: Capsule())
                                            }
                                        }
                                        Text(store.isPlusUser
                                             ? tr("profile.plus_features")
                                             : tr("profile.plus_features_inf"))
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    DazuIcon("chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.lg)
                                        .fill(Color.bgCard)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Radius.lg)
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [Color.auroraAmber.opacity(0.5), Color.auroraAmber.opacity(0.15)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1
                                                )
                                        )
                                )
                            }
                            .dropsPressable()
                            .padding(.horizontal, 16)
                        }

                        // ── GRUPPE: Sichtbarkeit ─────────────────────
                        // Kategorie-Überschrift entfernt — die Section-Title
                        // mit Icon darunter trägt denselben Namen und reicht.
                        settingsSection(icon: "location.fill", color: Color(UIColor.systemGreen), title: tr("settings.visibility"), assetName: "SetSichtbarkeit") {
                            locationSection
                            Divider().padding(.leading, 60)
                            notificationSection
                        }

                        // Datenschutz-Hinweis
                        HStack(alignment: .top, spacing: 10) {
                            DazuIcon("lock.shield.fill", accent: false)
                                .font(.system(size: 13))
                                .foregroundColor(.textTertiary)
                                .padding(.top, 1)
                            Text(tr("settings.privacy_note"))
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 2)

                        // Entdecken
                        // ── GRUPPE: Entdecken ────────────────────────
                        settingsCategoryHeader(tr("settings.discover_header"))

                        settingsSection(icon: "scope", color: Color(UIColor.systemBlue), title: tr("settings.drops_radius"), assetName: "SetRadius") {
                            radiusSection
                        }

                        settingsSection(icon: "house.fill", color: Color.accentOrange, title: tr("settings.home_zone"), assetName: "SetHeimzone") {
                            homeZoneSection
                        }

                        // Power-Hour Section entfernt (Feature deaktiviert).

                        settingsSection(icon: "person.2.fill", color: Color.auroraOrange, title: tr("settings.age_groups"), assetName: "SetAltersgruppen") {
                            ageGroupSection
                        }

                        // Darstellung — Kategorie-Header entfernt, Section-
                        // Title mit Icon trägt denselben Namen.
                        settingsSection(icon: "circle.lefthalf.filled", color: Color(UIColor.systemIndigo), title: tr("settings.appearance"), assetName: "SetDarstellung") {
                            appearanceSection
                        }

                        // Community Creator — Antrag + Dashboard nach Genehmigung
                        // (Deaktiviert bis zur nächsten Version via FeatureFlags.communitiesEnabled)
                        if FeatureFlags.communitiesEnabled {
                            settingsSection(icon: "star.circle.fill", color: Color.brand, title: tr("settings.community_creator"), assetName: "SetCommunity") {
                                partnershipBadgeRow
                                Divider().padding(.leading, 16)
                                communityCreatorRow
                                if let myCommunity = store.myCommunity {
                                    Divider().padding(.leading, 66)
                                    myCommunityRow(myCommunity)
                                }
                            }
                        }

                        // Sicherheit — Kategorie-Header entfernt, Section-
                        // Title mit Icon trägt denselben Namen.
                        settingsSection(icon: "nosign", color: .red, title: tr("settings.security"), assetName: "SetBlockiert") {
                            Button(action: { activeSettingsSheet = .blockedList }) {
                                HStack(spacing: 14) {
                                    dazuRowIcon(assetName: "SetBlockiert")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tr("settings.blocked_users"))
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundColor(.brandNight)
                                        Text(store.blockedUserNames.isEmpty
                                             ? tr("settings.no_blocked")
                                             : tr("settings.x_blocked").replacingOccurrences(of: "{count}", with: "\(store.blockedUserNames.count)"))
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(.brandNight.opacity(0.6))
                                    }
                                    Spacer()
                                    DazuIcon("chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.brandNight.opacity(0.45))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                            }
                            .dropsPressable()
                        }

                        // Hilfe & Feedback
                        settingsSection(icon: "questionmark.circle.fill", color: Color(UIColor.systemBlue), title: tr("settings.help_feedback"), assetName: "SetHilfe") {
                            faqLinkRow
                            Divider().padding(.leading, 60)
                            feedbackRow
                            Divider().padding(.leading, 60)
                            if AppLinks.instagramURL != nil {
                                instagramRow
                                Divider().padding(.leading, 60)
                            }
                            languageRow
                        }

                        // Datenschutz + Konto
                        settingsSection(icon: "hand.raised.fill", color: Color.auroraViolet, title: tr("settings.privacy_account"), assetName: "SetSchloss") {
                            privacySection
                            Divider().padding(.leading, 60)
                            accountSection
                        }

                        // Admin — nur sichtbar für Admins
                        if store.isAdmin || isAdminByCredentials {
                            settingsSection(icon: "star.fill", color: Color.brandViolet, title: tr("settings.administration"), assetName: "SetAdmin") {
                                Button(action: { activeSettingsSheet = .admin }) {
                                    HStack(spacing: 14) {
                                        dazuRowIcon(assetName: "SetAdminPanel")
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(tr("settings.admin_panel"))
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                .foregroundColor(.brandNight)
                                            Text(tr("settings.admin_panel_sub"))
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                                .foregroundColor(.brandNight.opacity(0.6))
                                        }
                                        Spacer()
                                        DazuIcon("chevron.right")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.brandNight.opacity(0.45))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                                }
                                .dropsPressable()
                            }
                        }

                        // Version am Ende — hilfreich für Support
                        VStack(spacing: 4) {
                            Text("dazu")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.brandViolet.opacity(0.65))
                            Text(tr("profile.version").replacingOccurrences(of: "{ver}", with: appBundleVersion))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.brandNight.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 8)
                }
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y < 10
                } action: { _, atTop in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settingsAtTop = atTop
                    }
                }
                .onScrollGeometryChange(for: Bool.self) { geo in
                    // Konsistent zu Feed/Profil: Chip faded sobald Inline-
                    // Logo weggescrollt ist, nicht erst wenn Hero komplett
                    // raus ist. Hochwertiger, flüssigerer Übergang.
                    geo.contentOffset.y > 50
                } action: { _, newValue in
                    settingsIsScrolled = newValue
                }
                .scrollAdaptiveDazuHeader(isScrolled: settingsIsScrolled)
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if settingsAtTop {
                        languageToggle
                            .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
                    }
                }
            }
            .onAppear {
                editedPhone = store.userPhone
            }
            .sheet(item: $activeSettingsSheet) { sheet in
                switch sheet {
                case .admin:            AdminPanelView().environmentObject(store)
                case .blockedList:      BlockedUsersSheet().environmentObject(store)
                case .privacy:          LegalView(type: .privacy)
                case .terms:            LegalView(type: .terms)
                case .dropsPlus:        DropsPlusView()
                case .communityCreator: CommunityCreatorApplicationSheet().environmentObject(store)
                case .phoneLink:        PhoneLinkSheet().environmentObject(store)
                }
            }
            .sheet(item: $dashboardCommunity) { community in
                CommunityCreatorDashboardSheet(community: community)
                    .environmentObject(store)
            }
            .alert(tr("account.confirm_delete"), isPresented: $showDeleteAlert) {
                Button(tr("common.cancel"), role: .cancel) {}
                Button(tr("common.delete"), role: .destructive) {
                    isDeletingAccount = true
                    store.deleteAccount { errorMsg in
                        isDeletingAccount = false
                        if let msg = errorMsg {
                            deleteErrorMessage = msg
                            showDeleteError = true
                        }
                    }
                }
            } message: {
                Text(tr("account.delete_warning"))
            }
            .alert(tr("account.delete_failed"), isPresented: $showDeleteError) {
                Button(tr("common.ok"), role: .cancel) {}
            } message: {
                Text(deleteErrorMessage ?? tr("profile.unknown_error"))
            }
            .overlay {
                if isDeletingAccount {
                    ZStack {
                        Color.black.opacity(0.55).ignoresSafeArea()
                        VStack(spacing: 14) {
                            DazuLoader().tint(.white)
                            Text(tr("settings.deleting_account"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(28)
                        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Color.white.opacity(0.75)))
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isDeletingAccount)
            .alert(tr("account.age_restricted_title"), isPresented: $showTeensLockedInfo) {
                Button(tr("form.understood"), role: .cancel) {}
            } message: {
                Text(tr("account.age_restricted_msg"))
            }
        } // NavigationStack
    }



    // MARK: - Community Creator Rows

    /// Kooperations-Badge: Drops × Clero — nebeneinander, zeigt den Co-Brand
    /// schon BEVOR der User auf "Bewerben" tippt.
    private var partnershipBadgeRow: some View {
        HStack(alignment: .center, spacing: 8) {
            settingsPartnerPill(logoAsset: "drops_logo",
                                brand:     "DROPS",
                                subtitle:  tr("community.partnership_drops"),
                                accent:    Color.auroraOrange)
            Text("×")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.textTertiary)
            settingsPartnerPill(logoAsset: "clero_logo",
                                brand:     "CLERO",
                                subtitle:  tr("community.partnership_clero"),
                                accent:    Color.brand)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func settingsPartnerPill(logoAsset: String, brand: String, subtitle: String, accent: Color) -> some View {
        HStack(spacing: 6) {
            Image(logoAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(brand)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundColor(accent)
                Text(subtitle)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            Capsule()
                .fill(accent.opacity(0.10))
                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 1))
        )
    }

    /// Erste Zeile: Antrag stellen / Status anzeigen. Wird IMMER gezeigt.
    private var communityCreatorRow: some View {
        Button(action: { activeSettingsSheet = .communityCreator }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(LinearGradient.aurora.opacity(0.18))
                        .frame(width: 36, height: 36)
                    if store.isCommunityCreator {
                        DazuIcon("checkmark.seal.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.brand)
                    } else {
                        Image("clero_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isCommunityCreator ? tr("community.creator_verified") : tr("community.creator_become"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(creatorStatusSubtitle)
                        .font(.system(size: 12))
                        .foregroundColor(creatorStatusColor)
                }
                Spacer()
                if store.communityCreatorStatus == nil {
                    Text(tr("community.apply_button"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(LinearGradient.aurora))
                } else {
                    DazuIcon("chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .dropsPressable()
    }

    private var creatorStatusSubtitle: String {
        switch store.communityCreatorStatus {
        case "pending":  return tr("community.application_pending")
        case "denied":   return tr("community.application_denied")
        case "approved": return tr("community.application_approved")
        default:         return tr("community.starter_text")
        }
    }

    private var creatorStatusColor: Color {
        switch store.communityCreatorStatus {
        case "pending":  return .accentOrange
        case "denied":   return .accentRed
        case "approved": return .brand
        default:         return .textSecondary
        }
    }

    /// Zweite Zeile: erscheint NUR wenn der User eine genehmigte Community hat.
    /// Tap öffnet das Dashboard mit Mitgliederliste + Push-Funktion.
    private func myCommunityRow(_ community: Community) -> some View {
        Button(action: { dashboardCommunity = community }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(LinearGradient.aurora.opacity(0.20))
                        .frame(width: 36, height: 36)
                    DazuIcon(community.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.brand)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(community.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Text("\(community.memberCount) \(community.memberCount == 1 ? tr("community.community_member") : tr("community.community_members")) · \(community.district)")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                DazuIcon("chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .dropsPressable()
    }

    private func statsItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }


    // MARK: - Settings Section Container

    // AnyView-Rückgabe statt generischem some View — verhindert Stack Overflow
    // durch TupleView<(SettingsA, SettingsB, ...)> mit je unterschiedlichem
    // Content-Typ. Alle ~9 Aufrufe im LazyVStack haben jetzt denselben Typ.
    /// Gruppen-Header zwischen settings-Sections (Rondesignlab-caps).
    private func settingsCategoryHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .tracking(1.4)
            .foregroundColor(.brandViolet)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsSection<Content: View>(icon: String, color: Color, title: String, assetName: String? = nil, @ViewBuilder content: () -> Content) -> AnyView {
        AnyView(
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    SettingsHeaderIcon(icon: icon, color: color, assetName: assetName)
                    Text(title.uppercased())
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.75))
                        .tracking(1.2)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.bottom, 8)

                VStack(spacing: 0) { content() }
                    .frame(maxWidth: .infinity)
                    .liquidGlass(cornerRadius: Radius.xl)
                    .padding(.horizontal, 16)
            }
        )
    }

    // MARK: - Radius Section

    // Free:  500m / 1km / 2km            (max 2km)
    // Plus:  500m / 1km / 2km / 5km / 10km / 25km / ∞
    private var radiusSteps: [Double] {
        // Wenn Drops+ deaktiviert ist (Launch-Phase) bekommen alle User die
        // volle Auswahl — sonst wäre der 2km-Cap eine harte Einschränkung
        // ohne Upgrade-Pfad.
        let unlocked = !FeatureFlags.dropsPlusEnabled || store.isPlusUser
        return unlocked
            ? [500, 1000, 2000, 5000, 10000, 25000, 50000]
            : [500, 1000, 2000]
    }
    private var radiusIndex: Double {
        let idx = radiusSteps.firstIndex(where: { $0 >= store.radiusFilter }) ?? radiusSteps.count - 1
        return Double(idx)
    }
    private func radiusTickLabel(_ v: Double) -> String {
        if v >= 50000 { return "∞" }
        return v >= 1000 ? "\(Int(v / 1000))km" : "\(Int(v))m"
    }
    private func radiusWalkLabel(_ v: Double) -> String {
        switch v {
        case 500:   return tr("profile.radius_6min")
        case 1000:  return tr("profile.radius_12min")
        case 2000:  return tr("profile.radius_25min")
        case 5000:  return tr("profile.radius_60min")
        case 10000: return tr("profile.radius_2h")
        case 25000: return tr("profile.radius_citywide")
        case 50000: return tr("profile.radius_unlimited")
        default:    return ""
        }
    }

    @ViewBuilder private var radiusSection: some View {
        // Free-User: Radius auf max 2km clampen — aber nur wenn Drops+ als
        // Feature aktiv ist. Bei deaktiviertem Plus haben alle User vollen Radius.
        let clampedFilter: Double = {
            if FeatureFlags.dropsPlusEnabled && !store.isPlusUser && store.radiusFilter > 2000 {
                DispatchQueue.main.async { store.radiusFilter = 2000; store.saveAll() }
                return 2000
            }
            return store.radiusFilter
        }()
        let steps = radiusSteps

        VStack(spacing: 0) {
            // Aktueller Wert + Walk-Label
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(clampedFilter >= 50000 ? "∞"
                     : clampedFilter >= 1000 ? String(format: "%.0f km", clampedFilter / 1000)
                     : "\(Int(clampedFilter)) m")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.brandViolet)
                    .contentTransition(.numericText())
                Text(radiusWalkLabel(clampedFilter))
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                Spacer()
                DazuIcon("figure.walk", accent: false)
                    .font(.system(size: 15))
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)

            // Slider
            Slider(
                value: Binding(
                    get: { radiusIndex },
                    set: { idx in
                        let newValue = steps[Int(idx.rounded())]
                        if newValue != store.radiusFilter {
                            store.radiusFilter = newValue
                            Haptic.selection()
                        }
                    }
                ),
                in: 0...Double(steps.count - 1),
                step: 1
            ) { editing in
                if !editing { store.saveAll() }
            }
            .tint(.brandViolet)
            .padding(.horizontal, 16)

            // Tick-Labels
            HStack {
                ForEach(steps, id: \.self) { step in
                    Text(radiusTickLabel(step))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(clampedFilter == step ? .brandViolet : .textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 4)

            Divider().padding(.horizontal, 16)

            // Info-Zeile
            HStack(spacing: 10) {
                DazuIcon("eye.fill", accent: false)
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(clampedFilter >= 50000
                         ? tr("profile.see_all_city")
                         : tr("profile.see_within_km").replacingOccurrences(of: "{dist}", with: clampedFilter >= 1000 ? String(format: "%.0f km", clampedFilter / 1000) : "\(Int(clampedFilter)) m"))
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if FeatureFlags.dropsPlusEnabled && !store.isPlusUser {
                        Text(tr("settings.plus_unlimited"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.brandViolet.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    // MARK: - Home Zone Section

    private let homeZoneSteps: [Double] = [50, 75, 100, 150, 200, 300, 400, 500]

    private var homeZoneIndex: Double {
        let idx = homeZoneSteps.firstIndex(where: { $0 >= store.homeZoneRadius }) ?? homeZoneSteps.count - 1
        return Double(idx)
    }

    private func homeZoneLabel(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fkm", v / 1000) : "\(Int(v))m"
    }

    @ViewBuilder private var homeZoneSection: some View {
        VStack(spacing: 0) {
            // Status-Zeile
            HStack(spacing: 12) {
                DazuIcon("house.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(store.homeZoneCoordinate != nil ? Color.brandViolet : Color.brandNight.opacity(0.4))
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.homeZoneCoordinate != nil ? tr("profile.home_zone_active") : tr("profile.no_home_zone"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.brandNight)
                    Text(store.homeZoneCoordinate != nil
                         ? tr("profile.home_radius").replacingOccurrences(of: "{radius}", with: homeZoneLabel(store.homeZoneRadius))
                         : tr("profile.tap_set"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.6))
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            // Mini-Karte (nur wenn Heimzone gesetzt)
            if let homeCoord = store.homeZoneCoordinate {
                let liveRadius = homeZoneSteps[Int(localHomeZoneIndex.rounded())]
                // position-Binding statt initialPosition+.id() → kein View-Destroy bei
                // Slider-Bewegung → kein Scroll-Reset mehr in der übergeordneten ScrollView
                Map(position: $mapCameraPosition) {
                    Annotation("", coordinate: homeCoord) {
                        ZStack {
                            Circle()
                                .fill(Color.brandViolet)
                                .frame(width: 30, height: 30)
                            DazuIcon("house.fill", accent: false)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .shadow(color: Color.brandViolet.opacity(0.5), radius: 4)
                    }
                    MapCircle(center: homeCoord, radius: liveRadius)
                        .foregroundStyle(Color.brandViolet.opacity(0.14))
                        .stroke(Color.brandViolet.opacity(0.6), lineWidth: 1.5)
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .disabled(true)
            }

            // Radius-Slider (nur wenn aktiv)
            if store.homeZoneCoordinate != nil {
                VStack(spacing: 4) {
                    HStack {
                        Text(tr("settings.radius"))
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                        Spacer()
                        Text(homeZoneLabel(homeZoneSteps[Int(localHomeZoneIndex.rounded())]))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(Color.accentOrange)
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 16)

                    Slider(
                        value: $localHomeZoneIndex,
                        in: 0...Double(homeZoneSteps.count - 1),
                        step: 1
                    ) { editing in
                        if !editing {
                            // Store + Save nur beim Loslassen
                            let v = homeZoneSteps[Int(localHomeZoneIndex.rounded())]
                            store.homeZoneRadius = v
                            Haptic.selection()
                            store.saveAll()
                        }
                    }
                    .tint(Color.accentOrange)
                    .padding(.horizontal, 16)
                    .onAppear {
                        localHomeZoneIndex = homeZoneIndex
                        // Initiale Kamera-Position setzen
                        if let coord = store.homeZoneCoordinate {
                            let r = homeZoneSteps[Int(localHomeZoneIndex.rounded())]
                            mapCameraPosition = .region(MKCoordinateRegion(
                                center: coord,
                                latitudinalMeters: r * 4,
                                longitudinalMeters: r * 4
                            ))
                        }
                    }
                    .onChange(of: localHomeZoneIndex) { _, _ in
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        // Kamera smooth updaten — kein .id()-Trick nötig
                        if let coord = store.homeZoneCoordinate {
                            let r = homeZoneSteps[Int(localHomeZoneIndex.rounded())]
                            withAnimation(.easeInOut(duration: 0.25)) {
                                mapCameraPosition = .region(MKCoordinateRegion(
                                    center: coord,
                                    latitudinalMeters: r * 4,
                                    longitudinalMeters: r * 4
                                ))
                            }
                        }
                    }

                    HStack {
                        ForEach(homeZoneSteps, id: \.self) { s in
                            Text(homeZoneLabel(s))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(
                                    homeZoneSteps[Int(localHomeZoneIndex.rounded())] == s
                                    ? Color.accentOrange : .textTertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 14).padding(.bottom, 8)
                }
            }

            Divider().padding(.horizontal, 16)

            // Aktionen
            HStack(spacing: 0) {
                Button(action: {
                    store.setHomeZone(coordinate: store.currentUser.coordinate)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }) {
                    Label { Text(store.homeZoneCoordinate != nil ? tr("profile.update") : tr("profile.set")) } icon: { DazuIcon("location.fill") }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.brandViolet)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                if store.homeZoneCoordinate != nil {
                    Divider().frame(height: 36)
                    Button(action: {
                        store.removeHomeZone()
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    }) {
                        Label { Text(tr("profile.remove")) } icon: { DazuIcon("trash") }
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.brandOrange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
            }
        }
    }


    // MARK: - Age Group Section

    @ViewBuilder private var ageGroupSection: some View {
        if store.isAgeRestricted {
            // ── Unter 18: Nur eigene Gruppe anzeigen, Rest komplett versteckt ──
            VStack(alignment: .leading, spacing: 14) {
                // Schutz-Banner
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.accentOrange.opacity(0.15)).frame(width: 36, height: 36)
                            DazuIcon("hand.raised.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.orange)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("settings.youth_protection"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.textPrimary)
                            Text(tr("settings.locked_until"))
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                        Spacer()
                        if let age = store.userAge {
                            Text("\(age) \(tr("profile.y_short"))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textTertiary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ageProtectRow(icon: "eye.slash.fill", text: tr("settings.cannot_see_other_groups"))
                        ageProtectRow(icon: "person.2.fill", text: tr("settings.see_only_teens"))
                        ageProtectRow(icon: "checkmark.shield.fill", text: tr("settings.full_access_at_18"))
                        ageProtectRow(icon: "lock.rotation", text: tr("settings.protected_by_id"))
                    }
                }
                .padding(14)
                .background(Color.accentOrange.opacity(0.07), in: RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Color.accentOrange.opacity(0.20), lineWidth: 1))

                // Nur eigene Gruppe als aktive Kachel
                if let own = store.userAgeGroup {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Radius.md).fill(Color.brand.opacity(0.10)).frame(width: 44, height: 44)
                            DazuIcon(own.systemIcon).font(.system(size: 20)).foregroundColor(.brand)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(own.label)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.brand)
                            Text(tr("settings.your_age_group"))
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        DazuIcon("checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.brand)
                    }
                    .padding(12)
                    .background(Color.brand.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Color.brand.opacity(0.25), lineWidth: 1.5))
                }
            }
            .padding(14)
        } else {
            // ── Normal: Min/Max-Alter-Slider ───────────────────────────────
            VStack(spacing: 0) {
                // Anzeige: aktueller Bereich
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(localAgeMin)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.brand)
                        .contentTransition(.numericText())
                    Text("–")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.textSecondary)
                    Text(localAgeMax >= 60 ? "60+" : "\(localAgeMax)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.brand)
                        .contentTransition(.numericText())
                    Text(tr("settings.years"))
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                    Spacer()
                    if let own = store.userAgeGroup {
                        HStack(spacing: 4) {
                            DazuIcon(own.systemIcon).font(.system(size: 11))
                            Text(tr("settings.you_label").replacingOccurrences(of: "{label}", with: own.label))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.brand)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.brand.opacity(0.1), in: Capsule())
                    }
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)

                // Slider: Mindestalter
                VStack(spacing: 2) {
                    HStack {
                        Text(tr("settings.min_age"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textTertiary)
                        Spacer()
                        Text("\(localAgeMin)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.brand)
                    }
                    .padding(.horizontal, 16)
                    Slider(
                        value: Binding(
                            get: { Double(localAgeMin) },
                            set: { val in
                                let v = Int(val.rounded())
                                if v <= localAgeMax - 1 { localAgeMin = v }
                            }
                        ),
                        in: 18...59, step: 1
                    ) { editing in
                        if !editing {
                            store.ageFilterMin = localAgeMin
                            store.saveAll()
                            Haptic.selection()
                        }
                    }
                    .tint(.brand)
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 6)
                .onAppear { localAgeMin = store.ageFilterMin }

                // Slider: Höchstalter
                VStack(spacing: 2) {
                    HStack {
                        Text(tr("settings.max_age"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textTertiary)
                        Spacer()
                        Text(localAgeMax >= 60 ? "60+" : "\(localAgeMax)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.brand)
                    }
                    .padding(.horizontal, 16)
                    Slider(
                        value: Binding(
                            get: { Double(min(localAgeMax, 60)) },
                            set: { val in
                                let v = Int(val.rounded())
                                if v >= localAgeMin + 1 { localAgeMax = v >= 60 ? 99 : v }
                            }
                        ),
                        in: 19...60, step: 1
                    ) { editing in
                        if !editing {
                            store.ageFilterMax = localAgeMax
                            store.saveAll()
                            Haptic.selection()
                        }
                    }
                    .tint(.brand)
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 10)
                .onAppear { localAgeMax = min(store.ageFilterMax, 60) }

                // Tick-Labels
                HStack {
                    Text("18").font(.system(size: 9)).foregroundColor(.textTertiary)
                    Spacer()
                    Text("30").font(.system(size: 9)).foregroundColor(.textTertiary)
                    Spacer()
                    Text("45").font(.system(size: 9)).foregroundColor(.textTertiary)
                    Spacer()
                    Text("60+").font(.system(size: 9)).foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 18).padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder private func ageProtectRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            DazuIcon(icon)
                .font(.system(size: 11))
                .foregroundColor(.orange.opacity(0.8))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Interests Section

    // MARK: - Appearance Section

    private func appearanceIcon(for mode: MapStyleMode) -> String {
        switch mode {
        case .auto:  return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark:  return "moon.fill"
        }
    }
    private func appearanceSubtitle(for mode: MapStyleMode) -> String {
        switch mode {
        case .auto:  return tr("profile.appearance_auto")
        case .light: return tr("profile.appearance_light")
        case .dark:  return tr("profile.appearance_dark")
        }
    }

    /// Kompakte „Sprache"-Row in Hilfe & Feedback — ein Menu statt eine
    /// Grid-Section, damit Settings kompakt bleiben. Beim Erstlauf wird die
    /// System-Sprache automatisch gewählt (`LinkUpApp.init`), diese Row ist
    /// nur zum manuellen Überschreiben.
    @ViewBuilder private var languageRow: some View {
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
            HStack(spacing: 14) {
                DazuIcon("globe")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.brandViolet)
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("settings.language"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandNight)
                    let current = AppLanguage(rawValue: appLanguage) ?? .german
                    Text("\(current.flag)  \(current.label)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.6))
                }
                Spacer()
                DazuIcon("chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.brandNight.opacity(0.45))
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
    }

    @ViewBuilder private var appearanceSection: some View {
        ForEach(MapStyleMode.allCases, id: \.rawValue) { mode in
            let isSelected = mapStyleModeRaw == mode.rawValue
            HStack(spacing: 14) {
                // Kein eigener Lavendel-Tile mehr — die Card-Fläche (liquidGlass)
                // bringt den Hintergrund mit; sonst Doppel-Rahmen (vgl. andere
                // Einstellungs-Rows wie Blockierte Nutzer, Datenschutz).
                DazuIcon(appearanceIcon(for: mode))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? .brandViolet : .brandNight.opacity(0.6))
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label)
                        .font(.system(size: 15))
                        .foregroundColor(.textPrimary)
                    Text(appearanceSubtitle(for: mode))
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                CustomSwitch(isOn: isSelected) {
                    // Kein withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) mehr um den AppStorage-
                    // Write — die Spring-Kurve (0.3 s response) lief gegen die
                    // OS-Color-Scheme-Transition und ließ den Wechsel träge
                    // wirken. Außerdem cacht der iOS-26-`glassEffect` sein
                    // Rendering bis die SwiftUI-Animation fertig ist, weshalb
                    // der Settings-Block noch in der alten Hell-Optik blieb.
                    // Direkter Write → SwiftUI propagiert den Schema-Wechsel
                    // sofort, das System animiert den Übergang selbst.
                    mapStyleModeRaw = mode.rawValue
                }
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 16).padding(.vertical, 10)
            if mode != MapStyleMode.allCases.last {
                Divider().padding(.leading, 66)
            }
        }
    }

    /// Kompaktes Sprach-Menu für die Toolbar — zeigt Flagge + Kürzel der aktiven
    /// Sprache, beim Tippen klappt ein Menu mit allen Sprachen auf (name + flag).
    /// Skaliert mit beliebig vielen `AppLanguage`-Cases.
    @ViewBuilder private var languageToggle: some View {
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
                        Text(lang.label)
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
                Text(current.shortCode)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.textSecondary)
                DazuIcon("chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.textSecondary.opacity(0.7))
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .liquidGlassCapsule(shadowRadius: 6)
        }
    }

    // MARK: - Shared Row Helper

    @ViewBuilder
    private func inlineToggle(_ title: String, subtitle: String,
                               icon: String, color: Color,
                               isOn: Binding<Bool>,
                               assetName: String? = nil) -> some View {
        // Alle Row-Icons im Settings jetzt einheitlich Violett auf Lavendel-
        // Hintergrund (color-Parameter nur noch für Toggle-Tint, der bleibt
        // Orange im neuen dazu-Design). `assetName` übernimmt Vorrang vor
        // dem SF-Symbol wenn gesetzt (custom dazu-Set-Icons).
        HStack(spacing: 14) {
            // Icon direkt — der Card-Lavendel sitzt bereits dahinter,
            // ein eigenes Tile würde als Doppel-Rect sichtbar sein.
            Group {
                if let asset = assetName {
                    DazuAssetIcon(asset: asset)
                        .foregroundColor(.brandViolet)
                        .frame(width: 22, height: 22)
                } else {
                    DazuIcon(icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.brandViolet)
                }
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.brandNight)
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.brandOrange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Location Section

    @ViewBuilder private var locationSection: some View {
        inlineToggle(tr("settings.visible_on_map"),
                     subtitle: tr("settings.visible_on_map_sub"),
                     icon: "mappin.and.ellipse",
                     color: Color(UIColor.systemPurple),
                     isOn: Binding(
                        get: { presenceSharing },
                        set: { newValue in
                            if newValue {
                                // Beim Aktivieren: erst Bestätigungs-Sheet
                                showPresenceOptInSheet = true
                            } else {
                                presenceSharing = false
                                if let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
                                    RealtimeDBManager.shared.stopSharingPresence(uid: uid)
                                }
                            }
                        }),
                     assetName: "SetKartenPin")
        .sheet(isPresented: $showPresenceOptInSheet) {
            PresenceOptInSheet(
                onConfirm: {
                    presenceSharing = true
                    showPresenceOptInSheet = false
                },
                onCancel: { showPresenceOptInSheet = false }
            )
        }

    }

    // MARK: - Notification Section

    @ViewBuilder private var notificationSection: some View {
        inlineToggle(tr("settings.notifications"),
                     subtitle: tr("settings.notifications_sub"),
                     icon: "bell.badge",
                     color: Color(UIColor.systemOrange),
                     isOn: $notificationsOn,
                     assetName: "SetGlocke")
        .onChange(of: notificationsOn) { _, newValue in
            // hasSeenWelcome guard: Permissions erst nach WelcomeSheet anfragen.
            // @AppStorage mit Default true triggert onChange beim ersten Render —
            // ohne diesen Guard würde requestPermission() vor dem Onboarding feuern.
            guard UserDefaults.standard.bool(forKey: "hasSeenWelcome") else { return }
            if newValue { PushNotificationManager.shared.requestPermission() }
        }

        if notificationsOn {
            Divider().padding(.leading, 60)
            // Benachrichtigungsradius
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    dazuRowIcon(assetName: "SetGlocke")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("settings.notification_radius"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.brandNight)
                        Text(tr("settings.notif_radius_sub"))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.6))
                    }
                }
                .padding(.horizontal, 16)

                let radiusOptions: [(label: String, value: Double)] = [
                    ("500m", 500), ("1 km", 1000), ("2 km", 2000), ("5 km", 5000), ("10 km", 10000)
                ]
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(radiusOptions, id: \.value) { option in
                            let selected = store.notificationRadius == option.value
                            Button {
                                store.notificationRadius = option.value
                                store.saveAll()
                                Haptic.selection()
                            } label: {
                                Text(option.label)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(selected ? .white : .brandNight.opacity(0.7))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(selected ? Color.brandOrange : Color.brandLavender)
                                    )
                            }
                            .dropsPressable()
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Phone Section (einziges änderbares Profil-Feld nach Onboarding)

    @ViewBuilder private var phoneSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                dazuRowIcon(assetName: "SetTelefon")
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("settings.phone_number"))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundColor(.brandViolet.opacity(0.7))
                    TextField("+49 151 …", text: $editedPhone)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandNight)
                        .keyboardType(.phonePad)
                        .focused($phoneFocused)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button(tr("profile.done")) {
                                    phoneFocused = false
                                    store.saveUserPhone(editedPhone.trimmingCharacters(in: .whitespaces))
                                }
                                .fontWeight(.semibold)
                            }
                        }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            HStack(spacing: 6) {
                DazuIcon("person.2.fill", accent: false).font(.system(size: 10))
                Text(tr("settings.phone_optional"))
                    .font(.system(size: 11))
            }
            .foregroundColor(.textTertiary)
            .padding(.horizontal, 16).padding(.bottom, 10)
        }
    }

    private var appBundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    private var appBundleBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
    /// Kompakte Variante für Feedback-Mail etc.
    private var appVersionString: String {
        "Dazu v\(appBundleVersion) (\(appBundleBuild))"
    }

    @ViewBuilder private var feedbackSection: some View {
        Button {
            openFeedbackMail()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.auroraTeal.opacity(0.15))
                        .frame(width: 36, height: 36)
                    DazuIcon("exclamationmark.bubble.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.auroraTeal)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("settings.bug_feedback"))
                        .font(.system(size: 15))
                        .foregroundColor(.textPrimary)
                    Text(tr("settings.write_short_mail"))
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                DazuIcon("chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .dropsPressable()
    }

    private func openFeedbackMail() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build   = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let device  = UIDevice.current.model
        let iosVer  = UIDevice.current.systemVersion
        let uid     = FirebaseAuth.Auth.auth().currentUser?.uid ?? "—"

        let subject = "Dazu Feedback – v\(version) (\(build))"
        let body = """


        ———
        (Bitte oben deine Nachricht einfügen)

        App: dazu v\(version) (Build \(build))
        Gerät: \(device) · iOS \(iosVer)
        User-ID: \(uid)
        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@dazuapp.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body",    value: body)
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }

    @ViewBuilder private var blockedUsersSection: some View {
        if store.blockedUserNames.isEmpty {
            HStack(spacing: 14) {
                dazuRowIcon(assetName: "SetHaken")
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("profile.no_blocked"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandNight)
                    Text(tr("profile.blocked_explainer"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.6))
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        } else {
            ForEach(Array(store.blockedUserNames).sorted(), id: \.self) { name in
                HStack(spacing: 14) {
                    dazuRowIcon(assetName: "SetBlockiert")
                    Text(name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandNight)
                    Spacer()
                    Button(tr("profile.unblock")) {
                        store.blockedUserNames.remove(name)
                        store.saveAll()
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.brandViolet)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                if name != Array(store.blockedUserNames).sorted().last {
                    Divider().padding(.leading, 60)
                }
            }
        }
    }

    /// Standard-Row-Icon im dazu-Design: Violett ohne eigenes Tile-Rect.
    /// Der Lavendel-Hintergrund kommt von der umgebenden `liquidGlass`-Card,
    /// eine eigene Lavendel-Box würde sich als sichtbares Doppel-Rect
    /// abzeichnen.
    @ViewBuilder private func dazuRowIcon(systemName: String) -> some View {
        DazuIcon(systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.brandViolet)
            .frame(width: 40, height: 40)
    }

    /// Custom-dazu-Icon-Set-Variante (SetGlocke, SetSchutz, …). Template-
    /// rendered, ohne eigenes Lavendel-Tile.
    @ViewBuilder private func dazuRowIcon(assetName: String) -> some View {
        DazuAssetIcon(asset: assetName)
            .foregroundColor(.brandViolet)
            .frame(width: 22, height: 22)
            .frame(width: 40, height: 40)
    }

    @ViewBuilder private var faqLinkRow: some View {
        Button {
            if let url = URL(string: "https://dazuapp.com/#faq") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 14) {
                dazuRowIcon(assetName: "SetHilfe")
                VStack(alignment: .leading, spacing: 2) {
                    Text("FAQ")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandNight)
                    Text(tr("settings.faq_sub"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.6))
                }
                Spacer()
                DazuIcon("arrow.up.right.square")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.brandNight.opacity(0.45))
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .dropsPressable()
    }

    /// Folgen auf Instagram: öffnet das dazu-Profil (App oder Browser).
    @ViewBuilder private var instagramRow: some View {
        Button {
            if let url = AppLinks.instagramURL { UIApplication.shared.open(url) }
        } label: {
            HStack(spacing: 14) {
                dazuRowIcon(assetName: "SetInstagram")
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("settings.instagram"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandNight)
                    Text("@" + AppLinks.instagramHandle + " · " + tr("settings.instagram_sub"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.6))
                }
                Spacer()
                DazuIcon("arrow.up.right.square")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.brandNight.opacity(0.45))
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .dropsPressable()
    }

    @ViewBuilder private var feedbackRow: some View {
        Button {
            // Mailto-Link mit vorausgefülltem Betreff/Body — User kann direkt
            // in seiner Mail-App mit Kontext (App-Version + Build) tippen.
            let subject = "Dazu Feedback / Bug-Report"
            let body = """


            ---
            App-Version: \(appBundleVersion) (Build \(appBundleBuild))
            iOS: \(UIDevice.current.systemVersion)
            Gerät: \(UIDevice.current.model)
            """
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = "contact@dazuapp.com"
            components.queryItems = [
                URLQueryItem(name: "subject", value: subject),
                URLQueryItem(name: "body", value: body),
            ]
            if let url = components.url {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 14) {
                dazuRowIcon(assetName: "SetBug")
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("settings.bug_feedback"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandNight)
                    Text(tr("profile.email_contact"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.6))
                }
                Spacer()
                DazuIcon("envelope.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.brandNight.opacity(0.45))
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .dropsPressable()
    }

    @ViewBuilder private var privacySection: some View {
        Button { activeSettingsSheet = .privacy } label: {
            HStack(spacing: 14) {
                dazuRowIcon(assetName: "SetSchutz")
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("settings.privacy"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandNight)
                    Text(tr("settings.legal"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.6))
                }
                Spacer()
                DazuIcon("chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.brandNight.opacity(0.45))
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .dropsPressable()
    }

    // MARK: - Account Section

    /// Prüft ob der eingeloggte User bereits eine Phone-Nummer als Auth-
    /// Provider verknüpft hat. Blendet den „Nummer verknüpfen"-Button aus
    /// wenn ja (dann hat er schon beide Methoden parat).
    private var hasLinkedPhoneProvider: Bool {
        guard let user = Auth.auth().currentUser else { return false }
        return user.phoneNumber != nil
            || user.providerData.contains(where: { $0.providerID == "phone" })
    }

    @ViewBuilder private var accountSection: some View {
        // Telefonnummer verknüpfen — nur anzeigen wenn noch nicht verknüpft.
        if !hasLinkedPhoneProvider {
            Button { activeSettingsSheet = .phoneLink } label: {
                HStack(spacing: 14) {
                    DazuIcon("phone.badge.plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.brandViolet)
                        .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("settings.link_phone"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.brandNight)
                        Text(tr("settings.link_phone_subtitle"))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.6))
                    }
                    Spacer()
                    DazuIcon("chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.brandNight.opacity(0.45))
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
            }
            .dropsPressable()
            Divider().padding(.leading, 60)
        }

        // Abmelden
        Button {
            store.logout()
        } label: {
            HStack(spacing: 14) {
                dazuRowIcon(assetName: "SetAbmelden")
                Text(tr("account.logout"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.brandNight)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .dropsPressable()

        Divider().padding(.leading, 60)

        // Konto löschen — Text + Icon rot, kein eigener Tile-Hintergrund
        // mehr (die Card-Fläche bringt den Hintergrund mit).
        Button { showDeleteAlert = true } label: {
            HStack(spacing: 14) {
                DazuIcon("person.crop.circle.badge.minus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.brandOrange)
                    .frame(width: 38, height: 38)
                Text(tr("settings.delete_account"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.brandOrange)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .dropsPressable()

    }

}

/// Top-N Aktivitäten des Users nach Häufigkeit — Grundlage der Interessen-
/// Chip-Row im Profil. Gruppiert nach activityEmoji + activityName.
fileprivate func topActivityChips(from drops: [PastDrop], limit: Int)
    -> [(emoji: String, name: String, count: Int)]
{
    var map: [String: (emoji: String, name: String, count: Int)] = [:]
    for d in drops {
        let key = "\(d.activityEmoji)|\(d.activityName)"
        var entry = map[key] ?? (d.activityEmoji, d.activityName, 0)
        entry.count += 1
        map[key] = entry
    }
    return Array(map.values)
        .sorted { $0.count > $1.count }
        .prefix(limit)
        .map { $0 }
}

// MARK: - Profil-Hotspot-Map (eigene Drop-Locations)

/// Read-only MKMapView mit kleinen violetten Pins für jede vergangene
/// Drop-Location des Users. Auto-fittet die Region auf alle Pins. Wenn
/// keine Koordinaten vorhanden sind, rendert nichts.
fileprivate struct ProfileHotspotMap: View {
    let drops: [PastDrop]

    private var coords: [CLLocationCoordinate2D] {
        drops.compactMap { $0.coordinate }
    }

    var body: some View {
        if coords.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tr("profile.hotspots"))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.textTertiary)
                        .kerning(0.6)
                        .textCase(.uppercase)
                    Spacer()
                    Text("\(coords.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.brandViolet)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.brandLavender.opacity(0.7)))
                }
                .padding(.horizontal, 2)
                HotspotMapView(coordinates: coords)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card)
                            .stroke(Color.brandViolet.opacity(0.15), lineWidth: 0.5)
                    )
                    .allowsHitTesting(false)
            }
        }
    }
}

/// UIViewRepresentable-Wrapper um MKMapView mit kleinen violetten Dots pro
/// Koordinate. Scroll/Zoom aus — rein dekorativ.
fileprivate struct HotspotMapView: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.showsUserLocation = false
        map.showsCompass = false
        map.showsScale = false
        map.register(HotspotDotView.self,
                     forAnnotationViewWithReuseIdentifier: HotspotDotView.reuseID)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeAnnotations(map.annotations)
        let anns = coordinates.map { c -> MKPointAnnotation in
            let a = MKPointAnnotation(); a.coordinate = c; return a
        }
        map.addAnnotations(anns)
        if let region = fittingRegion(for: coordinates) {
            map.setRegion(region, animated: false)
        }
    }

    private func fittingRegion(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coords.first else { return nil }
        if coords.count == 1 {
            return MKCoordinateRegion(center: first,
                                      span: MKCoordinateSpan(latitudeDelta: 0.02,
                                                             longitudeDelta: 0.02))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLng = first.longitude, maxLng = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude);  maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude); maxLng = max(maxLng, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLng + maxLng) / 2)
        // 1.4-facher Padding damit die Pins nicht am Rand kleben.
        let span = MKCoordinateSpan(latitudeDelta: max(0.01, (maxLat - minLat) * 1.4),
                                    longitudeDelta: max(0.01, (maxLng - minLng) * 1.4))
        return MKCoordinateRegion(center: center, span: span)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            return map.dequeueReusableAnnotationView(
                withIdentifier: HotspotDotView.reuseID,
                for: annotation
            )
        }
    }
}

fileprivate final class HotspotDotView: MKAnnotationView {
    static let reuseID = "HotspotDotView"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 14, height: 14)
        backgroundColor = .clear
        canShowCallout = false
        // Zwei-Layer-Dot: violetter Kern + weißer Ring für Lesbarkeit.
        let outer = CALayer()
        outer.frame = bounds
        outer.cornerRadius = 7
        outer.backgroundColor = UIColor.white.cgColor
        outer.shadowColor = UIColor.black.cgColor
        outer.shadowOpacity = 0.18
        outer.shadowRadius = 2
        outer.shadowOffset = CGSize(width: 0, height: 1)
        layer.addSublayer(outer)
        let inner = CALayer()
        inner.frame = CGRect(x: 2, y: 2, width: 10, height: 10)
        inner.cornerRadius = 5
        inner.backgroundColor = UIColor(red: 0.357, green: 0.239, blue: 0.961, alpha: 1).cgColor
        outer.addSublayer(inner)
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Stat Tile

private struct StatTile: View {
    let value: String
    let label: String
    let icon:  String
    let color: Color
    /// Wenn gesetzt: Tap öffnet dieses Detail-Sheet.
    var onTap: (() -> Void)? = nil

    @State private var tapped = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Icon-Container immer Lavendel — einheitlich für alle Kacheln.
            // `color` steuert nur die Icon-Tint-Farbe.
            DazuIcon(icon)
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.brandLavender))
                .scaleEffect(tapped ? 1.2 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.55), value: tapped)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.brandNight)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundColor(.brandNight.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.selection()
            tapped.toggle()
            onTap?()
        }
    }
}

// MARK: - Blockierte Nutzer Sheet (Untermenü)

struct BlockedUsersSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Header-Erklärung
                    HStack(spacing: 12) {
                        DazuIcon("info.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.brand)
                        Text(tr("profile.blocked_users_msg"))
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(Color.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.md))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Liste oder Empty-State
                    if store.blockedUserNames.isEmpty {
                        VStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.10))
                                    .frame(width: 72, height: 72)
                                DazuIcon("checkmark.circle.fill")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                            Text(tr("profile.nobody_blocked"))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text(tr("profile.block_from_profile"))
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(store.blockedUserNames).sorted(), id: \.self) { name in
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 9)
                                            .fill(Color.accentRed.opacity(0.12))
                                            .frame(width: 36, height: 36)
                                        DazuIcon("nosign")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.red)
                                    }
                                    Text(name)
                                        .font(.system(size: 15))
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                    Button(tr("profile.unblock")) {
                                        store.blockedUserNames.remove(name)
                                        store.saveAll()
                                    }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.brand)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                if name != Array(store.blockedUserNames).sorted().last {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.white.opacity(0.75)))
                        .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle(tr("profile.blocked_users"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("profile.done")) { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - Name Change Sheet

struct NameChangeSheet: View {
    let currentName: String
    let pendingName: String?
    let cooldownDays: Int          // 0 = erlaubt, >0 = gesperrt
    @Binding var input: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private var isOnCooldown: Bool { cooldownDays > 0 }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                DazuIcon("person.text.rectangle.fill", accent: false)
                    .padding(.top, 24)
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(colors: [.auroraOrange, .auroraGreen],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text(tr("profile.change_display_name"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(tr("profile.name_change_explainer"))
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
            }
            .padding(.bottom, 20)

            // Cooldown-Banner
            if isOnCooldown {
                HStack(spacing: 10) {
                    DazuIcon("clock.badge.exclamationmark", accent: false)
                        .font(.system(size: 14))
                        .foregroundColor(.accentRed)
                    Text((cooldownDays == 1 ? tr("profile.next_change_day") : tr("profile.next_change_days")).replacingOccurrences(of: "{days}", with: "\(cooldownDays)"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.accentRed)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Color.accentRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }
            // Ausstehende Anfrage
            else if let pending = pendingName {
                HStack(spacing: 10) {
                    DazuIcon("hourglass")
                        .font(.system(size: 13))
                        .foregroundColor(.accentOrange)
                    Text(tr("profile.pending_review").replacingOccurrences(of: "{name}", with: pending))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.accentOrange)
                    Spacer()
                    Button(tr("profile.withdraw")) {
                        onCancel()
                        dismiss()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentRed)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Color.accentOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }

            // Textfeld
            HStack(spacing: 12) {
                DazuIcon("person.fill", accent: false)
                    .font(.system(size: 15))
                    .foregroundColor(.textTertiary)
                TextField(tr("profile.new_name"), text: $input)
                    .font(.system(size: 16, weight: .medium))
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { submitIfValid() }
                    .disabled(isOnCooldown)
                if !input.isEmpty && !isOnCooldown {
                    Button { input = "" } label: {
                        DazuIcon("xmark.circle.fill")
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Color.bgCard
                .opacity(isOnCooldown ? 0.5 : 1),
                        in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)

            Spacer(minLength: 20)

            // Buttons
            VStack(spacing: 10) {
                Button {
                    submitIfValid()
                } label: {
                    Text(tr("profile.submit_request"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            isValid && !isOnCooldown
                            ? LinearGradient(colors: [.auroraOrange, .auroraGreen],
                                             startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color(UIColor.systemGray3)],
                                             startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                }
                .disabled(!isValid || isOnCooldown)

                Button(tr("profile.cancel_btn")) { dismiss() }
                    .font(.system(size: 15))
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Color.bgGrouped)
        .onAppear { if !isOnCooldown { focused = true } }
    }

    private var isValid: Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != currentName && trimmed.count >= 2
    }

    private func submitIfValid() {
        guard isValid && !isOnCooldown else { return }
        onSubmit()
        dismiss()
    }
}

// MARK: - Nav Pop Gesture Disabler

/// Killt ALLE Edge-Pan-Recognizer im Window-Hierarchy + Navigation-Pop-Geste.
/// iOS 26 reaktiviert die Geste teilweise lazy nach dem initialen Disable —
/// daher mehrfaches Polling über die ersten 5 Sekunden.
private struct NavPopGestureDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        for i in 0..<25 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.2) {
                kill(from: uiView)
            }
        }
    }

    private func kill(from view: UIView) {
        // Navigation-Controller Pop-Geste abschalten.
        if let nav = sequence(first: view as UIResponder, next: { $0.next })
            .compactMap({ $0 as? UINavigationController })
            .first {
            nav.interactivePopGestureRecognizer?.isEnabled = false
            nav.interactivePopGestureRecognizer?.delegate  = nil
        }
        // Edge-Pan-Recognizer im Window-Hierarchy killen (iOS-26 "Swipe-from-anywhere").
        guard let window = view.window else { return }
        func recurse(_ v: UIView) {
            for recog in v.gestureRecognizers ?? [] {
                if recog is UIScreenEdgePanGestureRecognizer {
                    recog.isEnabled = false
                    recog.delegate  = nil
                }
            }
            for sub in v.subviews { recurse(sub) }
        }
        recurse(window)
    }
}

// MARK: - Age Range Slider



// MARK: - Stat Detail Sheet
//
// Beim Tap auf eine Statistik-Kachel (Runden gesamt / Beigetreten /
// Freunde / Treffen) öffnet dieses Sheet mit der jeweiligen Liste.
enum StatDetailKind: String, Identifiable {
    case roundsCreated, roundsJoined, friends, meetings
    var id: String { rawValue }

    var title: (first: String, accent: String) {
        switch self {
        case .roundsCreated: return (tr("stat.your_rounds_first"), tr("stat.your_rounds_accent"))
        case .roundsJoined:  return (tr("stat.joined_first"), tr("stat.joined_accent"))
        case .friends:       return (tr("stat.friends_first"), tr("stat.friends_accent"))
        case .meetings:      return (tr("stat.meetings_first"), tr("stat.meetings_accent"))
        }
    }

    var subtitle: String {
        switch self {
        case .roundsCreated: return tr("stat.rounds_created_sub")
        case .roundsJoined:  return tr("stat.rounds_joined_sub")
        case .friends:       return tr("stat.friends_sub")
        case .meetings:      return tr("stat.meetings_sub")
        }
    }
}

struct StatDetailSheet: View {
    let kind: StatDetailKind
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    /// Cache für die Freund-Altersangaben — wird on-appear aus Firebase
    /// hydriert pro UID. nil = noch nicht geladen oder kein Birthdate.
    @State private var friendAges: [String: Int] = [:]
    /// Cache für letzten Online-Heartbeat pro Freund-UID.
    @State private var friendLastActive: [String: Date] = [:]
    /// User den der Nutzer in dieser Liste angetippt hat — triggert das
    /// MiniProfileSheet als inner sheet. nil = nichts offen.
    @State private var tappedFriend: User? = nil
    /// PastDrop den der Nutzer in der Runden-Liste angetippt hat — öffnet
    /// das DropSummarySheet mit allen Details der vergangenen Runde.
    @State private var tappedPastDrop: PastDrop? = nil

    var body: some View {
        ZStack {
            Color.brandCream.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    (Text(kind.title.first + " ").foregroundColor(.brandNight)
                     + Text(kind.title.accent).foregroundColor(.brandViolet)
                     + Text(".").foregroundColor(.brandOrange))
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(kind.subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.6))
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }

                Button(action: { dismiss() }) {
                    Text(tr("common.close"))
                        .dropsPrimaryButton()
                }
                .dropsPressable()
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
            }
        }
        .onAppear { hydrateFriendAges() }
        .sheet(item: $tappedFriend) { f in
            MiniProfileSheet(
                name: f.name,
                emoji: f.emoji,
                profileImageURL: f.profileImageURL,
                reliabilityScore: f.reliabilityPoints,
                subtitle: tr("profile.your_friend"),
                accentColor: .brand,
                userUID: f.firebaseUID,
                canBlock: false,
                isFriend: true
            ) { tappedFriend = nil }
            .environmentObject(store)
            .presentationDetents([.height(460)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $tappedPastDrop) { drop in
            DropSummarySheet(drop: drop)
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .roundsCreated:
            let drops = store.pastDrops.filter { $0.wasHost }
            if drops.isEmpty { emptyState(tr("stat.no_own_rounds")) }
            else { pastDropsList(drops) }
        case .roundsJoined:
            let drops = store.pastDrops.filter { !$0.wasHost }
            if drops.isEmpty { emptyState(tr("stat.no_joined_rounds")) }
            else { pastDropsList(drops) }
        case .friends:
            if store.friends.isEmpty { emptyState("Noch keine Freunde") }
            else {
                // Zwei-Spalten-Grid mit Kacheln: Avatar + Name + Alter +
                // Status (online/offline) + Verlässlich-Badge wenn trusted.
                let cols = [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)]
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(store.friends, id: \.id) { f in
                        Button(action: { tappedFriend = f }) {
                            friendTile(f)
                        }
                        .buttonStyle(.plain)
                        .dropsPressable()
                    }
                }
            }
        case .meetings:
            // „Treffen"-Liste aus mehreren Quellen zusammenfügen:
            // 1. Lokale pastDrops (jede vergangene Runde = ein Treffen, mit
            //    Datum + Aktivität).
            // 2. Confirmed encounters die noch nicht als pastDrop existieren
            //    (BLE-Begegnungen ohne Drop-Kontext).
            // 3. Falls BEIDE leer, aber die Score-Kachel showUps > 0 zeigt,
            //    einen Fallback-Hinweis mit der Zahl rendern — die Details
            //    liegen in Firebase, nicht lokal.
            let drops = store.pastDrops.sorted(by: { $0.date > $1.date })
            let confirmed = store.encounters.filter { $0.confirmed }
            let totalShown = drops.count + confirmed.count

            if totalShown == 0 {
                if store.reliabilityScore.showUps > 0 {
                    // Platzhalter-Einträge in Zahl von showUps zeigen — ohne
                    // Details, aber damit der User sieht dass die Treffen
                    // zählen. Erklärung oben.
                    VStack(spacing: 10) {
                        Text(tr("profile.showups_count")
                            .replacingOccurrences(of: "{n}", with: "\(store.reliabilityScore.showUps)"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.7))
                            .multilineTextAlignment(.center)
                        Text(tr("profile.showups_hint"))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)

                    ForEach(0..<store.reliabilityScore.showUps, id: \.self) { i in
                        detailRow(
                            emoji: "✨",
                            title: tr("stat.meetup"),
                            sub: i == 0 ? tr("stat.recently") : tr("stat.a_while_ago")
                        )
                    }
                } else {
                    emptyState(tr("stat.no_meetups"))
                }
            } else {
                ForEach(drops, id: \.id) { d in
                    detailRow(
                        emoji: d.activityEmoji,
                        title: d.activityName,
                        sub: "\(d.date.formatted(.dateTime.day().month())) · \(d.participantCount) \(d.participantCount == 1 ? "Person" : "Personen")"
                    )
                }
                ForEach(confirmed, id: \.id) { e in
                    Button(action: {
                        if let friend = store.friends.first(where: {
                            ($0.firebaseUID != nil && $0.firebaseUID == e.friendUID)
                            || $0.name == e.friendName
                        }) {
                            tappedFriend = friend
                        }
                    }) {
                        userRow(name: e.friendName,
                                profileImageURL: e.friendProfileImageURL,
                                sub: e.createdAt.formatted(.dateTime.day().month()))
                    }
                    .buttonStyle(.plain)
                    .dropsPressable()
                }
            }
        }
    }

    /// Row für vergangene Runden — zeigt die Activity-Emoji im Lavendel-Tile,
    /// da das hier das thematische Icon ist (Kaffee, Tennis, Essen), nicht
    /// ein User-Avatar.
    /// Reichhaltige Runden-Liste (vorher der eigene `pastDropsSection`-Block
    /// im Profil). Tap öffnet das DropSummarySheet mit allen Details.
    @ViewBuilder
    private func pastDropsList(_ drops: [PastDrop]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(drops.enumerated()), id: \.element.id) { i, drop in
                Button { tappedPastDrop = drop } label: {
                    HStack(spacing: 14) {
                        // Mini-Map mit Activity-Emoji-Chip + Host-Krone overlay.
                        // Nutzt die eingefrorene Drop-Koordinate — zeigt wo
                        // das Treffen war, viel aussagekräftiger als ein Icon.
                        ZStack(alignment: .bottomTrailing) {
                            if let coord = drop.coordinate {
                                MiniMapSnapshot(coordinate: coord,
                                                size: CGSize(width: 48, height: 48),
                                                cornerRadius: 11,
                                                metersSpan: 400)
                            } else {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Color.brandLavender)
                                    .frame(width: 48, height: 48)
                            }
                            // Activity-Emoji als Chip unten rechts
                            ZStack {
                                Circle().fill(Color.bgPrimary)
                                    .frame(width: 22, height: 22)
                                DazuActivityIcon(drop.activityEmoji)
                                    .font(.system(size: 12))
                            }
                            .overlay(Circle().stroke(Color.brand.opacity(0.2), lineWidth: 1))
                            .offset(x: 5, y: 5)
                            if drop.wasHost {
                                DazuIcon("crown.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.accentOrange)
                                    .padding(3)
                                    .background(Color.bgPrimary, in: Circle())
                                    .offset(x: -2, y: -48 + 10)
                            }
                        }

                        // Content-Spalte — zwei Zeilen (Activity + Host /
                        // Location) plus eine schmale Zeit-Zeile darunter.
                        // Vorher stand Location + Datum + Uhrzeit alles in
                        // einer HStack mit Spacer rechts, was auf schmalen
                        // Karten jedes Wort in Einzelzeilen gebrochen hat
                        // ("Englisc / her / Garten"). lineLimit(1) +
                        // minimumScaleFactor kappen den Overflow sauber.
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(drop.activityName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(1)
                                if drop.wasHost {
                                    Text(tr("profile.host"))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.accentOrange)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Color.accentOrange.opacity(0.1), in: Capsule())
                                        .fixedSize()
                                }
                            }
                            Text(drop.locationName)
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text("\(drop.dateLabel) · \(drop.timeLabel)")
                                .font(.system(size: 11))
                                .foregroundColor(.textTertiary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 6)

                        // Nur 2 Avatare statt 3 — spart ~18pt für Content.
                        HStack(spacing: -8) {
                            ForEach(drop.participants.prefix(2)) { p in
                                if let url = p.profileImageURL, !url.isEmpty {
                                    RemoteProfileImage(
                                        url: url,
                                        fallbackEmoji: p.emoji,
                                        size: 24,
                                        strokeColor: Color.primary.opacity(0.08)
                                    )
                                } else {
                                    DazuPersonIcon()
                                        .font(.system(size: 13))
                                        .frame(width: 24, height: 24)
                                        .background(Color.bgPrimary, in: Circle())
                                        .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                                }
                            }
                        }
                        .padding(.trailing, 2)

                        DazuIcon("chevron.right")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                }
                .dropsPressable()
                .contextMenu {
                    Button(role: .destructive) {
                        store.deletePastDrop(id: drop.id)
                    } label: {
                        Label(tr("common.delete"), systemImage: "trash")
                    }
                }

                if i < drops.count - 1 {
                    Divider().padding(.leading, 70)
                }
            }
        }
        .liquidGlass(cornerRadius: Radius.lg)
    }

    @ViewBuilder
    private func detailRow(emoji: String, title: String, sub: String?) -> some View {
        HStack(spacing: 14) {
            DazuActivityIcon(emoji)
                .font(.system(size: 22))
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.brandLavender))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.brandNight)
                if let sub = sub {
                    Text(sub)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.55))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .liquidGlass(cornerRadius: 18)
    }

    /// Lädt die Birthdates aller Freunde aus Firebase und berechnet daraus
    /// das aktuelle Alter. Wird on-appear getriggert und füllt den `friendAges`-
    /// Cache. User ohne Birthdate werden einfach übersprungen.
    private func hydrateFriendAges() {
        for friend in store.friends {
            guard let uid = friend.firebaseUID, !uid.isEmpty else { continue }
            // Alter laden falls noch nicht cached.
            if friendAges[uid] == nil {
                RealtimeDBManager.shared.fetchUserMeta(uid: uid) { _, birthdate in
                    guard let bd = birthdate else { return }
                    let comps = Calendar.current.dateComponents([.year], from: bd, to: Date())
                    guard let years = comps.year, years > 0, years < 120 else { return }
                    DispatchQueue.main.async {
                        friendAges[uid] = years
                    }
                }
            }
            // Letzten Online-Heartbeat laden.
            RealtimeDBManager.shared.fetchLastActive(uid: uid) { lastActive in
                guard let la = lastActive else { return }
                DispatchQueue.main.async {
                    friendLastActive[uid] = la
                }
            }
        }
    }

    /// Formatiert einen Last-Active-Zeitpunkt als „vor X Min / Std / Tagen"
    /// bzw. „Online" wenn <5 min alt.
    private func lastActiveLabel(for date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 5 * 60 { return "Online" }
        if delta < 60 * 60 { return "vor \(Int(delta / 60)) Min" }
        if delta < 24 * 60 * 60 { return "vor \(Int(delta / 3600)) Std" }
        let d = Int(delta / 86400)
        return d == 1 ? "gestern" : "vor \(d) Tagen"
    }

    /// Kompakte Freunde-Kachel für den Grid: Avatar oben, Name + Alter
    /// darunter, Online-Dot und Verlässlich-Badge als Chips.
    @ViewBuilder
    private func friendTile(_ friend: User) -> some View {
        VStack(spacing: 10) {
            // Avatar mit Online-Dot unten rechts
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let url = friend.profileImageURL, !url.isEmpty {
                        RemoteProfileImage(url: url, fallbackEmoji: "",
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

                Circle()
                    .fill(friend.isAvailable
                          ? Color.onlineGreen
                          : Color(red: 0.60, green: 0.60, blue: 0.65))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.brandCream, lineWidth: 2))
            }

            // Name + Alter (falls aus Firebase geladen)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(friend.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.brandNight)
                    .lineLimit(1)
                if let uid = friend.firebaseUID, let age = friendAges[uid] {
                    Text("· \(age)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.45))
                }
            }

            // Status: "Online" (grün) wenn live, sonst „vor X Min / Std / Tagen"
            // aus dem Last-Active-Cache. + Verlässlich-Siegel wenn trusted.
            HStack(spacing: 4) {
                let statusText: String = {
                    if friend.isAvailable { return "Online" }
                    if let uid = friend.firebaseUID,
                       let la = friendLastActive[uid] {
                        return lastActiveLabel(for: la)
                    }
                    return "Offline"
                }()
                let isLive = statusText == "Online"
                Text(statusText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(isLive ? .onlineGreen : .brandNight.opacity(0.5))
                    .lineLimit(1)
                if ReliabilityScore.isTrusted(forPoints: friend.reliabilityPoints) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.brandViolet)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.brandLavender.opacity(0.6)))
    }

    /// Row für User (Freunde, Begegnungen) — zeigt das Profilbild wenn
    /// vorhanden, sonst das dazu-Profil-Icon in einem Lavendel-Kreis.
    /// Minimal: kein Tile-Hintergrund, nur Avatar + Name + optionaler Sub.
    @ViewBuilder
    private func userRow(name: String, profileImageURL: String?, sub: String?) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.brandLavender).frame(width: 42, height: 42)
                if let url = profileImageURL, !url.isEmpty {
                    RemoteProfileImage(url: url, fallbackEmoji: "", size: 42,
                                       strokeColor: .clear)
                } else {
                    DazuProfileIcon(size: 26)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.brandNight)
                if let sub = sub {
                    Text(sub)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.55))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4).padding(.vertical, 8)
    }

    @ViewBuilder
    private func emptyState(_ text: String) -> some View {
        // Vertikal zentriert innerhalb des Sheet-Content-Bereichs. Icon ist
        // das dazu-Logo (TabDazu) damit die Marke als beruhigende Signatur
        // in leeren Zuständen wiederkehrt.
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(Color.brandLavender)
                    .frame(width: 88, height: 88)
                Image("TabDazu")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.brandViolet.opacity(0.8))
                    .frame(width: 42, height: 42)
            }
            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.brandNight.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

// MARK: - Phone Link Sheet

/// Verknüpft eine Telefonnummer mit dem bestehenden Firebase-Account
/// (Apple/Google). Zwei-Step-Flow analog zu LoginView, aber nutzt
/// `linkPhoneToCurrentUser` statt `signIn` — so bleibt der User
/// derselbe, bekommt aber eine zusätzliche Auth-Methode.
struct PhoneLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore
    @StateObject private var auth = FirebaseAuthManager()
    @State private var phoneNumber = ""
    @State private var enteredCode = ""
    @State private var step: Step = .phone
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var selectedCountry = CountryCode(flag: "🇩🇪", name: "Deutschland", dial: "+49")
    @State private var showCountryPicker = false

    enum Step { case phone, code }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandLavender.ignoresSafeArea()
                VStack(spacing: 18) {
                    Spacer().frame(height: 20)

                    Image(systemName: "phone.badge.plus")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundColor(.brandViolet)
                        .padding(.bottom, 4)

                    Text(step == .phone
                         ? tr("settings.phone_link_sheet_title")
                         : tr("settings.sms_code_enter_title"))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.brandNight)

                    Text(step == .phone
                         ? tr("settings.phone_link_sheet_body")
                         : tr("settings.sms_code_enter_body"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.brandNight.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .fixedSize(horizontal: false, vertical: true)

                    if step == .phone {
                        HStack(spacing: 10) {
                            Button {
                                showCountryPicker = true
                            } label: {
                                HStack(spacing: 6) {
                                    Text(selectedCountry.flag)
                                    Text(selectedCountry.dial)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.brandNight)
                                    Image(systemName: "chevron.down").font(.caption)
                                        .foregroundColor(.brandNight.opacity(0.5))
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(Capsule().fill(Color.white.opacity(0.6)))
                            }
                            TextField("1771234567", text: $phoneNumber)
                                .keyboardType(.numberPad)
                                .font(.system(size: 16, weight: .medium))
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(Capsule().fill(Color.white.opacity(0.6)))
                        }
                        .padding(.horizontal, 24)
                    } else {
                        TextField("Code", text: $enteredCode)
                            .keyboardType(.numberPad)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color.white.opacity(0.6)))
                            .padding(.horizontal, 24)
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Button(action: primaryAction) {
                        if isLoading {
                            DazuLoader().tint(.white).frame(height: 20)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Capsule().fill(Color.brandViolet))
                        } else {
                            Text(step == .phone ? tr("auth.send_code") : tr("auth.link_verb"))
                                .dropsPrimaryButton()
                        }
                    }
                    .dropsPressable()
                    .padding(.horizontal, 24)
                    .disabled(isLoading || (step == .phone ? phoneNumber.count < 4 : enteredCode.count < 4))

                    Spacer()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .foregroundColor(.brandViolet)
                }
            }
            .sheet(isPresented: $showCountryPicker) {
                CountryPickerSheet(selected: $selectedCountry)
            }
        }
    }

    private func primaryAction() {
        if step == .phone { sendCode() } else { verifyAndLink() }
    }

    private func sendCode() {
        let fullNumber = "\(selectedCountry.dial)\(phoneNumber.filter { $0.isNumber })"
        isLoading = true; errorMessage = nil
        Task {
            await auth.sendVerificationCode(to: fullNumber)
            isLoading = false
            if case .smsSent = auth.state {
                withAnimation(.easeInOut(duration: 0.22)) { step = .code }
            } else if case .error(let msg) = auth.state {
                errorMessage = msg
            }
        }
    }

    private func verifyAndLink() {
        isLoading = true; errorMessage = nil
        Task {
            let result = await auth.linkPhoneToCurrentUser(code: enteredCode)
            isLoading = false
            if result.success, let phone = result.phone {
                // Phone in RTDB + Index aktualisieren
                RealtimeDBManager.shared.saveUserPhone(phone)
                store.showInfoToast(tr("auth.phone_link_success"), icon: "checkmark.circle.fill")
                dismiss()
            } else if case .error(let msg) = auth.state {
                errorMessage = msg
            } else {
                errorMessage = tr("auth.phone_link_failed")
            }
        }
    }
}
