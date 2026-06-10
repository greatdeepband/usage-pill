import Foundation
import Testing
@testable import UsageCore

// ---------------------------------------------------------------------------
// URLProtocol stub — one handler per test; tests are .serialized to avoid races.
// ---------------------------------------------------------------------------
final class StubProtocol: URLProtocol, @unchecked Sendable {
    /// Set this before each test; the stub calls it to produce (Data, HTTPURLResponse).
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

private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: config)
}

private func makeResponse(statusCode: Int, url: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

// ---------------------------------------------------------------------------
// Tests — serialized so the shared nonisolated(unsafe) handler cannot race.
// ---------------------------------------------------------------------------
@Suite(.serialized)
struct UsageFetcherLiveTests {

    // (a) 401 → throws FetchError.unauthorized
    @Test func returns401AsUnauthorized() async throws {
        StubProtocol.handler = { _ in (Data(), makeResponse(statusCode: 401)) }
        let fetcher = UsageFetcher(
            loadCredentials: { OAuthCredentials(accessToken: "tok", expiresAt: nil) },
            session: makeSession()
        )
        await #expect(throws: FetchError.unauthorized) {
            _ = try await fetcher.fetch()
        }
    }

    // (b) 200 + garbage body → throws FetchError.undecodable
    @Test func returns200WithGarbodyAsUndecodable() async throws {
        StubProtocol.handler = { _ in (Data("not-json".utf8), makeResponse(statusCode: 200)) }
        let fetcher = UsageFetcher(
            loadCredentials: { OAuthCredentials(accessToken: "tok", expiresAt: nil) },
            session: makeSession()
        )
        await #expect(throws: FetchError.undecodable) {
            _ = try await fetcher.fetch()
        }
    }

    // (c) loadCredentials throws CredentialsError.notFound → propagates without network hit
    @Test func propagatesCredentialsError() async throws {
        var networkHit = false
        StubProtocol.handler = { _ in networkHit = true; return (Data(), makeResponse(statusCode: 200)) }
        let fetcher = UsageFetcher(
            loadCredentials: { throw CredentialsError.notFound },
            session: makeSession()
        )
        await #expect(throws: CredentialsError.notFound) {
            _ = try await fetcher.fetch()
        }
        #expect(networkHit == false)
    }

    // (d) 200 + valid minimal JSON → returns decoded snapshot
    @Test func decodesValidResponse() async throws {
        let json = #"{"five_hour":{"utilization":50.0,"resets_at":"2026-06-11T00:49:59Z"}}"#
        StubProtocol.handler = { _ in (Data(json.utf8), makeResponse(statusCode: 200)) }
        let fetcher = UsageFetcher(
            loadCredentials: { OAuthCredentials(accessToken: "tok", expiresAt: nil) },
            session: makeSession()
        )
        let snap = try await fetcher.fetch()
        #expect(snap.session?.utilization == 50.0)
        #expect(snap.session?.resetsAt != nil)
    }
}
