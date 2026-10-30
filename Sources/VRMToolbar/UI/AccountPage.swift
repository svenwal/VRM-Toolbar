import SwiftUI

struct AccountPage: View {
    let store: MetricStore
    enum Mode: String, CaseIterable { case token = "Access token", password = "Email & password" }
    @State private var mode: Mode = .token
    @State private var token = ""
    @State private var username = ""
    @State private var password = ""
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Account", subtitle: "Connect to your Victron VRM portal")
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented).labelsHidden()
                switch mode {
                case .token:
                    SecureField("Access token", text: $token).textFieldStyle(.roundedBorder)
                    Text("Create one in VRM › Preferences › Integrations. Works with 2FA and enables the live stream.")
                        .font(.caption).foregroundStyle(.secondary)
                case .password:
                    TextField("Email", text: $username).textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
                    Text("Accounts with two-factor authentication must use an access token.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Sign in") { Task { await signIn() } }.glassButton(prominent: true).disabled(busy || !valid)
                    Button("Sign out") {
                        AuthStore.clear()
                        Task { await store.configure(nil) }
                        message = "Signed out."
                    }.glassButton()
                    if busy { ProgressView().controlSize(.small) }
                }
                if let message { Text(message).font(.callout) }
            }
            .padding(20).glassCard()

            VStack(alignment: .leading, spacing: 8) {
                Label("Connection", systemImage: "antenna.radiowaves.left.and.right").font(.headline)
                Text(statusText).font(.callout).foregroundStyle(.secondary)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading).glassCard()
        }
        .onAppear {
            switch AuthStore.load() {
            case .token(let t): mode = .token; token = t
            case .password(let u, let p): mode = .password; username = u; password = p
            case nil: break
            }
        }
    }

    private var valid: Bool {
        mode == .token ? !token.trimmingCharacters(in: .whitespaces).isEmpty : !username.isEmpty && !password.isEmpty
    }

    private var statusText: String {
        switch store.status {
        case .notConfigured: "Not signed in."
        case .idle: "Connecting…"
        case .ok:
            "Connected – \(store.installations.count) installation(s). "
                + (store.streaming.isEmpty ? "Live stream: " + (store.streamError ?? "connecting…") : "Live stream: on.")
        case .error(let m): "Error: \(m)"
        }
    }

    private func signIn() async {
        busy = true; defer { busy = false }
        let creds: Credentials = mode == .token
            ? .token(token.trimmingCharacters(in: .whitespacesAndNewlines))
            : .password(username: username, password: password)
        do {
            let sites = try await store.test(creds)
            AuthStore.save(creds)
            await store.configure(creds)
            message = "Signed in – found \(sites.count) installation(s)."
        } catch {
            message = error.localizedDescription
        }
    }
}
