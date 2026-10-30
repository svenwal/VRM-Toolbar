import XCTest
@testable import VRMToolbar

final class ConfigTests: XCTestCase {
    func testOldStyleAndItemsStillDecode() throws {
        // Saved by a version without textMode / unit.
        let style = #"{"material":"neon","layout":"tiles","opacity":0.5}"#
        let s = try JSONDecoder().decode(FloatingStyle.self, from: Data(style.utf8))
        XCTAssertEqual(s.material, .neon)
        XCTAssertEqual(s.textMode, .auto)
        XCTAssertEqual(s.scale, 1)

        let item = #"{"id":"CD2F5E3E-6A21-4664-94AF-FB249FB34E55","target":"dock","installationId":1,"metricKey":"bs#0","label":"","metricName":"x","symbol":""}"#
        let i = try JSONDecoder().decode(DisplayItem.self, from: Data(item.utf8))
        XCTAssertNil(i.unit)
    }

    @MainActor
    func testUnitOverrideReplacesVRMUnit() {
        let store = MetricStore(displays: DisplayStore())
        var item = DisplayItem(target: .dock, installationId: 1, metricKey: "mqtt:tank/0/Level")
        item.unit = "%"
        store.setLiveForTesting(site: 1, path: "tank/0/Level", Metric(name: "Level", formatted: "42", raw: 42))
        XCTAssertEqual(store.metric(for: item)?.formatted, "42 %")
    }
}

final class HistoryTests: XCTestCase {
    func testStatsParserReadsPairsInSecondsAndMillis() {
        let json = #"{"success":true,"records":{"bs":[[1700000900000,81.5],[1700000000,80],[1700001800,null]]},"totals":{}}"#
        let s = StatsParser.parse(Data(json.utf8), code: "bs")
        XCTAssertEqual(s.map(\.v), [80, 81.5])           // sorted, null dropped
        XCTAssertEqual(s[0].t.timeIntervalSince1970, 1_700_000_000)
        XCTAssertEqual(s[1].t.timeIntervalSince1970, 1_700_000_900)
    }

