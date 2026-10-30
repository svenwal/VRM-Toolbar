import AppKit
import SwiftUI

/// Renders dock displays into the app's Dock tile and shows the Dock icon only when needed.
@MainActor
final class DockTileController {
    private let store: MetricStore
    private let host: NSHostingView<DockTileView>

    init(store: MetricStore) {
        self.store = store
        host = NSHostingView(rootView: DockTileView(store: store))
        host.frame = NSRect(origin: .zero, size: NSApp.dockTile.size == .zero ? NSSize(width: 128, height: 128) : NSApp.dockTile.size)
        observeForever { [weak self] in self?.sync() }
    }

    private func sync() {
        let hasDock = !store.displays.items(for: .dock).isEmpty
        let policy: NSApplication.ActivationPolicy = hasDock || store.displays.alwaysShowDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        _ = store.metrics; _ = store.lastUpdate  // track
        NSApp.dockTile.contentView = hasDock ? host : nil
        host.rootView = DockTileView(store: store)
        NSApp.dockTile.display()
    }
}

struct DockTileView: View {
    let store: MetricStore

    var body: some View {
        let items = store.activeItems(store.displays.items(for: .dock))
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.18, blue: 0.55), Color(red: 0.02, green: 0.04, blue: 0.16)],
                                     startPoint: .topTrailing, endPoint: .bottomLeading))
                .overlay(
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 96, weight: .black))
                        .foregroundStyle(LinearGradient(colors: [.yellow.opacity(0.28), .orange.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                        .rotationEffect(.degrees(8))
                        .offset(x: 18, y: -6)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                )
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
            VStack(spacing: 4) {
                ForEach(items.prefix(3)) { item in
                    VStack(spacing: 0) {
                        if !item.label.isEmpty {
                            Text(item.label).font(.system(size: 14, weight: .medium)).opacity(0.8)
                        }
                        Text(store.metric(for: item)?.formatted ?? "…")
                            .font(.system(size: items.count > 1 ? 26 : 40, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.4).lineLimit(1)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(10)
            .opacity(store.isStale ? 0.5 : 1)
        }
        .padding(6)
    }
}
