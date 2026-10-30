import XCTest
@testable import VRMToolbar

final class MQTTTests: XCTestCase {
    func testConnectEncoding() {
        let d = [UInt8](MQTTEncoder.connect(clientId: "c", username: "u", password: "p", keepAlive: 60))
        XCTAssertEqual(d[0], 0x10)
        XCTAssertEqual(Array(d[2...9]), [0, 4, 0x4D, 0x51, 0x54, 0x54, 4, 0xC2])
        XCTAssertEqual(Int(d[1]), d.count - 2)
    }

    func testParserHandlesSplitAndJoinedPackets() {
        let pub = MQTTEncoder.publish(topic: "N/abc/system/0/Dc/Battery/Soc", payload: Data(#"{"value":85}"#.utf8))
        var p = MQTTParser()
        let half = pub.count / 2
        XCTAssertTrue(p.feed(pub.prefix(half)).isEmpty)
        let rest = p.feed(pub.suffix(from: half) + Data([0xD0, 0]) + Data([0x20, 2, 0, 0]))
        XCTAssertEqual(rest.count, 3)
        guard case .publish(let topic, let payload, _) = rest[0] else { return XCTFail() }
        XCTAssertEqual(topic, "N/abc/system/0/Dc/Battery/Soc")
        XCTAssertEqual(String(decoding: payload, as: UTF8.self), #"{"value":85}"#)
        guard case .connack(let code) = rest[2] else { return XCTFail() }
        XCTAssertEqual(code, 0)
    }

    func testLargeRemainingLength() {
        let payload = Data(repeating: 0x41, count: 300)
        var p = MQTTParser()
        let out = p.feed(MQTTEncoder.publish(topic: "t", payload: payload))
        guard case .publish(_, let got, _) = out.first else { return XCTFail() }
        XCTAssertEqual(got.count, 300)
    }

    func testShardMatchesDocumentedFormula() {
        XCTAssertEqual(LiveTopics.shard(for: "abc"), (97 + 98 + 99) % 128)
    }

    func testTopicParsingAndFormatting() {
        let m = LiveTopics.parse(topic: "N/abc/system/0/Dc/Battery/Soc", payload: Data(#"{"value":85}"#.utf8), portal: "abc")
        XCTAssertEqual(m?.path, "system/0/Dc/Battery/Soc")
        XCTAssertEqual(m?.metric?.formatted, "85 %")  // whole numbers carry no decimals in any locale
        let p = LiveTopics.parse(topic: "N/abc/system/0/Dc/Pv/Power", payload: Data(#"{"value":936.4}"#.utf8), portal: "abc")
        XCTAssertEqual(p?.metric?.formatted, "936 W")
        XCTAssertNil(LiveTopics.parse(topic: "N/abc/full_publish_completed", payload: Data(#"{"value":1}"#.utf8), portal: "abc"))
        XCTAssertNil(LiveTopics.parse(topic: "N/abc/system/0/X/Y", payload: Data(#"{"value":null}"#.utf8), portal: "abc")?.metric)
    }

    func testDiagnosticLivePath() throws {
        let json = #"{"records":[{"code":"bs","description":"SOC","instance":512,"dbusServiceType":"battery","dbusPath":"/Soc"}]}"#
        let r = try JSONDecoder().decode(DiagnosticsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.records[0].livePath, "battery/512/Soc")
    }
}
