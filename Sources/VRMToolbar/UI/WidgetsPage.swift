import SwiftUI

/// Widget sets: named collections of values. Each Notification Center widget is pointed at one set
/// (right-click the widget › Edit Widget). Values are assigned under Displays › Show in › Widget.
struct WidgetsPage: View {
    let store: MetricStore
    @Bindable var displays: DisplayStore
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Widgets", subtitle: "Collect values for Notification Center and desktop widgets")
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 8) {
                    Button { selection = displays.addWidgetSet().id } label: { Label("New widget set", systemImage: "plus").frame(maxWidth: .infinity) }
                        .glassButton(prominent: true)
                        .padding(.bottom, 4)
                    ForEach(Array(displays.widgetSets.enumerated()), id: \.element.id) { index, set in
                        DisplayListRow(title: set.name,
                                       value: "\(displays.items(inWidget: set).count) value(s)",
                                       isSelected: selection == set.id,
                                       leadingInset: 8,
                                       canDelete: displays.widgetSets.count > 1,
                                       space: "widgetsList",
                                       moveUp: index > 0 ? { withAnimation(.smooth(duration: 0.2)) { displays.moveWidgetSet(set.id, by: -1) } } : nil,
                                       moveDown: index < displays.widgetSets.count - 1 ? { withAnimation(.smooth(duration: 0.2)) { displays.moveWidgetSet(set.id, by: 1) } } : nil,
                                       isDragged: false,
                                       dragChanged: { _ in },
                                       dragEnded: {},
                                       select: { selection = set.id },
                                       delete: {
                                           if selection == set.id { selection = nil }
                                           displays.removeWidgetSet(set.id)
                                       })
                    }
                }
                .padding(12).frame(width: 220).glassCard()

                Group {
                    if let i = displays.widgetSets.firstIndex(where: { $0.id == selection }) {
                        WidgetSetEditor(store: store, displays: displays, set: $displays.widgetSets[i])
                    } else {
                        Text("Select a widget set").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding(18).frame(maxWidth: .infinity).glassCard()
            }
        }
        .onAppear { selection = selection ?? displays.widgetSets.first?.id }
    }
}

struct WidgetSetEditor: View {
    let store: MetricStore
    let displays: DisplayStore
    @Binding var set: WidgetSetConfig

    var body: some View {
        let items = displays.items(inWidget: set)
        VStack(alignment: .leading, spacing: 14) {
            TextField("Name", text: $set.name).textFieldStyle(.roundedBorder)
            Text("Values in this set").font(.headline)
            if items.isEmpty {
                Text("Nothing here yet. Add a display and choose Show in › Widget.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        HStack {
                            Text(item.title(in: store)).lineLimit(1)
                            Spacer()
                            Text(store.metric(for: item)?.formatted ?? "…").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.vertical, 7).padding(.horizontal, 10)
                    }
                }
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Text("To show this set, add a VRM Toolbar widget, right-click it, choose Edit Widget and pick “\(set.name)”. Reorder values under Displays.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
