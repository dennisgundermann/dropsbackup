import SwiftUI

// MARK: - Legal Document Type

enum LegalDocumentType {
    case privacy, terms, impressum
}

// MARK: - Language Helper

/// Reads the current app language from UserDefaults at render time.
/// Used by all legal content structs for DE/EN switching.
private func legalPick<T>(_ de: T, _ en: T) -> T {
    let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "de"
    return lang == "en" ? en : de
}

// MARK: - Legal View (Container)

struct LegalView: View {
    let type: LegalDocumentType
    @AppStorage("appLanguage") private var appLanguage = "de"
    @Environment(\.dismiss) private var dismiss

    var title: String {
        switch type {
        case .privacy:   return legalPick("Datenschutzerklärung", "Privacy Policy")
        case .terms:     return legalPick("Nutzungsbedingungen",   "Terms of Use")
        case .impressum: return legalPick("Impressum",             "Legal Notice")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgSecondary.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        switch type {
                        case .privacy:   PrivacyContent()
                        case .terms:     TermsContent()
                        case .impressum: ImpressumContent()
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(tr("common.close")) { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.brand)
                }
            }
        }
    }
}

// MARK: - Shared Components

private struct LegalSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.textPrimary)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.bgPrimary)
        .cornerRadius(Radius.card)
        .overlay(RoundedRectangle(cornerRadius: Radius.card)
            .stroke(Color(UIColor.separator).opacity(0.4), lineWidth: 0.5))
        .padding(.bottom, 10)
    }
}

private struct LegalHeader: View {
    let icon: String
    let color: Color
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 60, height: 60)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.bottom, 6)
    }
}

// MARK: - Privacy Policy Content

