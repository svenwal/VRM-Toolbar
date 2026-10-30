import Foundation

/// Minimal MQTT 3.1.1 packet encoding/decoding (QoS 0 publish/subscribe is all we need).
enum MQTTPacket {
    case connack(returnCode: UInt8)
    case publish(topic: String, payload: Data, packetId: UInt16?)
    case suback
    case pingresp
    case other(type: UInt8)
}

enum MQTTEncoder {
    static func connect(clientId: String, username: String, password: String, keepAlive: UInt16) -> Data {
        var body = string("MQTT")
        body.append(4)            // protocol level 3.1.1
        body.append(0b1100_0010)  // username, password, clean session
        body.append(contentsOf: [UInt8(keepAlive >> 8), UInt8(keepAlive & 0xFF)])
        body.append(string(clientId))
        body.append(string(username))
        body.append(string(password))
        return packet(0x10, body)
    }

    static func subscribe(packetId: UInt16, filter: String) -> Data {
        var body = Data([UInt8(packetId >> 8), UInt8(packetId & 0xFF)])
        body.append(string(filter))
        body.append(0)  // QoS 0
        return packet(0x82, body)
    }

    static func publish(topic: String, payload: Data) -> Data {
        packet(0x30, string(topic) + payload)
    }

    static func puback(packetId: UInt16) -> Data { Data([0x40, 2, UInt8(packetId >> 8), UInt8(packetId & 0xFF)]) }
    static let pingreq = Data([0xC0, 0])
    static let disconnect = Data([0xE0, 0])

    private static func string(_ s: String) -> Data {
        let b = Array(s.utf8)
        return Data([UInt8(b.count >> 8), UInt8(b.count & 0xFF)]) + b
    }

    private static func packet(_ header: UInt8, _ body: Data) -> Data {
        var out = Data([header])
        var n = body.count
        repeat {
            var byte = UInt8(n % 128)
            n /= 128
            if n > 0 { byte |= 0x80 }
            out.append(byte)
        } while n > 0
        return out + body
    }
}

/// Accumulates stream bytes (WebSocket frames may split or join packets) and yields whole packets.
struct MQTTParser {
    private var buffer = Data()

    mutating func feed(_ data: Data) -> [MQTTPacket] {
        buffer.append(data)
        var packets: [MQTTPacket] = []
        while let (packet, consumed) = parseOne() {
            packets.append(packet)
            buffer = Data(buffer.dropFirst(consumed))
        }
        return packets
    }

    private func parseOne() -> (MQTTPacket, Int)? {
        let b = [UInt8](buffer)
        guard b.count >= 2 else { return nil }
        var length = 0, multiplier = 1, idx = 1
        while true {
            guard idx < b.count else { return nil }
            let byte = b[idx]
            length += Int(byte & 0x7F) * multiplier
            idx += 1
            if byte & 0x80 == 0 { break }
            multiplier *= 128
            if multiplier > 128 * 128 * 128 { return nil }
        }
        guard b.count >= idx + length else { return nil }
        let body = Array(b[idx ..< idx + length])
        let total = idx + length
        let type = b[0] >> 4
        switch type {
        case 2:
            return (.connack(returnCode: body.count >= 2 ? body[1] : 0xFF), total)
        case 3:
            guard body.count >= 2 else { return (.other(type: type), total) }
            let tlen = Int(body[0]) << 8 | Int(body[1])
            guard body.count >= 2 + tlen else { return (.other(type: type), total) }
            let topic = String(decoding: body[2 ..< 2 + tlen], as: UTF8.self)
            var offset = 2 + tlen
            var packetId: UInt16?
            if (b[0] >> 1) & 0x3 > 0, body.count >= offset + 2 {
                packetId = UInt16(body[offset]) << 8 | UInt16(body[offset + 1])
                offset += 2
            }
            return (.publish(topic: topic, payload: Data(body[offset...]), packetId: packetId), total)
        case 9: return (.suback, total)
        case 13: return (.pingresp, total)
        default: return (.other(type: type), total)
        }
    }
}
