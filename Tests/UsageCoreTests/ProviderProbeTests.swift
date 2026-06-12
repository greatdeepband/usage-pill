import Foundation
import Testing
@testable import UsageCore

// ---------------------------------------------------------------------------
// Own URLProtocol subclass — isolated from all other suites' statics.
// ---------------------------------------------------------------------------
final class ProbeStubProtocol: URLProtocol, @unchecked Sendable {
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

private func makeProbeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ProbeStubProtocol.self]
    return URLSession(configuration: config)
}

private func makeProbeResponse(
    statusCode: Int,
    url: URL = URL(string: "https://api.example.com/balance")!
) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

// ---------------------------------------------------------------------------
// Tests — serialized within this suite.
// ---------------------------------------------------------------------------
@Suite(.serialized)
struct ProviderProbeTests {

    // 1. DeepSeek-shaped body: numeric strings and a boolean.
    //    discover() must return a field for "balance_infos.0.total_balance" == 110.53
    //    and must NOT include any field for the boolean "is_available".
    @Test func flattensNumericLeavesWithPaths() async throws {
        let json = """
        {
            "balance_infos": [
                {
                    "currency": "USD",
                    "total_balance": "110.53",
                    "granted_balance": "0.00",
                    "topped_up_balance": "110.53",
                    "is_available": true
                }
            ]
        }
        """
        ProbeStubProtocol.handler = { _ in
            (Data(json.utf8), makeProbeResponse(statusCode: 200))
        }
        let probe = ProviderProbe(session: makeProbeSession())
        let fields = try await probe.discover(url: "https://api.example.com/balance", key: "k1")

        // Must contain the balance field with correct value
        let balanceField = fields.first { $0.path == "balance_infos.0.total_balance" }
        #expect(balanceField != nil)
        #expect(balanceField?.value == 110.53)

        // Must NOT contain the boolean field
        let boolField = fields.first { $0.path == "balance_infos.0.is_available" }
        #expect(boolField == nil)
    }

    // 2. Dict keys are flattened in sorted (alphabetical) order.
    @Test func sortedDeterministically() async throws {
        // Pure flatten test — no network needed
        let obj: [String: Any] = ["zebra": 3.0, "apple": 1.0, "mango": 2.0]
        var fields: [DiscoveredField] = []
        ProviderProbe.flatten(obj, path: "", depth: 0, into: &fields)
        let paths = fields.map(\.path)
        #expect(paths == ["apple", "mango", "zebra"])
        #expect(fields.map(\.value) == [1.0, 2.0, 3.0])
    }

    // 3. Depth cap: no path longer than 6 components;
    //    Field cap: exactly 50 results when more than 50 are available.
    @Test func capsDepthAndFieldCount() async throws {
        // Build a deeply nested object (8 levels)
        let deep: [String: Any] = [
            "a": ["b": ["c": ["d": ["e": ["f": ["g": ["h": 42.0]]]]]]]
        ]
        var deepFields: [DiscoveredField] = []
        ProviderProbe.flatten(deep, path: "", depth: 0, into: &deepFields)
        // The 8-level leaf is BEYOND the cap → nothing returned at all.
        #expect(deepFields.isEmpty)

        // Positive borderline: a leaf reached at exactly depth 6 IS returned —
        // this is the live coverage of the cap (without it, the cap could be
        // broken to `depth <= 0` and the test above would still pass).
        let borderline: [String: Any] = ["a": ["b": ["c": ["d": ["e": ["f": 42.0]]]]]]
        var borderFields: [DiscoveredField] = []
        ProviderProbe.flatten(borderline, path: "", depth: 0, into: &borderFields)
        #expect(borderFields.count == 1)
        #expect(borderFields.first?.path == "a.b.c.d.e.f")

        // Build an object with 60 numeric fields
        var wideObj: [String: Any] = [:]
        for i in 0..<60 { wideObj["field\(String(format: "%02d", i))"] = Double(i) }
        var wideFields: [DiscoveredField] = []
        ProviderProbe.flatten(wideObj, path: "", depth: 0, into: &wideFields)
        #expect(wideFields.count == 50)
    }

    // 4. No numeric leaves → empty result.
    @Test func emptyWhenNoNumbers() async throws {
        let obj: [String: Any] = ["a": "x", "b": true]
        var fields: [DiscoveredField] = []
        ProviderProbe.flatten(obj, path: "", depth: 0, into: &fields)
        #expect(fields.isEmpty)
    }

    // 5. 401 → .unauthorized; 200 + "nope" → .undecodable.
    @Test func authAndGarbageMapLikeEngine() async throws {
        let probe = ProviderProbe(session: makeProbeSession())

        ProbeStubProtocol.handler = { _ in (Data(), makeProbeResponse(statusCode: 401)) }
        await #expect(throws: FetchError.unauthorized) {
            _ = try await probe.discover(url: "https://api.example.com/balance", key: "k1")
        }

        ProbeStubProtocol.handler = { _ in (Data("nope".utf8), makeProbeResponse(statusCode: 200)) }
        await #expect(throws: FetchError.undecodable) {
            _ = try await probe.discover(url: "https://api.example.com/balance", key: "k1")
        }
    }
}