private struct PrivacyContent: View {
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        Group {
            LegalHeader(
                icon: "lock.shield.fill",
                color: Color(UIColor.systemBlue),
                subtitle: legalPick("Zuletzt aktualisiert: April 2026",
                                    "Last updated: April 2026")
            )

            LegalSection(
                title: legalPick("1. Verantwortlicher", "1. Data Controller"),
                text: legalPick("""
Verantwortlich für die Verarbeitung personenbezogener Daten im Sinne der DSGVO ist:

Dennis Gundermann · Lissi-Kaeser-Str. 7, 80797 München · dazuapp.com

Kontakt: contact@drops-app.de

Bei Fragen zum Datenschutz kannst du uns jederzeit per E-Mail kontaktieren.
""", """
The controller responsible for the processing of personal data under the GDPR is:

Dennis Gundermann · Lissi-Kaeser-Str. 7, 80797 Munich, Germany · dazuapp.com

Contact: contact@drops-app.de

For any questions about data protection, you can reach us anytime via email.
""")
            )

            LegalSection(
                title: legalPick("2. Welche Daten wir erheben", "2. Data We Collect"),
                text: legalPick("""
KONTO & AUTHENTIFIZIERUNG
• Sign in with Apple – Apple User ID, Nonce (SHA256-Hash), optional E-Mail, Authorization Code (für Token-Widerrufung bei Kontolöschung)
• Handynummer (Pflichtangabe bei Registrierung — damit dich deine Kontakte finden können)

PROFIL
• Name (frei wählbar)
• Geburtsdatum (Selbstangabe, zur Altersprüfung ≥ 16)
• Geschlecht (optional)
• E-Mail (nur bei Sign in with Apple, falls freigegeben)
• Profilbild (optional, auf Firebase Storage)
• Zuverlässigkeits-Score (Anzahl bestätigter / nicht eingehaltener Treffen)

NUTZUNG DER APP
• Standortdaten (GPS, nur bei aktivem Plan – siehe Abschnitt 4)
• Erstellte Pläne (Koordinaten, Emoji, Aktivitätsname, Ablaufzeit)
• Beitritte, Beitrittsanfragen, aufgezeichnete Begegnungen
• Freundschaftsbeziehungen (reine Verknüpfung, keine Inhalte)

DISCOVERY-INDIZES
• Normalisierte Telefonnummer (E.164-Format) und E-Mail (normalisiert) als Suchindex, damit Freunde dich finden können

TECHNIK & KOMMUNIKATION
• FCM-Token (für Push-Benachrichtigungen, nur lokal)
• Bluetooth-Proximity-Token (anonyme 8-Zeichen-Kennung, siehe Abschnitt 5)
• Live-Activity-Daten (Name, Emoji, Profilbild, Teilnehmerzahl)
• dazu+ Kauf-Status
• Gerätetyp, Betriebssystem, App-Version

LOKAL (verlässt dein Gerät nicht)
• BLE-Bestätigungshistorie (zur Missbrauchs-Vermeidung)
• Push-Benachrichtigungs-Zeitstempel (zur Rate-Limitierung)

NICHT gespeichert: Ausweisdaten, biometrische Rohdaten, dein Adressbuch. Der Kontakt-Abgleich findet ausschließlich auf deinem Gerät statt.
""", """
ACCOUNT & AUTHENTICATION
• Sign in with Apple – Apple User ID, nonce (SHA256 hash), optional email, authorization code (to revoke tokens on account deletion)
• Phone number (mandatory at registration — so your contacts can find you)

PROFILE
• Name (freely chosen)
• Date of birth (self-reported, for age verification ≥ 16)
• Gender (optional)
• Email (only from Sign in with Apple, if shared)
• Profile picture (optional, on Firebase Storage)
• Reliability score (number of confirmed / missed meetings)

APP USAGE
• Location data (GPS, only with an active Plan – see section 4)
• Created Pläne (coordinates, emoji, activity name, expiry time)
• Joins, join requests, recorded encounters
• Friendship connections (link only, no content)

DISCOVERY INDEXES
• Normalized phone number (E.164 format) and email (normalized) as a search index, so friends can find you

TECHNICAL & COMMUNICATIONS
• FCM token (for push notifications, stored locally only)
• Bluetooth proximity token (anonymous 8-char identifier, see section 5)
• Live Activity data (name, emoji, profile picture, participant count)
• dazu+ purchase status
• Device type, operating system, app version

LOCAL (never leaves your device)
• BLE confirmation history (to prevent abuse)
• Push notification timestamps (for rate limiting)

NOT stored: ID documents, biometric raw data, your address book. Contact matching happens exclusively on your device.
""")
            )

            LegalSection(
                title: legalPick("3. Zweck & Rechtsgrundlage", "3. Purpose & Legal Basis"),
                text: legalPick("""
Wir verarbeiten deine Daten für folgende Zwecke:

• Vertragserfüllung (Art. 6 Abs. 1 lit. b DSGVO): Authentifizierung, Kontoverwaltung, Plan-Erstellung, Karte, Begegnungen, Bluetooth-Proximity, Push-Benachrichtigungen, dazu+

• Einwilligung (Art. 6 Abs. 1 lit. a DSGVO): Kontakt-Abgleich, Profilbild-Upload

• Berechtigtes Interesse (Art. 6 Abs. 1 lit. f DSGVO): Moderation & Missbrauchs-Vermeidung (Admin-Panel, Sperren, Zuverlässigkeits-Score), Sicherheit der Plattform

Einwilligungen kannst du jederzeit über die App-Einstellungen oder durch Kontolöschung widerrufen.
""", """
We process your data for the following purposes:

• Performance of contract (Art. 6(1)(b) GDPR): authentication, account management, Plan creation, map, encounters, Bluetooth proximity, push notifications, dazu+

• Consent (Art. 6(1)(a) GDPR): contact matching, profile picture upload

• Legitimate interest (Art. 6(1)(f) GDPR): moderation & abuse prevention (admin panel, bans, reliability score), platform security

You can withdraw consent at any time via the app settings or by deleting your account.
""")
            )

            LegalSection(
                title: legalPick("4. Standortdaten", "4. Location Data"),
                text: legalPick("""
Dazu erhebt deinen Standort NUR, wenn mindestens eine dieser Bedingungen erfüllt ist:
• Du hast einen aktiven Plan erstellt
• Du bist einem Plan beigetreten
• Du hast in den Einstellungen freiwillig „Auf der Karte sichtbar“ aktiviert (standardmäßig aus)

GENAUIGKEIT: GPS mit bester Auflösung. Auf der Karte für andere Nutzer wird der Standort durch den Plan-Radius maskiert.

HINTERGRUND-MODUS: Damit Pläne auch im Hintergrund aktualisiert werden, läuft Location-Tracking weiter, solange ein Plan aktiv ist. Ohne aktiven Plan werden keine Standortdaten mehr erhoben oder übertragen — es sei denn, du hast „Auf der Karte sichtbar“ aktiviert.

KARTENPRÄSENZ (OPTIONAL): Wenn du „Auf der Karte sichtbar“ aktivierst, wird deine letzte bekannte Position auf ein Raster von ca. 500 m gerundet (nie straßengenau) und erst nach mindestens 20 Minuten für andere angezeigt — Live-Tracking ist nicht möglich. Alle Nutzer sehen dein Profilbild bzw. Emoji, nur Freunde zusätzlich deinen Namen. Ohne neue Bewegung verschwindet dein Eintrag nach 4 Stunden; beim Deaktivieren wird er sofort gelöscht.

SPEICHERUNG: Der aktuelle Standort wird live an die Firebase Realtime Database (EU-Region, Frankfurt) übertragen und bei Plan-Beendigung sofort gelöscht. Wir speichern KEINE historischen Bewegungsprofile.
""", """
Dazu collects your location ONLY when at least one of the following applies:
• You created an active Plan
• You joined a Plan
• You voluntarily enabled “Visible on the map” in settings (off by default)

ACCURACY: GPS at best resolution. On the map for other users, your location is masked by the Plan radius.

BACKGROUND MODE: To allow Plans to update in the background, location tracking continues as long as a Plan is active. Without an active Plan, location data is no longer collected or transmitted — unless you enabled “Visible on the map”.

MAP PRESENCE (OPTIONAL): If you enable “Visible on the map”, your last known position is rounded to a grid of about 500 m (never street-level) and shown to others only after at least 20 minutes — live tracking is not possible. All users see your profile picture or emoji; only friends also see your name. Without new movement your entry disappears after 4 hours; when you disable the setting it is deleted immediately.

STORAGE: Your current location is transmitted live to the Firebase Realtime Database (EU region, Frankfurt) and deleted immediately when the Plan ends. We do NOT store historical movement profiles.
""")
            )

            LegalSection(
                title: legalPick("5. Bluetooth & automatische Treffen-Bestätigung",
                                 "5. Bluetooth & Automatic Encounter Confirmation"),
                text: legalPick("""
Dazu nutzt Bluetooth Low Energy (BLE), um tatsächliche Treffen zwischen Plan-Teilnehmern automatisch zu erkennen — ohne dass du manuell bestätigen musst.

ÜBERTRAGEN WIRD:
• Eine anonyme 8-Zeichen-Kennung (abgeleitet aus deiner internen Nutzer-ID, NICHT deine Telefonnummer oder E-Mail)
• Eine drop-spezifische Service-UUID
• Keine Namen, keine Profilbilder, keine Standortdaten, keine MAC-Adressen

MISSBRAUCHS-VERMEIDUNG (drei Schutzebenen):
1. Mindestdauer: Frühestens 5 Minuten nach Plan-Beitritt kann eine Begegnung registriert werden
2. Partner-Cooldown: Dieselbe Person wird maximal alle 6 Stunden bestätigt
3. Tages-Limit: Maximal 4 Bluetooth-Bestätigungen pro Tag

ENTFERNUNG: Eine Begegnung wird nur registriert, wenn das Signal stärker als -72 dBm ist (ca. 5-10 Meter).

HINTERGRUND-MODUS: BLE läuft im Hintergrund, solange ein Plan aktiv ist. Ohne aktiven Plan wird Bluetooth nicht genutzt.

SPEICHERUNG: Die BLE-Bestätigungshistorie wird AUSSCHLIESSLICH lokal auf deinem Gerät gespeichert und verlässt dein iPhone nicht. Nur die eigentliche Begegnung wird in der Realtime DB als Verknüpfung zwischen den beiden Nutzer-IDs gespeichert.

RECHTSGRUNDLAGE: Art. 6 Abs. 1 lit. b DSGVO (Kernfunktion von Dazu).
""", """
Dazu uses Bluetooth Low Energy (BLE) to automatically detect actual meetings between Plan participants — without you having to manually confirm.

WHAT IS TRANSMITTED:
• An anonymous 8-character identifier (derived from your internal user ID, NOT your phone number or email)
• A Plan-specific service UUID
• No names, no profile pictures, no location data, no MAC addresses

ABUSE PREVENTION (three layers):
1. Minimum duration: an encounter can only be registered at least 5 minutes after joining a Plan
2. Partner cooldown: the same person can only be confirmed at most every 6 hours
3. Daily limit: maximum 4 Bluetooth confirmations per day

DISTANCE: An encounter is only registered when the signal is stronger than -72 dBm (approx. 5-10 meters).

BACKGROUND MODE: BLE runs in the background as long as a Plan is active. Without an active Plan, Bluetooth is not used.

STORAGE: The BLE confirmation history is stored EXCLUSIVELY locally on your device and never leaves your iPhone. Only the actual encounter is stored in the Realtime DB as a link between the two user IDs.

LEGAL BASIS: Art. 6(1)(b) GDPR (core function of Dazu).
""")
            )

            LegalSection(
                title: legalPick("6. Kontakt-Abgleich (optional)", "6. Contact Matching (Optional)"),
                text: legalPick("""
Wenn du die Funktion „Freunde finden" nutzt, kannst du Dazu dein Adressbuch durchsuchen lassen, um Kontakte zu entdecken, die ebenfalls Dazu nutzen.

ABLAUF:
• Telefonnummern werden zu E.164-Format normalisiert, E-Mails werden normalisiert
• Jede normalisierte Adresse wird mit dem Firebase-Discovery-Index verglichen
• Bei Treffer wird dir der entsprechende Dazu-Nutzer zur Freundschaftsanfrage angeboten

NICHT GESPEICHERT: Dein Adressbuch wird weder an unsere Server übertragen noch lokal dauerhaft kopiert. Nur die Übereinstimmungen, die du aktiv als Freund hinzufügst, werden gespeichert.

RECHTSGRUNDLAGE: Ausdrückliche Einwilligung (Art. 6 Abs. 1 lit. a DSGVO). Widerruf über iOS-Systemeinstellungen (Einstellungen → Dazu → Kontakte).
""", """
If you use the "Find Friends" feature, you can let Dazu search your address book to discover contacts who also use Dazu.

PROCESS:
• Phone numbers are normalized to E.164 format, emails are normalized
• Each normalized address is compared against the Firebase discovery index
• On a match, the corresponding Dazu user is offered to you for a friend request

NOT STORED: Your address book is neither transmitted to our servers nor permanently copied locally. Only the matches you actively add as friends are stored.

LEGAL BASIS: Explicit consent (Art. 6(1)(a) GDPR). Revoke via iOS system settings (Settings → Dazu → Contacts).
""")
            )

            LegalSection(
                title: legalPick("7. Push-Benachrichtigungen", "7. Push Notifications"),
                text: legalPick("""
Mit deiner Zustimmung senden wir Push-Benachrichtigungen über Apple Push Notification Service (APNs) und Firebase Cloud Messaging (FCM).

ARTEN:
• Pläne in deiner Nähe (max. 1× alle 30 Minuten)
• Warnung bei Plänen in deiner Heimzone (max. 1× alle 60 Minuten)
• Beitrittsanfragen zu deinem Plan
• Automatische Bestätigung abgelaufener Beitrittsanfragen
• Jemand ist deinem Plan beigetreten
• Neue aufgezeichnete Begegnungen
• Freund startet Plan in deiner Nähe
• Re-Engagement-Hinweise bei längerer Inaktivität

FCM-TOKEN: Das Gerät-Token wird nur lokal in den App-Einstellungen gespeichert, nicht in der Datenbank. Du kannst Push jederzeit über iOS-Systemeinstellungen deaktivieren.
""", """
With your consent, we send push notifications via Apple Push Notification Service (APNs) and Firebase Cloud Messaging (FCM).

TYPES:
• Plans near you (max. 1× every 30 minutes)
• Alert for Plans in your home zone (max. 1× every 60 minutes)
• Join requests to your Plan
• Automatic confirmation of expired join requests
• Someone joined your Plan
• New recorded encounters
• A friend started a Plan near you
• Re-engagement reminders during longer periods of inactivity

FCM TOKEN: The device token is stored only locally in the app settings, not in the database. You can disable push at any time via iOS system settings.
""")
            )

            LegalSection(
                title: legalPick("8. Live Activity (Dynamic Island & Sperrbildschirm)",
                                 "8. Live Activity (Dynamic Island & Lock Screen)"),
                text: legalPick("""
Sobald du einem Plan beitrittst oder einen startest, zeigt iOS im Dynamic Island und auf dem Sperrbildschirm eine Live-Übersicht.

ANGEZEIGTE DATEN: Plan-Name, Emoji, Teilnehmerzahl, Ablaufzeit, Vornamen und Profilbilder der Teilnehmer sowie deren voraussichtliche Ankunftszeit.

TECHNISCH: Die Live-Activity läuft über Apples ActivityKit LOKAL auf deinem Gerät. APNs wird nur als Trigger-Kanal für Aktualisierungen genutzt — keine Nutzerdaten werden an Apple übertragen.

ADRESSERMITTLUNG: Die Plan-Adresse wird über Apples CLGeocoder-Dienst aus den GPS-Koordinaten ermittelt. Dabei werden die Koordinaten kurzzeitig an Apple-Server übertragen. Apples Datenschutzrichtlinien: apple.com/privacy
""", """
As soon as you join or start a Plan, iOS shows a live overview in the Dynamic Island and on the lock screen.

DATA DISPLAYED: Plan name, emoji, participant count, expiry time, first names and profile pictures of participants, and their estimated arrival times.

TECHNICAL: The Live Activity runs LOCALLY on your device via Apple's ActivityKit. APNs is used only as a trigger channel for updates — no user data is transmitted to Apple.

ADDRESS LOOKUP: The Plan address is determined via Apple's CLGeocoder service from the GPS coordinates. The coordinates are briefly transmitted to Apple servers during this process. Apple's privacy policy: apple.com/privacy
""")
            )

            LegalSection(
                title: legalPick("9. dazu+ (In-App-Kauf)", "9. dazu+ (In-App Purchase)"),
                text: legalPick("""
dazu+ ist ein optionales kostenpflichtiges Zusatz-Feature (z.B. Plan-Hervorhebung auf der Karte, größerer Suchradius, Score-Schutz).

ZAHLUNGSABWICKLUNG: Der Kauf läuft ausschließlich über Apples App Store mit deiner Apple-ID. Wir erhalten keine Zahlungsdaten, keine Apple-ID und keine Kreditkarteninformationen.

WAS DAZU SPEICHERT: Nur die Information, dass du dazu+ freigeschaltet hast (Flag isPlusUser: true in deinem Nutzerprofil).

SPEICHERDAUER: Bis zur Kontolöschung. Rückerstattung über Apple.
""", """
dazu+ is an optional paid premium feature (e.g. Plan highlighting on the map, larger search radius, score protection).

PAYMENT PROCESSING: The purchase runs exclusively via Apple's App Store using your Apple ID. We receive no payment data, no Apple ID, and no credit card information.

WHAT DAZU STORES: Only the fact that you unlocked dazu+ (flag isPlusUser: true in your user profile).

RETENTION: Until account deletion. Refunds via Apple.
""")
            )

            LegalSection(
                title: legalPick("10. Moderation & Admin-Funktionen",
                                 "10. Moderation & Admin Functions"),
                text: legalPick("""
Zur Sicherung der Plattform gegen Missbrauch existiert ein Admin-Bereich mit eingeschränktem Zugriff.

WER HAT ZUGRIFF: Ausschließlich der Betreiber (Dennis Gundermann) sowie ggf. manuell benannte Moderatoren.

WAS ADMINS EINSEHEN KÖNNEN:
• Nutzerliste mit Name, E-Mail, Registrierungsdatum, Sperr- und dazu+-Status
• Aktive Pläne (Aktivitätsname, Emoji)
• Aggregierte Statistiken

WAS ADMINS TUN KÖNNEN: Nutzer sperren/entsperren, Pläne vorzeitig beenden, Accounts löschen (bei Verstößen), dazu+-Status manuell setzen.

RECHTSGRUNDLAGE: Berechtigtes Interesse an einer sicheren Plattform (Art. 6 Abs. 1 lit. f DSGVO).
""", """
To protect the platform from abuse, there is an admin area with restricted access.

WHO HAS ACCESS: Exclusively the operator (Dennis Gundermann) and, where applicable, manually appointed moderators.

WHAT ADMINS CAN SEE:
• User list with name, email, registration date, ban and dazu+ status
• Active Pläne (activity name, emoji)
• Aggregated statistics

WHAT ADMINS CAN DO: Ban/unban users, end Plans early, delete accounts (for violations), manually set dazu+ status.

LEGAL BASIS: Legitimate interest in a safe platform (Art. 6(1)(f) GDPR).
""")
            )

            LegalSection(
                title: legalPick("11. Drittanbieter & Auftragsverarbeiter",
                                 "11. Third Parties & Data Processors"),
                text: legalPick("""
GOOGLE LLC / GOOGLE IRELAND LTD.:
• Firebase Authentication – Apple-Sign-In-Verifizierung
• Firebase Realtime Database (Region europe-west1, Frankfurt) – Live-Daten (Pläne, Standort, Begegnungen)
• Firebase Storage – Profilbilder
• Firebase Firestore – Profilergänzungen (Zuverlässigkeits-Score, Profilbild-URL)
• Firebase Cloud Messaging – Push-Zustellung

Google LLC ist unter dem EU-US Data Privacy Framework zertifiziert. Eine Auftragsverarbeitungsvereinbarung (AVV) nach Art. 28 DSGVO ist abgeschlossen. Details: policies.google.com/privacy

APPLE INC.:
• Sign in with Apple (optional)
• Apple Push Notification Service (APNs)
• App Store / StoreKit – dazu+ Kaufabwicklung
• CLGeocoder – Koordinaten → Adresse (für Live Activity)

Details: apple.com/legal/privacy

KEINE WEITEREN DRITTANBIETER. Dazu nutzt keine Werbe-SDKs, keine externen Analyse-Tools (z.B. Google Analytics, Firebase Analytics, Mixpanel, Facebook SDK) und kein Tracking für Marketingzwecke.
""", """
GOOGLE LLC / GOOGLE IRELAND LTD.:
• Firebase Authentication – Apple Sign-In verification
• Firebase Realtime Database (region europe-west1, Frankfurt) – live data (Pläne, location, encounters)
• Firebase Storage – profile pictures
• Firebase Firestore – profile supplements (reliability score, profile picture URL)
• Firebase Cloud Messaging – push delivery

Google LLC is certified under the EU-US Data Privacy Framework. A Data Processing Agreement (DPA) under Art. 28 GDPR is in place. Details: policies.google.com/privacy

APPLE INC.:
• Sign in with Apple (optional)
• Apple Push Notification Service (APNs)
• App Store / StoreKit – dazu+ purchase processing
• CLGeocoder – coordinates → address (for Live Activity)

Details: apple.com/legal/privacy

NO OTHER THIRD PARTIES. Dazu uses no advertising SDKs, no external analytics tools (e.g. Google Analytics, Firebase Analytics, Mixpanel, Facebook SDK), and no tracking for marketing purposes.
""")
            )

            LegalSection(
                title: legalPick("12. Speicherdauer", "12. Retention Periods"),
                text: legalPick("""
• Kontodaten: Bis zur Kontolöschung
• Profilbild: Bis zur Kontolöschung oder manuellem Entfernen
• Pläne: Bis zur Beendigung durch dich oder automatischem Ablauf
• Beitritte/Anfragen: Automatisch mit Plan-Ende gelöscht
• Standort: Live, sofortige Löschung nach Plan-Ende
• Aufgezeichnete Begegnungen: Bis zur Kontolöschung
• Discovery-Indizes (Telefon/E-Mail): Bis zur Kontolöschung
• BLE-Bestätigungshistorie (lokal): Tägliche Liste zurückgesetzt um Mitternacht; Partner-Cooldown bis App-Deinstallation
• FCM-Token (lokal): Bis App-Deinstallation
""", """
• Account data: until account deletion
• Profile picture: until account deletion or manual removal
• Plans: until ended by you or automatic expiry
• Joins/requests: automatically deleted with the Plan's end
• Location: live, immediate deletion after the Plan ends
• Recorded encounters: until account deletion
• Discovery indexes (phone/email): until account deletion
• BLE confirmation history (local): daily list reset at midnight; partner cooldown until app uninstall
• FCM token (local): until app uninstall
""")
            )

            LegalSection(
                title: legalPick("13. Deine Rechte", "13. Your Rights"),
                text: legalPick("""
Du hast das Recht auf:

• Auskunft über gespeicherte Daten (Art. 15 DSGVO)
• Berichtigung unrichtiger Daten (Art. 16 DSGVO)
• Löschung deiner Daten (Art. 17 DSGVO) – direkt in der App möglich
• Einschränkung der Verarbeitung (Art. 18 DSGVO)
• Datenübertragbarkeit (Art. 20 DSGVO)
• Widerspruch gegen die Verarbeitung (Art. 21 DSGVO)
• Widerruf erteilter Einwilligungen (Art. 7 Abs. 3 DSGVO)
• Beschwerde bei einer Aufsichtsbehörde (Art. 77 DSGVO)

Zur Ausübung deiner Rechte: contact@drops-app.de

Zuständige Aufsichtsbehörde: Bayerisches Landesamt für Datenschutzaufsicht (BayLDA), Promenade 18, 91522 Ansbach
""", """
You have the right to:

• Information about stored data (Art. 15 GDPR)
• Rectification of inaccurate data (Art. 16 GDPR)
• Erasure of your data (Art. 17 GDPR) – available directly in the app
• Restriction of processing (Art. 18 GDPR)
• Data portability (Art. 20 GDPR)
• Objection to processing (Art. 21 GDPR)
• Withdrawal of consent (Art. 7(3) GDPR)
• Lodging a complaint with a supervisory authority (Art. 77 GDPR)

To exercise your rights: contact@drops-app.de

Competent supervisory authority: Bavarian State Office for Data Protection Supervision (BayLDA), Promenade 18, 91522 Ansbach, Germany
""")
            )

            LegalSection(
                title: legalPick("14. Datensicherheit", "14. Data Security"),
                text: legalPick("""
• Alle Übertragungen erfolgen TLS-verschlüsselt
• Firebase-Sicherheitsregeln stellen sicher, dass jeder Nutzer nur auf seine eigenen Daten schreibend zugreifen kann
• Plan-Standorte sind nur über den vom Host definierten Sichtbarkeits-Radius zugänglich
• Der Zuverlässigkeits-Score ist für andere Nutzer nicht sichtbar
""", """
• All transmissions are TLS-encrypted
• Firebase security rules ensure that each user can write only to their own data
• Plan locations are only accessible through the visibility radius defined by the host
• The reliability score is not visible to other users
""")
            )

            LegalSection(
                title: legalPick("15. Minderjährige", "15. Minors"),
                text: legalPick(
                    "Dazu ist nicht für Personen unter 18 Jahren bestimmt. Bei der Registrierung wird das Geburtsdatum abgefragt und Accounts unter 18 werden blockiert. Falls du Kenntnis davon hast, dass eine minderjährige Person Dazu nutzt, wende dich bitte an contact@drops-app.de.",
                    "Dazu is not intended for persons under 18 years of age. The date of birth is requested at registration and accounts under 18 are blocked. If you become aware that a minor is using Dazu, please contact contact@drops-app.de."
                )
            )

            LegalSection(
                title: legalPick("16. Änderungen dieser Erklärung", "16. Changes to This Policy"),
                text: legalPick(
                    "Wir behalten uns vor, diese Datenschutzerklärung anzupassen, um rechtliche oder technische Änderungen abzubilden. Bei wesentlichen Änderungen informieren wir dich per Push-Benachrichtigung oder beim nächsten App-Start. Maßgebend ist die jeweils aktuelle Version, die auf drops-app.de/datenschutz abrufbar ist. Das Datum der letzten Aktualisierung findest du oben.",
                    "We reserve the right to update this privacy policy to reflect legal or technical changes. For material changes, we'll notify you via push notification or on the next app launch. The version currently published at drops-app.de/datenschutz is authoritative. The date of the last update is shown above."
                )
            )
        }
    }
}

