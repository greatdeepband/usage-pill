import Foundation
import Testing
@testable import UsageCore

// ---------------------------------------------------------------------------
// Own URLProtocol subclass — isolated from all other suites' statics.
// ---------------------------------------------------------------------------
final class SpendStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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

private func makeSpendSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SpendStubProtocol.self]
    return URLSession(configuration: config)
}

private func makeSpendResponse(
    statusCode: Int,
    url: URL = URL(string: "https://api.openai.com/v1/organization/costs")!,
    headerFields: [String: String]? = nil
) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headerFields)!
}

private func makeSpendSpec() -> ProviderSpec {
    ProviderSpec(
        id: UUID(), displayName: "OpenAI", adapter: .openAISpend,
        url: "https://api.openai.com/v1/organization/costs",
        headerName: "Authorization", headerTemplate: "Bearer {key}",
        valuePath: "", subtractPath: nil, scale: 1,
        valueKind: .currency, currencyCode: "USD", warnBelow: nil,
        visibility: .pinned
    )
}

// Fixture (shape per OpenAI Costs API docs):
private let costsBody = #"""
{"object":"page","data":[
  {"object":"bucket","start_time":1764547200,"end_time":1764633600,
   "results":[{"object":"organization.costs.result","amount":{"value":1.25,"currency":"usd"}}]},
  {"object":"bucket","start_time":1764633600,"end_time":1764720000,
   "results":[{"object":"organization.costs.result","amount":{"value":2.50,"currency":"usd"}},
              {"object":"organization.costs.result","amount":{"value":0.25,"currency":"usd"}}]}
],"has_more":false,"next_page":null}
"""#

// ---------------------------------------------------------------------------
// Tests — serialized within this suite.
// ---------------------------------------------------------------------------
@Suite(.serialized)
struct OpenAISpendAdapterTests {

    @Test func sumsAllBucketsAndResults() async throws {
        nonisolated(unsafe) var capturedRequest: URLRequest?
        SpendStubProtocol.handler = { req in
            capturedRequest = req
            return (Data(costsBody.utf8), makeSpendResponse(statusCode: 200))
        }
        let adapter = OpenAISpendAdapter(session: makeSpendSession())
        let value = try await adapter.fetchValue(spec: makeSpendSpec(), key: "admin-key")
        #expect(value == 4.0) // 1.25 + 2.50 + 0.25
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer admin-key")
    }

    @Test func monthWindowStartsAtUTCMonthStart() async throws {
        // Injected now = 2026-06-15T10:30:00Z
        // Expected start_time = 2026-06-01T00:00:00Z — compute from DateComponents, not hardcoded.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 1
        comps.hour = 0; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        let expectedStart = Calendar(identifier: .gregorian).date(from: comps)!
        let expectedEpoch = Int(expectedStart.timeIntervalSince1970)

        var injectedNowComps = DateComponents()
        injectedNowComps.year = 2026; injectedNowComps.month = 6; injectedNowComps.day = 15
        injectedNowComps.hour = 10; injectedNowComps.minute = 30; injectedNowComps.second = 0
        injectedNowComps.timeZone = TimeZone(identifier: "UTC")
        let injectedNow = Calendar(identifier: .gregorian).date(from: injectedNowComps)!

        nonisolated(unsafe) var capturedURL: URL?
        SpendStubProtocol.handler = { req in
            capturedURL = req.url
            return (Data(costsBody.utf8), makeSpendResponse(statusCode: 200))
        }
        let adapter = OpenAISpendAdapter(session: makeSpendSession(), now: { injectedNow })
        _ = try await adapter.fetchValue(spec: makeSpendSpec(), key: "k")
        let components = URLComponents(url: capturedURL!, resolvingAgainstBaseURL: false)
        let startTimeParam = components?.queryItems?.first(where: { $0.name == "start_time" })?.value
        #expect(startTimeParam == String(expectedEpoch))
    }

    @Test func emptyDataSumsToZero() async throws {
        let emptyBody = #"{"data":[],"has_more":false}"#
        SpendStubProtocol.handler = { _ in
            (Data(emptyBody.utf8), makeSpendResponse(statusCode: 200))
        }
        let adapter = OpenAISpendAdapter(session: makeSpendSession())
        let value = try await adapter.fetchValue(spec: makeSpendSpec(), key: "k")
        #expect(value == 0.0)
    }

    @Test func mapsAuthRateLimitGarbage() async throws {
        let adapter = OpenAISpendAdapter(session: makeSpendSession())
        let spec = makeSpendSpec()

        // 401 → .unauthorized
        SpendStubProtocol.handler = { _ in (Data(), makeSpendResponse(statusCode: 401)) }
        await #expect(throws: FetchError.unauthorized) {
            _ = try await adapter.fetchValue(spec: spec, key: "k")
        }

        // 429 with Retry-After: 60 → .rateLimited(60)
        SpendStubProtocol.handler = { _ in
            (Data(), makeSpendResponse(statusCode: 429, headerFields: ["Retry-After": "60"]))
        }
        await #expect(throws: FetchError.rateLimited(retryAfter: 60)) {
            _ = try await adapter.fetchValue(spec: spec, key: "k")
        }

        // 200 with garbage body → .undecodable
        SpendStubProtocol.handler = { _ in (Data("nope".utf8), makeSpendResponse(statusCode: 200)) }
        await #expect(throws: FetchError.undecodable) {
            _ = try await adapter.fetchValue(spec: spec, key: "k")
        }
    }

    @Test func missingAmountsAreSkippedNotFatal() async throws {
        // One result has amount.value, one is missing it — only the good one sums.
        let body = #"""
        {"data":[
          {"results":[
            {"amount":{"value":5.0,"currency":"usd"}},
            {"no_amount_field":"x"}
          ]}
        ],"has_more":false}
        """#
        SpendStubProtocol.handler = { _ in
            (Data(body.utf8), makeSpendResponse(statusCode: 200))
        }
        let adapter = OpenAISpendAdapter(session: makeSpendSession())
        let value = try await adapter.fetchValue(spec: makeSpendSpec(), key: "k")
        #expect(value == 5.0)
    }
}
