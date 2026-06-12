import Foundation
import Testing
@testable import UsageCore

// ---------------------------------------------------------------------------
// Own URLProtocol subclass — isolated from all other suites' statics.
// ---------------------------------------------------------------------------
final class EngineStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?
    nonisolated(unsafe) static var requestCount: Int = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        EngineStubProtocol.requestCount += 1
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeEngineSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [EngineStubProtocol.self]
    return URLSession(configuration: config)
}

private func makeEngineResponse(
    statusCode: Int,
    url: URL = URL(string: "https://api.example.com/balance")!,
    headerFields: [String: String]? = nil
) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headerFields)!
}

/// Builds a ProviderSpec with sensible defaults; all fields are overridable.
private func makeSpec(
    url: String = "https://api.example.com/balance",
    headerName: String = "Authorization",
    headerTemplate: String = "Bearer {key}",
    valuePath: String = "value",
    subtractPath: String? = nil,
    scale: Double = 1.0
) -> ProviderSpec {
    ProviderSpec(
        id: UUID(),
        displayName: "Test Provider",
        adapter: .generic,
        url: url,
        headerName: headerName,
        headerTemplate: headerTemplate,
        valuePath: valuePath,
        subtractPath: subtractPath,
        scale: scale,
        valueKind: .currency,
        currencyCode: "USD",
        warnBelow: nil,
        visibility: .pinned
    )
}

// ---------------------------------------------------------------------------
// Tests — serialized within this suite.
// ---------------------------------------------------------------------------
@Suite(.serialized)
struct ProviderEngineTests {

    // 1. Basic fetch: 200 with DeepSeek-shaped body, valuePath extracts nested value,
    //    request carries correct Authorization header.
    @Test func fetchesAndExtractsValue() async throws {
        let json = #"{"balance_infos":[{"currency":"USD","total_balance":"110.53"}]}"#
        nonisolated(unsafe) var capturedRequest: URLRequest?
        EngineStubProtocol.handler = { req in
            capturedRequest = req
            return (Data(json.utf8), makeEngineResponse(statusCode: 200))
        }
        EngineStubProtocol.requestCount = 0
        let spec = makeSpec(
            url: "https://api.example.com/balance",
            valuePath: "balance_infos.0.total_balance"
        )
        let engine = ProviderEngine(session: makeEngineSession())
        let value = try await engine.fetchValue(spec: spec, key: "k1")
        #expect(value == 110.53)
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer k1")
        #expect(capturedRequest?.url?.absoluteString == "https://api.example.com/balance")
    }

    // 2. subtractPath: value = valuePath - subtractPath.
    @Test func subtractPathComputesRemaining() async throws {
        let json = #"{"data":{"total_credits":50.0,"total_usage":41.25}}"#
        EngineStubProtocol.handler = { _ in (Data(json.utf8), makeEngineResponse(statusCode: 200)) }
        EngineStubProtocol.requestCount = 0
        let spec = makeSpec(
            valuePath: "data.total_credits",
            subtractPath: "data.total_usage"
        )
        let engine = ProviderEngine(session: makeEngineSession())
        let value = try await engine.fetchValue(spec: spec, key: "k1")
        #expect(value == 8.75)
    }

    // 3. Scale multiplier applied after extraction.
    @Test func scaleApplies() async throws {
        let json = #"{"cents":1234}"#
        EngineStubProtocol.handler = { _ in (Data(json.utf8), makeEngineResponse(statusCode: 200)) }
        EngineStubProtocol.requestCount = 0
        let spec = makeSpec(valuePath: "cents", scale: 0.01)
        let engine = ProviderEngine(session: makeEngineSession())
        let value = try await engine.fetchValue(spec: spec, key: "k1")
        #expect(abs(value - 12.34) < 1e-9)
    }

    // 4. Custom header name and raw template.
    @Test func rawHeaderTemplateAndCustomHeaderName() async throws {
        let json = #"{"value":99.0}"#
        nonisolated(unsafe) var capturedRequest: URLRequest?
        EngineStubProtocol.handler = { req in
            capturedRequest = req
            return (Data(json.utf8), makeEngineResponse(statusCode: 200))
        }
        EngineStubProtocol.requestCount = 0
        let spec = makeSpec(
            headerName: "x-api-key",
            headerTemplate: "{key}"
        )
        let engine = ProviderEngine(session: makeEngineSession())
        _ = try await engine.fetchValue(spec: spec, key: "k1")
        #expect(capturedRequest?.value(forHTTPHeaderField: "x-api-key") == "k1")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    // 5. Status code mapping: 401 → .unauthorized; 429+Retry-After → .rateLimited(60); 200+garbage → .undecodable.
    @Test func mapsAuthRateLimitAndGarbage() async throws {
        let engine = ProviderEngine(session: makeEngineSession())
        let spec = makeSpec()

        // 401 → unauthorized
        EngineStubProtocol.handler = { _ in (Data(), makeEngineResponse(statusCode: 401)) }
        EngineStubProtocol.requestCount = 0
        await #expect(throws: FetchError.unauthorized) {
            _ = try await engine.fetchValue(spec: spec, key: "k1")
        }

        // 429 with Retry-After: 60 → rateLimited(retryAfter: 60)
        EngineStubProtocol.handler = { _ in
            (Data(), makeEngineResponse(statusCode: 429, headerFields: ["Retry-After": "60"]))
        }
        EngineStubProtocol.requestCount = 0
        await #expect(throws: FetchError.rateLimited(retryAfter: 60)) {
            _ = try await engine.fetchValue(spec: spec, key: "k1")
        }

