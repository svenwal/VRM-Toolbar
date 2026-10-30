import AppKit

/// One NSStatusItem per menu-bar display (MenuBarExtra can't be created dynamically).
@MainActor
final class StatusItemController: NSObject {
    private let store: MetricStore
    private var statusItems: [UUID: NSStatusItem] = [:]

    func frame(for item: UUID) -> NSRect? { statusItems[item]?.button?.window?.frame }

    init(store: MetricStore) {
        self.store = store
        super.init()
        observeForever { [weak self] in self?.sync() }
    }

    private func sync() {
        let items = store.activeItems(store.displays.items(for: .menuBar))
        let ids = Set(items.map(\.id))
        for (id, si) in statusItems where !ids.contains(id) {
            NSStatusBar.system.removeStatusItem(si)
            statusItems[id] = nil
        }
        for item in items {
            let si = statusItems[item.id] ?? {
                let s = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                statusItems[item.id] = s
                if let button = s.button {
                    button.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                                          owner: self, userInfo: ["id": item.id]))
                }
                return s
            }()
            si.button?.title = item.text(in: store)
            si.button?.alphaValue = store.isStale ? 0.5 : 1
            si.button?.image = item.symbol.isEmpty ? nil
                : NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
            si.button?.imagePosition = .imageLeading
            si.menu = makeMenu()
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        switch store.status {
        case .error(let msg): menu.addItem(withTitle: "⚠︎ \(msg)", action: nil, keyEquivalent: "")
        case .notConfigured: menu.addItem(withTitle: "Not signed in", action: nil, keyEquivalent: "")
        default: break
        }
        for item in store.displays.items {
            let name = item.label.isEmpty ? (store.metric(for: item)?.name ?? item.metricName) : item.label
            menu.addItem(withTitle: "\(name): \(store.metric(for: item)?.formatted ?? "…")", action: nil, keyEquivalent: "")
        }
        if let t = store.lastUpdate {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Updated \(t.formatted(date: .omitted, time: .standard))", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for i in [refresh, settings] { i.target = self }
        [refresh, settings, quit].forEach(menu.addItem)
        return menu
    }

    @objc func mouseEntered(_ event: NSEvent) {
        if let id = event.trackingArea?.userInfo?["id"] as? UUID { store.hoverEnter(HoverTarget(item: id, source: .statusItem(id))) }
    }

    @objc func mouseExited(_ event: NSEvent) {
        if let id = event.trackingArea?.userInfo?["id"] as? UUID { store.hoverExit(HoverTarget(item: id, source: .statusItem(id))) }
    }

    @objc private func refresh() { store.refreshNow() }
    @objc private func openSettings() { AppActions.openSettings() }
}

enum AppActions {
    @MainActor static func openSettings() {
        SettingsWindowController.shared.show()
    }
}
