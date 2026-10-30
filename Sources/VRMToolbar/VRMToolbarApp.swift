import SwiftUI

@MainActor
final class AppModel {
    static let shared = AppModel()
    let displays = DisplayStore()
    let store: MetricStore
    private var statusItems: StatusItemController?
    private var dock: DockTileController?
    private var floating: FloatingPanelController?
    private var hoverChart: HoverChartController?

    private init() { store = MetricStore(displays: displays) }

    func start() {
        statusItems = StatusItemController(store: store)
        dock = DockTileController(store: store)
        floating = FloatingPanelController(store: store)
        hoverChart = HoverChartController(store: store) { [weak self] source in
            switch source {
            case .window(let id): self?.floating?.frame(for: id)
            case .statusItem(let id): self?.statusItems?.frame(for: id)
            }
        }
        Task { await store.configure(AuthStore.load()) }
        if AuthStore.load() == nil { AppActions.openSettings() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.makeMainMenu()
        AppModel.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppActions.openSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func showSettings(_ sender: Any?) { AppActions.openSettings() }

    /// Minimal app menu (shown while the Dock icon is visible): Settings… and Quit.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide VRM Toolbar", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(withTitle: "Quit VRM Toolbar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = menu
        return main
    }
}

// Plain AppKit entry point: all windows are managed by SettingsWindowController and the panel controllers,
// so there is no SwiftUI scene (which would add an empty "Settings" window).
@main
@MainActor
enum VRMToolbarMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
