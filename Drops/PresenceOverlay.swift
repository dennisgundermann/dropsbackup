import SwiftUI
import MapKit

/// SwiftUI-Overlay über der MKMapView: zeigt für jeden Presence-Eintrag ein
/// Profilbild (rund, mit Namen bei Freunden, nur Age-Chip bei Fremden).
/// Fremde haben kein Namen-Chip, aber immer noch das Bild — der Schutz
/// liegt in der 500m-Gitter-Position + 20-Min-Delay, nicht in der Anonymität.
struct PresencePin: Identifiable, Equatable {
    let id: String
    let point: CGPoint
    let emoji: String
    let name: String?
    let profileImageURL: String?
    let ageLabel: String
    let isFriend: Bool
    static func == (a: PresencePin, b: PresencePin) -> Bool {
        a.id == b.id && a.point == b.point
    }
}

struct PresenceOverlay: View {
    let pinsProvider: () -> [PresencePin]

    @State private var flyingReactions: [FlyingReaction] = []

    var body: some View {
        TimelineView(.animation) { _ in
            let pins = pinsProvider()
            ZStack(alignment: .topLeading) {
                ForEach(pins) { pin in
                    PresenceMarker(pin: pin)
                        .position(pin.point)
                        .contentShape(Circle())
                        .onTapGesture { spawnReaction(emoji: pin.emoji, at: pin.point) }
                }

                // Fliegende Emoji-Reactions (ephemer, verschwinden nach ~1.2s)
                ForEach(flyingReactions) { r in
                    FlyingReactionView(reaction: r)
                }
            }
        }
    }

    private func spawnReaction(emoji: String, at origin: CGPoint) {
        let reaction = FlyingReaction(id: UUID(), emoji: emoji, origin: origin, createdAt: Date())
        flyingReactions.append(reaction)
        // Auto-cleanup nach Animation-Dauer
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            flyingReactions.removeAll { $0.id == reaction.id }
        }
    }
}

// MARK: - Flying Reaction (Tap-Feedback)

struct FlyingReaction: Identifiable, Equatable {
    let id: UUID
    let emoji: String
    let origin: CGPoint
    let createdAt: Date
    /// Zufällige seitliche Streuung (-20..20 px)
    let drift: CGFloat = CGFloat.random(in: -25...25)
}

private struct FlyingReactionView: View {
    let reaction: FlyingReaction
    @State private var animated = false

    var body: some View {
        DazuIcon("hand.wave.fill", accent: false)
            .font(.system(size: animated ? 44 : 18))
            .foregroundColor(.brandOrangeFixed)
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            .opacity(animated ? 0.0 : 1.0)
            .position(
                x: reaction.origin.x + (animated ? reaction.drift : 0),
                y: reaction.origin.y + (animated ? -80 : -20)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.1)) {
                    animated = true
                }
            }
            .allowsHitTesting(false)
    }
}

// MARK: - Marker

private struct PresenceMarker: View {
    let pin: PresencePin
    var body: some View {
        VStack(spacing: 3) {
            avatarCircle
            if pin.isFriend, let name = pin.name {
                Text(name.prefix(14))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.75)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            }
            Text(pin.ageLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.accentOrange.opacity(0.85)))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
    }

    private var avatarCircle: some View {
        ZStack {
            // Aurora-Aura
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.accentOrange.opacity(0.22), .clear],
                        center: .center, startRadius: 8, endRadius: 30
                    )
                )
                .frame(width: 60, height: 60)

            // Weißer Base-Kreis mit Aurora-Ring
            Circle()
                .fill(.white)
                .frame(width: 44, height: 44)
                .overlay(
                    Circle().stroke(Color.brandOrangeFixed, lineWidth: 3)
                )
                .shadow(color: Color.accentOrange.opacity(0.35), radius: 8, y: 2)
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)

            // Nutzt existing RemoteProfileImage (SharedComponents) — hat cache +
            // fire-and-forget URLSession, überlebt TimelineView-Rerenders.
            RemoteProfileImage(
                url: pin.profileImageURL,
                fallbackEmoji: pin.emoji,
                size: 38,
                strokeColor: .clear
            )
        }
    }
}

// MARK: - Self Marker (eigener User an echter Position)

struct SelfCharacterOverlay: View {
    let profileImageURL: String?
    let fallbackEmoji: String
    let pointProvider: () -> CGPoint?

    // Image-State HIER (nicht in nested RemoteProfileImage) damit es den
    // TimelineView-Rerender überlebt.
    @State private var image: UIImage? = nil

    var body: some View {
        TimelineView(.animation) { _ in
            if let point = pointProvider() {
                marker.position(point)
            }
        }
        .allowsHitTesting(false)
        .onAppear { loadIfNeeded() }
        .onChange(of: profileImageURL) { _ in loadIfNeeded() }
    }

    private func loadIfNeeded() {
        guard let urlString = profileImageURL, !urlString.isEmpty,
              let url = URL(string: urlString) else {
            image = nil; return
        }
        if let cached = ProfileImageCache.shared.get(urlString) {
            image = cached; return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let img = UIImage(data: data) else { return }
            ProfileImageCache.shared.set(urlString, image: img)
            DispatchQueue.main.async { self.image = img }
        }.resume()
    }

    private var marker: some View {
        ZStack {
            // Aura
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.accentOrange.opacity(0.35), .clear],
                        center: .center, startRadius: 10, endRadius: 40
                    )
                )
                .frame(width: 80, height: 80)

            // Base + Ring
            Circle()
                .fill(.white)
                .frame(width: 54, height: 54)
                .overlay(
                    Circle().stroke(Color.brandOrangeFixed, lineWidth: 4)
                )
                .shadow(color: Color.accentOrange.opacity(0.5), radius: 10, y: 3)

            // Image oder Emoji — direkt aus @State damit TimelineView das nicht killt
            Group {
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    DazuPersonIcon().font(.system(size: 28))
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(Circle())
        }
    }
}