        // 200 with garbage body → undecodable
        EngineStubProtocol.handler = { _ in (Data("nope".utf8), makeEngineResponse(statusCode: 200)) }
        EngineStubProtocol.requestCount = 0
        await #expect(throws: FetchError.undecodable) {
            _ = try await engine.fetchValue(spec: spec, key: "k1")
        }
    }

    // 6. valuePath missing in valid JSON → .undecodable.
    @Test func missingPathIsUndecodable() async throws {
        let json = #"{"a":1}"#
        EngineStubProtocol.handler = { _ in (Data(json.utf8), makeEngineResponse(statusCode: 200)) }
        EngineStubProtocol.requestCount = 0
        let spec = makeSpec(valuePath: "b")
        let engine = ProviderEngine(session: makeEngineSession())
        await #expect(throws: FetchError.undecodable) {
            _ = try await engine.fetchValue(spec: spec, key: "k1")
        }
    }

    // 7. valuePath resolves but subtractPath missing → .undecodable.
    @Test func missingSubtractPathIsUndecodable() async throws {
        let json = #"{"total":50.0}"#
        EngineStubProtocol.handler = { _ in (Data(json.utf8), makeEngineResponse(statusCode: 200)) }
        EngineStubProtocol.requestCount = 0
        let spec = makeSpec(valuePath: "total", subtractPath: "missing")
        let engine = ProviderEngine(session: makeEngineSession())
        await #expect(throws: FetchError.undecodable) {
            _ = try await engine.fetchValue(spec: spec, key: "k1")
        }
    }

    // 8. Bad URL → .network; stub never receives a request.
    @Test func badURLIsNetworkErrorWithoutRequest() async throws {
        EngineStubProtocol.handler = { _ in (Data(), makeEngineResponse(statusCode: 200)) }
        EngineStubProtocol.requestCount = 0
        let spec = makeSpec(url: "not a url")
        let engine = ProviderEngine(session: makeEngineSession())
        await #expect(throws: FetchError.network) {
            _ = try await engine.fetchValue(spec: spec, key: "k1")
        }
        #expect(EngineStubProtocol.requestCount == 0)
    }

    // 9. Overflow: value * scale → infinity → .undecodable.
    @Test func nonFiniteResultIsUndecodable() async throws {
        let json = #"{"v":1e308}"#
        EngineStubProtocol.handler = { _ in (Data(json.utf8), makeEngineResponse(statusCode: 200)) }
        EngineStubProtocol.requestCount = 0
        let spec = makeSpec(valuePath: "v", scale: 1e308)
        let engine = ProviderEngine(session: makeEngineSession())
        await #expect(throws: FetchError.undecodable) {
            _ = try await engine.fetchValue(spec: spec, key: "k1")
        }
    }
    // Pins the arithmetic ORDER: (primary − subtract) × scale, not (primary × scale) − subtract.
    @Test func subtractHappensBeforeScale() async throws {
        EngineStubProtocol.handler = { req in
            let body = Data(#"{"a":10,"b":4}"#.utf8)
            return (body, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let spec = makeSpec(valuePath: "a", subtractPath: "b", scale: 2)
        let value = try await ProviderEngine(session: makeEngineSession()).fetchValue(spec: spec, key: "k1")
        #expect(value == 12) // (10 − 4) × 2 — a swapped order would yield 16
    }
    // https-only: an http:// URL must be rejected BEFORE any request.
    @Test func httpSchemeIsRejectedWithoutRequest() async throws {
        EngineStubProtocol.requestCount = 0
        let spec = makeSpec(url: "http://api.example.com/balance")
        await #expect(throws: FetchError.network) {
            _ = try await ProviderEngine(session: makeEngineSession()).fetchValue(spec: spec, key: "k1")
        }
        #expect(EngineStubProtocol.requestCount == 0)
    }

    // Native-adapter specs must never execute as generic GETs.
    @Test func nonGenericAdapterIsRefused() async throws {
        EngineStubProtocol.requestCount = 0
        var spec = makeSpec()
        spec.adapter = .openAISpend
        await #expect(throws: FetchError.undecodable) {
            _ = try await ProviderEngine(session: makeEngineSession()).fetchValue(spec: spec, key: "k1")
        }
        #expect(EngineStubProtocol.requestCount == 0)
    }

}
