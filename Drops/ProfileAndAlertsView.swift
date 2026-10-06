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
    @State private var showImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var showImageSourceSheet = false
    @State private var showEmojiPicker = false
    @State private var showScoreInfo = false
    @State private var showHeroPicker = false
    @State private var showNameChangeSheet = false
    @State private var nameChangeInput = ""
    /// Persistierter Profil-Hero-Hintergrund. Default: aurora.
    @AppStorage("ud_profileHeroTemplate") private var profileHeroTemplateRaw = ProfileHeroTemplate.aurora.rawValue
    /// Beta-Badge-Cutoff: zentralisiert in AppStore.qualifiesForBetaBadge —
    /// dieselbe Logik wird jetzt überall in der App verwendet.
    private var qualifiesForBetaBadge: Bool {
        store.qualifiesForBetaBadge
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

                        // Rondesignlab-Style Hero
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                DazuWordmark(color: .brandNight, dotColor: .brandOrange)
                                    .frame(height: 24)
                                Spacer()
                            }
                            VStack(alignment: .leading, spacing: -4) {
                                Text("Dein")
                                    .foregroundColor(.brandNight)
                                Text("Kreis.")
                                    .foregroundColor(.brandViolet)
                            }
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 20)

                        // Eigener Status
                        myStatusCard

                        // Drop-Statistiken
                        dropStatsSection

                        // Letzte Begegnungen (direkt unter Statistiken)
                        encountersSection

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

                        // Offline-Freunde
                        if !offlineFriends.isEmpty {
                            friendSection(
                                title: tr("profile.unavailable"),
                                badge: nil,
                                friends: offlineFriends,
                                isOnline: false
                            )
                        }

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
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(image: $store.selfieImage,
                                isPresented: $showImagePicker,
                                sourceType: imagePickerSource)
            }
            .confirmationDialog(tr("profile.change_picture"), isPresented: $showImageSourceSheet, titleVisibility: .visible) {
                Button(tr("profile.take_photo")) {
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        DispatchQueue.main.async {
                            if granted {
                                imagePickerSource = .camera
                                showImagePicker = true
                            }
                        }
                    }
                }
                Button(tr("profile.pick_from_library")) {
                    imagePickerSource = .photoLibrary
                    showImagePicker = true
                }
                Button(tr("profile.cancel"), role: .cancel) {}
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
                            Image(systemName: "bolt.fill")
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
                    if ReliabilityScore.isTrusted(forPoints: store.reliabilityScore.points) {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.seal.fill")
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
                        Image(systemName: "camera.fill")
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
                Image(systemName: "person.crop.circle.badge.checkmark")
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
                Image(systemName: "sparkles")
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
                                    .overlay(Text(suggestion.emoji).font(.system(size: 32)))
                                    .overlay(Circle().stroke(Color.brand.opacity(0.2), lineWidth: 1.5))
                                // Dismiss-X
                                Button {
                                    withAnimation(.spring(response: 0.3)) {
                                        store.dismissSuggestion(id: suggestion.id)
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
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
                Image(systemName: "person.badge.plus")
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
                                .overlay(Text("👋").font(.system(size: 22)))
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
                            Image(systemName: "xmark")
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
                            Image(systemName: "checkmark")
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
                Image(systemName: "figure.walk.arrival")
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
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.brandLavender)
                                .frame(width: 40, height: 40)
                            Image(systemName: "person.2.wave.2.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.brandViolet)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("profile.no_encounters_yet"))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.brandNight)
                            Text(tr("profile.no_encounters_sub"))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.brandNight.opacity(0.6))
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
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
        let rs      = store.reliabilityScore
        let streak  = weeklyStreak
        let favEmoji = store.pastDrops
            .map { $0.activityEmoji }
            .reduce(into: [:]) { $0[$1, default: 0] += 1 }
            .max(by: { $0.value < $1.value })?.key ?? "✨"

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
                        Text("🔥").font(.system(size: 11))
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

            // ── 2x2 Grid aus Stat-Tiles im Rondesignlab-Style.
            // „Zuverlässigkeit %" rausgenommen — stattdessen „Treffen"
            // (Anzahl bestätigter Begegnungen) als positiver, lesbarer Wert.
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    StatTile(value: "\(total)",
                             label: tr("profile.drops_total"),
                             icon: "bolt.fill",
                             color: Color.brandViolet)
                        .modifier(DazuStatCardStyle())
                    StatTile(value: "\(joined)",
                             label: tr("profile.joined"),
                             icon: "person.fill.badge.plus",
                             color: Color.brandOrange)
                        .modifier(DazuStatCardStyle())
                }
                HStack(spacing: 12) {
                    StatTile(value: "\(store.friends.count)",
                             label: tr("profile.friends"),
                             icon: "person.2.fill",
                             color: Color.brandViolet)
                        .modifier(DazuStatCardStyle())
                    StatTile(value: "\(rs.showUps)",
                             label: "Treffen",
                             icon: "checkmark.seal.fill",
                             color: Color.brandOrange)
                        .modifier(DazuStatCardStyle())
                }
            }
            .padding(.vertical, 2)

            // ── Lieblings-Aktivität (nur wenn schon Drops da) ─────
            if total > 0 {
                HStack(spacing: 12) {
                    Text(favEmoji).font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("profile.favorite_activity"))
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                        Text(store.pastDrops
                            .filter { $0.activityEmoji == favEmoji }
                            .first?.activityName ?? "")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                    }
                    Spacer()
                    Text("\(store.pastDrops.filter { $0.activityEmoji == favEmoji }.count)×")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.white.opacity(0.75)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: Drop-Verlauf

    @State private var selectedPastDrop: PastDrop? = nil

    @ViewBuilder private var pastDropsSection: some View {
        if !store.pastDrops.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(tr("profile.recent_drops"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    Text("\(store.pastDrops.count) gesamt")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 20).padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(Array(store.pastDrops.enumerated()), id: \.element.id) { i, drop in
                        Button { selectedPastDrop = drop } label: {
                            HStack(spacing: 14) {
                                // Emoji + Host-Indikator
                                ZStack(alignment: .bottomTrailing) {
                                    Text(drop.activityEmoji)
                                        .font(.system(size: 24))
                                        .frame(width: 40, height: 40)
                                        .background(Color.brand.opacity(0.08), in: Circle())
                                    if drop.wasHost {
                                        Image(systemName: "crown.fill")
                                            .font(.system(size: 8))
                                            .foregroundColor(.accentOrange)
                                            .padding(2)
                                            .background(Color.bgPrimary, in: Circle())
                                            .offset(x: 2, y: 2)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(drop.activityName)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.textPrimary)
                                        if drop.wasHost {
                                            Text(tr("profile.host"))
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.accentOrange)
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(Color.accentOrange.opacity(0.1), in: Capsule())
                                        }
                                    }
                                    HStack(spacing: 4) {
                                        Text(drop.locationName)
                                            .font(.system(size: 12))
                                            .foregroundColor(.textSecondary)
                                        Text("·")
                                            .foregroundColor(.textTertiary)
                                        Text(drop.dateLabel)
                                            .font(.system(size: 12))
                                            .foregroundColor(.textSecondary)
                                        Text(drop.timeLabel)
                                            .font(.system(size: 12))
                                            .foregroundColor(.textTertiary)
                                    }
                                }

                                Spacer()

                                // Teilnehmer-Avatare (max 3) — Profilbild bevorzugt,
                                // Emoji als Fallback. Bisher zeigte die Liste immer
                                // das Default-😊 statt der echten Profilbilder.
                                HStack(spacing: -8) {
                                    ForEach(drop.participants.prefix(3)) { p in
                                        if let url = p.profileImageURL, !url.isEmpty {
                                            RemoteProfileImage(
                                                url: url,
                                                fallbackEmoji: p.emoji,
                                                size: 26,
                                                strokeColor: Color.primary.opacity(0.08)
                                            )
                                        } else {
                                            Text(p.emoji)
                                                .font(.system(size: 14))
                                                .frame(width: 26, height: 26)
                                                .background(Color.bgPrimary, in: Circle())
                                                .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                                        }
                                    }
                                }
                                .padding(.trailing, 4)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundColor(.textTertiary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }
                        .dropsPressable()

                        if i < store.pastDrops.count - 1 {
                            Divider().padding(.leading, 70)
                        }
                    }
                }
                .liquidGlass(cornerRadius: Radius.lg)
                .padding(.horizontal, 16)
            }
            .sheet(item: $selectedPastDrop) { drop in
                DropSummarySheet(drop: drop)
            }
        }
    }

    // MARK: Freund hinzufügen

    private var addFriendCard: some View {
        // Gleicher Stil wie FreundeEmptyState (Sunset-Gradient-Pill für die
        // Primary-Action „Aus Kontakten hinzufügen", Brand-Outline-Pill für
        // „Einladungslink teilen") — vorher hatte diese Card noch das alte
        // Row-Layout mit Icon-Quadraten und Chevrons, was inkonsistent zum
        // Empty-State aussah. Jetzt einheitlich.
        VStack(spacing: 8) {
            Button(action: { showAddSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                    Text(tr("profile.add_from_contacts"))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18).padding(.vertical, 11)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color.auroraOrange, Color.auroraGreen],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                )
                .shadow(color: Color.auroraOrange.opacity(0.35), radius: 10, y: 3)
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
                    Image(systemName: "square.and.arrow.up")
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
    }
}

