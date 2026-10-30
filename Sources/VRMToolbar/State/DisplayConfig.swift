import AppKit
import Foundation
import Observation
import SwiftUI

enum DisplayTarget: String, Codable, CaseIterable, Identifiable {
    case menuBar, dock, floating
    var id: String { rawValue }
    var title: String {
        switch self {
        case .menuBar: "Menu bar"
        case .dock: "Dock icon"
        case .floating: "Floating window"
        }
    }
    var symbol: String {
        switch self {
        case .menuBar: "menubar.rectangle"
        case .dock: "dock.rectangle"
        case .floating: "macwindow"
        }
    }
}

struct DisplayItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var target: DisplayTarget = .menuBar
    var installationId: Int
    var metricKey: String
    var label: String = ""
    /// Fallback name shown before the first poll completes.
    var metricName: String = ""
    var symbol: String = ""   // optional SF Symbol name (menu bar)
    /// Optional unit shown instead of whatever VRM provides (e.g. "%" for a tank level).
    var unit: String?
    /// In a floating window with the Hero layout, this value is the big one.
    var isHero: Bool?
    /// Show this display only while the value is above `idleThreshold` (e.g. shore power / AC input).
    var hideWhenIdle: Bool?
    var idleThreshold: Double?
    /// Which floating window shows this item (nil → the first window).
    var windowId: UUID?
}

// MARK: - Floating window styling

struct RGBA: Codable, Hashable {
    var r: Double, g: Double, b: Double, a: Double = 1

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent, a: ns.alphaComponent)
    }

    static let electric = RGBA(r: 0.25, g: 0.78, b: 1.0)
}

struct FloatingStyle: Codable, Hashable {
    enum Material: String, Codable, CaseIterable, Identifiable {
        case glass, frosted, solid, neon
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }
    enum Layout: String, Codable, CaseIterable, Identifiable {
        case list, tiles, hero
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }
    enum Typeface: String, Codable, CaseIterable, Identifiable {
        case rounded, standard, monospaced, serif
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var design: Font.Design {
            switch self {
            case .rounded: .rounded
            case .standard: .default
            case .monospaced: .monospaced
            case .serif: .serif
            }
        }
    }

    var material: Material = .glass
    var layout: Layout = .list
    var typeface: Typeface = .rounded
    var tint: RGBA = .electric
    /// Background opacity (0.1 – 1).
    var opacity: Double = 1
    var cornerRadius: Double = 22
    /// Overall size multiplier.
    var scale: Double = 1
    var showLabels = true
    var alwaysOnTop = true
    var textMode: TextMode = .auto
    var customText: RGBA = RGBA(r: 1, g: 1, b: 1)
    /// Hero layout: how many secondary values share a row before a new row starts.
    var heroColumns = 3

    enum TextMode: String, Codable, CaseIterable, Identifiable {
        case auto, light, dark, accent, custom
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    init() {}

    // Tolerant decoding: styles saved by older versions lack newer keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        material = try c.decodeIfPresent(Material.self, forKey: .material) ?? material
        layout = try c.decodeIfPresent(Layout.self, forKey: .layout) ?? layout
        typeface = try c.decodeIfPresent(Typeface.self, forKey: .typeface) ?? typeface
        tint = try c.decodeIfPresent(RGBA.self, forKey: .tint) ?? tint
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? opacity
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? cornerRadius
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? scale
        showLabels = try c.decodeIfPresent(Bool.self, forKey: .showLabels) ?? showLabels
        alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? alwaysOnTop
        textMode = try c.decodeIfPresent(TextMode.self, forKey: .textMode) ?? textMode
        customText = try c.decodeIfPresent(RGBA.self, forKey: .customText) ?? customText
        heroColumns = try c.decodeIfPresent(Int.self, forKey: .heroColumns) ?? heroColumns
    }

    /// Text colour for this style; `.auto` is near-white with a hint of the accent.
    var textColor: Color {
        switch textMode {
        case .auto: material == .neon ? tint.color : RGBA(r: 0.8 + 0.2 * tint.r, g: 0.8 + 0.2 * tint.g, b: 0.8 + 0.2 * tint.b).color
        case .light: .white
        case .dark: .black
        case .accent: tint.color
        case .custom: customText.color
        }
    }

    /// Dark text needs the light variant of materials underneath it.
    var prefersDarkAppearance: Bool { textMode != .dark }
}

struct FloatingWindowConfig: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var isVisible = true
    var style = FloatingStyle()
}

