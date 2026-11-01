import SwiftUI
import VRMShared
import WidgetKit

@main
struct VRMWidgets: WidgetBundle {
    var body: some Widget {
        BatteryWidget()
        ValuesWidget()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : SnapshotStore.read() ?? WidgetSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: SnapshotStore.read() ?? WidgetSnapshot())
        // The app reloads timelines when values change; this is only the fallback.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

// MARK: - Widgets

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "world.walther.vrm-toolbar.battery", provider: SnapshotProvider()) { entry in
            BatteryView(snapshot: entry.snapshot).vrmBackground(level: entry.snapshot.batteryLevel)
        }
        .configurationDisplayName("Battery")
        .description("State of charge as a ring, with your other values beside it.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ValuesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "world.walther.vrm-toolbar.values", provider: SnapshotProvider()) { entry in
            ValuesView(snapshot: entry.snapshot).vrmBackground(level: entry.snapshot.batteryLevel)
        }
        .configurationDisplayName("Values")
        .description("The values from your Displays page, in the same order.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Theme (mirrors GlassKit in the app)

enum Theme {
    static func battery(_ level: Double?) -> Color {
        guard let level else { return Color(red: 0.35, green: 0.8, blue: 1) }
        if level > 0.6 { return Color(red: 0.2, green: 0.9, blue: 0.6) }
        if level > 0.3 { return Color(red: 1, green: 0.75, blue: 0.25) }
        return Color(red: 1, green: 0.35, blue: 0.4)
    }
}

extension View {
    /// Dark navy with an accent glow that follows the charge level, like the app's aurora.
    func vrmBackground(level: Double?) -> some View {
        containerBackground(for: .widget) {
            ZStack {
                Color(red: 0.03, green: 0.05, blue: 0.11)
                RadialGradient(colors: [Theme.battery(level).opacity(0.42), .clear], center: .topTrailing, startRadius: 0, endRadius: 220)
                RadialGradient(colors: [Color(red: 0.4, green: 0.2, blue: 0.8).opacity(0.35), .clear], center: .bottomLeading, startRadius: 0, endRadius: 200)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Views

struct Ring: View {
    var value: Double?
    var lineWidth: CGFloat

    var body: some View {
        let tint = Theme.battery(value)
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: lineWidth)
            Circle().trim(from: 0, to: value ?? 0)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.7), radius: 5)
            if let value {
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.6).padding(lineWidth + 2)
            } else {
                Image(systemName: "bolt.fill").font(.title2).foregroundStyle(tint)
            }
        }
    }
}

struct Footer: View {
    let snapshot: WidgetSnapshot
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: snapshot.isStale ? "exclamationmark.circle" : "clock")
            if let t = snapshot.updated { Text(t, style: .time) } else { Text("No data") }
        }
        .font(.system(size: 10)).foregroundStyle(snapshot.isStale ? Color.orange : .white.opacity(0.45))
    }
}

struct EmptyState: View {
    let snapshot: WidgetSnapshot
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "bolt.badge.plus").font(.title).foregroundStyle(.yellow)
            Text(snapshot.isSignedIn ? "No displays yet" : "Not signed in").font(.headline)
            Text(snapshot.isSignedIn ? "Add values in VRM Toolbar › Displays." : "Open VRM Toolbar to sign in.")
                .font(.caption).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ValueCell: View {
    let item: WidgetSnapshot.Item
    var big = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
            Text(item.value).font(.system(size: big ? 24 : 19, weight: .bold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BatteryView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        if snapshot.items.isEmpty && snapshot.batteryLevel == nil {
            EmptyState(snapshot: snapshot)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    VStack(spacing: 4) {
                        Ring(value: snapshot.batteryLevel, lineWidth: family == .systemSmall ? 10 : 12)
                            .frame(maxWidth: 110, maxHeight: 110)
                        if family == .systemSmall { Text("Battery").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7)) }
                    }
                    if family == .systemMedium {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Battery").font(.system(size: 15, weight: .semibold, design: .rounded))
                            ForEach(snapshot.items.filter { !$0.title.localizedCaseInsensitiveContains("charge") && !$0.title.localizedCaseInsensitiveContains("soc") }.prefix(3)) { ValueCell(item: $0) }
                            Spacer(minLength: 0)
                        }
                    }
                }
                if family == .systemMedium { Footer(snapshot: snapshot) }
            }
        }
    }
}

struct ValuesView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    private var limit: Int { family == .systemSmall ? 3 : family == .systemMedium ? 4 : 8 }

    var body: some View {
        if snapshot.items.isEmpty {
            EmptyState(snapshot: snapshot)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if family == .systemSmall {
                    VStack(alignment: .leading, spacing: 8) { cells(big: false) }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], alignment: .leading, spacing: family == .systemLarge ? 18 : 10) {
                        cells(big: true)
                    }
                }
                Spacer(minLength: 0)
                Footer(snapshot: snapshot)
            }
        }
    }

    @ViewBuilder
    private func cells(big: Bool) -> some View {
        ForEach(snapshot.items.prefix(limit)) { ValueCell(item: $0, big: big) }
    }
}
