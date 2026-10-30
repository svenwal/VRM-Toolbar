import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case overview, account, displays, windows, general
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .account: "Account"
        case .displays: "Displays"
        case .windows: "Windows"
        case .general: "General"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "bolt.fill"
        case .account: "person.crop.circle"
        case .displays: "gauge.with.dots.needle.67percent"
        case .windows: "macwindow.on.rectangle"
        case .general: "gearshape"
        }
    }
}

/// Glass sidebar floating over an aurora that shifts mood with the battery level.
struct RootView: View {
    let model: AppModel
    @State private var page: Page = .overview
    @Namespace private var selection

    private var store: MetricStore { model.store }

    var body: some View {
        ZStack {
            AuroraBackground(level: store.batteryLevel)
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 200)
                    .padding(.leading, 12).padding(.vertical, 12)
                ScrollView {
                    Group {
                        switch page {
                        case .overview: OverviewPage(store: store, go: { page = $0 })
                        case .account: AccountPage(store: store)
                        case .displays: DisplaysPage(store: store, displays: model.displays)
                        case .windows: WindowsPage(store: store, displays: model.displays)
                        case .general: GeneralPage(displays: model.displays)
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 44).padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(minWidth: 860, minHeight: 600)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 28, height: 28)
                    .background(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .orange.opacity(0.6), radius: 6)
                VStack(alignment: .leading, spacing: 0) {
                    Text("VRM Toolbar").font(.system(size: 13, weight: .bold, design: .rounded))
                    HStack(spacing: 4) {
                        Circle().fill(statusColor).frame(width: 6, height: 6)
                        Text(statusText).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 34).padding(.bottom, 14).padding(.horizontal, 6)

            ForEach(Page.allCases) { p in
                Button { withAnimation(.smooth(duration: 0.25)) { page = p } } label: {
                    Label(p.title, systemImage: p.symbol)
                        .font(.system(size: 13, weight: page == p ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .background {
                            if page == p {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.white.opacity(0.14))
                                    .matchedGeometryEffect(id: "sel", in: selection)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Live updates via MQTT").font(.system(size: 10)).foregroundStyle(.tertiary).padding(6)
        }
        .padding(8)
        .glassCard(radius: 26)
    }

    private var statusColor: Color {
        switch store.status {
        case .ok: store.streaming.isEmpty ? .yellow : .green
        case .error: .red
        default: .gray
        }
    }

    private var statusText: String {
        switch store.status {
        case .ok: store.streaming.isEmpty ? "Polling" : "Live"
        case .error: "Error"
        case .idle: "Connecting"
        case .notConfigured: "Signed out"
        }
    }
}

/// Settings window shown from the menu, Dock or floating window.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = false  // would swallow drag & drop in the lists; the title bar still moves the window
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 860, height: 600)
            w.contentView = NSHostingView(rootView: RootView(model: AppModel.shared))
            if !w.setFrameUsingName("VRMToolbarMain") { w.center() }
            w.setFrameAutosaveName("VRMToolbarMain")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
