import Foundation

struct Installation: Codable, Identifiable, Hashable {
    let idSite: Int
    let name: String
    /// Portal ID used in MQTT topics.
    var identifier: String? = nil
    var mqttWebHost: String? = nil
    var id: Int { idSite }

    enum CodingKeys: String, CodingKey {
        case idSite, name, identifier
        case mqttWebHost = "mqtt_webhost"
    }
}

/// One entry of `/installations/{id}/diagnostics`.
struct DiagnosticRecord: Decodable, Hashable {
    let code: String
    let description: String
    let instance: Int?
    let formattedValue: String?
    let rawValue: Double?
    let dbusServiceType: String?
    let dbusPath: String?
    let idDataAttribute: Int?

    var key: String { MetricKey.make(code: code, instance: instance) }

    /// The equivalent MQTT path (`service/instance/path`), when VRM tells us the D-Bus location.
    var livePath: String? {
        guard let dbusServiceType, let dbusPath, let instance else { return nil }
        return "\(dbusServiceType)/\(instance)\(dbusPath.hasPrefix("/") ? "" : "/")\(dbusPath)"
    }

    enum CodingKeys: String, CodingKey {
        case code, description, instance, formattedValue, rawValue, dbusServiceType, dbusPath, idDataAttribute
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        description = (try? c.decode(String.self, forKey: .description)) ?? code
        instance = try? c.decode(Int.self, forKey: .instance)
        dbusServiceType = try? c.decode(String.self, forKey: .dbusServiceType)
        dbusPath = try? c.decode(String.self, forKey: .dbusPath)
        idDataAttribute = try? c.decode(Int.self, forKey: .idDataAttribute)
        formattedValue = (try? c.decode(String.self, forKey: .formattedValue))
            ?? (try? c.decode(Double.self, forKey: .formattedValue)).map { String($0) }
        // rawValue is a number for most attributes but may be a string/null.
        rawValue = (try? c.decode(Double.self, forKey: .rawValue))
            ?? (try? c.decode(String.self, forKey: .rawValue)).flatMap(Double.init)
    }

    init(code: String, description: String, instance: Int?, formattedValue: String?, rawValue: Double?,
         dbusServiceType: String? = nil, dbusPath: String? = nil, idDataAttribute: Int? = nil) {
        self.code = code; self.description = description; self.instance = instance
        self.formattedValue = formattedValue; self.rawValue = rawValue
        self.dbusServiceType = dbusServiceType; self.dbusPath = dbusPath; self.idDataAttribute = idDataAttribute
    }
}

enum MetricKey {
    static func make(code: String, instance: Int?) -> String { "\(code)#\(instance ?? 0)" }
}

struct LoginResponse: Decodable { let token: String; let idUser: Int }
struct InstallationsResponse: Decodable { let records: [Installation] }
struct DiagnosticsResponse: Decodable { let records: [DiagnosticRecord] }
struct MeResponse: Decodable {
    struct User: Decodable { let id: Int; let email: String? }
    let user: User
}

enum Credentials: Codable, Equatable {
    case token(String)
    case password(username: String, password: String)
}

enum VRMError: LocalizedError, Equatable {
    case notConfigured
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int)
    case twoFactorRequired

    var errorDescription: String? {
        switch self {
        case .notConfigured: "No VRM account configured."
        case .unauthorized: "VRM rejected the credentials."
        case .rateLimited: "VRM rate limit hit; backing off."
        case .http(let c): "VRM returned HTTP \(c)."
        case .twoFactorRequired: "This account uses 2FA – create an access token in VRM (Preferences › Integrations) and use it instead."
        }
    }
}
