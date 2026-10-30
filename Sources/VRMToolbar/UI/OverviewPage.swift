import SwiftUI

struct PageHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 30, weight: .bold, design: .rounded))
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
        }
    }
}

struct OverviewPage: View {
    let store: MetricStore
    let go: (Page) -> Void

    var body: some View {
        let level = store.batteryLevel
        let tint = Color.battery(level)
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Overview", subtitle: store.installations.first.map { "\($0.name) · \(store.streaming.isEmpty ? "polling" : "live")" })

            HStack(spacing: 22) {
                RingGauge(value: level, tint: tint).frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 6) {
                    Text(level == nil ? "Waiting for data" : "Battery").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text(heroDetail).font(.callout).foregroundStyle(.secondary)
                    if let t = store.lastUpdate {
                        Label("Updated \(t.formatted(date: .omitted, time: .standard))", systemImage: "clock")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .glassCard(radius: 28, tint: tint)

            if store.displays.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bolt.badge.plus").font(.system(size: 34)).foregroundStyle(.yellow)
                    Text("Nothing on display yet").font(.headline)
                    Text("Pick values to show in the menu bar, Dock icon or a floating window.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Add a display") { go(.displays) }.glassButton(prominent: true)
                }
                .padding(28).frame(maxWidth: .infinity).glassCard()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                    ForEach(store.displays.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: item.target.symbol).font(.caption).foregroundStyle(.secondary)
                                Text(item.title(in: store)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Text(store.metric(for: item)?.formatted ?? "…")
                                .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(.smooth, value: store.metric(for: item)?.formatted)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(radius: 20)
                    }
                }
            }
        }
    }

    private var heroDetail: String {
        switch store.status {
        case .notConfigured: "Sign in on the Account page to get started."
        case .error(let m): m
        default:
            store.batteryLevel == nil ? "Add a battery value (state of charge) to see it here." : "Colours across the app follow your charge level."
        }
    }
}
