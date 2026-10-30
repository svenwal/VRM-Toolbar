import AppKit
import SwiftUI

/// One borderless, always-on-top panel per configured floating window.
@MainActor
final class FloatingPanelController {
    private let store: MetricStore
    private var panels: [UUID: NSPanel] = [:]

    func frame(for window: UUID) -> NSRect? { panels[window]?.frame }

    init(store: MetricStore) {
        self.store = store
        observeForever { [weak self] in self?.sync() }
    }

    private func sync() {
        let displays = store.displays
        let configs = displays.windows
        for (id, panel) in panels where !configs.contains(where: { $0.id == id }) {
            panel.orderOut(nil)
            panels[id] = nil
        }
        for config in configs {
            let show = config.isVisible && !store.activeItems(displays.items(in: config)).isEmpty
            if !show { panels[config.id]?.orderOut(nil); continue }
            let panel = panels[config.id] ?? makePanel(for: config)
            panels[config.id] = panel
            panel.level = config.style.alwaysOnTop ? .floating : .normal
            panel.appearance = NSAppearance(named: config.style.prefersDarkAppearance ? .darkAqua : .aqua)
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    private func makePanel(for config: FloatingWindowConfig) -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
                        styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: FloatingView(store: store, windowId: config.id) { [weak p] size in
            // Grow/shrink with the content while keeping the top-left corner fixed.
            guard let p, size.width > 0, size.height > 0 else { return }
            var frame = p.frame
            frame.origin.y += frame.height - size.height
            frame.size = size
            p.setFrame(frame, display: true)
        })
        let name = "VRMFloating-\(config.id.uuidString)"
        p.setFrameAutosaveName(name)
        if !p.setFrameUsingName(name), let screen = NSScreen.main {
            // Cascade new windows so they don't stack exactly.
            let offset = CGFloat(panels.count) * 36
            p.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - 260 - offset, y: screen.visibleFrame.maxY - 40 - offset))
        }
        return p
    }
}

/// The panel's root view: looks up its config, reports size changes, adds the context menu.
struct FloatingView: View {
    let store: MetricStore
    let windowId: UUID
    var onSizeChange: (CGSize) -> Void = { _ in }

    var body: some View {
        if let config = store.displays.windows.first(where: { $0.id == windowId }) {
            FloatingContent(store: store, config: config, hoverable: true)
                .onGeometryChange(for: CGSize.self, of: { $0.size }, action: onSizeChange)
                .opacity(store.isStale ? 0.6 : 1)
                .contextMenu {
                    Button("Settings…") { AppActions.openSettings() }
                    Button("Refresh") { store.refreshNow() }
                    Divider()
                    Button("Hide This Window") {
                        if let i = store.displays.windows.firstIndex(where: { $0.id == windowId }) {
                            store.displays.windows[i].isVisible = false
                        }
                    }
                    Button("Quit") { NSApp.terminate(nil) }
                }
        }
    }
}

/// Renders a window's items in its style. Shared by the panel and the settings preview.
struct FloatingContent: View {
    let store: MetricStore
    let config: FloatingWindowConfig
    /// Preview mode shows sample values when a window has no items.
    var placeholder = false
    /// Real floating windows show the history popup while a row is hovered.
    var hoverable = false

    private var style: FloatingStyle { config.style }
    private var s: Double { style.scale }

    private struct Row: Identifiable {
        let id: UUID
        let title: String
        let value: String
        var isHero = false
    }

    private var rows: [Row] {
        // The settings preview (not hoverable) shows every value so it can be styled while idle.
        let all = store.displays.items(in: config)
        let items = hoverable ? store.activeItems(all) : all
        if items.isEmpty && placeholder {
            return [Row(id: UUID(), title: "Battery", value: "87 %"), Row(id: UUID(), title: "Solar", value: "1 240 W"),
                    Row(id: UUID(), title: "Consumption", value: "630 W")]
        }
        return items.map {
            Row(id: $0.id, title: $0.title(in: store), value: store.metric(for: $0)?.formatted ?? "…", isHero: $0.isHero == true)
        }
    }

    /// Hero layout: the value flagged as hero comes first; without a flag, the first one.
    private var heroOrdered: [Row] {
        guard let i = rows.firstIndex(where: \.isHero) else { return rows }
        var r = rows
        r.insert(r.remove(at: i), at: 0)
        return r
    }

