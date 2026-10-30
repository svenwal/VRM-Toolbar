import XCTest
@testable import VRMToolbar

final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String], String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, headers, body) = Self.handler!(request)
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class VRMClientTests: XCTestCase {
    private func client() -> VRMClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubProtocol.self]
        return VRMClient(session: URLSession(configuration: cfg))
    }

    func testDiagnosticsDecodingIsLenient() throws {
        let json = #"{"records":[{"code":"bs","description":"Battery State of Charge","instance":512,"formattedValue":"85.2 %","rawValue":85.2},{"code":"x","rawValue":"12"}]}"#
        let r = try JSONDecoder().decode(DiagnosticsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.records[0].key, "bs#512")
        XCTAssertEqual(r.records[0].rawValue, 85.2)
        XCTAssertEqual(r.records[1].rawValue, 12)
        XCTAssertEqual(r.records[1].description, "x")
    }

    func testTokenAuthUsesTokenHeaderAndFetchesInstallations() async throws {
        StubProtocol.handler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "X-Authorization"), "Token abc")
            if req.url!.path.hasSuffix("users/me") { return (200, [:], #"{"user":{"id":7}}"#) }
            XCTAssertTrue(req.url!.path.hasSuffix("users/7/installations"))
            return (200, [:], #"{"records":[{"idSite":1,"name":"Home"}]}"#)
        }
        let c = client()
        await c.setCredentials(.token("abc"))
        let sites = try await c.installations()
        XCTAssertEqual(sites, [Installation(idSite: 1, name: "Home")])
    }

    func testPasswordLoginReauthenticatesOn401() async throws {
        nonisolated(unsafe) var logins = 0
        nonisolated(unsafe) var diagCalls = 0
        StubProtocol.handler = { req in
            if req.url!.path.hasSuffix("auth/login") {
                logins += 1
                return (200, [:], #"{"token":"t\#(logins)","idUser":7}"#)
            }
            diagCalls += 1
            if diagCalls == 1 { return (401, [:], "{}") }
            XCTAssertEqual(req.value(forHTTPHeaderField: "X-Authorization"), "Bearer t2")
            return (200, [:], #"{"records":[]}"#)
        }
        let c = client()
        await c.setCredentials(.password(username: "a", password: "b"))
        _ = try await c.diagnostics(site: 1)
        XCTAssertEqual(logins, 2)
    }

    func testRateLimitSurfacesRetryAfter() async {
        StubProtocol.handler = { _ in (429, ["Retry-After": "42"], "{}") }
        let c = client()
        await c.setCredentials(.token("abc"))
        do { _ = try await c.diagnostics(site: 1); XCTFail() }
        catch { XCTAssertEqual(error as? VRMError, .rateLimited(retryAfter: 42)) }
    }
}
