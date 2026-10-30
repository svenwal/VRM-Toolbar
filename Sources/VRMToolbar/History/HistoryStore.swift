import Foundation
import Observation

struct Sample: Hashable {
    let t: Date
    let v: Double
}

struct SeriesStats {
    let min: Sample
    let max: Sample
    let avg: Double
}

/// Parses `/installations/{id}/stats` responses. Two shapes exist:
/// - `records[code] = [[timestamp, value], …]` (summed/first device), and
/// - with `show_instance=1`: `records = [{instance, stats: {code: [[timestamp, value], …]}}, …]` (one entry per device).
enum StatsParser {
    static func parse(_ data: Data, code: String, instance: Int? = nil) -> [Sample] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var rows: [[Any]]?
        if let perDevice = obj["records"] as? [[String: Any]] {
            let entry = perDevice.first { ($0["instance"] as? NSNumber)?.intValue == instance }
                ?? (instance == nil && perDevice.count == 1 ? perDevice.first : nil)
            rows = (entry?["stats"] as? [String: Any])?[code] as? [[Any]]
        } else if let records = obj["records"] as? [String: Any] {
            rows = records[code] as? [[Any]]
        }
        return (rows ?? []).compactMap { row in
            guard row.count >= 2,
                  let ts = (row[0] as? NSNumber)?.doubleValue,
                  let v = (row[1] as? NSNumber)?.doubleValue else { return nil }
            return Sample(t: Date(timeIntervalSince1970: ts > 1e11 ? ts / 1000 : ts), v: v)
        }
        .sorted { $0.t < $1.t }
    }
}

/// Session-local samples (any value, incl. streamed ones) plus VRM's stored history (by attribute code).
@Observable @MainActor
final class HistoryStore {
    struct Remote {
        var samples: [Sample]
        var fetchedAt: Date
    }

    private(set) var local: [String: [Sample]] = [:]
    private(set) var remote: [String: Remote] = [:]
    private(set) var loading: Set<String> = []
    private var lastRecorded: [String: Date] = [:]

    func record(_ key: String, _ value: Double, at date: Date = Date()) {
        if let last = lastRecorded[key], date.timeIntervalSince(last) < 5 { return }
        lastRecorded[key] = date
        var arr = local[key, default: []]
        arr.append(Sample(t: date, v: value))
        if arr.count > 4000 { arr.removeFirst(arr.count - 4000) }  // ≈ 5½ h at one sample per 5 s
        local[key] = arr
    }

    func loadRemote(key: String, fetch: () async throws -> [Sample]) async {
        if let r = remote[key], Date().timeIntervalSince(r.fetchedAt) < 300 { return }
        guard !loading.contains(key) else { return }
        loading.insert(key)
        defer { loading.remove(key) }
        let samples = (try? await fetch()) ?? []
        remote[key] = Remote(samples: samples, fetchedAt: Date())
    }

    /// VRM history followed by whatever we recorded locally after its last point.
    func series(localKey: String, remoteKey: String?) -> [Sample] {
        let stored = remoteKey.flatMap { remote[$0]?.samples } ?? []
        let recent = local[localKey] ?? []
        guard let last = stored.last?.t else { return recent }
        return stored + recent.filter { $0.t > last }
    }

    func hasRemote(_ key: String?) -> Bool { key.flatMap { remote[$0]?.samples.isEmpty == false } ?? false }

    nonisolated static func stats(_ series: [Sample]) -> SeriesStats? {
        guard let lo = series.min(by: { $0.v < $1.v }), let hi = series.max(by: { $0.v < $1.v }) else { return nil }
        return SeriesStats(min: lo, max: hi, avg: series.map(\.v).reduce(0, +) / Double(series.count))
    }
}

extension HistoryStore {
    func setRemoteForTesting(_ key: String, _ samples: [Sample]) {
        remote[key] = Remote(samples: samples, fetchedAt: Date())
    }
}
