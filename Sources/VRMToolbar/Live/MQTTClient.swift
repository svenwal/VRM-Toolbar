import Foundation

enum MQTTError: LocalizedError {
    case refused(UInt8)
    case closed

    var errorDescription: String? {
        switch self {
        case .refused(4), .refused(5): "MQTT login refused (check the access token)."
        case .refused(let c): "MQTT connection refused (code \(c))."
        case .closed: "MQTT connection closed."
        }
    }
}

/// MQTT 3.1.1 over WebSocket. `run` returns/throws when the connection ends.
@MainActor
final class MQTTClient {
    private let session = URLSession(configuration: .ephemeral)
    private var task: URLSessionWebSocketTask?
    private var parser = MQTTParser()
    private var pingTask: Task<Void, Never>?
    private var nextPacketId: UInt16 = 1

    func run(url: URL, clientId: String, username: String, password: String,
             onConnected: @escaping () -> Void,
             onMessage: @escaping (_ topic: String, _ payload: Data) -> Void) async throws {
        let task = session.webSocketTask(with: url, protocols: ["mqtt"])
        self.task = task
        task.resume()
        defer {
            pingTask?.cancel()
            task.cancel(with: .goingAway, reason: nil)
            self.task = nil
        }
        try await send(MQTTEncoder.connect(clientId: clientId, username: username, password: password, keepAlive: 60))
        while true {
            let message = try await task.receive()
            let data: Data
            switch message {
            case .data(let d): data = d
            case .string(let s): data = Data(s.utf8)
            @unknown default: continue
            }
            for packet in parser.feed(data) {
                switch packet {
                case .connack(let code):
                    guard code == 0 else { throw MQTTError.refused(code) }
                    startPing()
                    onConnected()
                case .publish(let topic, let payload, let id):
                    if let id { try? await send(MQTTEncoder.puback(packetId: id)) }
                    onMessage(topic, payload)
                default: break
                }
            }
        }
    }

    func subscribe(_ filter: String) {
        let id = nextPacketId
        nextPacketId = nextPacketId == .max ? 1 : nextPacketId + 1
        Task { try? await send(MQTTEncoder.subscribe(packetId: id, filter: filter)) }
    }

    func publish(topic: String, payload: Data = Data()) {
        Task { try? await send(MQTTEncoder.publish(topic: topic, payload: payload)) }
    }

    private func send(_ data: Data) async throws {
        guard let task else { throw MQTTError.closed }
        try await task.send(.data(data))
    }

    private func startPing() {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                try? await self?.send(MQTTEncoder.pingreq)
            }
        }
    }
}
