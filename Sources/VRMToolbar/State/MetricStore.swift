import Foundation
import Observation
import OSLog

struct Metric: Equatable {
    var name: String
    var formatted: String
    var raw: Double?
}

@Observable @MainActor
final class MetricStore {
    enum Status: Equatable {
        case notConfigured
        case idle
        case ok
        case error(String)
    }

    static let liveKeyPrefix = "mqtt:"
    static let log = Logger(subsystem: "world.walther.vrm-toolbar", category: "history")
    private var samplerTask: Task<Void, Never>?

    private(set) var installations: [Installation] = []
    /// installationId → metricKey → latest polled value
    private(set) var metrics: [Int: [String: Metric]] = [:]
    /// installationId → MQTT path (`service/instance/path`) → latest streamed value
    private(set) var live: [Int: [String: Metric]] = [:]
    /// Installations whose MQTT stream is currently connected.
    private(set) var streaming: Set<Int> = []
    private(set) var streamError: String?
    private(set) var lastUpdate: Date?
    private(set) var status: Status = .notConfigured

    let displays: DisplayStore
    private let client: VRMClient
    private var task: Task<Void, Never>?
    private var backoff: TimeInterval = 0
    private var streams: [Int: LiveStream] = [:]
    /// installationId → polled metricKey → MQTT path
    private var livePaths: [Int: [String: String]] = [:]
    private var streamingEnabled = true

    let history = HistoryStore()
    /// The value whose history popup is currently shown (set by hovering a display).
    private(set) var hover: HoverTarget?
    private var hoverShowTask: Task<Void, Never>?
    private var hoverHideTask: Task<Void, Never>?

    init(displays: DisplayStore, client: VRMClient = VRMClient()) {
        self.displays = displays
        self.client = client
    }

    var isStale: Bool {
        // Streamed values update continuously, so a connected stream counts as fresh.
        if !streaming.isEmpty { return false }
        guard let lastUpdate else { return true }
        return Date().timeIntervalSince(lastUpdate) > displays.refreshInterval * 3
    }

    func metric(for item: DisplayItem) -> Metric? {
        guard var m = rawMetric(for: item) else { return nil }
        if let unit = item.unit?.trimmingCharacters(in: .whitespaces), !unit.isEmpty {
            // Replace VRM's own unit: use the numeric value when we have one.
            if let raw = m.raw {
                m.formatted = raw.formatted(.number.precision(.fractionLength(0 ... 1)).grouping(.never)) + " " + unit
            } else {
                m.formatted += " " + unit
            }
        }
        return m
    }

    private func rawMetric(for item: DisplayItem) -> Metric? {
        let site = item.installationId
        if item.metricKey.hasPrefix(Self.liveKeyPrefix) {
            return live[site]?[String(item.metricKey.dropFirst(Self.liveKeyPrefix.count))]
        }
        if streaming.contains(site), let path = livePaths[site]?[item.metricKey], let m = live[site]?[path] {
            return m
        }
        guard let all = metrics[site] else { return nil }
        if let m = all[item.metricKey] { return m }
        // Older configs saved the name but lost the key; match by name instead.
        guard item.metricKey.isEmpty, !item.metricName.isEmpty else { return nil }
        return all.values.first { $0.name == item.metricName }
    }

    /// Polled and streamed values for the picker; streamed ones carry the `mqtt:` key prefix.
    func metricList(for installation: Int) -> [(key: String, metric: Metric)] {
        let polled = (metrics[installation] ?? [:]).map { (key: $0.key, metric: $0.value) }
        let streamed = (live[installation] ?? [:]).map {
            (key: Self.liveKeyPrefix + $0.key, metric: Metric(name: "⚡ " + $0.value.name, formatted: $0.value.formatted, raw: $0.value.raw))
        }
        return (polled + streamed).sorted { $0.metric.name < $1.metric.name }
    }

    // MARK: - Lifecycle

