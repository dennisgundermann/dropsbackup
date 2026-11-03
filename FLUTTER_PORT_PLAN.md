# dazu Flutter – Port-Plan iOS 2.0.2 → Android

Stand: 2026-11-03. iOS Marketing-Version = `2.0.2`, Flutter pubspec = `2.0.2+1`.
Nur portiert was in 2.0.2 **aktiv** ist — Feature-Flags & Beta-Toggles beachtet.

Legende: ⭐ fehlt komplett · 🔺 großer Delta · 🟡 teilweise portiert · ✅ grob paritätisch · 🚫 nicht aktiv in 2.0.2

---

## 🚫 Nicht aktiv in iOS 2.0.2 — NICHT PORTIERT

| iOS-Datei | LoC | Flag / Grund |
|---|---:|---|
| `Communities.swift` | 2628 | `FeatureFlags.communitiesEnabled = false` |
| `DropsPlusView 2.swift` | 480 | `FeatureFlags.dropsPlusEnabled = false` |
| `DropsStoreManager.swift` | 145 | nur relevant wenn Plus aktiv |
| `CityGateView.swift` | 1177 | `BetaConfig.cityRestrictionEnabled = false` |
| `PartnerSpots.swift` + `PartnerSpotViews.swift` | 504 | User explizit: brauche ich nicht |
| `DropsAppIntents 2.swift` | 4 | iOS-only (Siri Shortcuts) |
| `DropLiveActivityAttributes.swift` | 36 | iOS-only (Dynamic Island) |
| `AppDelegate.swift` | 421 | iOS-only Lifecycle |
| `AdminPanelView.swift` | 3029 | Admin-only Panel (nicht für User-App) |
| `DropTips.swift` | 56 | redundant zu FirstDropCoachOverlay |
| `LegalView.swift` | 772 | Flutter nutzt url_launcher auf dazuapp.com |

**Summe gespart:** ~9200 LoC Swift — die nicht nach Flutter mussten.

---

## ✅ Diese Session komplett portiert

### Models (`lib/models/`)
| iOS | Flutter |
|---|---|
| `Models.swift` DropEvent-Delta | `runde.dart` erweitert um `durationMinutes`, `dropDescription`, `scheduledStartOffset` |
| `Models.swift` DropParticipant-Delta | `teilnehmer.dart` erweitert um `locTimeMs`, `statusMessage` |
| `Models.swift` User, Activity, DropLocation | `drop_location.dart` + Location-Type-Enum |
| `Models.swift` AgeGroup | `age_group.dart` mit `label`/`minAge`/`maxAge`/`icon`/`color` + `groupFor()` + `defaultVisible()` |
| `Models.swift` FeedDistanceFilter | `feed_distance_filter.dart` |
| `Models.swift` FirstDropCelebration | `first_drop_celebration.dart` |
| `Models.swift` PastDrop + PastDropParticipant | `past_drop.dart` mit JSON-Serialisierung für SharedPrefs |
| `Models.swift` Encounter | `encounter.dart` mit `timeRemaining`, `isExpired`, `copyWith` |
| `Models.swift` AlertItem | `alert_item.dart` |
| `Models.swift` IncomingJoinRequest | `incoming_join_request.dart` mit `autoAcceptAt`, `waitingMinutes` |
| `Models.swift` FriendSuggestion | `friend_suggestion.dart` |
| `DesignSystem.swift` ReliabilityScore (560-672) | `reliability_score.dart` + 10 Unit-Tests |

### Services (`lib/services/`)
| iOS | Flutter |
|---|---|
| iOS `tr(key)` + 5-Sprachen-Dict (1442 LoC) | `l10n/l10n.dart` + `strings_{de,en,it,fr,es}.dart` (1215 Keys) |
| `ContentFilter.swift` | `content_filter.dart` + 12 Unit-Tests |
| `NetworkMonitor.swift` | `network_monitor.dart` (connectivity_plus) |
| iOS AppStore reliability mutations (verteilt) | `reliability_service.dart` + 8 Unit-Tests, hooks für Create/End/OnSite/FirstBonus/Boost |
| iOS `RealtimeDBManager.recordEncounter` + observers | `encounter_service.dart` (watchMine/confirm/deny/markSeen/record) |
| iOS `UserProfileService.fetchBadges` | `user_profile_service.dart` erweitert |
| iOS `countNearbyDrops` | `runden_service.countNearbyRunden` |