// MARK: - Store

@Observable
final class DisplayStore {
    var items: [DisplayItem] { didSet { save() } }
    var windows: [FloatingWindowConfig] { didSet { save() } }
    var refreshInterval: TimeInterval { didSet { UserDefaults.standard.set(refreshInterval, forKey: Self.intervalKey) } }

    private static let itemsKey = "displays.v1"
    private static let windowsKey = "floatingWindows.v1"
    private static let intervalKey = "refreshInterval"
    private static let legacyOpacityKey = "floatingOpacity"

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.itemsKey),
           let items = try? JSONDecoder().decode([DisplayItem].self, from: data) {
            self.items = items
        } else {
            self.items = []
        }
        if let data = defaults.data(forKey: Self.windowsKey),
           let windows = try? JSONDecoder().decode([FloatingWindowConfig].self, from: data), !windows.isEmpty {
            self.windows = windows
        } else {
            // First run with windows: carry over the old single-window opacity.
            var first = FloatingWindowConfig(name: "Window 1")
            if let o = defaults.object(forKey: Self.legacyOpacityKey) as? Double { first.style.opacity = min(max(o, 0.1), 1) }
            self.windows = [first]
        }
        let i = defaults.double(forKey: Self.intervalKey)
        refreshInterval = i == 0 ? 60 : min(max(i, 30), 600)
    }

    func items(for target: DisplayTarget) -> [DisplayItem] { items.filter { $0.target == target } }

    /// Floating items belonging to `window`; unassigned items fall to the first window.
    func items(in window: FloatingWindowConfig) -> [DisplayItem] {
        let ids = Set(windows.map(\.id))
        return items.filter { item in
            guard item.target == .floating else { return false }
            if let w = item.windowId, ids.contains(w) { return w == window.id }
            return window.id == windows.first?.id
        }
    }

    /// Items are ordered within the place they appear: menu bar, Dock, or one floating window.
    func groupKey(_ item: DisplayItem) -> String {
        guard item.target == .floating else { return item.target.rawValue }
        if let w = item.windowId, windows.contains(where: { $0.id == w }) { return w.uuidString }
        return windows.first?.id.uuidString ?? "floating"
    }

    /// Moves an item one step up (-1) or down (+1) among the items of its group.
    func move(_ id: UUID, by offset: Int) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let key = groupKey(items[i])
        let siblings = items.indices.filter { groupKey(items[$0]) == key }
        guard let pos = siblings.firstIndex(of: i), siblings.indices.contains(pos + offset) else { return }
        items.swapAt(i, siblings[pos + offset])
    }

    /// Drag & drop: puts `id` where `target` is (before it when moving up, after it when moving down).
    func move(_ id: UUID, onto target: UUID) {
        guard id != target,
              let from = items.firstIndex(where: { $0.id == id }),
              let to = items.firstIndex(where: { $0.id == target }),
              groupKey(items[from]) == groupKey(items[to]) else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)   // `to` still points at the right slot: removing earlier shifts, inserting restores
    }

    func moveWindow(_ id: UUID, by offset: Int) {
        guard let i = windows.firstIndex(where: { $0.id == id }), windows.indices.contains(i + offset) else { return }
        windows.swapAt(i, i + offset)
    }

    func moveWindow(_ id: UUID, onto target: UUID) {
        guard id != target,
              let from = windows.firstIndex(where: { $0.id == id }),
              let to = windows.firstIndex(where: { $0.id == target }) else { return }
        let w = windows.remove(at: from)
        windows.insert(w, at: to)
    }

    @discardableResult
    func addWindow() -> FloatingWindowConfig {
        var w = FloatingWindowConfig(name: "Window \(windows.count + 1)")
        w.style.tint = [RGBA.electric, RGBA(r: 1, g: 0.78, b: 0.2), RGBA(r: 0.3, g: 0.9, b: 0.55), RGBA(r: 1, g: 0.4, b: 0.6)][windows.count % 4]
        windows.append(w)
        return w
    }

    func removeWindow(_ id: UUID) {
        guard windows.count > 1 else { return }
        // Items of the removed window move to the first remaining window.
        let fallback = windows.first { $0.id != id }?.id
        for i in items.indices where items[i].windowId == id { items[i].windowId = fallback }
        windows.removeAll { $0.id == id }
    }

    private func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: Self.itemsKey) }
        if let data = try? JSONEncoder().encode(windows) { defaults.set(data, forKey: Self.windowsKey) }
    }
}
