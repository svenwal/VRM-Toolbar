import Foundation

/// What the menu bar app hands to the Notification Center widgets. The app is not sandboxed and the widget
/// extension has no network access, so the snapshot travels as a JSON file in the shared app-group container.
public struct WidgetSnapshot: Codable, Equatable {
    public struct Item: Codable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var value: String
        /// Where the display lives: "Menu bar", "Dock icon" or a floating window's name.
        public var group: String

        public init(id: String, title: String, value: String, group: String) {
            self.id = id; self.title = title; self.value = value; self.group = group
        }
    }

    public var updated: Date?
    public var isSignedIn: Bool
    public var isStale: Bool
    /// Battery state of charge, 0…1.
    public var batteryLevel: Double?
    public var items: [Item]

    public init(updated: Date? = nil, isSignedIn: Bool = false, isStale: Bool = false, batteryLevel: Double? = nil, items: [Item] = []) {
        self.updated = updated; self.isSignedIn = isSignedIn; self.isStale = isStale
        self.batteryLevel = batteryLevel; self.items = items
    }

    /// Placeholder content for the widget gallery.
    public static let sample = WidgetSnapshot(
        updated: Date(), isSignedIn: true, batteryLevel: 0.87,
        items: [
            .init(id: "1", title: "Battery", value: "87 %", group: "Menu bar"),
            .init(id: "2", title: "Solar yield", value: "412 W", group: "Menu bar"),
            .init(id: "3", title: "Consumption", value: "186 W", group: "Window 1"),
            .init(id: "4", title: "Fresh water", value: "64 %", group: "Window 1"),
            .init(id: "5", title: "Battery voltage", value: "13.2 V", group: "Window 1"),
            .init(id: "6", title: "Shore power", value: "0 W", group: "Dock icon"),
        ])
}

public enum SnapshotStore {
    /// Team-prefixed so macOS accepts it without a provisioning profile.
    public static let groupID = "6KUJKPXRC9.world.walther.vrm-toolbar"

    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?.appendingPathComponent("snapshot.json")
    }

    public static func read() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    public static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url else { return false }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