    func configure(_ credentials: Credentials?) async {
        await client.setCredentials(credentials)
        installations = []
        metrics = [:]
        stopStreams()
        lastUpdate = nil
        task?.cancel()
        samplerTask?.cancel()
        samplerTask = credentials == nil ? nil : Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.sampleDisplayedValues()
            }
        }
        guard credentials != nil else { status = .notConfigured; return }
        status = .idle
        task = Task { [weak self] in await self?.loop() }
    }

    func refreshNow() {
        guard status != .notConfigured else { return }
        task?.cancel()
        task = Task { [weak self] in await self?.loop() }
    }

    /// Validates credentials without starting the poll loop; returns the installations.
    func test(_ credentials: Credentials) async throws -> [Installation] {
        let probe = VRMClient()
        await probe.setCredentials(credentials)
        return try await probe.installations()
    }

    /// Start streaming for an installation (e.g. one being browsed in the picker).
    func ensureStream(for site: Int) {
        guard streamingEnabled, streams[site] == nil,
              let installation = installations.first(where: { $0.idSite == site }) else { return }
        let stream = LiveStream(
            installation: installation,
            credentials: { [client] in try await client.mqttCredentials() },
            onValue: { [weak self] path, metric in
                guard let self else { return }
                if let metric {
                    live[site, default: [:]][path] = metric
                    recordIfWatched(site: site, path: path, metric: metric)
                } else {
                    live[site]?[path] = nil
                }
            },
            onState: { [weak self] connected, error in
                guard let self else { return }
                if connected { streaming.insert(site) } else { streaming.remove(site) }
                if connected { streamError = nil } else if let error { streamError = error }
            })
        guard stream.canStream else { return }
        streams[site] = stream
        stream.start()
    }

    private func stopStreams() {
        streams.values.forEach { $0.stop() }
        streams = [:]
        live = [:]
        livePaths = [:]
        streaming = []
        streamError = nil
    }

    // MARK: - Polling

    /// When every display is served by the stream, poll rarely to save API quota.
    private var allDisplaysStreamed: Bool {
        let items = displays.items
        return !items.isEmpty && items.allSatisfy { item in
            streaming.contains(item.installationId)
                && (item.metricKey.hasPrefix(Self.liveKeyPrefix) || livePaths[item.installationId]?[item.metricKey] != nil)
        }
    }

    private func loop() async {
        while !Task.isCancelled {
            await pollOnce()
            let base = allDisplaysStreamed ? max(displays.refreshInterval, 300) : displays.refreshInterval
            try? await Task.sleep(for: .seconds(max(base, backoff)))
        }
    }

    private func pollOnce() async {
        do {
            if installations.isEmpty { installations = try await client.installations() }
            // Poll every installation referenced by a display; fall back to the first for the picker.
            var ids = Set(displays.items.map(\.installationId))
            if ids.isEmpty, let first = installations.first { ids = [first.idSite] }
            for id in ids {
                let records = try await client.diagnostics(site: id)
                var m: [String: Metric] = [:]
                var paths: [String: String] = [:]
                for r in records {
                    m[r.key] = Metric(name: r.description, formatted: r.formattedValue ?? "–", raw: r.rawValue)
                    if let p = r.livePath { paths[r.key] = p }
                }
                metrics[id] = m
                livePaths[id] = paths
                healEmptyKeys(site: id)
                recordPolled(site: id)
                ensureStream(for: id)
            }
            lastUpdate = Date()
            status = .ok
            backoff = 0
        } catch is CancellationError {
            return
        } catch let VRMError.rateLimited(retry) {
            backoff = retry ?? min(max(backoff * 2, displays.refreshInterval * 2), 900)
            status = .error(VRMError.rateLimited(retryAfter: retry).localizedDescription)
        } catch VRMError.unauthorized {
            backoff = 900
            status = .error(VRMError.unauthorized.localizedDescription)
        } catch {
            backoff = min(max(backoff * 2, 30), 300)
            status = .error(error.localizedDescription)
        }
    }

    /// Ensure the picker has data for `installation` even if no display references it yet.
    func loadMetrics(for installation: Int) async {
        ensureStream(for: installation)
        guard let records = try? await client.diagnostics(site: installation) else { return }
        var m: [String: Metric] = [:]
        var paths: [String: String] = [:]
        for r in records {
            m[r.key] = Metric(name: r.description, formatted: r.formattedValue ?? "–", raw: r.rawValue)
            if let p = r.livePath { paths[r.key] = p }
        }
        metrics[installation] = m
        livePaths[installation] = paths
    }
}

