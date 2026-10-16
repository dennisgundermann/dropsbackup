import SwiftUI

/// First-Time-Erklärung + Bestätigung wenn der User seinen Standort mit
/// anderen Dazu-Nutzern teilen möchte. Wird IMMER gezeigt beim Aktivieren
/// des Toggles, nicht nur beim ersten Mal — damit der User immer nochmal
/// bewusst „Ja" sagt und nicht versehentlich auf Sichtbar bleibt.
struct PresenceOptInSheet: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.brandCream.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ZStack {
                            Circle()
                                .fill(Color.brandLavender.opacity(0.9))
                                .frame(width: 92, height: 92)
                            DazuIcon("figure.wave")
                                .font(.system(size: 42, weight: .heavy))
                                .foregroundColor(.brandOrange)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)

                        VStack(alignment: .leading, spacing: -2) {
                            Text("Auf der")
                                .foregroundColor(.brandNight)
                            Text("Karte sichtbar.")
                                .foregroundColor(.brandViolet)
                        }
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 24)

                        Text("Zeig anderen, dass du unterwegs bist. So passieren spontane Treffen.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 24)

                        VStack(spacing: 10) {
                            bullet(icon: "clock.badge.checkmark.fill",
                                   title: "Zeitversetzt (20 Min)",
                                   body: "Andere sehen deine Position mit ~20 Min Verzögerung. Live-Tracking ist nicht möglich.")
                            bullet(icon: "scope",
                                   title: "Grob (~500 m)",
                                   body: "Deine Position wird auf ein 500 m-Grid gerundet — nie straßengenau.")
                            bullet(icon: "person.2.fill",
                                   title: "Freunde sehen deinen Namen",
                                   body: "Alle sehen dein Profilbild. Nur Freunde sehen zusätzlich den Namen.")
                            bullet(icon: "moon.zzz.fill",
                                   title: "Automatisch aus nach 4h",
                                   body: "Ohne neue Bewegung verschwindest du nach 4 Stunden vom Radar.")
                            bullet(icon: "hand.raised.fill",
                                   title: "Jederzeit stoppbar",
                                   body: "Hier abschalten — dein Eintrag wird sofort gelöscht.")
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    }
                    .padding(.bottom, 12)
                }

                VStack(spacing: 10) {
                    Button(action: onConfirm) {
                        Text("Ja, sichtbar machen")
                            .dropsPrimaryButton()
                    }
                    Button(action: onCancel) {
                        Text("Abbrechen")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.brandNight.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 22)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func bullet(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            DazuIcon(icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.brandViolet)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.brandLavender))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.brandNight)
                Text(body)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.brandNight.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .liquidGlass(cornerRadius: 18)
    }
}