// MARK: - Drop Summary Sheet

struct DropSummarySheet: View {
    let drop: PastDrop
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "de"

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
                        Text(drop.activityEmoji)
                            .font(.system(size: 52))
                            .frame(width: 84, height: 84)
                            .background(Color.brand.opacity(0.08), in: Circle())

                        Text(drop.activityName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.textPrimary)

                        HStack(spacing: 6) {
                            Image(systemName: "mappin.circle.fill")
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
                                Image(systemName: "crown.fill")
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
                                            Text(p.emoji)
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
                                                Image(systemName: "crown.fill")
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("common.done")) { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.brand)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private func statTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
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
                        Text(encounter.friendEmoji).font(.system(size: 24))
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
                            Image(systemName: "checkmark.circle.fill")
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
                            Image(systemName: "hourglass")
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
                                Image(systemName: "person.badge.plus")
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
                            Image(systemName: "checkmark.circle.fill")
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
                        Image(systemName: "antenna.radiowaves.left.and.right")
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
                Text(note.requesterEmoji)
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
                        Image(systemName: "figure.walk")
                            .font(.system(size: 10))
                            .foregroundColor(.onlineGreen)
                        Text(dist)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.onlineGreen)
                    }
                } else {
                    Text("\(note.dropEmoji) \(note.dropActivity) · \(note.timeAgoLabel)")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            Image(systemName: "figure.walk.arrival")
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
                    Text(encounter.friendEmoji).font(.system(size: 26))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
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
                    Image(systemName: "person.2.fill")
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
                                    .overlay(Text(s.emoji).font(.system(size: 28)))
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
                    Image(systemName: "magnifyingglass").foregroundColor(.textTertiary)
                    TextField(tr("profile.search_name"), text: $searchText)
                        .font(.system(size: 15)).foregroundColor(.textPrimary)
                }
                .padding(12)
                .liquidGlass(cornerRadius: 14)
                .padding(.horizontal, 16).padding(.vertical, 12)

                if vm.isLoading {
                    Spacer()
                    ProgressView().tint(.brand).scaleEffect(0.9)
                        .tint(.brand)
                    Text(tr("profile.searching_contacts"))
                        .font(.system(size: 13)).foregroundColor(.textSecondary)
                        .padding(.top, 10)
                    Spacer()
                } else if vm.permissionDenied {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.xmark")
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
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 40)).foregroundColor(.textTertiary)
                        Text(tr("profile.no_contacts_on_drops"))
                            .font(.system(size: 14)).foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                    }
                    Spacer()
                } else {
                    // Treffer
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.brand)
                        Text("\(vm.matches.count) KONTAKT\(vm.matches.count == 1 ? "" : "E") AUF DROPS")
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
                        Image(systemName: "square.and.arrow.up")
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
            Circle().fill(Color.brand.opacity(0.1)).frame(width: 44, height: 44)
                .overlay(Text(emoji).font(.system(size: 22)))
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
                        // Zeit-ETA + km-Entfernung kombiniert
                        Text("\(store.etaString(to: friend.coordinate)) · \(store.distanceString(to: friend.coordinate))")
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
                    Image(systemName: "chevron.right")
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
    @AppStorage("settingLocationSharing") private var locationSharing = true
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
    /// Dashboard-Sheet für die eigene Community (separater State weil
    /// .sheet(item:) eine Community als Identifier braucht).
    @State private var dashboardCommunity: Community? = nil

    enum SettingsSheet: String, Identifiable {
        case admin, blockedList, privacy, terms, dropsPlus, communityCreator
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

                        // Rondesignlab-Style Hero
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                DazuWordmark(color: .brandNight, dotColor: .brandOrange)
                                    .frame(height: 24)
                                Spacer()
                            }
                            VStack(alignment: .leading, spacing: -4) {
                                Text("Deine")
                                    .foregroundColor(.brandNight)
                                Text("Welt.")
                                    .foregroundColor(.brandViolet)
                            }
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 20)

                        // ── Drops+ Banner ────────────────────────────────
                        // Aus für den initialen Launch — wieder einschalten
                        // via `FeatureFlags.dropsPlusEnabled = true` in Models.swift.
                        if FeatureFlags.dropsPlusEnabled {
                            Button { activeSettingsSheet = .dropsPlus } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "bolt.fill")
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
                                    Image(systemName: "chevron.right")
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
                        settingsCategoryHeader("SICHTBARKEIT")

                        settingsSection(icon: "location.fill", color: Color(UIColor.systemGreen), title: tr("settings.visibility")) {
                            locationSection
                            Divider().padding(.leading, 60)
                            notificationSection
                        }

                        // Datenschutz-Hinweis
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lock.shield.fill")
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
                        settingsCategoryHeader("ENTDECKEN")

                        settingsSection(icon: "scope", color: Color(UIColor.systemBlue), title: tr("settings.drops_radius")) {
                            radiusSection
                        }

                        settingsSection(icon: "house.fill", color: Color.accentOrange, title: tr("settings.home_zone")) {
                            homeZoneSection
                        }

                        // Power-Hour Übersicht — Referenz wann der höhere
                        // Bonus läuft. Dauerhaft sichtbar, aktive Slots
                        // werden farblich hervorgehoben.
                        settingsSection(icon: "bolt.fill", color: Color.accentOrange, title: tr("settings.power_hour_times")) {
                            powerHourSection
                        }

                        settingsSection(icon: "person.2.fill", color: Color.auroraOrange, title: tr("settings.age_groups")) {
                            ageGroupSection
                        }

                        // Darstellung
                        // ── GRUPPE: Darstellung ──────────────────────
                        settingsCategoryHeader("DARSTELLUNG")

                        settingsSection(icon: "circle.lefthalf.filled", color: Color(UIColor.systemIndigo), title: tr("settings.appearance")) {
                            appearanceSection
                        }

                        // Community Creator — Antrag + Dashboard nach Genehmigung
                        // (Deaktiviert bis zur nächsten Version via FeatureFlags.communitiesEnabled)
                        if FeatureFlags.communitiesEnabled {
                            settingsSection(icon: "star.circle.fill", color: Color.brand, title: tr("settings.community_creator")) {
                                partnershipBadgeRow
                                Divider().padding(.leading, 16)
                                communityCreatorRow
                                if let myCommunity = store.myCommunity {
                                    Divider().padding(.leading, 66)
                                    myCommunityRow(myCommunity)
                                }
                            }
                        }

                        // Sicherheit — Blockierte Nutzer (Untermenü)
                        // ── GRUPPE: Sicherheit & Rechtliches ─────────
                        settingsCategoryHeader("SICHERHEIT & RECHTLICHES")

                        settingsSection(icon: "nosign", color: .red, title: tr("settings.security")) {
                            Button(action: { activeSettingsSheet = .blockedList }) {
                                HStack(spacing: 14) {
                                    dazuRowIcon(systemName: "nosign")
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
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.brandNight.opacity(0.45))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                            }
                            .dropsPressable()
                        }

                        // Hilfe & Feedback
                        settingsSection(icon: "questionmark.circle.fill", color: Color(UIColor.systemBlue), title: tr("settings.help_feedback")) {
                            faqLinkRow
                            Divider().padding(.leading, 60)
                            feedbackRow
                        }

                        // Datenschutz + Konto
                        settingsSection(icon: "hand.raised.fill", color: Color.auroraViolet, title: tr("settings.privacy_account")) {
                            privacySection
                            Divider().padding(.leading, 60)
                            accountSection
                        }

                        // Admin — nur sichtbar für Admins
                        if store.isAdmin || isAdminByCredentials {
                            settingsSection(icon: "star.fill", color: Color.brandViolet, title: tr("settings.administration")) {
                                Button(action: { activeSettingsSheet = .admin }) {
                                    HStack(spacing: 14) {
                                        dazuRowIcon(systemName: "shield.lefthalf.filled")
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(tr("settings.admin_panel"))
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                .foregroundColor(.brandNight)
                                            Text(tr("settings.admin_panel_sub"))
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                                .foregroundColor(.brandNight.opacity(0.6))
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
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
                            ProgressView().tint(.white)
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
                        Image(systemName: "checkmark.seal.fill")
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
                    Image(systemName: "chevron.right")
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
                    Image(systemName: community.icon)
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
                Image(systemName: "chevron.right")
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

    private func settingsSection<Content: View>(icon: String, color: Color, title: String, @ViewBuilder content: () -> Content) -> AnyView {
        AnyView(
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    SettingsHeaderIcon(icon: icon, color: color)
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
                    .foregroundColor(Color(UIColor.systemBlue))
                    .contentTransition(.numericText())
                Text(radiusWalkLabel(clampedFilter))
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                Spacer()
                Image(systemName: "figure.walk")
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
            .tint(Color(UIColor.systemBlue))
            .padding(.horizontal, 16)

            // Tick-Labels
            HStack {
                ForEach(steps, id: \.self) { step in
                    Text(radiusTickLabel(step))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(clampedFilter == step ? Color(UIColor.systemBlue) : .textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 4)

            Divider().padding(.horizontal, 16)

            // Info-Zeile
            HStack(spacing: 10) {
                Image(systemName: "eye.fill")
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
                            .foregroundColor(Color(UIColor.systemBlue).opacity(0.8))
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
                ZStack {
                    Circle()
                        .fill(Color.brandLavender)
                        .frame(width: 40, height: 40)
                    Image(systemName: "house.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(store.homeZoneCoordinate != nil ? Color.brandViolet : Color.brandNight.opacity(0.4))
                }
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
                            Image(systemName: "house.fill")
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
                    Label(store.homeZoneCoordinate != nil ? tr("profile.update") : tr("profile.set"),
                          systemImage: "location.fill")
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
                        Label(tr("profile.remove"), systemImage: "trash")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.brandOrange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
            }
        }
    }

    // MARK: - Power-Hour Section
    //
    // Statische Übersicht aller konfigurierten Power-Hour-Slots aus
    // AppStore.powerHourWindows. Aktive Slots werden orange hervorgehoben.
    // Erinnert den User wann der höhere Bonus läuft, ohne dass er erst
    // eine Push-Notification abwarten muss.
    @ViewBuilder private var powerHourSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Mini-Beschreibung
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
                    .padding(.top, 1)
                Text(tr("settings.power_hour_intro").replacingOccurrences(of: "{points}", with: "\(AppStore.powerHourBonus)"))
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().padding(.leading, 16)

            // Slot-Liste
            ForEach(Array(AppStore.powerHourWindows.enumerated()), id: \.offset) { idx, window in
                powerHourRow(window: window)
                if idx < AppStore.powerHourWindows.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    /// Eine Zeile pro Power-Hour-Window. Zeigt Label, Wochentag-Range,
    /// Zeit-Range und einen "Aktiv jetzt"-Badge wenn der Slot gerade läuft.
    @ViewBuilder
    private func powerHourRow(window: AppStore.PowerHourWindow) -> some View {
        let active = isWindowActive(window)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(window.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    if active {
                        Text(tr("settings.active_now"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentOrange))
                    }
                }
                Text("\(window.daysLabel) · \(window.timeRangeLabel)")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("+\(AppStore.powerHourBonus)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundColor(.accentOrange)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.accentOrange.opacity(0.12)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(active ? Color.accentOrange.opacity(0.06) : Color.clear)
    }

    /// Formatiert eine Set<Int> mit Apple-Wochentagen (1=So…7=Sa) zu
    /// einem deutschen Range-String wie "Mo–Do" oder "Fr–Sa" oder "So".
    /// Bei nicht-zusammenhängenden Tagen werden sie kommasepariert.
    private func weekdayLabel(_ days: Set<Int>) -> String {
        // Apple weekday → Index in deutscher Wochenreihenfolge (Mo=0…So=6)
        let names = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
        let mondayFirst = days.map { ($0 == 1 ? 6 : $0 - 2) }.sorted()
        guard let first = mondayFirst.first, let last = mondayFirst.last else { return "" }

        // Zusammenhängend? → Range
        let isContiguous = mondayFirst.count == (last - first + 1)
        if isContiguous {
            return mondayFirst.count == 1
                ? names[first]
                : "\(names[first])–\(names[last])"
        }
        // Sonst kommasepariert
        return mondayFirst.map { names[$0] }.joined(separator: ", ")
    }

    /// True wenn der gegebene Slot gerade läuft (Wochentag + Stunde matchen).
    private func isWindowActive(_ window: AppStore.PowerHourWindow) -> Bool {
        let now = Date()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        let hour = cal.component(.hour, from: now)
        return window.weekdays.contains(weekday)
            && hour >= window.startHour
            && hour < window.endHour
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
                            Image(systemName: "hand.raised.fill")
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
                            Text("\(age) J.")
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
                            Image(systemName: own.systemIcon).font(.system(size: 20)).foregroundColor(.brand)
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
                        Image(systemName: "checkmark.circle.fill")
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
                            Image(systemName: own.systemIcon).font(.system(size: 11))
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
            Image(systemName: icon)
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

    @ViewBuilder private var appearanceSection: some View {
        ForEach(MapStyleMode.allCases, id: \.rawValue) { mode in
            let isSelected = mapStyleModeRaw == mode.rawValue
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Color.brand.opacity(isSelected ? 0.18 : 0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: appearanceIcon(for: mode))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? .brand : .textSecondary)
                }
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

    /// Kompaktes DE/EN-Toggle für die Toolbar (oben rechts in den Einstellungen).
    /// Liquid-Glass-Pille mit zwei Buttons; der aktive Code bekommt einen
    /// Brand-Akzent-Hintergrund, die Pille selber sitzt auf einem .glassEffect.
    @ViewBuilder private var languageToggle: some View {
        HStack(spacing: 0) {
            ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                let isSelected = appLanguage == lang.rawValue
                Button {
                    if appLanguage != lang.rawValue {
                        Haptic.selection()
                        withAnimation(.easeInOut(duration: 0.18)) {
                            appLanguage = lang.rawValue
                        }
                    }
                } label: {
                    Text(lang.shortCode)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .white : .textSecondary)
                        .frame(minWidth: 28)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.brand : Color.clear)
                                .shadow(color: isSelected ? Color.brand.opacity(0.35) : .clear,
                                        radius: 6, y: 2)
                        )
                }
                .dropsPressable()
            }
        }
        .padding(2)
        .liquidGlassCapsule(shadowRadius: 6)
    }

    // MARK: - Shared Row Helper

    @ViewBuilder
    private func inlineToggle(_ title: String, subtitle: String,
                               icon: String, color: Color,
                               isOn: Binding<Bool>) -> some View {
        // Alle Row-Icons im Settings jetzt einheitlich Violett auf Lavendel-
        // Hintergrund (color-Parameter nur noch für Toggle-Tint, der bleibt
        // Orange im neuen dazu-Design).
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.brandLavender)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.brandViolet)
            }
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
        inlineToggle(tr("settings.location_sharing"),
                     subtitle: tr("settings.visibility_info"),
                     icon: "location.fill",
                     color: .onlineGreen,
                     isOn: $locationSharing)

        Divider().padding(.leading, 60)

        inlineToggle("Auf der Karte sichtbar",
                     subtitle: "Andere Dazu-Nutzer sehen dein Profilbild auf der Karte — mit 20 Min Verzögerung und auf ~500m gerundet. Freunde sehen zusätzlich deinen Namen, Fremde nur das Bild.",
                     icon: "figure.wave",
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
                        }))
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
                     icon: "bell.fill",
                     color: Color(UIColor.systemOrange),
                     isOn: $notificationsOn)
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
                    dazuRowIcon(systemName: "bell.badge.waveform.fill")
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
                dazuRowIcon(systemName: "phone.fill")
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
                Image(systemName: "person.2.fill").font(.system(size: 10))
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
                    Image(systemName: "exclamationmark.bubble.fill")
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
                Image(systemName: "chevron.right")
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

        App: Drops v\(version) (Build \(build))
        Gerät: \(device) · iOS \(iosVer)
        User-ID: \(uid)
        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@drops-app.de"
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
                dazuRowIcon(systemName: "checkmark")
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
                    dazuRowIcon(systemName: "nosign")
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

    /// Standard-Row-Icon im dazu-Design: Violett auf Lavendel-Rounded-Rect.
    @ViewBuilder private func dazuRowIcon(systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.brandLavender)
                .frame(width: 38, height: 38)
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.brandViolet)
        }
    }

    @ViewBuilder private var faqLinkRow: some View {
        Button {
            if let url = URL(string: "https://drops-app.de/#faq") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 14) {
                dazuRowIcon(systemName: "questionmark.circle.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("FAQ")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandNight)
                    Text(tr("settings.faq_sub"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.6))
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
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
            components.path = "contact@drops-app.de"
            components.queryItems = [
                URLQueryItem(name: "subject", value: subject),
                URLQueryItem(name: "body", value: body),
            ]
            if let url = components.url {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 14) {
                dazuRowIcon(systemName: "ladybug.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("settings.bug_feedback"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandNight)
                    Text(tr("profile.email_contact"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.6))
                }
                Spacer()
                Image(systemName: "envelope.fill")
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
                dazuRowIcon(systemName: "hand.raised.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("settings.privacy"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.brandNight)
                    Text(tr("settings.legal"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.brandNight.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.brandNight.opacity(0.45))
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .dropsPressable()
    }

    // MARK: - Account Section

    @ViewBuilder private var accountSection: some View {
        // Abmelden
        Button {
            store.logout()
        } label: {
            HStack(spacing: 14) {
                dazuRowIcon(systemName: "rectangle.portrait.and.arrow.right")
                Text(tr("account.logout"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.brandNight)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .dropsPressable()

        Divider().padding(.leading, 60)

        // Konto löschen — bleibt rot (destructive Standard)
        Button { showDeleteAlert = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.brandOrange.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: "person.crop.circle.badge.minus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.brandOrange)
                }
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

// MARK: - Stat Tile

private struct StatTile: View {
    let value: String
    let label: String
    let icon:  String
    let color: Color

    @State private var tapped = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Großes Icon-Badge oben (nicht neben dem Text)
            Image(systemName: icon)
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(color.opacity(0.15)))
                .scaleEffect(tapped ? 1.2 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.55), value: tapped)

            // Riesige Zahl
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.brandNight)
                .monospacedDigit()
                .contentTransition(.numericText())

            // Kleiner Label-Caps drunter
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundColor(.brandNight.opacity(0.5))
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.selection()
            tapped.toggle()
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
                        Image(systemName: "info.circle.fill")
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
                                Image(systemName: "checkmark.circle.fill")
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
                                        Image(systemName: "nosign")
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
                Image(systemName: "person.text.rectangle.fill")
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
                    Image(systemName: "clock.badge.exclamationmark")
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
                    Image(systemName: "hourglass")
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
                Image(systemName: "person.fill")
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
                        Image(systemName: "xmark.circle.fill")
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


