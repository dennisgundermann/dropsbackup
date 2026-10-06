import Foundation
import UserNotifications
import CoreLocation

// MARK: - Push / Local Notification Manager

@MainActor
final class PushNotificationManager {

    static let shared = PushNotificationManager()
    private init() {}

    // MARK: - Notification IDs
    private enum ID {
        static let reEngagement   = "drops_reengagement"
        static let nearbyDrops    = "drops_nearby"
        static let dropin         = "dropin"
        static let arrived        = "drops_arrived"
        static let encounter      = "encounter"
        static let homeZone       = "drops_homezone"
        static let inactivity     = "drops_inactivity_24h"
        static let profilePic     = "drops_profile_pic_reminder"
        /// Prefix für die mehreren wiederholenden Power-Hour-Trigger
        /// (pro Wochentag × Window-Startzeit ein eigener Identifier).
        static let powerHourPrefix = "drops_powerhour_"
    }

    // MARK: - UserDefaults Keys
    private enum UDKey {
        static let lastNearbyNotif          = "pn_last_nearby_notif"
        static let sessionHadAction         = "pn_session_had_action"
        static let lastReEngageNotif        = "pn_last_reengage_notif"
        static let lastHomeZoneNotif        = "pn_last_homezone_notif"
        static let registeredAt             = "pn_registered_at"
        static let profilePicScheduled      = "pn_profile_pic_scheduled"
    }

    // MARK: - Session State
    private var sessionHadAction = false

