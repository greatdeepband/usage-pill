import Foundation
import Testing
@testable import UsageCore

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

private func makeToken(_ id: String) -> OAuthCredentials {
    OAuthCredentials(accessToken: id, expiresAt: nil)
}

// ---------------------------------------------------------------------------
// CredentialsCache tests
// ---------------------------------------------------------------------------

@Suite struct CredentialsCacheTests {

    // 1. loadsOnceAndCaches
    // Two calls to credentials() should only invoke the loader once.
    @Test func loadsOnceAndCaches() async throws {
        nonisolated(unsafe) var callCount = 0
        let cache = CredentialsCache(load: {
            callCount += 1
            return makeToken("tokenA")
        })
        let first = try await cache.credentials()
        let second = try await cache.credentials()
        #expect(first.accessToken == "tokenA")
        #expect(second.accessToken == "tokenA")
        #expect(callCount == 1)
    }

    // 2. reloadAfterUnauthorizedDetectsRotation
    // After a 401, if the loader returns a NEW token, reloadAfterUnauthorized() returns it.
    @Test func reloadAfterUnauthorizedDetectsRotation() async throws {
        nonisolated(unsafe) var callCount = 0
        let tokens = ["tokenA", "tokenB"]
        let cache = CredentialsCache(load: {
            let t = tokens[min(callCount, tokens.count - 1)]
            callCount += 1
            return makeToken(t)
        })
        let initial = try await cache.credentials()
        #expect(initial.accessToken == "tokenA")

        let reloaded = try await cache.reloadAfterUnauthorized(tokenUsed: initial.accessToken)
        #expect(reloaded?.accessToken == "tokenB")
    }

    // 3. reloadReturnsNilWhenTokenUnchanged
    // If the loader returns the SAME token, reloadAfterUnauthorized() returns nil
    // (a retry with the same token would be pointless).
    @Test func reloadReturnsNilWhenTokenUnchanged() async throws {
        let cache = CredentialsCache(load: { makeToken("tokenA") })
        _ = try await cache.credentials()
        let result = try await cache.reloadAfterUnauthorized(tokenUsed: "tokenA")
        #expect(result == nil)
    }

    // 4. reloadIsThrottled
    // A second reloadAfterUnauthorized() called within the throttle window returns
    // nil without hitting the loader. Advancing past the window makes it work again.
    @Test func reloadIsThrottled() async throws {
        nonisolated(unsafe) var clockOffset: TimeInterval = 0
        nonisolated(unsafe) var callCount = 0
        nonisolated(unsafe) var tokenSuffix = 0

        let cache = CredentialsCache(
            load: {
                callCount += 1
                tokenSuffix += 1
                return makeToken("token\(tokenSuffix)")
            },
            reloadThrottle: 600,
            now: { Date(timeIntervalSinceReferenceDate: clockOffset) }
        )

        // Warm the cache (token1)
        _ = try await cache.credentials()
        // callCount == 1 here

        // First forced reload at t=0: returns token2 (rotated)
        let first = try await cache.reloadAfterUnauthorized(tokenUsed: "token1")
        #expect(first?.accessToken == "token2")
        let countAfterFirst = callCount  // should be 2

        // Immediately second reload (still t=0): caller already has token2, no
        // short-circuit applies; throttle kicks in → nil, loader NOT called.
        let second = try await cache.reloadAfterUnauthorized(tokenUsed: "token2")
        #expect(second == nil)
        #expect(callCount == countAfterFirst) // loader was NOT hit

        // Advance clock past throttle window
        clockOffset = 601
        // Third reload: throttle expired, loader called → returns token3
        let third = try await cache.reloadAfterUnauthorized(tokenUsed: "token2")
        #expect(third?.accessToken == "token3")
        #expect(callCount == countAfterFirst + 1)
    }

