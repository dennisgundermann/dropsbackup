import SwiftUI
import StoreKit

// MARK: - Drops+ Paywall

struct DropsPlusView: View {
    @ObservedObject private var store = DropsStoreManager.shared
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    /// Wird nur dann auf true gesetzt, wenn der User im aktuellen Sheet auf "Kaufen" getippt hat —
    /// verhindert, dass das Success-Popup beim bloßen Öffnen einer bereits aktiven Paywall auftaucht.
    @State private var justActivated = false

    var body: some View {
        ZStack(alignment: .topTrailing) {

            // ── Hintergrund — warmes Cream mit sanftem Gold-Schimmer ─────
            Color.bgGrouped.ignoresSafeArea()
            RadialGradient(
                colors: [Color.auroraAmber.opacity(0.10), .clear],
                center: .topLeading,
                startRadius: 0, endRadius: 420
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [Color(hex: "fcd34d").opacity(0.08), .clear],
                center: .bottomTrailing,
                startRadius: 0, endRadius: 360
            )
            .ignoresSafeArea()

            // ── Inhalt ───────────────────────────────────────────────────
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection
                    featuresSection.padding(.top, 36)
                    purchaseSection.padding(.top, 32)
                    footerSection.padding(.top, 20).padding(.bottom, 48)
                }
                .padding(.horizontal, 24)
            }

            // ── Schließen-Button ─────────────────────────────────────────
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.top, 16).padding(.trailing, 20)
        }
        .onChange(of: store.isPlusUser) { _, newValue in
            // Kauf erfolgreich → Paywall schließen, Global Success-Popup triggern
            if newValue && justActivated {
                justActivated = false
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    appStore.showDropsPlusSuccess = true
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 52)

            // Leucht-Halo + Icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.auroraAmber.opacity(0.22), .clear],
                            center: .center,
                            startRadius: 0, endRadius: 60
                        )
                    )
                    .frame(width: 110, height: 110)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.auroraGoldLight, Color.auroraGoldDark],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }

            // Titel — im Premium-Light: dunkles Monogramm + Gold-Plus-Zeichen
            (Text("dazu")
                .foregroundColor(.textPrimary)
             + Text("+")
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.auroraGoldLight, Color.auroraGoldDark],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            )
            .font(.system(size: 40, weight: .bold, design: .rounded))

            Text(tr("plus.pay_once_forever"))
                .font(.system(size: 15))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                PlusFeatureRow(
                    icon: "scope",
                    title: tr("plus.feature_radius_title"),
                    description: tr("plus.feature_radius_desc"),
                    comingSoon: false
                )
                PlusFeatureRow(
                    icon: "eye.fill",
                    title: tr("plus.feature_viewers_title"),
                    description: tr("plus.feature_viewers_desc"),
                    comingSoon: false
                )
            }

            // ── Bald verfügbar ────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    Text(tr("plus.coming_soon"))
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.8)
                }
                .foregroundColor(.textTertiary)
                .padding(.leading, 4)

                VStack(spacing: 12) {
                    PlusFeatureRow(
                        icon: "shield.fill",
                        title: tr("plus.feature_no_score_loss_title"),
                        description: tr("plus.feature_no_score_loss_desc"),
                        comingSoon: true
                    )
                    PlusFeatureRow(
                        icon: "clock.arrow.circlepath",
                        title: tr("plus.feature_extend_title"),
                        description: tr("plus.feature_extend_desc"),
                        comingSoon: true
                    )
                    PlusFeatureRow(
                        icon: "chart.bar.fill",
                        title: tr("plus.feature_stats_title"),
                        description: tr("plus.feature_stats_desc"),
                        comingSoon: true
                    )
                }
            }
        }
    }

    // MARK: - Kauf

    private var purchaseSection: some View {
        VStack(spacing: 14) {
            if store.isPlusUser {
                // Bereits gekauft
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.auroraGoldLight, Color.auroraGoldDark],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    Text(tr("plus.you_are_plus"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(tr("plus.all_features_active"))
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.auroraGoldLight.opacity(0.2), lineWidth: 1)
                )
            } else {
                // Preis
                if let price = store.product?.displayPrice {
                    Text(tr("plus.one_time_price").replacingOccurrences(of: "{price}", with: price))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textSecondary)
                }

                // Kaufen-Button — goldener CTA bleibt, auf Light-Hintergrund noch eleganter
                Button {
                    justActivated = true
                    Task { await store.purchase() }
                } label: {
                    ZStack {
                        if store.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 15, weight: .bold))
                                Text(tr("plus.unlock_plus"))
                                    .font(.system(size: 17, weight: .bold))
                            }
                            .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [Color.auroraGoldLight, Color.auroraGoldDark],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                    .shadow(color: Color.auroraGoldLight.opacity(0.35), radius: 14, y: 5)
                }
                .disabled(store.isLoading || store.product == nil)

                if let err = store.purchaseError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.accentRed)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await store.restorePurchases() }
            } label: {
                Text(tr("plus.restore_purchase"))
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
                    .underline()
            }
            .disabled(store.isLoading)

            Text(tr("plus.footer"))
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Drops+ Success Popup (global, from purchase or admin grant)