    // MARK: - Permission

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
    }

    /// Fragt nur wenn der User noch nie gefragt wurde (notDetermined).
    /// Sicher mehrfach aufrufbar — keine doppelten Dialoge.
    func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            DispatchQueue.main.async { self.requestPermission() }
        }
    }

    // MARK: - Session Action Tracking
    // Ruf das auf wenn der User etwas sinnvolles tut (Drop erstellen, beitreten, Detail öffnen)

    func trackAction() {
        sessionHadAction = true
    }

    func resetSession() {
        sessionHadAction = false
    }

    // MARK: - Re-Engagement Notification
    // Wird beim App-Backgrounding geplant wenn kein sinnvoller Schritt gemacht wurde.

    func scheduleReEngagementIfNeeded() {
        guard !sessionHadAction else {
            cancelReEngagementNotification()
            return
        }

        // Nicht spammen: mindestens 2 Stunden zwischen zwei Re-Engagement-Pushs
        let lastSent = UserDefaults.standard.double(forKey: UDKey.lastReEngageNotif)
        if lastSent > 0 {
            let elapsed = Date().timeIntervalSince1970 - lastSent
            guard elapsed > 2 * 3600 else { return }
        }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = ["type": "reengagement"]

        // Marketing-Copy mit Curiosity, Pain-Points & FOMO. Bewusst kein
        // Hinweis auf konkrete Drops in der Nähe (würde sonst falsche
        // Erwartung wecken — das macht checkNearbyDrops separat).
        let messages: [(title: String, body: String)] = [
            (tr("push.reengage.1_title"), tr("push.reengage.1_body")),
            (tr("push.reengage.2_title"), tr("push.reengage.2_body")),
            (tr("push.reengage.3_title"), tr("push.reengage.3_body")),
            (tr("push.reengage.4_title"), tr("push.reengage.4_body")),
            (tr("push.reengage.5_title"), tr("push.reengage.5_body")),
            (tr("push.reengage.6_title"), tr("push.reengage.6_body")),
            (tr("push.reengage.7_title"), tr("push.reengage.7_body")),
            (tr("push.reengage.8_title"), tr("push.reengage.8_body")),
            (tr("push.reengage.9_title"), tr("push.reengage.9_body")),
        ]
        let pick = messages[Int.random(in: 0 ..< messages.count)]
        content.title = pick.title
        content.body  = pick.body

        // Nach 18 Minuten feuern
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 18 * 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: ID.reEngagement,
            content: content,
            trigger: trigger
        )

        let center = UNUserNotificationCenter.current()
        // Vorherige ersetzen
        center.removePendingNotificationRequests(withIdentifiers: [ID.reEngagement])
        center.add(request)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UDKey.lastReEngageNotif)
    }

    func cancelReEngagementNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [ID.reEngagement])
    }

    // MARK: - Nearby Drops Notification
    // Prüft ob Drops in der Nähe sind und benachrichtigt ggf. — max. 1x pro 30 Min.

    func checkNearbyDrops(_ drops: [MapAnnotationItem], userLocation: CLLocationCoordinate2D,
                          radius: Double = 2000) {
        // Vom User einstellbar (Standard 2 km). Gibt an wie nah ein Drop
        // sein muss damit eine Benachrichtigung ausgelöst wird.
        let nearbyRadius: Double = max(500, radius)

        let nearby = drops.filter { $0.isNearby(from: userLocation, maxMeters: nearbyRadius) }
        print("[nearby] checkNearbyDrops: total=\(drops.count) inRadius=\(nearby.count)")
        guard !nearby.isEmpty else { return }

        // Throttle: max 1x alle 20 Min (vorher 30 — etwas reaktiver,
        // ohne in Spam zu kippen).
        let lastSent = UserDefaults.standard.double(forKey: UDKey.lastNearbyNotif)
        if lastSent > 0 {
            let elapsed = Date().timeIntervalSince1970 - lastSent
            if elapsed <= 20 * 60 {
                print("[nearby] SKIPPED — throttle (\(Int(elapsed))s ago)")
                return
            }
        }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = ["type": "nearby_drops"]

        if nearby.count == 1, let drop = nearby.first {
            let dist = Int(drop.distance(from: userLocation))
            let distStr = dist >= 1000
                ? String(format: "%.1f km", Double(dist) / 1000)
                : "\(dist) m"
            content.title = tr("push.nearby_single_title")
                .replacingOccurrences(of: "{emoji}", with: drop.emoji)
                .replacingOccurrences(of: "{activity}", with: drop.activity)
            content.body = tr("push.nearby_single_body")
                .replacingOccurrences(of: "{name}", with: drop.name)
                .replacingOccurrences(of: "{dist}", with: distStr)
        } else {
            let closest = nearby.sorted { $0.distance(from: userLocation) < $1.distance(from: userLocation) }
            let top = closest.prefix(2).map { "\($0.emoji) \($0.activity)" }.joined(separator: ", ")
            content.title = tr("push.nearby_multi_title")
                .replacingOccurrences(of: "{count}", with: "\(nearby.count)")
            content.body = tr("push.nearby_multi_body")
                .replacingOccurrences(of: "{top}", with: top)
        }

        // Sofort (nil trigger = wird direkt zugestellt wenn App im Hintergrund)
        let request = UNNotificationRequest(
            identifier: ID.nearbyDrops,
            content: content,
            trigger: nil
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [ID.nearbyDrops])
        center.add(request)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UDKey.lastNearbyNotif)
    }

    // MARK: - Power-Hour Notifications
    //
    // Planen wir wiederkehrend lokal: pro Power-Hour-Window × Wochentag wird
    // ein eigener UNCalendarNotificationTrigger angelegt. iOS feuert die
    // automatisch jede Woche zur passenden Uhrzeit, ohne dass die App
    // running sein muss. Beim App-Start räumen wir alte Power-Hour-Pushs
    // weg und planen sie frisch — so bleiben Änderungen am Window-Schema
    // automatisch in Sync.
    //
    // Texte sind variabel ausgewählt aus einem kleinen Pool, damit der
    // User nicht jede Woche exakt denselben Wortlaut sieht (Push-Müdigkeit).
    func schedulePowerHourNotifications() {
        let center = UNUserNotificationCenter.current()
        Task { @MainActor in
            // 1. Alte Power-Hour-Requests entfernen (Prefix-basiert)
            let pending = await center.pendingNotificationRequests()
            let staleIDs = pending
                .map { $0.identifier }
                .filter { $0.hasPrefix(ID.powerHourPrefix) }
            if !staleIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            }

            // 2. Drei Notification-Typen pro Window + Weekday:
            //    a) "Pre" — 1h vor Start ("Power-Hour startet bald")
            //    b) "Start" — exakt zum Start
            //    c) "End-Warn" — 1h vor Ende ("letzte Chance")
            //
            // Texte sind variabel ausgewählt aus einem kleinen Pool, damit der
            // User nicht jede Woche exakt denselben Wortlaut sieht.
            let startMessages: [(title: String, body: String)] = [
                (tr("push.ph_start.1_title"), tr("push.ph_start.1_body")),
                (tr("push.ph_start.2_title"), tr("push.ph_start.2_body")),
                (tr("push.ph_start.3_title"), tr("push.ph_start.3_body")),
            ]
            let preMessages: [(title: String, body: String)] = [
                (tr("push.ph_pre.1_title"), tr("push.ph_pre.1_body")),
                (tr("push.ph_pre.2_title"), tr("push.ph_pre.2_body")),
                (tr("push.ph_pre.3_title"), tr("push.ph_pre.3_body")),
            ]
            let endMessages: [(title: String, body: String)] = [
                (tr("push.ph_end.1_title"), tr("push.ph_end.1_body")),
                (tr("push.ph_end.2_title"), tr("push.ph_end.2_body")),
                (tr("push.ph_end.3_title"), tr("push.ph_end.3_body")),
            ]

            for window in AppStore.powerHourWindows {
                for weekday in window.weekdays {
                    // a) Pre-Notification 1h vor Start
                    let preHour = window.startHour - 1
                    if preHour >= 0 {
                        do {
                            try await scheduleRecurring(
                                on: center,
                                id: "\(ID.powerHourPrefix)\(weekday)_\(window.startHour)_pre",
                                weekday: weekday, hour: preHour, minute: 0,
                                messages: preMessages,
                                type: "powerhour_pre",
                                windowLabel: window.label
                            )
                        } catch {
                            print("[powerHour] ⚠️ pre wd=\(weekday) h=\(preHour) failed: \(error.localizedDescription)")
                        }
                    }

                    // b) Start-Notification
                    do {
                        try await scheduleRecurring(
                            on: center,
                            id: "\(ID.powerHourPrefix)\(weekday)_\(window.startHour)_start",
                            weekday: weekday, hour: window.startHour, minute: 0,
                            messages: startMessages,
                            type: "powerhour_start",
                            windowLabel: window.label
                        )
                    } catch {
                        print("[powerHour] ⚠️ start wd=\(weekday) h=\(window.startHour) failed: \(error.localizedDescription)")
                    }

                    // c) End-Warn-Notification 1h vor Ende
                    let endWarnHour = window.endHour - 1
                    if endWarnHour > window.startHour {
                        do {
                            try await scheduleRecurring(
                                on: center,
                                id: "\(ID.powerHourPrefix)\(weekday)_\(window.startHour)_endwarn",
                                weekday: weekday, hour: endWarnHour, minute: 0,
                                messages: endMessages,
                                type: "powerhour_endwarn",
                                windowLabel: window.label
                            )
                        } catch {
                            print("[powerHour] ⚠️ endwarn wd=\(weekday) h=\(endWarnHour) failed: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    /// Helper: legt einen wiederkehrenden Calendar-Trigger an.
    private func scheduleRecurring(
        on center: UNUserNotificationCenter,
        id: String,
        weekday: Int, hour: Int, minute: Int,
        messages: [(title: String, body: String)],
        type: String,
        windowLabel: String
    ) async throws {
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour    = hour
        comps.minute  = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        let pick = messages[Int.random(in: 0 ..< messages.count)]
        let content = UNMutableNotificationContent()
        content.title = pick.title
        content.body  = pick.body
        content.sound = .default
        content.userInfo = ["type": type, "window": windowLabel]

        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await center.add(req)
    }

    // MARK: - Daily Evening Re-Engagement
    //
    // Recurring 19:00-Push an Wochentagen ohne Power-Hour-Window (Mo, Di,
    // Do — falls Power-Hour Mi/Fr/Sa läuft). Ziel: passive User morgens
    // anstoßen wenn primary Use-Case (Feierabend-Drop) am wahrscheinlichsten
    // ist. Throttle auf weekday-Basis vermeidet Doppel-Push wenn User
    // ohnehin Power-Hour-Push bekommt.
    //
    // Wird genauso wie Power-Hour beim App-Start frisch geplant — alte
    // Requests werden via Prefix-Match gelöscht.
    func scheduleDailyEveningPrompts() {
        let center = UNUserNotificationCenter.current()
        let prefix = "drops_evening_"

        Task { @MainActor in
            // Alte Requests aufräumen
            let pending = await center.pendingNotificationRequests()
            let staleIDs = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            if !staleIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            }

            // Power-Hour-Weekdays bestimmen — auf diesen Tagen NICHT zusätzlich
            // pushen, sonst Doppelung mit den `powerhour_pre`-Notifications.
            let phWeekdays = Set(AppStore.powerHourWindows.flatMap { $0.weekdays })

            // Nachrichten-Pool — Marketing-Copy, casual + curiosity
            let messages: [(title: String, body: String)] = [
                (tr("push.evening.1_title"), tr("push.evening.1_body")),
                (tr("push.evening.2_title"), tr("push.evening.2_body")),
                (tr("push.evening.3_title"), tr("push.evening.3_body")),
                (tr("push.evening.4_title"), tr("push.evening.4_body")),
                (tr("push.evening.5_title"), tr("push.evening.5_body")),
            ]

            // Mo (2), Di (3), Do (5) — Wochentage ohne Power-Hour bevorzugt.
            // Sonntag ist eher ruhig, Sa/Fr läuft Power-Hour. Wenn Power-Hour-
            // Schema sich ändert, schließt phWeekdays-Filter automatisch aus.
            let candidateWeekdays = [2, 3, 5]
            let activeWeekdays = candidateWeekdays.filter { !phWeekdays.contains($0) }

            for weekday in activeWeekdays {
                var comps = DateComponents()
                comps.weekday = weekday
                comps.hour = 19
                comps.minute = 0

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let pick = messages[Int.random(in: 0..<messages.count)]
                let content = UNMutableNotificationContent()
                content.title = pick.title
                content.body  = pick.body
                content.sound = .default
                content.userInfo = ["type": "evening_reengagement"]

                let req = UNNotificationRequest(
                    identifier: "\(prefix)\(weekday)_19",
                    content: content,
                    trigger: trigger
                )
                do {
                    try await center.add(req)
                } catch {
                    print("[eveningPrompt] ⚠️ wd=\(weekday) failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Entfernt alle geplanten Daily-Evening-Pushs. Beim Logout/Push-Off.
    func cancelAllEveningPrompts() {
        let center = UNUserNotificationCenter.current()
        Task { @MainActor in
            let pending = await center.pendingNotificationRequests()
            let ids = pending.map(\.identifier).filter { $0.hasPrefix("drops_evening_") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Entfernt alle geplanten Power-Hour-Pushs. Praktisch beim Logout
    /// oder wenn der User Push-Benachrichtigungen abschaltet.
    func cancelAllPowerHourNotifications() {
        let center = UNUserNotificationCenter.current()
        Task { @MainActor in
            let pending = await center.pendingNotificationRequests()
            let ids = pending
                .map { $0.identifier }
                .filter { $0.hasPrefix(ID.powerHourPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Home Zone Warning Notification
    // Feuert wenn der User seine Heimzone betritt und fremde Drops in der Nähe sind.
    // Max. 1x alle 60 Minuten um Spam zu vermeiden.

    func notifyHomeZoneWarning(nearbyDropCount: Int) {
        // Throttle: max 1x pro 60 Min
        let lastSent = UserDefaults.standard.double(forKey: UDKey.lastHomeZoneNotif)
        if lastSent > 0 {
            let elapsed = Date().timeIntervalSince1970 - lastSent
            guard elapsed > 60 * 60 else { return }
        }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = ["type": "homezone_warning"]

        let messages: [(title: String, body: String)] = [
            (tr("push.homezone.1_title"),
             nearbyDropCount > 1
             ? tr("push.homezone.1_body_multi").replacingOccurrences(of: "{count}", with: "\(nearbyDropCount)")
             : tr("push.homezone.1_body_single")),
            (tr("push.homezone.2_title"), tr("push.homezone.2_body")),
            (tr("push.homezone.3_title"), tr("push.homezone.3_body")),
        ]
        let pick = messages[Int.random(in: 0 ..< messages.count)]
        content.title = pick.title
        content.body  = pick.body

        let request = UNNotificationRequest(
            identifier: ID.homeZone,
            content: content,
            trigger: nil
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [ID.homeZone])
        center.add(request)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UDKey.lastHomeZoneNotif)
    }

    // MARK: - Join Request Notifications

    /// Push wenn Host NICHT in der App ist und jemand beitreten will
    func notifyIncomingJoinRequest(joinerName: String, activityName: String) {
        let content = UNMutableNotificationContent()
        content.title = tr("push.join_req_title")
        content.body  = tr("push.join_req_body")
            .replacingOccurrences(of: "{joiner}", with: joinerName)
            .replacingOccurrences(of: "{activity}", with: activityName)
        content.sound = .default
        content.userInfo = ["type": "join_request"]
        schedule(content, id: "join_request_\(Date().timeIntervalSince1970)")
    }

    /// Push an Host wenn Auto-Accept ausgelöst wurde
    func notifyAutoAccepted(joinerName: String, activityName: String) {
        let content = UNMutableNotificationContent()
        content.title = tr("push.auto_acc_title")
        content.body  = tr("push.auto_acc_body")
            .replacingOccurrences(of: "{joiner}", with: joinerName)
            .replacingOccurrences(of: "{activity}", with: activityName)
        content.sound = .default
        content.userInfo = ["type": "auto_accept"]
        schedule(content, id: "auto_accept_\(Date().timeIntervalSince1970)")
    }

    /// Lokale Push an JOINER wenn Host die Anfrage angenommen hat (manuell
    /// oder per 5-Min-Auto-Accept). Joiner hat sonst keinen Trigger der
    /// ihm die Bestätigung zeigt — `myJoinRequestStatus` flippt zwar, aber
    /// wenn die App im Background ist sieht der User nichts.
    func notifyMyJoinAccepted(hostName: String, activityName: String) {
        let content = UNMutableNotificationContent()
        content.title = tr("push.my_join_acc_title")
        content.body  = tr("push.my_join_acc_body")
            .replacingOccurrences(of: "{host}", with: hostName)
            .replacingOccurrences(of: "{activity}", with: activityName)
        content.sound = .default
        content.userInfo = ["type": "join_accepted"]
        schedule(content, id: "join_accepted_\(Date().timeIntervalSince1970)")
    }

    /// Lokale Push an JOINER wenn Host nach 5 min nicht reagiert hat. Wir
    /// haben dann auf Host-Seite Auto-Accept ausgelöst — der Push erinnert
    /// den Joiner daran, dass es jetzt los geht (oder er noch verlassen kann).
    func notifyHostDidntRespond(hostName: String, activityName: String) {
        let content = UNMutableNotificationContent()
        content.title = tr("push.host_noresp_title")
        content.body  = tr("push.host_noresp_body")
            .replacingOccurrences(of: "{host}", with: hostName)
            .replacingOccurrences(of: "{activity}", with: activityName)
        content.sound = .default
        content.userInfo = ["type": "join_auto_accepted"]
        schedule(content, id: "host_no_response_\(Date().timeIntervalSince1970)")
    }

    /// Lokale Push an EMPFÄNGER wenn ein Freund ihn zu seinem Drop einlädt
    /// (über das MiniProfileSheet → "Zu meinem Drop einladen"). Ohne diesen
    /// Push merkt der Empfänger nichts wenn die App im Hintergrund ist —
    /// der In-App-Alert poppt erst beim nächsten Foreground.
    func notifyIncomingDropInvitation(hostName: String, hostEmoji: String,
                                      activityName: String, dropEmoji: String) {
        let content = UNMutableNotificationContent()
        content.title = tr("push.invite_title")
            .replacingOccurrences(of: "{emoji}", with: hostEmoji)
            .replacingOccurrences(of: "{host}", with: hostName)
        content.body  = tr("push.invite_body")
            .replacingOccurrences(of: "{host}", with: hostName)
            .replacingOccurrences(of: "{dropEmoji}", with: dropEmoji)
            .replacingOccurrences(of: "{activity}", with: activityName)
        content.sound = .default
        content.userInfo = ["type": "drop_invitation"]
        schedule(content, id: "drop_invitation_\(Date().timeIntervalSince1970)")
    }

    /// Lokale Push an JOINER wenn der Host den Drop beendet hat. Sonst
    /// merkt der Joiner es erst wenn er die App öffnet — ist aber wichtig
    /// dass er Bescheid weiß damit er nicht umsonst hingeht.
    /// Begrenzung: läuft nur solange die Joiner-App live observed (im
    /// Hintergrund OK, vollständig gekillt → keine Erkennung möglich,
    /// ohne Cloud Function nicht änderbar).
    func notifyHostCancelledDrop(dropEmoji: String, activityName: String) {
        let content = UNMutableNotificationContent()
        content.title = tr("push.host_cancel_title")
            .replacingOccurrences(of: "{emoji}", with: dropEmoji)
        content.body  = tr("push.host_cancel_body")
            .replacingOccurrences(of: "{activity}", with: activityName)
        content.sound = .default
        content.userInfo = ["type": "host_cancelled"]
        schedule(content, id: "host_cancelled_\(Date().timeIntervalSince1970)")
    }

    // MARK: - Drop-In Notification (jemand tritt eigenem Drop bei)

    func notifyDropIn(joinerName: String, activityName: String) {
        let content = UNMutableNotificationContent()
        content.title = tr("push.dropin_title")
        content.body  = tr("push.dropin_body")
            .replacingOccurrences(of: "{joiner}", with: joinerName)
            .replacingOccurrences(of: "{activity}", with: activityName)
        content.sound = .default
        content.userInfo = ["type": "dropin"]
        // Kein hartkodiertes badge=1 mehr — sonst klebt eine "1" am Icon
        // bis der User die App öffnet, und es addiert sich auch nicht
        // sinnvoll auf. Badge-Clear läuft jetzt in AppDelegate beim
        // Foreground-Wechsel, das reicht.
        schedule(content, id: "\(ID.dropin)_\(Date().timeIntervalSince1970)")
    }

    // MARK: - Teilnehmer angekommen (BLE-bestätigt)

    func notifyParticipantArrived(name: String, activityName: String) {
        let content = UNMutableNotificationContent()
        content.title = tr("push.arrived_title")
            .replacingOccurrences(of: "{name}", with: name)
        content.body  = tr("push.arrived_body")
            .replacingOccurrences(of: "{activity}", with: activityName)
        content.sound = .default
        content.userInfo = ["type": "arrived"]
        schedule(content, id: "\(ID.arrived)_\(Int(Date().timeIntervalSince1970))")
    }

    // MARK: - Begegnung

    func notifyNewEncounter(withName: String, activityName: String) {
        let content = UNMutableNotificationContent()
        content.title = tr("push.encounter_title")
        content.body  = tr("push.encounter_body")
            .replacingOccurrences(of: "{activity}", with: activityName)
            .replacingOccurrences(of: "{name}", with: withName)
        content.sound = .default
        content.userInfo = ["type": "encounter"]
        schedule(content, id: "\(ID.encounter)_\(Date().timeIntervalSince1970)")
    }

    // MARK: - Reliability-Punkte erhalten

    /// Wird bei jedem Punktgewinn gefeuert (Show-Up, Drop-Beitritt etc.).
    /// reason: kurzer Kontext-Text (z.B. "Dein Drop wurde besucht").
    func notifyPointsEarned(delta: Int, totalPoints: Int, reason: String) {
        guard delta > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = tr("push.points_title")
            .replacingOccurrences(of: "{delta}", with: "\(delta)")
        content.body  = tr("push.points_body")
            .replacingOccurrences(of: "{reason}", with: reason)
            .replacingOccurrences(of: "{total}", with: "\(totalPoints)")
        content.sound = .default
        content.userInfo = ["type": "points_earned", "delta": delta, "total": totalPoints]
        schedule(content, id: "points_\(Date().timeIntervalSince1970)")
    }

    // MARK: - Ablauf-Erinnerungen (bestehende Logik, jetzt hier zentralisiert)
    // Werden von DropNotificationManager in Models.swift gesteuert.

    // MARK: - Helpers

    var currentFCMToken: String? {
        UserDefaults.standard.string(forKey: "fcmToken")
    }

    private func schedule(_ content: UNMutableNotificationContent,
                          id: String,
                          trigger: UNNotificationTrigger? = nil) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 24h Inactivity Reminder

    /// Plant eine lokale Benachrichtigung 24h nach dem letzten Drop.
    /// Wird gecancelt sobald der User einen neuen Drop erstellt oder jointet.
    func scheduleInactivityReminder() {
        cancelInactivityReminder()
        let content = UNMutableNotificationContent()
        content.title = tr("push.inactivity_title")
        content.body  = tr("push.inactivity_body")
        content.sound = .default
        content.userInfo = ["type": "inactivity"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 24 * 3_600, repeats: false)
        schedule(content, id: ID.inactivity, trigger: trigger)
    }

    /// Entfernt die ausstehende Inactivity-Benachrichtigung.
    func cancelInactivityReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [ID.inactivity])
    }

    // MARK: - Profilbild-Erinnerung (48 h nach Registrierung)

    /// Einmalig beim Abschluss des Onboardings aufrufen — speichert den
    /// Registrierungszeitpunkt für die Delay-Berechnung.
    func recordRegistration() {
        guard UserDefaults.standard.double(forKey: UDKey.registeredAt) == 0 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UDKey.registeredAt)
    }

    /// Entfernt eine ggf. noch ausstehende Profilbild-Erinnerung (Feature entfällt, Bild ist freiwillig).
    func cancelProfilePictureReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [ID.profilePic])
        UserDefaults.standard.removeObject(forKey: UDKey.profilePicScheduled)
    }
}