### Widgets (`lib/widgets/`)
| iOS | Flutter |
|---|---|
| `FirstDropCoachView.swift` | `first_drop_coach_overlay.dart` (Spotlight-Scrim + Pulse + 3 Steps) |
| `PresenceOptInSheet.swift` | `presence_opt_in_sheet.dart` (Modal mit 5 Bullets) |
| `NetworkMonitor.swift → OfflineBanner` | `offline_banner.dart` (Rot/Grün Chip mit Puls) |
| `DesignSystem.swift ReliabilityBadgeView` | `trusted_badge.dart` (inline + full Varianten) |
| `DesignSystem.swift ReliabilityInfoSheet` | `reliability_info_sheet.dart` (Hero + Progress + Tiers + Stats) |
| iOS FirstDropCelebration-Variante | `first_drop_celebration_sheet.dart` (Elastic-Pop + Chip + CTA) |
| `ProfileAndAlertsView.swift EncounterRow` | `encounter_row.dart` (4 Zustände) |

### UI-Integrationen
- `create_screen` — Content-Filter-Hook, Duration/When iOS-Parität (30min/1h/2h/4h/Ohne Limit + „Heute Abend"), First-Drop-Coach-Overlay via 3 GlobalKeys, First-Host-Celebration, Boost-Bonus auto, Reliability record on publish
- `profil_screen` — ZUVERLÄSSIGKEIT-Card mit Live-Listener + Tap → InfoSheet, BEGEGNUNGEN-Section mit EncounterRow + Confirm/Deny/AddFriend-Callbacks, Streak-Chip zeigt echten Counter
- `einstellungen_screen` — SPRACHE-Picker (5 Sprachen mit Flagge + Haken), Admin „Reliability zurücksetzen"
- `umgebung_screen` — First-Join-Celebration nach erstem tritRundeBei
- `main_shell` — OfflineBanner Overlay
- `main.dart` — L10nProvider wraps MaterialApp
- `runden_service.beendeRunde` — HostSuccess bei ≥2 Teilnehmern oder NoShow bei ≥12 Min pending (Launch-Phase-Toleranz)
- `presence_service` — recordJoinerArrival idempotent beim ersten Vor-Ort-Trigger

### Dependencies
- `connectivity_plus: ^6.1.0` (NetworkMonitor)

---

## 📊 Session-Metriken

- 12 Model-Dateien + 11 neue Widgets + 4 neue Services + 2 Service-Erweiterungen
- Localization: 1215 Keys × 5 Sprachen
- `dart analyze lib/`: 11 warnings (alle pre-existing dead code / withOpacity-Deprecations), 0 Errors
- **30/30 Unit-Tests grün** (12 ContentFilter + 10 ReliabilityScore + 8 ReliabilityService)

---

## 🔜 Noch offen (Follow-up Sessions)

| Priorität | Thema | iOS Datei | Umfang |
|---|---|---|---|
| 🔴 Hoch | BLE-Meetup (Task #33) | `BluetoothMeetupManager.swift` | 378 LoC + Android/iOS Permissions + Device-Testing |
| 🟡 Mittel | CreateDropView: People-Slider (2-15), Description-Feld, Custom-Zeit-Picker | `CreateDropView.swift` 2972→450 LoC | ~500 LoC Dart |
| 🟡 Mittel | LiveMapView-Delta: Side-Panel, Custom-Marker-Rendering, PresenceOverlay auf Google-Maps | `LiveMapView.swift` 6437→244 LoC | ~1000 LoC Dart (incl. flutter custom marker generator) |
| 🟡 Mittel | FeedView-Delta: 2.0.2 Rework der Umgebung + Live Tabs | `FeedView.swift` 2492→1758 LoC | ~500-800 LoC Dart |
| 🟡 Mittel | OnboardingView-Delta | `OnboardingView.swift` 3812→406 LoC | ~1000 LoC Dart |
| 🟢 Niedrig | ProfileAndAlertsView-Delta Alerts-Tab | `ProfileAndAlertsView.swift` 5932→2186 LoC | eingebettet in Profil, Großteil schon erledigt |
| 🟢 Niedrig | SharedComponents.swift selektiv (nur benötigte) | 3030 LoC | ergibt sich mit View-Deltas |
| 🟢 Niedrig | Scheduled-Push-Reminder (Cloud Function Trigger für scheduled starts) | functions/ | cross-platform, serverseitig |
