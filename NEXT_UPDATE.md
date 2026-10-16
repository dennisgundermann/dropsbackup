# Drops — Nächstes Update Roadmap

Stand: nach Feature-Sprint Mai 2026.

---

## ✅ Erledigt (war im letzten Roadmap-Stand)

- **First-Drop-Walkthrough** — implementiert
- **Reliability-Tier-Vereinfachung** — implementiert
- **Share-Drop-Link (Strava-Pattern)** — implementiert

---

## Zuletzt umgesetzt (Feature-Sprint Mai 2026)

- Animierter Hero-Gradient in allen drei Haupt-Tabs (Freunde, Einstellungen, Umgebung) — Template-gesteuert via `@AppStorage`
- `EmojiScatterBackground` — 8 kleine Emojis mit staggered Fade-Loop im Profil-Header
- `MiniProfileSheet` — voller Hintergrundgradient + weiches Gradient-Mask, AngularGradient-Tier-Ring, weißes Icon
- LiquidGlass-Karten in FeedView
- Stats 2×2-Grid im Profil
- `GhostDropFeedCard` zeigt Host-Name + Alter
- Reale vergangene Drops (Ghost) auf Karte + im Feed-Ghost-Abschnitt
- Demo-Drop-Pins deutlich besser sichtbar (Opacity 82%, Sättigung 80%, Scale 93%)
- Bug-Fix: eigene Ghost-Drops wurden zu früh aus `liveStrangerDrops` gefiltert

---

## Backlog (noch nicht priorisiert)

- App-Icon-Update auf D-Icon-Variante (Orange→Grün glossy, mit verstärkten Radar-Wellen)
- Live Activity im WelcomeSheet als echtes Dynamic-Island-Mock statt SF-Symbol
- Map+Feed-Merge (anderes UX-Pattern als Bottom-Sheet — z.B. Toggle Map↔Liste)
- Lokalisierung von `FeedStatus` (TODO in `FeedView.swift:444`)
- Drops+ Premium-Code aufräumen wenn permanent dormant
