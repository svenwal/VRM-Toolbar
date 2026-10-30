import SwiftUI

struct DisplaysPage: View {
    let store: MetricStore
    @Bindable var displays: DisplayStore
    @State private var selection: DisplayItem.ID?
    @State private var collapsed: Set<String> = []
    @State private var dragging: UUID?
    @State private var rowFrames: [UUID: CGRect] = [:]

    private struct ItemGroup: Identifiable {
        let id: String
        let title: String
        let symbol: String
        var tint: Color?
        let items: [DisplayItem]
    }

    /// Items grouped by where they appear: menu bar, Dock, and each floating window.
    private var groups: [ItemGroup] {
        var result: [ItemGroup] = []
        let bar = displays.items(for: .menuBar)
        if !bar.isEmpty { result.append(ItemGroup(id: "menuBar", title: "Menu bar", symbol: DisplayTarget.menuBar.symbol, items: bar)) }
        let dock = displays.items(for: .dock)
        if !dock.isEmpty { result.append(ItemGroup(id: "dock", title: "Dock icon", symbol: DisplayTarget.dock.symbol, items: dock)) }
        for w in displays.windows {
            let items = displays.items(in: w)
            if !items.isEmpty {
                result.append(ItemGroup(id: w.id.uuidString, title: w.name, symbol: DisplayTarget.floating.symbol, tint: w.style.tint.color, items: items))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Displays", subtitle: "Each display shows one value in the menu bar, Dock or a floating window")
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 8) {
                    Button { add() } label: { Label("Add display", systemImage: "plus").frame(maxWidth: .infinity) }
                        .glassButton(prominent: true).disabled(store.installations.isEmpty)
                        .padding(.bottom, 4)
                    ForEach(groups) { group in
                        let isCollapsed = collapsed.contains(group.id)
                        Button {
                            withAnimation(.smooth(duration: 0.2)) {
                                if isCollapsed { collapsed.remove(group.id) } else { collapsed.insert(group.id) }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                                    .rotationEffect(.degrees(isCollapsed ? 0 : 90)).frame(width: 12)
                                Image(systemName: group.symbol).foregroundStyle(group.tint ?? .secondary)
                                Text(group.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(group.items.count)").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 6).padding(.top, 6).contentShape(Rectangle())
                        }.buttonStyle(.plain)

                        if !isCollapsed {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                DisplayListRow(title: item.title(in: store),
                                               value: store.metric(for: item)?.formatted ?? "…",
                                               isSelected: selection == item.id,
                                               moveUp: index > 0 ? { withAnimation(.smooth(duration: 0.2)) { displays.move(item.id, by: -1) } } : nil,
                                               moveDown: index < group.items.count - 1 ? { withAnimation(.smooth(duration: 0.2)) { displays.move(item.id, by: 1) } } : nil,
                                               isDragged: dragging == item.id,
                                               dragChanged: { location in
                                                   // Swap with whichever row of the same group the pointer is over.
                                                   dragging = item.id
                                                   if let target = group.items.first(where: { $0.id != item.id && rowFrames[$0.id]?.contains(location) == true }) {
                                                       withAnimation(.smooth(duration: 0.18)) { displays.move(item.id, onto: target.id) }
                                                   }
                                               },
                                               dragEnded: { dragging = nil },
                                               select: { selection = item.id },
                                               delete: {
                                                   if selection == item.id { selection = nil }
                                                   displays.items.removeAll { $0.id == item.id }
                                               })
                                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("displaysList")) }) { rowFrames[item.id] = $0 }
                            }
                        }
                    }
                    if displays.items.isEmpty {
                        Text("No displays yet").font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
                    }
                }
                .padding(12).frame(width: 220).glassCard()
                .coordinateSpace(name: "displaysList")

                Group {
                    if let i = displays.items.firstIndex(where: { $0.id == selection }) {
                        DisplayEditor(store: store, displays: displays, item: $displays.items[i])
                    } else {
                        Text("Select or add a display").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding(18).frame(maxWidth: .infinity).glassCard()
            }
        }
    }

    private func add() {
        guard let site = store.installations.first else { return }
        let item = DisplayItem(target: .menuBar, installationId: site.idSite, metricKey: "", symbol: "bolt.fill")
        displays.items.append(item)
        selection = item.id
    }
}

