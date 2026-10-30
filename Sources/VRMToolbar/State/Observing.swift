import Foundation
import Observation

/// Re-runs `body` whenever any @Observable property read inside it changes.
@MainActor
func observeForever(_ body: @escaping @MainActor () -> Void) {
    withObservationTracking {
        body()
    } onChange: {
        Task { @MainActor in observeForever(body) }
    }
}

extension DisplayItem {
    @MainActor
    func text(in store: MetricStore) -> String {
        let value = store.metric(for: self)?.formatted ?? "…"
        return label.isEmpty ? value : "\(label) \(value)"
    }
}

extension DisplayItem {
    /// Label if set, else the metric's own name.
    @MainActor
    func title(in store: MetricStore) -> String {
        label.isEmpty ? (store.metric(for: self)?.name ?? metricName) : label
    }
}

extension MetricStore {
    /// Battery state of charge (0…1), if any streamed or displayed value looks like one.
    var batteryLevel: Double? {
        for item in displays.items {
            if let m = metric(for: item), let raw = m.raw, Self.looksLikeSoc(m.name) { return min(max(raw / 100, 0), 1) }
        }
        for (_, paths) in live {
            if let m = paths.first(where: { $0.key.hasSuffix("/Dc/Battery/Soc") })?.value, let raw = m.raw {
                return min(max(raw / 100, 0), 1)
            }
        }
        return nil
    }

    private static func looksLikeSoc(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("state of charge") || n.contains("soc")
    }
}
