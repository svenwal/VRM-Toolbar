import Foundation

/// Streams one installation's values from the VRM MQTT broker and reconnects on failure.
@MainActor
final class LiveStream {
    let installation: Installation
    private let credentials: () async throws -> (username: String, password: String)
    private let onValue: (_ path: String, _ metric: Metric?) -> Void
    private let onState: (_ connected: Bool, _ error: String?) -> Void
    private var task: Task<Void, Never>?

    init(installation: Installation,
         credentials: @escaping () async throws -> (username: String, password: String),
         onValue: @escaping (String, Metric?) -> Void,
         onState: @escaping (Bool, String?) -> Void) {
        self.installation = installation
        self.credentials = credentials
        self.onValue = onValue
        self.onState = onState
    }

    var canStream: Bool { installation.identifier != nil }

    func start() {
        guard task == nil, canStream else { return }
        task = Task { [weak self] in await self?.loop() }
    }

    func stop() {
        task?.cancel()
        task = nil
        onState(false, nil)
    }

    private func loop() async {
        guard let portal = installation.identifier else { return }
        var delay: TimeInterval = 5
        while !Task.isCancelled {
            let client = MQTTClient()
            var keepalive: Task<Void, Never>?
            do {
                let (user, pass) = try await credentials()
                try await client.run(
                    url: LiveTopics.webSocketURL(for: installation),
                    clientId: "vrmtoolbar-\(UUID().uuidString.prefix(8))",
                    username: user, password: pass,
                    onConnected: { [weak self] in
                        client.subscribe("N/\(portal)/#")
                        client.publish(topic: "R/\(portal)/keepalive")
                        keepalive = Task {
                            let options = Data(#"{"keepalive-options":["suppress-republish"]}"#.utf8)
                            while !Task.isCancelled {
                                try? await Task.sleep(for: .seconds(30))
                                client.publish(topic: "R/\(portal)/keepalive", payload: options)
                            }
                        }
                        delay = 5
                        self?.onState(true, nil)
                    },
                    onMessage: { [weak self] topic, payload in
                        guard let (path, metric) = LiveTopics.parse(topic: topic, payload: payload, portal: portal) else { return }
                        self?.onValue(path, metric)
                    })
            } catch is CancellationError {
                keepalive?.cancel()
                return
            } catch {
                onState(false, error.localizedDescription)
            }
            keepalive?.cancel()
            onState(false, nil)
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * 2, 120)
        }
    }
}

enum LiveTopics {
    /// Sum of the portal ID's character codes mod 128 selects the broker.
    static func shard(for portalId: String) -> Int {
        portalId.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 128
    }

    static func webSocketURL(for installation: Installation) -> URL {
        let host = installation.mqttWebHost
            ?? "webmqtt\(shard(for: installation.identifier ?? "")).victronenergy.com"
        return URL(string: "wss://\(host)/mqtt")!
    }

    /// `N/<portal>/<service>/<instance>/<path>` + `{"value": x}` → ("service/instance/path", Metric).
    /// A nil metric means the value went away.
    static func parse(topic: String, payload: Data, portal: String) -> (path: String, metric: Metric?)? {
        let prefix = "N/\(portal)/"
        guard topic.hasPrefix(prefix) else { return nil }
        let path = String(topic.dropFirst(prefix.count))
        guard path.split(separator: "/").count >= 3 else { return nil }  // skips e.g. full_publish_completed
        guard !payload.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let value = obj["value"], !(value is NSNull) else { return (path, nil) }
        let raw = (value as? NSNumber).flatMap { $0 === kCFBooleanTrue || $0 === kCFBooleanFalse ? nil : $0.doubleValue }
        let text = raw.map { format($0, path: path) } ?? (value as? String) ?? "–"
        return (path, Metric(name: displayName(path), formatted: text, raw: raw))
    }

    static func displayName(_ path: String) -> String {
        let parts = path.split(separator: "/", maxSplits: 2).map(String.init)
        return parts.count == 3 ? "\(parts[2]) (\(parts[0])/\(parts[1]))" : path
    }

    static func format(_ v: Double, path: String) -> String {
        let leaf = path.split(separator: "/").last.map(String.init) ?? ""
        let unit: String
        let digits: Int
        switch leaf {
        case "Soc", "Soh": (unit, digits) = ("%", 1)
        case "Power", "P": (unit, digits) = ("W", 0)
        case "Voltage", "V": (unit, digits) = ("V", 2)
        case "Current", "I": (unit, digits) = ("A", 1)
        case "Temperature": (unit, digits) = ("°C", 1)
        case "Frequency": (unit, digits) = ("Hz", 1)
        default: (unit, digits) = ("", v == v.rounded() ? 0 : 2)
        }
        let number = v.formatted(.number.precision(.fractionLength(0 ... digits)).grouping(.never))
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}