/// One display in the list; a trash button appears while the mouse is over it.
struct DisplayListRow: View {
    let title: String
    let value: String
    let isSelected: Bool
    /// Optional marker in front of the title (e.g. a colour dot).
    var marker: Color? = nil
    var leadingInset: CGFloat = 30
    var canDelete = true
    var space = "displaysList"
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?
    let isDragged: Bool
    let dragChanged: (CGPoint) -> Void
    let dragEnded: () -> Void
    let select: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            if let marker { Circle().fill(marker).frame(width: 10, height: 10) }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).lineLimit(1)
                Text(value).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if hovering {
                VStack(spacing: 0) {
                    arrow("chevron.up", moveUp)
                    arrow("chevron.down", moveDown)
                }
                if canDelete {
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(.red)
                        .frame(width: 24, height: 24).background(.red.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Delete")
                .transition(.opacity)
                }
            }
        }
        .padding(.vertical, 6).padding(.leading, leadingInset).padding(.trailing, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .background(isSelected ? Color.white.opacity(0.14) : hovering ? Color.white.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .opacity(isDragged ? 0.6 : 1)
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named(space))
                .onChanged { dragChanged($0.location) }
                .onEnded { _ in dragEnded() }
        )
    }

    private func arrow(_ symbol: String, _ action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).frame(width: 18, height: 11)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .opacity(action == nil ? 0.25 : 0.9)
        .help(symbol == "chevron.up" ? "Move up" : "Move down")
    }
}

struct DisplayEditor: View {
    let store: MetricStore
    let displays: DisplayStore
    @Binding var item: DisplayItem
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Show in", selection: $item.target) {
                ForEach(DisplayTarget.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if item.target == .floating {
                Picker("Window", selection: Binding(
                    get: { item.windowId ?? displays.windows.first?.id ?? UUID() },
                    set: { item.windowId = $0 })) {
                    ForEach(displays.windows) { Text($0.name).tag($0.id) }
                }
            }
            if item.target == .floating {
                Toggle("Hero value (big one in the Hero layout)", isOn: Binding(
                    get: { item.isHero == true },
                    set: { on in
                        // Only one hero per window.
                        if on, let window = displays.windows.first(where: { $0.id == (item.windowId ?? displays.windows.first?.id) }) {
                            let siblings = Set(displays.items(in: window).map(\.id))
                            for i in displays.items.indices where siblings.contains(displays.items[i].id) { displays.items[i].isHero = nil }
                        }
                        item.isHero = on ? true : nil
                    }))
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Only show while active", isOn: Binding(
                    get: { item.hideWhenIdle == true },
                    set: { item.hideWhenIdle = $0 ? true : nil }))
                if item.hideWhenIdle == true {
                    HStack {
                        Text("Active when above")
                        TextField("0", value: Binding(get: { item.idleThreshold ?? 0 }, set: { item.idleThreshold = $0 == 0 ? nil : $0 }),
                                  format: .number).textFieldStyle(.roundedBorder).frame(width: 70)
                        Text(item.unit ?? "(value's own unit)").foregroundStyle(.secondary)
                    }
                    Text("Hidden whenever the value is at or below this, e.g. shore power while unplugged.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.installations.count > 1 {
                Picker("Installation", selection: $item.installationId) {
                    ForEach(store.installations) { Text($0.name).tag($0.idSite) }
                }
            }
            HStack {
                TextField("Label (optional)", text: $item.label).textFieldStyle(.roundedBorder)
                TextField("Unit", text: Binding(get: { item.unit ?? "" }, set: { item.unit = $0.isEmpty ? nil : $0 }),
                          prompt: Text("e.g. %")).textFieldStyle(.roundedBorder).frame(width: 80)
                    .help("Optional. Replaces the unit VRM reports, e.g. % for a tank level.")
                if item.target == .menuBar {
                    TextField("SF Symbol", text: $item.symbol, prompt: Text("bolt.fill")).textFieldStyle(.roundedBorder).frame(width: 130)
                }
            }
            TextField("Search values — ⚡ marks live-streamed ones", text: $search).textFieldStyle(.roundedBorder)

            let list = store.metricList(for: item.installationId).filter {
                search.isEmpty || $0.metric.name.localizedCaseInsensitiveContains(search)
            }
            List(list, id: \.key, selection: Binding(
                get: { item.metricKey.isEmpty ? nil : item.metricKey },
                set: { (key: String?) in
                    guard let key else { return }
                    var updated = item
                    updated.metricKey = key
                    updated.metricName = store.metricList(for: item.installationId).first { $0.key == key }?.metric.name ?? ""
                    item = updated
                })) { row in
                HStack {
                    Text(row.metric.name).lineLimit(1)
                    Spacer()
                    Text(row.metric.formatted).foregroundStyle(.secondary).monospacedDigit()
                }
                .contentShape(Rectangle())
                .tag(row.key)
            }
            .scrollContentBackground(.hidden)
            .frame(minHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .task(id: item.installationId) { await store.loadMetrics(for: item.installationId) }
    }
}