    private var valueColor: Color { style.textColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            switch style.layout {
            case .list: list
            case .tiles: tiles
            case .hero: hero
            }
            if case .error = store.status {
                Label("Update failed", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10 * s, design: style.typeface.design)).foregroundStyle(.orange)
            }
        }
        .padding(14 * s)
        .frame(minWidth: 150 * s)
        .background { FloatingBackground(style: style) }
        .fixedSize()
    }

    /// Tracks the mouse over a row and asks the store to show its history.
    private func hoverable(_ row: Row) -> some ViewModifier {
        HoverRow(store: store, enabled: hoverable, target: HoverTarget(item: row.id, source: .window(config.id)))
    }

    private func label(_ text: String, size: Double = 11) -> some View {
        Text(text).font(.system(size: size * s, weight: .medium, design: style.typeface.design))
            .foregroundStyle(valueColor.opacity(0.68)).lineLimit(1)
    }

    private func value(_ text: String, size: Double) -> some View {
        Text(text).font(.system(size: size * s, weight: .semibold, design: style.typeface.design))
            .monospacedDigit().foregroundStyle(valueColor).lineLimit(1)
            .shadow(color: style.material == .neon ? style.tint.color.opacity(0.8) : .clear, radius: 6)
    }

    private var list: some View {
        ForEach(rows) { row in
            HStack(alignment: .firstTextBaseline, spacing: 14 * s) {
                if style.showLabels { label(row.title) }
                Spacer(minLength: 0)
                value(row.value, size: 20)
            }
            .modifier(hoverable(row))
        }
    }

    private var tiles: some View {
        let chunks = stride(from: 0, to: rows.count, by: 2).map { Array(rows[$0 ..< min($0 + 2, rows.count)]) }
        return VStack(spacing: 8 * s) {
            ForEach(chunks, id: \.first?.id) { chunk in
                HStack(spacing: 8 * s) {
                    ForEach(chunk) { row in
                        VStack(alignment: .leading, spacing: 2 * s) {
                            if style.showLabels { label(row.title, size: 10) }
                            value(row.value, size: 22)
                        }
                        .frame(minWidth: 84 * s, alignment: .leading)
                        .padding(10 * s)
                        .background(style.tint.color.opacity(0.14), in: RoundedRectangle(cornerRadius: style.cornerRadius * 0.55, style: .continuous))
                        .modifier(hoverable(row))
                    }
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            let ordered = heroOrdered
            if let first = ordered.first {
                VStack(alignment: .leading, spacing: 0) {
                    if style.showLabels { label(first.title, size: 12) }
                    value(first.value, size: 44)
                }
                .modifier(hoverable(first))
                if ordered.count > 1 {
                    let columns = max(style.heroColumns, 1)
                    let rest = Array(ordered.dropFirst())
                    let chunks = stride(from: 0, to: rest.count, by: columns).map { Array(rest[$0 ..< min($0 + columns, rest.count)]) }
                    // A Grid keeps each column's left edge aligned across rows.
                    Grid(alignment: .leading, horizontalSpacing: 16 * s, verticalSpacing: 8 * s) {
                        ForEach(chunks, id: \.first?.id) { chunk in
                            GridRow {
                                ForEach(chunk) { row in
                                    VStack(alignment: .leading, spacing: 0) {
                                        if style.showLabels { label(row.title, size: 9) }
                                        value(row.value, size: 15)
                                    }
                                    .modifier(hoverable(row))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct FloatingBackground: View {
    let style: FloatingStyle

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        let tint = style.tint.color
        Group {
            switch style.material {
            case .glass:
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.regular.tint(tint.opacity(0.2)), in: shape)
                } else {
                    shape.fill(.ultraThinMaterial).overlay(shape.fill(tint.opacity(0.12)))
                        .overlay(shape.strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                }
            case .frosted:
                shape.fill(.regularMaterial)
            case .solid:
                shape.fill(Color.black.opacity(0.75)).overlay(shape.fill(tint.opacity(0.35)))
            case .neon:
                shape.fill(Color.black.opacity(0.88))
                    .overlay(shape.strokeBorder(tint, lineWidth: 1.5))
                    .overlay(shape.strokeBorder(tint, lineWidth: 3).blur(radius: 5).clipShape(shape))
            }
        }
        .opacity(style.opacity)
    }
}