    // 5. loaderErrorsPropagate
    // If the loader throws, credentials() propagates the error.
    @Test func loaderErrorsPropagate() async throws {
        let cache = CredentialsCache(load: { throw CredentialsError.notFound })
        await #expect(throws: CredentialsError.notFound) {
            _ = try await cache.credentials()
        }
    }

    // 6. failedLoadIsNegativeCached
    // After a failing credentials() call, a second call within the throttle
    // window re-throws the cached error without invoking the loader again.
    // Advancing the injected clock past the window allows the loader to be
    // called once more.
    @Test func failedLoadIsNegativeCached() async throws {
        nonisolated(unsafe) var clockOffset: TimeInterval = 0
        nonisolated(unsafe) var callCount = 0

        let cache = CredentialsCache(
            load: {
                callCount += 1
                throw CredentialsError.notFound
            },
            reloadThrottle: 600,
            now: { Date(timeIntervalSinceReferenceDate: clockOffset) }
        )

        // First call: loader invoked, error propagated, negative-cache populated.
        await #expect(throws: CredentialsError.notFound) {
            _ = try await cache.credentials()
        }
        #expect(callCount == 1)

        // Second call within window: cached error rethrown, loader NOT called again.
        await #expect(throws: CredentialsError.notFound) {
            _ = try await cache.credentials()
        }
        #expect(callCount == 1)

        // Advance clock past throttle window.
        clockOffset = 601

        // Third call: negative cache expired → loader called again.
        await #expect(throws: CredentialsError.notFound) {
            _ = try await cache.credentials()
        }
        #expect(callCount == 2)
    }

    // 7. reloadShortCircuitsWhenAnotherCallerAlreadyRotated
    // If another concurrent caller already reloaded a rotated token, a second
    // caller still holding the old token should get the already-rotated token
    // back immediately — without hitting the loader or consuming the throttle.
    @Test func reloadShortCircuitsWhenAnotherCallerAlreadyRotated() async throws {
        nonisolated(unsafe) var loaderCallCount = 0
        let tokens = ["tokenA", "tokenB"]
        let cache = CredentialsCache(load: {
            let t = tokens[min(loaderCallCount, tokens.count - 1)]
            loaderCallCount += 1
            return makeToken(t)
        })

        // caller 1: credentials() → tokenA (loader call #1)
        let credsA = try await cache.credentials()
        #expect(credsA.accessToken == "tokenA")
        #expect(loaderCallCount == 1)

        // caller 1: reloadAfterUnauthorized(tokenUsed: "tokenA") → tokenB (loader call #2)
        let reloaded = try await cache.reloadAfterUnauthorized(tokenUsed: "tokenA")
        #expect(reloaded?.accessToken == "tokenB")
        #expect(loaderCallCount == 2)

        // caller 2 (still holding tokenA): short-circuit — cached is tokenB ≠ tokenA
        // → returns tokenB immediately without calling the loader again.
        let shortCircuited = try await cache.reloadAfterUnauthorized(tokenUsed: "tokenA")
        #expect(shortCircuited?.accessToken == "tokenB")
        #expect(loaderCallCount == 2)  // loader NOT called a third time
    }

    // 8. throwingForcedReloadDropsCacheAndNegativeCaches
    // When reloadAfterUnauthorized() throws, the cached token is dropped and
    // the failure is negative-cached so the next credentials() call within the
    // window throws immediately without calling the loader — no re-prompt.
    @Test func throwingForcedReloadDropsCacheAndNegativeCaches() async throws {
        nonisolated(unsafe) var clockOffset: TimeInterval = 0
        nonisolated(unsafe) var callCount = 0

        // Loader returns tokenA on the first call, then throws .notFound.
        let cache = CredentialsCache(
            load: {
                callCount += 1
                if callCount == 1 { return makeToken("tokenA") }
                throw CredentialsError.notFound
            },
            reloadThrottle: 600,
            now: { Date(timeIntervalSinceReferenceDate: clockOffset) }
        )

        // Warm the cache with tokenA.
        let creds = try await cache.credentials()
        #expect(creds.accessToken == "tokenA")
        #expect(callCount == 1)

        // Forced reload at t=0: loader throws; poisoned token is dropped.
        await #expect(throws: CredentialsError.notFound) {
            _ = try await cache.reloadAfterUnauthorized(tokenUsed: "tokenA")
        }
        #expect(callCount == 2)

        // Immediately after, credentials() within the window: must throw .notFound
        // WITHOUT calling the loader (negative cache in effect; poisoned token gone).
        await #expect(throws: CredentialsError.notFound) {
            _ = try await cache.credentials()
        }
        #expect(callCount == 2)  // loader count pinned — no re-prompt
    }
}