extension MetricStore {
    func setLiveForTesting(site: Int, path: String, _ metric: Metric) { live[site, default: [:]][path] = metric }
}

// MARK: - Visibility

extension MetricStore {
    /// False when the display is set to "only while active" and its value is at or below the threshold.
    func isActive(_ item: DisplayItem) -> Bool {
        guard item.hideWhenIdle == true else { return true }
        let threshold = item.idleThreshold ?? 0
        guard let metric = metric(for: item) else {
            // A streamed value that vanished (null) means nothing is flowing; before any data we keep it visible.
            return !streaming.contains(item.installationId)
        }
        guard let raw = metric.raw else { return true }   // non-numeric: can't judge
        return abs(raw) > threshold
    }

    func activeItems(_ items: [DisplayItem]) -> [DisplayItem] { items.filter { isActive($0) } }
}

// MARK: - History & hover

struct HoverTarget: Equatable {
    enum Source: Hashable {
        case window(UUID)
        case statusItem(UUID)
    }
    var item: UUID
    var source: Source
}

extension MetricStore {
    /// Key under which an item's samples are kept locally; streamed and polled values of one metric share it.
    func historyKey(for item: DisplayItem) -> String {
        let site = item.installationId
        if item.metricKey.hasPrefix(Self.liveKeyPrefix) { return "\(site)|\(item.metricKey.dropFirst(Self.liveKeyPrefix.count))" }
        if let path = livePathFor(site: site, key: item.metricKey) { return "\(site)|\(path)" }
        return "\(site)|\(item.metricKey)"
    }

    /// VRM attribute code for the stats endpoint (e.g. "bs"), when we can tell.
    func statsCode(for item: DisplayItem) -> String? {
        statsKey(for: item)?.split(separator: "#").first.map(String.init)
    }

    /// The polled metric key (`code#instance`) behind an item, also for streamed items.
    func statsKey(for item: DisplayItem) -> String? {
        if !item.metricKey.hasPrefix(Self.liveKeyPrefix) { return item.metricKey.isEmpty ? nil : item.metricKey }
        // A streamed value: find the polled metric that maps to the same MQTT path.
        let path = String(item.metricKey.dropFirst(Self.liveKeyPrefix.count))
        return livePathsReverse(site: item.installationId, path: path)
    }

    /// Distinct per device: two tanks share a code but not an instance.
    func remoteKey(for item: DisplayItem) -> String? {
        statsKey(for: item).map { "\(item.installationId)|\($0)" }
    }

    /// How many devices of the installation report this item's code (two tanks → 2).
    func devicesSharingCode(_ item: DisplayItem) -> Int {
        guard let code = statsCode(for: item) else { return 1 }
        return (metrics[item.installationId] ?? [:]).keys.filter { $0.hasPrefix(code + "#") }.count
    }

    /// The stored VRM history for the item, unless it evidently belongs to another device:
    /// with several devices per code the stats endpoint may ignore `instance`, so a series whose latest
    /// value is far from the current one is rejected.
    func usableRemoteKey(for item: DisplayItem) -> String? {
        guard let key = remoteKey(for: item) else { return nil }
        guard devicesSharingCode(item) > 1,
              let last = history.remote[key]?.samples.last,
              let current = metric(for: item)?.raw else { return key }
        let tolerance = max(3, 0.15 * max(abs(current), abs(last.v)))
        return abs(current - last.v) <= tolerance ? key : nil
    }