// MARK: - Impressum Content

private struct ImpressumContent: View {
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        Group {
            LegalHeader(
                icon: "building.columns.fill",
                color: Color(UIColor.systemOrange),
                subtitle: legalPick("Angaben gemäß § 5 TMG",
                                    "Information according to § 5 TMG (German Telemedia Act)")
            )

            LegalSection(
                title: legalPick("Anbieter", "Provider"),
                text: legalPick(
                    "Dennis Gundermann\nLissi-Kaeser-Str. 7\n80797 München\n\nE-Mail: contact@drops-app.de\nWebsite: dazuapp.com\n\nDiese App wird von einer Privatperson entwickelt und betrieben. Es besteht keine Pflicht zur Umsatzsteuer-Identifikationsnummer.",
                    "Dennis Gundermann\nLissi-Kaeser-Str. 7\n80797 Munich, Germany\n\nEmail: contact@drops-app.de\nWebsite: dazuapp.com\n\nThis app is developed and operated by a private individual. There is no obligation to provide a VAT identification number."
                )
            )

            LegalSection(
                title: legalPick("Verantwortlich für den Inhalt", "Responsible for Content"),
                text: legalPick(
                    "Dennis Gundermann (Anschrift wie oben)\n\nDie Dazu App ist ein privates Nebenprojekt und wird nicht gewerblich betrieben.",
                    "Dennis Gundermann (address as above)\n\nThe Dazu app is a private side project and is not operated commercially."
                )
            )

            LegalSection(
                title: legalPick("Streitschlichtung", "Dispute Resolution"),
                text: legalPick(
                    "Die Europäische Kommission stellt eine Plattform zur Online-Streitbeilegung (OS) bereit:\nhttps://ec.europa.eu/consumers/odr\n\nWir sind nicht bereit oder verpflichtet, an Streitbeilegungsverfahren vor einer Verbraucherschlichtungsstelle teilzunehmen.",
                    "The European Commission provides a platform for online dispute resolution (ODR):\nhttps://ec.europa.eu/consumers/odr\n\nWe are not willing or obligated to participate in dispute resolution proceedings before a consumer arbitration board."
                )
            )

            LegalSection(
                title: legalPick("Haftung für Inhalte", "Liability for Content"),
                text: legalPick(
                    "Als Diensteanbieter sind wir gemäß § 7 Abs. 1 TMG für eigene Inhalte verantwortlich. Wir sind jedoch nicht verpflichtet, übermittelte oder gespeicherte fremde Informationen zu überwachen. Nutzer-generierte Inhalte (Plan-Beschreibungen) liegen in der Verantwortung der jeweiligen Nutzer.",
                    "As a service provider, we are responsible for our own content in accordance with § 7(1) TMG (German Telemedia Act). However, we are not obligated to monitor transmitted or stored third-party information. User-generated content (Plan descriptions) is the responsibility of the respective users."
                )
            )

            LegalSection(
                title: legalPick("Urheberrecht", "Copyright"),
                text: legalPick(
                    "Die durch uns erstellten Inhalte und Werke unterliegen dem deutschen Urheberrecht. Die Vervielfältigung, Bearbeitung, Verbreitung und jede Art der Verwertung außerhalb der Grenzen des Urheberrechts bedürfen der schriftlichen Zustimmung des Erstellers.",
                    "Content and works created by us are subject to German copyright law. Reproduction, modification, distribution, and any kind of exploitation beyond the limits of copyright law require the written consent of the creator."
                )
            )
        }
    }
}