    func testStatsParserToleratesNoData() {
        XCTAssertTrue(StatsParser.parse(Data(#"{"success":true,"records":false}"#.utf8), code: "bs").isEmpty)
    }

    func testMinMaxAvg() {
        let base = Date()
        let s = [3.0, 9.0, 6.0].enumerated().map { Sample(t: base.addingTimeInterval(Double($0.offset)), v: $0.element) }
        let st = HistoryStore.stats(s)
        XCTAssertEqual(st?.min.v, 3); XCTAssertEqual(st?.max.v, 9); XCTAssertEqual(st?.avg, 6)
    }

    func testUnitFollowsSample() {
        XCTAssertEqual(ValueFormat.string(72, like: "85 %"), "72 %")
        XCTAssertEqual(ValueFormat.string(1234.4, like: "936 W"), "1234 W")
    }

    @MainActor
    func testSeriesAppendsLocalSamplesAfterRemote() {
        let h = HistoryStore()
        h.record("1|x", 5)
        XCTAssertEqual(h.series(localKey: "1|x", remoteKey: nil).map(\.v), [5])
    }
}

final class VisibilityTests: XCTestCase {
    @MainActor
    func testOnlyShowWhileActive() {
        let store = MetricStore(displays: DisplayStore())
        var item = DisplayItem(target: .menuBar, installationId: 1, metricKey: "mqtt:vebus/0/Ac/ActiveIn/P")
        XCTAssertTrue(store.isActive(item))                       // option off → always shown

        item.hideWhenIdle = true
        item.idleThreshold = 10
        store.setLiveForTesting(site: 1, path: "vebus/0/Ac/ActiveIn/P", Metric(name: "AC in", formatted: "4 W", raw: 4))
        XCTAssertFalse(store.isActive(item))                      // at/below threshold → hidden
        store.setLiveForTesting(site: 1, path: "vebus/0/Ac/ActiveIn/P", Metric(name: "AC in", formatted: "850 W", raw: 850))
        XCTAssertTrue(store.isActive(item))
        store.setLiveForTesting(site: 1, path: "vebus/0/Ac/ActiveIn/P", Metric(name: "AC in", formatted: "-850 W", raw: -850))
        XCTAssertTrue(store.isActive(item))                       // feeding back also counts as flowing
    }
}

final class OrderingTests: XCTestCase {
    private func store() -> (DisplayStore, [DisplayItem]) {
        let d = DisplayStore()
        d.items = [
            DisplayItem(target: .menuBar, installationId: 1, metricKey: "a", label: "A"),
            DisplayItem(target: .dock, installationId: 1, metricKey: "x", label: "X"),
            DisplayItem(target: .menuBar, installationId: 1, metricKey: "b", label: "B"),
            DisplayItem(target: .menuBar, installationId: 1, metricKey: "c", label: "C"),
        ]
        return (d, d.items)
    }

    func testMoveByStepStaysInsideGroup() {
        let (d, i) = store()
        d.move(i[0].id, by: 1)                                   // A swaps with B, skipping the dock item
        XCTAssertEqual(d.items(for: .menuBar).map(\.label), ["B", "A", "C"])
        d.move(i[3].id, by: 1)                                   // last stays last
        XCTAssertEqual(d.items(for: .menuBar).map(\.label), ["B", "A", "C"])
        XCTAssertEqual(d.items(for: .dock).map(\.label), ["X"])
    }

    func testDropMovesBeforeOrAfterTarget() {
        let (d, i) = store()
        d.move(i[0].id, onto: i[3].id)                           // A down onto C → after C
        XCTAssertEqual(d.items(for: .menuBar).map(\.label), ["B", "C", "A"])
        d.move(i[3].id, onto: i[2].id)                           // C up onto B → before B
        XCTAssertEqual(d.items(for: .menuBar).map(\.label), ["C", "B", "A"])
        d.move(i[1].id, onto: i[2].id)                           // dock item onto menu bar item: ignored
        XCTAssertEqual(d.items(for: .dock).map(\.label), ["X"])
    }
}

final class WindowOrderingTests: XCTestCase {
    func testMoveWindows() {
        let d = DisplayStore()
        d.windows = [FloatingWindowConfig(name: "A"), FloatingWindowConfig(name: "B"), FloatingWindowConfig(name: "C")]
        let ids = d.windows.map(\.id)
        d.moveWindow(ids[0], by: 1)
        XCTAssertEqual(d.windows.map(\.name), ["B", "A", "C"])
        d.moveWindow(ids[0], by: -5)                                // out of range: ignored
        XCTAssertEqual(d.windows.map(\.name), ["B", "A", "C"])
        d.moveWindow(ids[2], onto: ids[1])                          // C up onto B → before B
        XCTAssertEqual(d.windows.map(\.name), ["C", "B", "A"])
    }
}

final class HealingTests: XCTestCase {
    @MainActor
    func testEmptyKeyIsResolvedFromName() {
        let displays = DisplayStore()
        displays.items = [DisplayItem(target: .floating, installationId: 1, metricKey: "", metricName: "Battery SOC")]
        let store = MetricStore(displays: displays)
        store.setPolledForTesting(site: 1, ["bs#512": Metric(name: "Battery SOC", formatted: "80 %", raw: 80)])
        XCTAssertEqual(displays.items[0].metricKey, "bs#512")
        XCTAssertEqual(store.statsCode(for: displays.items[0]), "bs")
    }
}

final class TankHistoryTests: XCTestCase {
    @MainActor
    func testTwoTanksGetSeparateHistoryKeys() {
        let displays = DisplayStore()
        let left = DisplayItem(target: .floating, installationId: 1, metricKey: "tl#20", label: "Left")
        let right = DisplayItem(target: .floating, installationId: 1, metricKey: "tl#21", label: "Right")
        displays.items = [left, right]
        let store = MetricStore(displays: displays)
        XCTAssertEqual(store.statsCode(for: left), "tl")
        XCTAssertEqual(store.statsCode(for: right), "tl")
        XCTAssertNotEqual(store.remoteKey(for: left), store.remoteKey(for: right))
    }

    func testStatsRequestCarriesTheInstance() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubProtocol.self]
        let client = VRMClient(session: URLSession(configuration: cfg))
        await client.setCredentials(.token("abc"))
        nonisolated(unsafe) var seen = ""
        StubProtocol.handler = { req in
            seen = req.url!.absoluteString
            return (200, [:], #"{"success":true,"records":[{"instance":20,"stats":{"tl":[[1700000000,2]]}},{"instance":21,"stats":{"tl":[[1700000000,96]]}}]}"#)
        }
        let samples = try await client.stats(site: 1, code: "tl", instance: 21)
        XCTAssertTrue(seen.contains("show_instance=1"))
        XCTAssertTrue(seen.contains("attributeCodes%5B%5D=tl"))
        XCTAssertEqual(samples.map(\.v), [96])
    }
}

final class SharedCodeHistoryTests: XCTestCase {
    @MainActor
    func testForeignSeriesIsRejectedForSharedCodes() {
        let displays = DisplayStore()
        let right = DisplayItem(target: .floating, installationId: 1, metricKey: "tl#21", label: "Right")
        displays.items = [right]
        let store = MetricStore(displays: displays)
        store.setPolledForTesting(site: 1, [
            "tl#20": Metric(name: "Tank left", formatted: "2 %", raw: 2),
            "tl#21": Metric(name: "Tank right", formatted: "96 %", raw: 96),
        ])
        let now = Date()
        store.history.setRemoteForTesting("1|tl#21", [Sample(t: now.addingTimeInterval(-900), v: 2), Sample(t: now, v: 2)])
        XCTAssertNil(store.usableRemoteKey(for: right))                 // 2 % vs 96 % → wrong device

        store.history.setRemoteForTesting("1|tl#21", [Sample(t: now.addingTimeInterval(-900), v: 95), Sample(t: now, v: 96)])
        XCTAssertEqual(store.usableRemoteKey(for: right), "1|tl#21")    // plausible → kept
    }

    @MainActor
    func testSamplerFillsFlatSeries() {
        let displays = DisplayStore()
        let item = DisplayItem(target: .floating, installationId: 1, metricKey: "mqtt:tank/3/Level", label: "Black")
        displays.items = [item]
        let store = MetricStore(displays: displays)
        store.setLiveForTesting(site: 1, path: "tank/3/Level", Metric(name: "Level", formatted: "40 %", raw: 40))
        store.sampleDisplayedValues()
        XCTAssertEqual(store.history.local["1|tank/3/Level"]?.map(\.v), [40])
    }
}

final class PerInstanceStatsTests: XCTestCase {
    func testPicksTheRequestedDevice() {
        // Shape returned by VRM with show_instance=1 (one entry per tank).
        let json = #"{"success":true,"records":[{"instance":20,"stats":{"tl":[[1793016482000,96],[1793017382000,96]]}},{"instance":21,"stats":{"tl":[[1793016482000,49]]}}]}"#
        let data = Data(json.utf8)
        XCTAssertEqual(StatsParser.parse(data, code: "tl", instance: 20).map(\.v), [96, 96])
        XCTAssertEqual(StatsParser.parse(data, code: "tl", instance: 21).map(\.v), [49])
        XCTAssertTrue(StatsParser.parse(data, code: "tl", instance: 99).isEmpty)   // unknown device: nothing, not a guess
    }
}