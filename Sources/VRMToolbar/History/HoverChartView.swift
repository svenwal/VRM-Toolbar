import AppKit
import Charts
import SwiftUI

/// Reports mouse enter/exit even when the app or panel isn't active (NSTrackingArea, `.activeAlways`).
struct HoverArea: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let v = TrackingView()
        v.onChange = onChange
        return v
    }

    func updateNSView(_ v: TrackingView, context: Context) { v.onChange = onChange }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
            super.updateTrackingAreas()
        }
        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

enum ValueFormat {
    /// Formats `v` with the same unit as `sample` (e.g. "85 %" → "72 %").
    static func string(_ v: Double, like sample: String) -> String {
        let unit = sample.drop { "0123456789.,-+ \u{202F}\u{00A0}".contains($0) }.trimmingCharacters(in: .whitespaces)
        let digits = abs(v) >= 100 ? 0 : 1
        let n = v.formatted(.number.precision(.fractionLength(0 ... digits)).grouping(.never))
        return unit.isEmpty ? n : "\(n) \(unit)"
    }
}

/// History popup: line chart of the last day (or since launch) with min / max / average.
struct HoverChartView: View {
    let store: MetricStore
    let item: DisplayItem
    let style: FloatingStyle
    var onSize: (CGSize) -> Void = { _ in }

    private var series: [Sample] { store.series(for: item) }
    private var fromVRM: Bool { store.history.hasRemote(store.usableRemoteKey(for: item)) }
    private var loading: Bool { store.remoteKey(for: item).map { store.history.loading.contains($0) } ?? false }

    var body: some View {
        let data = series
        let current = store.metric(for: item)?.formatted ?? "…"
        let text = style.textColor
        let tint = style.tint.color
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title(in: store)).font(.system(size: 12, weight: .medium, design: style.typeface.design))
                    .foregroundStyle(text.opacity(0.7)).lineLimit(1)
                Spacer(minLength: 12)
                Text(current).font(.system(size: 22, weight: .semibold, design: style.typeface.design)).monospacedDigit()
                    .foregroundStyle(text)
            }

            if data.count >= 2, let st = HistoryStore.stats(data) {
                chart(data, st: st, tint: tint, text: text)
                HStack(spacing: 14) {
                    stat("Min", st.min.v, st.min.t, current, text)
                    stat("Avg", st.avg, nil, current, text)
                    stat("Max", st.max.v, st.max.t, current, text)
                }
                Text(fromVRM ? "Last 24 hours · VRM" : "Since the app started")
                    .font(.system(size: 10)).foregroundStyle(text.opacity(0.5))
            } else {
                HStack(spacing: 8) {
                    if loading { ProgressView().controlSize(.small) }
                    Text(loading ? "Loading history…" : "Collecting data – the graph fills while the app runs.")
                        .font(.system(size: 11)).foregroundStyle(text.opacity(0.6))
                }
                .frame(maxWidth: .infinity, minHeight: 90)
            }
        }
        .padding(14)
        .frame(width: 330)
        .background { FloatingBackground(style: style) }
        .fixedSize()
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: onSize)
        .task(id: item.id) { await store.loadHistory(for: item) }
    }

    private func chart(_ data: [Sample], st: SeriesStats, tint: Color, text: Color) -> some View {
        let span = max(st.max.v - st.min.v, abs(st.max.v) * 0.02, 0.5)
        return Chart {
            ForEach(data, id: \.t) { s in
                AreaMark(x: .value("Time", s.t), yStart: .value("Base", st.min.v - span * 0.15), yEnd: .value("Value", s.v))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.4), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", s.t), y: .value("Value", s.v))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            PointMark(x: .value("Time", st.max.t), y: .value("Value", st.max.v)).foregroundStyle(text).symbolSize(28)
            PointMark(x: .value("Time", st.min.t), y: .value("Value", st.min.v)).foregroundStyle(text.opacity(0.6)).symbolSize(28)
        }
        .chartYScale(domain: (st.min.v - span * 0.15) ... (st.max.v + span * 0.15))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(text.opacity(0.1))
                AxisValueLabel(format: .dateTime.hour().minute()).foregroundStyle(text.opacity(0.55))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(text.opacity(0.1))
                if let d = v.as(Double.self) {
                    AxisValueLabel { Text(ValueFormat.string(d, like: store.metric(for: item)?.formatted ?? "")) }
                        .foregroundStyle(text.opacity(0.55))
                }
            }
        }
        .frame(height: 120)
    }

    private func stat(_ title: String, _ value: Double, _ when: Date?, _ sample: String, _ text: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(text.opacity(0.5))
            Text(ValueFormat.string(value, like: sample))
                .font(.system(size: 13, weight: .semibold, design: style.typeface.design)).monospacedDigit().foregroundStyle(text)
            Text(when.map { $0.formatted(date: .omitted, time: .shortened) } ?? " ")
                .font(.system(size: 9)).foregroundStyle(text.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shows the history popup beside the hovered window or menu bar item.
@MainActor
final class HoverChartController {
    private let store: MetricStore
    private let anchorFrame: (HoverTarget.Source) -> NSRect?
    private var panel: NSPanel?

    init(store: MetricStore, anchorFrame: @escaping (HoverTarget.Source) -> NSRect?) {
        self.store = store
        self.anchorFrame = anchorFrame
        observeForever { [weak self] in self?.sync() }
    }

    private func sync() {
        guard let hover = store.hover,
              let item = store.displays.items.first(where: { $0.id == hover.item }),
              let anchor = anchorFrame(hover.source) else {
            panel?.orderOut(nil)
            return
        }
        var style = FloatingStyle()
        if case .window(let id) = hover.source, let w = store.displays.windows.first(where: { $0.id == id }) { style = w.style }
        style.scale = 1

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.appearance = NSAppearance(named: style.prefersDarkAppearance ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: HoverChartView(store: store, item: item, style: style) { [weak self] size in
            self?.place(size: size, anchor: anchor)   // content grew/shrank (history arrived)
        })
        panel.contentView = host
        place(size: host.fittingSize, anchor: anchor)
        panel.orderFrontRegardless()
    }

    private func place(size: CGSize, anchor: NSRect) {
        guard let panel, size.width > 0, size.height > 0 else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? anchor
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - size.height - 8)
        if origin.y < visible.minY { origin.y = anchor.maxY + 8 }              // no room below → above
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return p
    }
}

/// Attaches hover tracking to a row of a floating window.
struct HoverRow: ViewModifier {
    let store: MetricStore
    let enabled: Bool
    let target: HoverTarget

    func body(content: Content) -> some View {
        if enabled {
            content.background(HoverArea { inside in
                if inside { store.hoverEnter(target) } else { store.hoverExit(target) }
            })
        } else {
            content
        }
    }
}
