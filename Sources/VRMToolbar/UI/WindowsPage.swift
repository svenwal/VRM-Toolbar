import SwiftUI

struct WindowsPage: View {
    let store: MetricStore
    @Bindable var displays: DisplayStore
    @State private var selection: UUID?
    @State private var dragging: UUID?
    @State private var rowFrames: [UUID: CGRect] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Floating windows", subtitle: "Create as many as you like, each with its own look")
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 8) {
                    Button { selection = displays.addWindow().id } label: { Label("New window", systemImage: "plus").frame(maxWidth: .infinity) }
                        .glassButton(prominent: true)
                        .padding(.bottom, 4)
                    ForEach(Array(displays.windows.enumerated()), id: \.element.id) { index, w in
                        let count = displays.items(in: w).count
                        DisplayListRow(title: w.name,
                                       value: "\(count) value(s)" + (w.isVisible ? "" : " · hidden"),
                                       isSelected: selection == w.id,
                                       marker: w.style.tint.color,
                                       leadingInset: 8,
                                       canDelete: displays.windows.count > 1,
                                       space: "windowsList",
                                       moveUp: index > 0 ? { withAnimation(.smooth(duration: 0.2)) { displays.moveWindow(w.id, by: -1) } } : nil,
                                       moveDown: index < displays.windows.count - 1 ? { withAnimation(.smooth(duration: 0.2)) { displays.moveWindow(w.id, by: 1) } } : nil,
                                       isDragged: dragging == w.id,
                                       dragChanged: { location in
                                           dragging = w.id
                                           if let target = displays.windows.first(where: { $0.id != w.id && rowFrames[$0.id]?.contains(location) == true }) {
                                               withAnimation(.smooth(duration: 0.18)) { displays.moveWindow(w.id, onto: target.id) }
                                           }
                                       },
                                       dragEnded: { dragging = nil },
                                       select: { selection = w.id },
                                       delete: {
                                           if selection == w.id { selection = nil }
                                           displays.removeWindow(w.id)
                                       })
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("windowsList")) }) { rowFrames[w.id] = $0 }
                    }
                }
                .padding(12).frame(width: 220).glassCard()
                .coordinateSpace(name: "windowsList")

                Group {
                    if let i = displays.windows.firstIndex(where: { $0.id == selection }) {
                        WindowEditor(store: store, config: $displays.windows[i])
                    } else {
                        Text("Select a window to style it").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding(18).frame(maxWidth: .infinity).glassCard()
            }
        }
        .onAppear { selection = selection ?? displays.windows.first?.id }
    }
}

struct WindowEditor: View {
    let store: MetricStore
    @Binding var config: FloatingWindowConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Name", text: $config.name).textFieldStyle(.roundedBorder)
                Toggle("Visible", isOn: $config.isVisible).toggleStyle(.switch)
            }

            // Live preview on a checkerboard-ish backdrop so transparency is visible.
            ZStack {
                LinearGradient(colors: [Color(red: 0.1, green: 0.2, blue: 0.5), Color(red: 0.55, green: 0.2, blue: 0.5), Color(red: 0.9, green: 0.5, blue: 0.2)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                FloatingContent(store: store, config: config, placeholder: true)
            }
            .frame(height: 190).frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Picker("Material", selection: $config.style.material) { ForEach(FloatingStyle.Material.allCases) { Text($0.title).tag($0) } }
                .pickerStyle(.segmented)
            Picker("Layout", selection: $config.style.layout) { ForEach(FloatingStyle.Layout.allCases) { Text($0.title).tag($0) } }
                .pickerStyle(.segmented)
            if config.style.layout == .hero {
                Stepper("Values per row: \(config.style.heroColumns)", value: $config.style.heroColumns, in: 1 ... 8)
            }
            Picker("Typeface", selection: $config.style.typeface) { ForEach(FloatingStyle.Typeface.allCases) { Text($0.title).tag($0) } }
                .pickerStyle(.segmented)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("Accent")
                    ColorPicker("", selection: Binding(get: { config.style.tint.color }, set: { config.style.tint = RGBA($0) }),
                                supportsOpacity: false).labelsHidden()
                }
                GridRow {
                    Text("Text")
                    HStack {
                        Picker("", selection: $config.style.textMode) {
                            ForEach(FloatingStyle.TextMode.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 110)
                        if config.style.textMode == .custom {
                            ColorPicker("", selection: Binding(get: { config.style.customText.color }, set: { config.style.customText = RGBA($0) }),
                                        supportsOpacity: false).labelsHidden()
                        }
                    }
                }
                slider("Opacity", value: $config.style.opacity, range: 0.1 ... 1, percent: true)
                slider("Size", value: $config.style.scale, range: 0.7 ... 2, percent: true)
                slider("Corners", value: $config.style.cornerRadius, range: 0 ... 40, percent: false)
                GridRow {
                    Text("Options")
                    HStack {
                        Toggle("Labels", isOn: $config.style.showLabels)
                        Toggle("Always on top", isOn: $config.style.alwaysOnTop)
                    }
                }
            }
            Text("Assign values to this window under Displays › Show in › Floating window.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, percent: Bool) -> some View {
        GridRow {
            Text(title)
            HStack {
                Slider(value: value, in: range)
                Group {
                    if percent { Text(value.wrappedValue, format: .percent.precision(.fractionLength(0))) }
                    else { Text(Int(value.wrappedValue), format: .number) }
                }
                .monospacedDigit().frame(width: 44, alignment: .trailing)
            }
        }
    }
}