// MARK: - v1.2.3: cache TTL + expiry-aware refresh (the 429-masks-401 trap)

@Test func pastExpiryCachedTokenIsRefreshedFromLoader() async throws {
    let clock = CacheClockBox(Date(timeIntervalSince1970: 0))
    let counter = CacheCallCounter()
    let stale = OAuthCredentials(
        accessToken: "tokenStale",
        expiresAt: Date(timeIntervalSince1970: 10) // expires almost immediately
    )
    let fresh = OAuthCredentials(accessToken: "tokenFresh", expiresAt: nil)
    let cache = CredentialsCache(
        load: {
            counter.increment()
            return counter.count == 1 ? stale : fresh
        },
        now: { clock.now }
    )
    #expect(try await cache.credentials().accessToken == "tokenStale")
    // Past expiry but inside the 60s recheck floor → still cached, loader untouched.
    clock.now = Date(timeIntervalSince1970: 30)
    #expect(try await cache.credentials().accessToken == "tokenStale")
    #expect(counter.count == 1)
    // Past expiry AND past the floor → silently re-read; new token served.
    clock.now = Date(timeIntervalSince1970: 61)
    #expect(try await cache.credentials().accessToken == "tokenFresh")
    #expect(counter.count == 2)
}

@Test func cacheTTLRefreshesEvenAValidToken() async throws {
    let clock = CacheClockBox(Date(timeIntervalSince1970: 0))
    let counter = CacheCallCounter()
    let a = OAuthCredentials(accessToken: "tokenA", expiresAt: Date(timeIntervalSince1970: 1_000_000))
    let b = OAuthCredentials(accessToken: "tokenB", expiresAt: Date(timeIntervalSince1970: 1_000_000))
    let cache = CredentialsCache(
        load: {
            counter.increment()
            return counter.count == 1 ? a : b
        },
        now: { clock.now }
    )
    _ = try await cache.credentials()
    clock.now = Date(timeIntervalSince1970: 1799) // inside TTL
    #expect(try await cache.credentials().accessToken == "tokenA")
    #expect(counter.count == 1)
    clock.now = Date(timeIntervalSince1970: 1801) // past TTL
    #expect(try await cache.credentials().accessToken == "tokenB")
    #expect(counter.count == 2)
}

@Test func failedTTLRefreshKeepsServingCachedToken() async throws {
    let clock = CacheClockBox(Date(timeIntervalSince1970: 0))
    let counter = CacheCallCounter()
    let a = OAuthCredentials(accessToken: "tokenA", expiresAt: nil)
    let cache = CredentialsCache(
        load: {
            counter.increment()
            if counter.count == 1 { return a }
            throw CredentialsError.notFound
        },
        now: { clock.now }
    )
    _ = try await cache.credentials()
    clock.now = Date(timeIntervalSince1970: 1801) // TTL due, refresh will throw
    #expect(try await cache.credentials().accessToken == "tokenA") // degrade, don't error
    #expect(counter.count == 2)
    // The failed refresh must not retry the loader on every subsequent poll.
    clock.now = Date(timeIntervalSince1970: 1810)
    _ = try await cache.credentials()
    #expect(counter.count == 2)
}

private final class CacheClockBox: @unchecked Sendable {
    var now: Date
    init(_ d: Date) { now = d }
}

private final class CacheCallCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}
