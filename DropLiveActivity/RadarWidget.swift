import WidgetKit
import SwiftUI

// MARK: - Timeline

/// Zeigt Anzahl aktiver Drops in der Nähe (aus SharedRadarState, geschrieben
/// von der Haupt-App). Statisches Widget — Tap öffnet die App via Deep-Link
/// `drops://map` (LinkUpApp routet auf den Karten-Tab).
struct RadarWidget: Widget {
    let kind: String = "RadarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RadarTimelineProvider()) { entry in
            RadarWidgetView(entry: entry)
                .radarContainerBackground()
        }
        .configurationDisplayName("Pläne in der Nähe")
        .description("Zeigt wie viele Pläne gerade in deinem Radius laufen.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

// MARK: - Background helper (iOS 16 fallback)

private extension View {
    /// Home-Screen-Widgets: Violet-Gradient. Lock-Screen-Accessory-Widgets
    /// bekommen keinen eigenen Hintergrund (iOS rendert sie auf das Wallpaper
    /// mit AccessoryWidget-Tint).
    @ViewBuilder
    func radarContainerBackground() -> some View {
        let gradient = LinearGradient(
            colors: [Color.widgetVioletLight, Color.widgetViolet],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) {
                // Für Accessory-Familien transparent, sonst Gradient.
                AccessoryAwareBackground(gradient: gradient)
            }
        } else {
            self.background(gradient)
        }
    }
}

@available(iOS 17.0, *)
private struct AccessoryAwareBackground: View {
    @Environment(\.widgetFamily) private var family
    let gradient: LinearGradient
    var body: some View {
        if family == .accessoryCircular
            || family == .accessoryRectangular
            || family == .accessoryInline {
            Color.clear
        } else {
            gradient
        }
    }
}

private extension View {
    /// Lock-Screen-Accessory-Hintergrund: iOS rendert ein getöntes Milchglas
    /// hinter dem Inhalt (`AccessoryWidgetBackground()`). Nicht auf Inline-
    /// Family — die ist textbasiert und wird vom System selbst getönt.
    @ViewBuilder
    func widgetAccessoryBackground() -> some View {
        if #available(iOS 16.0, *) {
            self.background(AccessoryWidgetBackground())
        } else {
            self
        }
    }
}

// MARK: - Drops-Zeichen

/// „Offene Runde" als kleine Glyphe für Widget-Header: offener Ring plus
/// oranger Punkt in der Lücke. Proportionen wie im App-Icon (256er-Raster:
/// Ring r=78, Strich 40, Punkt r=27 bei −48°).
struct DropsMarkGlyph: View {
    var size: CGFloat = 14
    var ringColor: Color = .white
    var dotColor: Color = .widgetOrange

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.74)
                .stroke(ringColor, style: StrokeStyle(lineWidth: size * 0.156, lineCap: .round))
                .frame(width: size * 0.609, height: size * 0.609)
            // Stamm rechts unten: macht aus dem offenen Ring das „a" der Wortmarke.
            Capsule()
                .fill(ringColor)
                .frame(width: size * 0.156, height: size * 0.461)
                .offset(x: size * 0.305, y: size * 0.152)
            Circle()
                .fill(dotColor)
                .frame(width: size * 0.211, height: size * 0.211)
                .offset(x: size * 0.204, y: -size * 0.226)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Entry / Provider

struct RadarEntry: TimelineEntry {
    let date: Date
    let state: SharedRadarState
}

