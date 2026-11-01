import AppIntents
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

// MARK: - Configuration

/// A widget set from the app's Widgets page, as offered in "Edit Widget".
struct SetEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Widget set")
    static let defaultQuery = SetQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct SetQuery: EntityQuery {
    private func all() -> [SetEntity] {
        (SnapshotStore.read() ?? WidgetSnapshot()).sets.map { SetEntity(id: $0.id, name: $0.name) }
    }
    func entities(for identifiers: [String]) async throws -> [SetEntity] { all().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [SetEntity] { all() }
    func defaultResult() async -> SetEntity? { all().first }
}

struct SelectSetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose values"
    static let description = IntentDescription("Pick which widget set this widget shows. Sets are managed in VRM Toolbar › Widgets.")

    @Parameter(title: "Widget set")
    var set: SetEntity?
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let set: WidgetSnapshot.ValueSet?
}

struct SnapshotProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { entry(.sample, nil) }

    func snapshot(for configuration: SelectSetIntent, in context: Context) async -> SnapshotEntry {
        context.isPreview ? entry(.sample, nil) : entry(SnapshotStore.read() ?? WidgetSnapshot(), configuration.set?.id)
    }

    func timeline(for configuration: SelectSetIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        // The app reloads timelines when values change; this is only the fallback.
        Timeline(entries: [entry(SnapshotStore.read() ?? WidgetSnapshot(), configuration.set?.id)],
                 policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func entry(_ snapshot: WidgetSnapshot, _ setId: String?) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: snapshot, set: snapshot.set(id: setId))
    }
}

// MARK: - Widgets

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "world.walther.vrm-toolbar.battery", intent: SelectSetIntent.self, provider: SnapshotProvider()) { entry in
            BatteryView(entry: entry).vrmBackground(level: entry.snapshot.batteryLevel)
        }
        .configurationDisplayName("Battery")
        .description("State of charge as a ring, with the values of a widget set beside it.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ValuesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "world.walther.vrm-toolbar.values", intent: SelectSetIntent.self, provider: SnapshotProvider()) { entry in
            ValuesView(entry: entry).vrmBackground(level: entry.snapshot.batteryLevel)
        }
        .configurationDisplayName("Values")
        .description("The values of a widget set. Edit the widget to choose which one.")
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
    var name: String?
    var body: some View {
        HStack(spacing: 4) {
            if let name { Text(name).lineLimit(1); Text("·") }
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
            Text(snapshot.isSignedIn ? "No values yet" : "Not signed in").font(.headline)
            Text(snapshot.isSignedIn ? "Choose Show in › Widget on the Displays page." : "Open VRM Toolbar to sign in.")
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
    let entry: SnapshotEntry

    var body: some View {
        let snapshot = entry.snapshot
        let items = entry.set?.items ?? []
        if items.isEmpty && snapshot.batteryLevel == nil {
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
                            ForEach(items.prefix(3)) { ValueCell(item: $0) }
                            Spacer(minLength: 0)
                        }
                    }
                }
                if family == .systemMedium { Footer(snapshot: snapshot, name: entry.set?.name) }
            }
        }
    }
}

struct ValuesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var limit: Int { family == .systemSmall ? 3 : family == .systemMedium ? 4 : 8 }

    var body: some View {
        let snapshot = entry.snapshot
        if (entry.set?.items ?? []).isEmpty {
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
                Footer(snapshot: snapshot, name: family == .systemSmall ? nil : entry.set?.name)
            }
        }
    }

    @ViewBuilder
    private func cells(big: Bool) -> some View {
        ForEach((entry.set?.items ?? []).prefix(limit)) { ValueCell(item: $0, big: big) }
    }
}
