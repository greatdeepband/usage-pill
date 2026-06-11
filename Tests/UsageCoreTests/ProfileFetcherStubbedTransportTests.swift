import Foundation
import Testing
@testable import UsageCore

// ---------------------------------------------------------------------------
// Separate URLProtocol subclass so this suite's handler does NOT share state
// with StubProtocol used by UsageFetcherStubbedTransportTests. The two suites
// can then run concurrently at the suite level without racing on a shared static.
// Within this suite, @Suite(.serialized) serialises tests so per-test handler
// assignments remain race-free.
// ---------------------------------------------------------------------------
final class ProfileStubProtocol: URLProtocol, @unchecked Sendable {
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

private func makeProfileSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ProfileStubProtocol.self]
    return URLSession(configuration: config)
}

private func makeProfileResponse(statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.anthropic.com/api/oauth/profile")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

private func makeProfileCache(token: String = "tok") -> CredentialsCache {
    CredentialsCache(load: { OAuthCredentials(accessToken: token, expiresAt: nil) })
}

// ---------------------------------------------------------------------------
// Tests — serialized within this suite; isolated from UsageFetcherLiveTests
// via the separate ProfileStubProtocol class and its own handler static.
// ---------------------------------------------------------------------------
@Suite(.serialized)
struct ProfileFetcherStubbedTransportTests {

    // 1. Every response 401, loader returns same token → reloadAfterUnauthorized
    //    returns nil (token unchanged) → throws FetchError.unauthorized, 1 request.
    @Test func profile401WithStableTokenThrowsUnauthorized() async throws {
        var requestCount = 0
        ProfileStubProtocol.handler = { _ in
            requestCount += 1
            return (Data(), makeProfileResponse(statusCode: 401))
        }
        let fetcher = ProfileFetcher(cache: makeProfileCache(token: "sameToken"), session: makeProfileSession())
        await #expect(throws: FetchError.unauthorized) {
            _ = try await fetcher.fetch()
        }
        #expect(requestCount == 1)
    }

    // 2. 401 then 200 with valid body, loader rotates tokenA→tokenB →
    //    returns Profile(email: "a@b.c"), 2 requests, second carries "Bearer tokenB".
    @Test func profile401WithRotatedTokenRetriesOnce() async throws {
        var requestCount = 0
        var observedAuthHeaders: [String] = []

        ProfileStubProtocol.handler = { req in
            requestCount += 1
            if let auth = req.value(forHTTPHeaderField: "Authorization") {
                observedAuthHeaders.append(auth)
            }
            if requestCount == 1 {
                return (Data(), makeProfileResponse(statusCode: 401))
            } else {
                let json = #"{"account":{"email":"a@b.c"}}"#
                return (Data(json.utf8), makeProfileResponse(statusCode: 200))
            }
        }

        nonisolated(unsafe) var loadCount = 0
        let tokens = ["tokenA", "tokenB"]
        let cache = CredentialsCache(load: {
            let t = tokens[min(loadCount, tokens.count - 1)]
            loadCount += 1
            return OAuthCredentials(accessToken: t, expiresAt: nil)
        })

        let fetcher = ProfileFetcher(cache: cache, session: makeProfileSession())
        let profile = try await fetcher.fetch()
        #expect(profile.email == "a@b.c")
        #expect(requestCount == 2)
        #expect(observedAuthHeaders == ["Bearer tokenA", "Bearer tokenB"])
    }

    // 3. Loader throws CredentialsError.notFound → fetch() throws CredentialsError, 0 network requests.
    @Test func profileCredentialErrorPropagates() async throws {
        var networkHit = false
        ProfileStubProtocol.handler = { _ in
            networkHit = true
            return (Data(), makeProfileResponse(statusCode: 200))
        }
        let cache = CredentialsCache(load: { throw CredentialsError.notFound })
        let fetcher = ProfileFetcher(cache: cache, session: makeProfileSession())
        await #expect(throws: CredentialsError.notFound) {
            _ = try await fetcher.fetch()
        }
        #expect(networkHit == false)
    }

    // 4. 200 + "not json" → FetchError.undecodable.
    @Test func profileGarbageBodyThrowsUndecodable() async throws {
        ProfileStubProtocol.handler = { _ in
            (Data("not json".utf8), makeProfileResponse(statusCode: 200))
        }
        let fetcher = ProfileFetcher(cache: makeProfileCache(), session: makeProfileSession())
        await #expect(throws: FetchError.undecodable) {
            _ = try await fetcher.fetch()
        }
    }

    // 5. Stub throws URLError(.cancelled) → fetch() throws CancellationError.
    @Test func profileUrlCancelledNormalizes() async throws {
        ProfileStubProtocol.handler = { _ in throw URLError(.cancelled) }
        let fetcher = ProfileFetcher(cache: makeProfileCache(), session: makeProfileSession())
        await #expect(throws: CancellationError.self) {
            _ = try await fetcher.fetch()
        }
    }
}
