import ServiceManagement
import SwiftUI

struct GeneralPage: View {
    @Bindable var displays: DisplayStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "General")
            VStack(alignment: .leading, spacing: 16) {
                Picker("Refresh every", selection: $displays.refreshInterval) {
                    ForEach([30.0, 60, 120, 300, 600], id: \.self) { s in
                        Text(s < 60 ? "\(Int(s)) seconds" : "\(Int(s / 60)) minute(s)").tag(s)
                    }
                }
                Text("Applies to polling. Streamed values update instantly; polling then only refreshes the list of available values.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                Text("The Dock icon appears only while at least one display targets the Dock.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading).glassCard()
        }
    }
}