// MARK: - Terms of Use Content

private struct TermsContent: View {
    @AppStorage("appLanguage") private var appLanguage = "de"

    var body: some View {
        Group {
            LegalHeader(
                icon: "doc.text.fill",
                color: Color(UIColor.systemIndigo),
                subtitle: legalPick("Zuletzt aktualisiert: April 2026",
                                    "Last updated: April 2026")
            )

            LegalSection(
                title: legalPick("1. Geltungsbereich", "1. Scope"),
                text: legalPick(
                    "Diese Nutzungsbedingungen gelten für die Nutzung der mobilen App \"Dazu\" und alle damit verbundenen Dienste. Mit der Nutzung der App erklärst du dich mit diesen Bedingungen einverstanden.",
                    "These terms of use apply to the use of the mobile app \"Dazu\" and all associated services. By using the app, you agree to these terms."
                )
            )

            LegalSection(
                title: legalPick("2. Nutzungsvoraussetzungen", "2. Eligibility"),
                text: legalPick("""
• Du musst mindestens 18 Jahre alt sein
• Du benötigst eine Apple-ID für „Sign in with Apple"
• Du musst eine gültige Handynummer hinterlegen, damit dich deine Kontakte finden können
• Du benötigst ein Gerät mit iOS 16.0 oder neuer
• Eine aktive Internetverbindung ist für die meisten Funktionen erforderlich
• Du bist verantwortlich für alle Aktivitäten unter deinem Account
""", """
• You must be at least 18 years old
• You need an Apple ID for "Sign in with Apple"
• You must provide a valid phone number so your contacts can find you
• You need a device running iOS 16.0 or later
• An active internet connection is required for most features
• You are responsible for all activity under your account
""")
            )

            LegalSection(
                title: legalPick("3. Erlaubte Nutzung", "3. Permitted Use"),
                text: legalPick(
                    "Dazu dient ausschließlich dazu, echte Begegnungen und spontane Treffen zwischen Menschen zu ermöglichen. Du verpflichtest dich, die App nur für persönliche, nicht-kommerzielle Zwecke zu verwenden und dabei alle geltenden Gesetze zu beachten.",
                    "Dazu exists exclusively to enable real encounters and spontaneous meetings between people. You agree to use the app only for personal, non-commercial purposes and to comply with all applicable laws."
                )
            )

            LegalSection(
                title: legalPick("4. Verbotene Aktivitäten", "4. Prohibited Activities"),
                text: legalPick("""
Folgende Aktivitäten sind untersagt:

• Erstellung falscher oder irreführender Pläne
• Belästigung, Bedrohung oder Nötigung anderer Nutzer
• Spam oder automatisierte Massenanfragen
• Umgehung von Sicherheitsmaßnahmen
• Kommerzielle Werbung oder Promotion
• Verwendung der App für illegale Aktivitäten jeglicher Art
• Erstellung mehrerer Accounts zur Umgehung von Sperren
""", """
The following activities are prohibited:

• Creating false or misleading Plans
• Harassing, threatening, or coercing other users
• Spam or automated mass requests
• Circumventing security measures
• Commercial advertising or promotion
• Using the app for illegal activities of any kind
• Creating multiple accounts to evade bans
""")
            )

            LegalSection(
                title: legalPick("5. Pläne erstellen", "5. Creating Pläne"),
                text: legalPick(
                    "Öffentliche Pläne sind für alle Nutzer in deiner Nähe sichtbar. Du bist verantwortlich für den Inhalt deiner Pläne. Pläne, die gegen diese Bedingungen verstoßen, können ohne Vorankündigung gelöscht werden. Pläne werden automatisch beendet, wenn du sie deaktivierst oder die App schließt.",
                    "Public Plans are visible to all users near you. You are responsible for the content of your Plans. Plans that violate these terms may be deleted without notice. Plans are automatically ended when you deactivate them or close the app."
                )
            )

            LegalSection(
                title: legalPick("6. dazu+ (In-App-Kauf)", "6. dazu+ (In-App Purchase)"),
                text: legalPick(
                    "dazu+ ist ein optionales kostenpflichtiges Zusatz-Feature. Der Kauf wird über den Apple App Store abgewickelt. Für Widerruf, Rückerstattung und Laufzeit gelten die Bedingungen von Apple. dazu+ schaltet ausschließlich Zusatzfunktionen frei und ändert nichts an den grundlegenden Pflichten aus diesen Nutzungsbedingungen.",
                    "dazu+ is an optional paid premium feature. Purchases are processed through the Apple App Store. Apple's terms apply for withdrawal, refunds, and subscription duration. dazu+ only unlocks additional features and does not change any of the fundamental obligations in these terms."
                )
            )

            LegalSection(
                title: legalPick("7. Geistiges Eigentum", "7. Intellectual Property"),
                text: legalPick(
                    "Alle Rechte an der App, dem Design, dem Logo und dem Code liegen beim Anbieter. Du erhältst eine nicht übertragbare, nicht-exklusive Lizenz zur persönlichen Nutzung der App. Du darfst die App weder kopieren, modifizieren, dekompilieren noch für andere Zwecke verwenden.",
                    "All rights to the app, design, logo, and code belong to the provider. You are granted a non-transferable, non-exclusive license to use the app personally. You may not copy, modify, decompile, or use the app for other purposes."
                )
            )

            LegalSection(
                title: legalPick("8. Haftungsbeschränkung", "8. Limitation of Liability"),
                text: legalPick(
                    "Dazu vermittelt lediglich die Möglichkeit zur Begegnung zwischen Nutzern und ist nicht verantwortlich für das Verhalten der Nutzer. Wir haften nicht für Schäden, die aus der Nutzung der App entstehen, sofern diese nicht auf grober Fahrlässigkeit oder Vorsatz beruhen.",
                    "Dazu merely facilitates the possibility of encounters between users and is not responsible for users' conduct. We are not liable for damages arising from use of the app unless caused by gross negligence or intent."
                )
            )

            LegalSection(
                title: legalPick("9. Verfügbarkeit", "9. Availability"),
                text: legalPick(
                    "Wir bemühen uns um eine hohe Verfügbarkeit der App, können diese aber nicht garantieren. Wartungsarbeiten, technische Störungen oder höhere Gewalt können zu vorübergehenden Ausfällen führen. Wir behalten uns das Recht vor, Funktionen jederzeit zu ändern oder einzustellen.",
                    "We strive for high availability of the app but cannot guarantee it. Maintenance, technical issues, or force majeure may cause temporary outages. We reserve the right to change or discontinue features at any time."
                )
            )

            LegalSection(
                title: legalPick("10. Account-Sperrung", "10. Account Suspension"),
                text: legalPick(
                    "Wir behalten uns vor, Accounts bei Verstößen gegen diese Bedingungen zu sperren oder zu löschen. Bei schwerwiegenden Verstößen erfolgt eine Sperrung ohne Vorankündigung. Du kannst dein Konto jederzeit selbst in den Einstellungen löschen.",
                    "We reserve the right to suspend or delete accounts in case of violations of these terms. In case of serious violations, suspension may occur without prior notice. You can delete your account yourself at any time in the settings."
                )
            )

            LegalSection(
                title: legalPick("11. Änderungen", "11. Changes"),
                text: legalPick(
                    "Wir können diese Nutzungsbedingungen jederzeit anpassen. Über wesentliche Änderungen wirst du vorab informiert. Die weitere Nutzung der App nach Inkrafttreten der Änderungen gilt als Zustimmung.",
                    "We may amend these terms of use at any time. You will be informed in advance of material changes. Continued use of the app after the changes take effect constitutes acceptance."
                )
            )

            LegalSection(
                title: legalPick("12. Anwendbares Recht", "12. Applicable Law"),
                text: legalPick(
                    "Es gilt das Recht der Bundesrepublik Deutschland. Gerichtsstand ist, soweit gesetzlich zulässig, der Sitz des Anbieters. Bei Streitigkeiten steht dir auch der Weg zur Online-Streitbeilegung der EU-Kommission offen: ec.europa.eu/consumers/odr",
                    "The law of the Federal Republic of Germany applies. The place of jurisdiction is, to the extent legally permissible, the registered office of the provider. For disputes, the EU Commission's online dispute resolution platform is also available: ec.europa.eu/consumers/odr"
                )
            )

            LegalSection(
                title: legalPick("13. Kontakt", "13. Contact"),
                text: legalPick(
                    "Bei Fragen zu diesen Nutzungsbedingungen wende dich an:\n\ncontact@drops-app.de\ndazuapp.com\n\nWir sind bemüht, deine Anfrage innerhalb von 5 Werktagen zu beantworten.",
                    "For questions about these terms of use, contact us at:\n\ncontact@drops-app.de\ndazuapp.com\n\nWe aim to respond to your request within 5 business days."
                )
            )
        }
    }
}
