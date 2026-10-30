import Foundation

actor VRMClient {
    static let baseURL = URL(string: "https://vrmapi.victronenergy.com/v2")!

    private let session: URLSession
    private let baseURL: URL
    private var credentials: Credentials?
    private var authHeader: String?
    private var userId: Int?

    init(session: URLSession = .shared, baseURL: URL = VRMClient.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func setCredentials(_ credentials: Credentials?) {
        self.credentials = credentials
        authHeader = nil
        userId = nil
    }

    func installations() async throws -> [Installation] {
        let id = try await currentUserId()
        let r: InstallationsResponse = try await get("users/\(id)/installations")
        return r.records
    }

    func diagnostics(site: Int) async throws -> [DiagnosticRecord] {
        let r: DiagnosticsResponse = try await get("installations/\(site)/diagnostics?count=1000")
        return r.records
    }

    /// History for one attribute code (e.g. "bs") over the last `hours`, 15-minute resolution.
    func stats(site: Int, code: String, instance: Int? = nil, hours: Int = 24) async throws -> [Sample] {
        let end = Int(Date().timeIntervalSince1970)
        var query = "type=custom&attributeCodes%5B%5D=\(code)&interval=15mins&start=\(end - hours * 3600)&end=\(end)"
        // Several devices can share one code (e.g. four tanks). Only `show_instance` returns them separately;
        // a plain `instance=` parameter is ignored by VRM.
        if instance != nil { query += "&show_instance=1" }
        let data = try await getData("installations/\(site)/stats?\(query)")
        return StatsParser.parse(data, code: code, instance: instance)
    }

    /// Username/password for the VRM MQTT broker (email + `Token <token>`).
    func mqttCredentials() async throws -> (username: String, password: String) {
        switch credentials {
        case nil:
            throw VRMError.notConfigured
        case .token(let t):
            let me: MeResponse = try await get("users/me")
            guard let email = me.user.email else { throw VRMError.http(0) }
            return (email, "Token \(t)")
        case .password(let u, let p):
            // Deprecated by Victron, but still accepted by the broker for now.
            return (u, p)
        }
    }

    // MARK: - Auth

    private func currentUserId() async throws -> Int {
        if let userId { return userId }
        try await authenticate()
        if let userId { return userId }
        let me: MeResponse = try await get("users/me")
        userId = me.user.id
        return me.user.id
    }

    private func authenticate() async throws {
        switch credentials {
        case nil:
            throw VRMError.notConfigured
        case .token(let t):
            authHeader = "Token \(t)"
        case .password(let u, let p):
            var req = URLRequest(url: baseURL.appendingPathComponent("auth/login"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["username": u, "password": p])
            let (data, resp) = try await session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 {
                if String(data: data, encoding: .utf8)?.localizedCaseInsensitiveContains("two") == true {
                    throw VRMError.twoFactorRequired
                }
                throw VRMError.unauthorized
            }
            try check(resp, data)
            let login = try JSONDecoder().decode(LoginResponse.self, from: data)
            authHeader = "Bearer \(login.token)"
            userId = login.idUser
        }
    }

    // MARK: - Requests

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await getData(path))
    }

    private func getData(_ path: String) async throws -> Data {
        if authHeader == nil { try await authenticate() }
        do {
            return try await perform(path)
        } catch VRMError.unauthorized {
            // Bearer tokens from password login expire; re-login once.
            guard case .password = credentials else { throw VRMError.unauthorized }
            authHeader = nil
            try await authenticate()
            return try await perform(path)
        }
    }

    private func perform(_ path: String) async throws -> Data {
        guard let url = URL(string: baseURL.absoluteString + "/" + path) else { throw VRMError.http(0) }
        var req = URLRequest(url: url)
        req.setValue(authHeader, forHTTPHeaderField: "X-Authorization")
        let (data, resp) = try await session.data(for: req)
        try check(resp, data)
        return data
    }

    private func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw VRMError.http(0) }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw VRMError.unauthorized
        case 429: throw VRMError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
        default: throw VRMError.http(http.statusCode)
        }
    }
}