    func series(for item: DisplayItem) -> [Sample] {
        history.series(localKey: historyKey(for: item), remoteKey: usableRemoteKey(for: item))
    }

    /// Live values only arrive when they change; sample every current value regularly so that
    /// slow-moving ones (tank levels) still draw a line.
    func sampleDisplayedValues() {
        for item in displays.items {
            if let raw = metric(for: item)?.raw { history.record(historyKey(for: item), raw) }
        }
    }

    func loadHistory(for item: DisplayItem) async {
        guard let statsKey = statsKey(for: item), let key = remoteKey(for: item) else { return }
        let parts = statsKey.split(separator: "#").map(String.init)
        guard let code = parts.first, !code.isEmpty else { return }
        let instance = parts.count > 1 ? Int(parts[1]) : nil
        // Is this the only device with that code? Then asking without an instance can't mix devices up.
        let site = item.installationId
        let sameCode = (metrics[site] ?? [:]).keys.filter { $0.hasPrefix(code + "#") }.count
        await history.loadRemote(key: key) { [client] in
            let samples = try await client.stats(site: site, code: code, instance: instance)
            if samples.isEmpty, sameCode <= 1 { return try await client.stats(site: site, code: code) }
            return samples
        }
        let loaded = history.remote[key]?.samples ?? []
        Self.log.notice("history \(key, privacy: .public): \(loaded.count) stored points, last \(loaded.last?.v ?? .nan), sharing code: \(sameCode), current \(self.metric(for: item)?.raw ?? .nan)")
    }

    func recordIfWatched(site: Int, path: String, metric: Metric) {
        guard let raw = metric.raw else { return }
        let key = "\(site)|\(path)"
        if displays.items.contains(where: { historyKey(for: $0) == key }) { history.record(key, raw) }
    }

    func recordPolled(site: Int) {
        for item in displays.items where item.installationId == site && !item.metricKey.hasPrefix(Self.liveKeyPrefix) {
            if streaming.contains(site), livePathFor(site: site, key: item.metricKey) != nil { continue }  // stream covers it
            if let raw = metrics[site]?[item.metricKey]?.raw { history.record(historyKey(for: item), raw) }
        }
    }

    // MARK: hover with debounce so moving between rows doesn't flicker

    func hoverEnter(_ target: HoverTarget) {
        hoverHideTask?.cancel()
        hoverShowTask?.cancel()
        if hover != nil { hover = target; return }
        hoverShowTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.hover = target
        }
    }

    func hoverExit(_ target: HoverTarget) {
        hoverShowTask?.cancel()
        hoverHideTask?.cancel()
        hoverHideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, self?.hover == target else { return }
            self?.hover = nil
        }
    }
}

extension MetricStore {
    fileprivate func livePathFor(site: Int, key: String) -> String? { livePaths[site]?[key] }
    fileprivate func livePathsReverse(site: Int, path: String) -> String? {
        livePaths[site]?.first { $0.value == path }?.key
    }
}

extension MetricStore {
    /// Early versions saved displays with only the metric's name. Look the key up once and store it,
    /// so history, streaming and stats work for those displays too.
    fileprivate func healEmptyKeys(site: Int) {
        guard let all = metrics[site] else { return }
        for i in displays.items.indices {
            let item = displays.items[i]
            guard item.installationId == site, item.metricKey.isEmpty, !item.metricName.isEmpty else { continue }
            if let key = all.filter({ $0.value.name == item.metricName }).keys.sorted().first {
                displays.items[i].metricKey = key
            }
        }
    }
}

extension MetricStore {
    func setPolledForTesting(site: Int, _ values: [String: Metric]) {
        metrics[site] = values
        healEmptyKeys(site: site)
    }
}
