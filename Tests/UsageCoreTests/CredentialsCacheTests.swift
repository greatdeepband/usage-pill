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

        let reloaded = try await cache.reloadAfterUnauthorized()
        #expect(reloaded?.accessToken == "tokenB")
    }

    // 3. reloadReturnsNilWhenTokenUnchanged
    // If the loader returns the SAME token, reloadAfterUnauthorized() returns nil
    // (a retry with the same token would be pointless).
    @Test func reloadReturnsNilWhenTokenUnchanged() async throws {
        let cache = CredentialsCache(load: { makeToken("tokenA") })
        _ = try await cache.credentials()
        let result = try await cache.reloadAfterUnauthorized()
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
        let first = try await cache.reloadAfterUnauthorized()
        #expect(first?.accessToken == "token2")
        let countAfterFirst = callCount  // should be 2

        // Immediately second reload (still t=0): throttled → nil, loader NOT called
        let second = try await cache.reloadAfterUnauthorized()
        #expect(second == nil)
        #expect(callCount == countAfterFirst) // loader was NOT hit

        // Advance clock past throttle window
        clockOffset = 601
        // Third reload: throttle expired, loader called → returns token3
        let third = try await cache.reloadAfterUnauthorized()
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

    // 7. throwingForcedReloadDropsCacheAndNegativeCaches
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
            _ = try await cache.reloadAfterUnauthorized()
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