struct RadarTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RadarEntry {
        RadarEntry(date: Date(), state: SharedRadarState(nearbyCount: 3, nextEndsAt: Date().addingTimeInterval(240), updatedAt: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (RadarEntry) -> Void) {
        completion(RadarEntry(date: Date(), state: SharedRadarStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RadarEntry>) -> Void) {
        let now = Date()
        let entry = RadarEntry(date: now, state: SharedRadarStore.read())
        // Refresh alle 10 Min — die App schreibt State bei jedem checkNearbyDrops,
        // Widget aktualisiert sich per WidgetCenter.reloadAllTimelines() zusätzlich.
        let next = now.addingTimeInterval(10 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Views

struct RadarWidgetView: View {
    let entry: RadarEntry
    @Environment(\.widgetFamily) private var family

    private var isStale: Bool {
        Date().timeIntervalSince(entry.state.updatedAt) > 15 * 60
    }

    var body: some View {
        Link(destination: URL(string: "dazu://map")!) {
            switch family {
            case .systemSmall:          smallLayout
            case .systemLarge:          largeLayout
            case .accessoryCircular:    circularAccessory
            case .accessoryRectangular: rectangularAccessory
            case .accessoryInline:      inlineAccessory
            default:                    mediumLayout
            }
        }
    }

    // MARK: Lock-Screen-Accessories

    @ViewBuilder
    private var circularAccessory: some View {
        // Ringanzeige: Count groß in der Mitte, umlaufender Fortschritts-
        // Ring als visueller Dot-Platzhalter (iOS tönt alles weiß).
        ZStack {
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: 0.74)
                .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-48))
            VStack(spacing: 0) {
                Text("\(entry.state.nearbyCount)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("nah")
                    .font(.system(size: 8, weight: .semibold))
            }
        }
        .widgetAccessoryBackground()
    }

    @ViewBuilder
    private var rectangularAccessory: some View {
        HStack(spacing: 6) {
            DropsMarkGlyph(size: 16, ringColor: .white, dotColor: .white)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.state.nearbyCount) in der Nähe")
                    .font(.system(size: 13, weight: .semibold))
                if let ends = entry.state.nextEndsAt, ends > Date() {
                    Text("Nächster endet \(ends, style: .timer)")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                } else {
                    Text("Tippen → öffnen")
                        .font(.system(size: 10, weight: .medium))
                        .opacity(0.75)
                }
            }
            Spacer(minLength: 0)
        }
        .widgetAccessoryBackground()
    }

    @ViewBuilder
    private var inlineAccessory: some View {
        if entry.state.nearbyCount > 0 {
            Text("dazu · \(entry.state.nearbyCount) in der Nähe")
        } else {
            Text("dazu · grad still")
        }
    }

    // MARK: Large

    @ViewBuilder
    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                DropsMarkGlyph(size: 18)
                Text("Pläne in der Nähe")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.9))

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(entry.state.nearbyCount)")
                    .font(.system(size: 92, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(entry.state.nearbyCount == 1 ? "läuft" : "laufen")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }

            if let ends = entry.state.nextEndsAt, ends > Date() {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Nächster endet \(ends, style: .timer)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.white.opacity(0.14), in: Capsule())
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Link(destination: URL(string: "dazu://create")!) {
                    tileCTA(icon: "plus", title: "Jetzt dazu")
                }
                Link(destination: URL(string: "dazu://feed")!) {
                    tileCTA(icon: "magnifyingglass", title: "Umgebung")
                }
            }

            if isStale {
                Text("Daten älter als 15 Min — öffne die App")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private func tileCTA(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            Text(title).font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
    }

    // MARK: Small

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                DropsMarkGlyph(size: 14)
                Text("Dazu")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
            Text("\(entry.state.nearbyCount)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(entry.state.nearbyCount == 1 ? "in deiner Nähe" : "in deiner Nähe")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            if let ends = entry.state.nextEndsAt, ends > Date() {
                Text("Nächster endet \(ends, style: .timer)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .monospacedDigit()
                    .lineLimit(1)
            } else if isStale {
                Text("Öffne die App")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: Medium

    private var mediumLayout: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    DropsMarkGlyph(size: 15)
                    Text("Pläne in der Nähe")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
                Text("\(entry.state.nearbyCount)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                if let ends = entry.state.nextEndsAt, ends > Date() {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Nächster endet")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(ends, style: .timer)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                } else if entry.state.nearbyCount == 0 {
                    Text("Grad still —\naber wer weiß")
                        .font(.system(size: 12, weight: .medium))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                if isStale {
                    Text("veraltet · App öffnen")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}
