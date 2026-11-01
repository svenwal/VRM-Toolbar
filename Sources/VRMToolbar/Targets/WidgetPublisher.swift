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
        let windowNames = Dictionary(uniqueKeysWithValues: displays.windows.map { ($0.id, $0.name) })
        let items = store.activeItems(displays.items).prefix(12).map { item -> WidgetSnapshot.Item in
            let group: String
            switch item.target {
            case .menuBar: group = DisplayTarget.menuBar.title
            case .dock: group = DisplayTarget.dock.title
            case .floating:
                let id = item.windowId.flatMap { windowNames[$0] != nil ? $0 : nil } ?? displays.windows.first?.id
                group = id.flatMap { windowNames[$0] } ?? DisplayTarget.floating.title
            }
            return .init(id: item.id.uuidString, title: item.title(in: store), value: store.metric(for: item)?.formatted ?? "…", group: group)
        }
        let isSignedIn: Bool
        if case .notConfigured = store.status { isSignedIn = false } else { isSignedIn = true }
        pending = WidgetSnapshot(updated: store.lastUpdate, isSignedIn: isSignedIn, isStale: store.isStale,
                                 batteryLevel: store.batteryLevel, items: Array(items))
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