struct DropsPlusSuccessView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // ── Premium-Light Hintergrund ─────────────────────────────────
            Color.bgGrouped.ignoresSafeArea()
            RadialGradient(
                colors: [Color.auroraAmber.opacity(0.10), .clear],
                center: .top,
                startRadius: 0, endRadius: 360
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // Icon mit dezentem Glow
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.auroraAmber.opacity(0.22), .clear],
                                center: .center,
                                startRadius: 0, endRadius: 60
                            )
                        )
                        .frame(width: 140, height: 140)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 76, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.auroraGoldLight, Color.auroraGoldDark],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }

                VStack(spacing: 10) {
                    // Titel dunkel + Plus-Zeichen in Gold
                    (Text(tr("plus.welcome"))
                        .foregroundColor(.textPrimary)
                     + Text("+")
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.auroraGoldLight, Color.auroraGoldDark],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    )
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                    Text(tr("plus.success_msg"))
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 32)

                // Feature-Kurzliste
                VStack(alignment: .leading, spacing: 10) {
                    SuccessFeatureLine(icon: "scope", text: tr("plus.radius_unlimited_feature"))
                    SuccessFeatureLine(icon: "eye.fill", text: tr("plus.you_see_viewers"))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .fill(Color.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .stroke(Color.auroraGoldLight.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 24)

                // Los-geht's-Button
                Button {
                    appStore.showDropsPlusSuccess = false
                    dismiss()
                } label: {
                    Text(tr("plus.lets_go"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [Color.auroraGoldLight, Color.auroraGoldDark],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                        .shadow(color: Color.auroraGoldLight.opacity(0.35), radius: 14, y: 5)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
            .padding(.vertical, 40)
        }
        .onAppear {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }
}

// MARK: - Feature Row

private struct PlusFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    var comingSoon: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        comingSoon
                            ? AnyShapeStyle(Color.textTertiary)
                            : AnyShapeStyle(LinearGradient(
                                colors: [Color.auroraGoldLight, Color.auroraGoldDark],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                              ))
                    )
            }
            .frame(width: 44, height: 44)
            .background(
                comingSoon
                    ? Color(UIColor.tertiarySystemGroupedBackground)
                    : Color.auroraAmber.opacity(0.10)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(comingSoon ? .textSecondary : .textPrimary)
                    if comingSoon {
                        Text(tr("plus.soon"))
                            .font(.system(size: 9, weight: .bold))
                            .kerning(0.4)
                            .foregroundColor(.textTertiary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.textTertiary.opacity(0.15), in: Capsule())
                    }
                }
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(comingSoon ? .textTertiary : .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(
                    comingSoon
                        ? Color.textTertiary.opacity(0.08)
                        : Color.auroraGoldLight.opacity(0.12),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Success Feature Line

private struct SuccessFeatureLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.auroraGoldLight, Color.auroraGoldDark],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textPrimary)
        }
    }
}

// MARK: - Preview

#Preview("Paywall") {
    DropsPlusView()
        .environmentObject(AppStore())
}

#Preview("Success") {
    DropsPlusSuccessView()
        .environmentObject(AppStore())
}
