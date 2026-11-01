import Foundation
import VRMShared
import WidgetKit

/// Mirrors the displays into the shared snapshot file and nudges WidgetKit to redraw.
@MainActor
final class WidgetPublisher {
    private let store: MetricStore
    private var pending: WidgetSnapshot?
    private var written: WidgetSnapshot?
    private var flushTask: Task<Void, Never>?
    private var lastReload = Date.distantPast

    init(store: MetricStore) {
        self.store = store
        observeForever { [weak self] in self?.capture() }
    }

    private func capture() {
        let displays = store.displays
        let sets = displays.widgetSets.map { set in
            let items = store.activeItems(displays.items(inWidget: set)).prefix(12).map { item in
                WidgetSnapshot.Item(id: item.id.uuidString, title: item.title(in: store), value: store.metric(for: item)?.formatted ?? "…")
            }
            return WidgetSnapshot.ValueSet(id: set.id.uuidString, name: set.name, items: Array(items))
        }
        let isSignedIn: Bool
        if case .notConfigured = store.status { isSignedIn = false } else { isSignedIn = true }
        pending = WidgetSnapshot(updated: store.lastUpdate, isSignedIn: isSignedIn, isStale: store.isStale,
                                 batteryLevel: store.batteryLevel, sets: sets)
        // Streamed values change constantly; coalesce them into one write every few seconds.
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.flush()
        }
    }

    private func flush() {
        flushTask = nil
        guard let snapshot = pending, snapshot != written else { return }
        guard SnapshotStore.write(snapshot) else { return }
        written = snapshot
        // WidgetKit rations reloads; once every 30 s at most is plenty for a glance.
        if Date().timeIntervalSince(lastReload) > 30 {
            lastReload = Date()
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                self?.flushTask = nil
                self?.written = nil   // force the next flush to reload
                self?.flush()
            }
        }
    }
}
