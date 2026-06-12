import Foundation

/// In-memory credential cache with negative caching. The keychain is touched
/// only on first load and when a 401 proves the token rotated.
///
/// **Negative caching**: a failed load (e.g. a denied keychain prompt) is
/// remembered for `reloadThrottle` seconds. This prevents a 60 s poll loop
/// from re-triggering the keychain prompt every cycle after the user dismisses
/// it once.
///
/// **Two separate timestamps**: `lastForcedReload` is set only by
/// `reloadAfterUnauthorized()`. It is deliberately NOT set by a successful
/// initial load so that a token rotating right after launch can still be
/// reloaded via the forced path.
public actor CredentialsCache {
    private let load: @Sendable () throws -> OAuthCredentials
    private let now: @Sendable () -> Date
    private let reloadThrottle: TimeInterval
    private let cacheTTL: TimeInterval
    /// Minimum spacing between re-reads triggered by a past-expiry cached token.
    private let expiredRecheckFloor: TimeInterval = 60
    private var cached: OAuthCredentials?
    private var loadedAt: Date?
    private var lastFailedLoad: (at: Date, error: Error)?  // negative cache
    private var lastForcedReload: Date?

    public init(
        load: @escaping @Sendable () throws -> OAuthCredentials,
        reloadThrottle: TimeInterval = 600,
        cacheTTL: TimeInterval = 1800,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.load = load
        self.reloadThrottle = reloadThrottle
        self.cacheTTL = cacheTTL
        self.now = now
    }

    /// Returns cached credentials, loading from the underlying provider only
    /// when nothing is cached yet — or silently REFRESHING the cache when it
    /// has outlived `cacheTTL`, or within `expiredRecheckFloor` when the
    /// cached token is past its own expiry stamp.
    ///
    /// The TTL exists because a 401 is not the only way a stale token fails:
    /// the server can answer a long-stale token with 429 (observed in the
    /// field), and the 401-triggered reload path never fires. The TTL bounds
    /// how long the cache can diverge from the keychain regardless of which
    /// status codes come back. A failed refresh keeps serving the cached
    /// token — degrading to the last-known credential, never erroring.
    ///
    /// If the most recent load attempt failed within the throttle window,
    /// the cached error is rethrown immediately — no second call to the
    /// loader, no second keychain prompt.
    public func credentials() throws -> OAuthCredentials {
        if let current = cached {
            let age = loadedAt.map { now().timeIntervalSince($0) } ?? .infinity
            let pastExpiry = current.expiresAt.map { $0 <= now() } ?? false
            let refreshDue = age >= cacheTTL || (pastExpiry && age >= expiredRecheckFloor)
            guard refreshDue else { return current }
            if let fresh = try? load() {
                cached = fresh
                loadedAt = now()
                lastFailedLoad = nil
                return fresh
            }
            // Refresh failed (e.g. transient keychain hiccup): keep serving
            // the cached token; the next due window will try again.
            loadedAt = now() // don't retry the loader on every poll
            return current
        }
        // Negative cache: a failed load (e.g. denied keychain prompt) is not
        // retried within the throttle window — this is what stops a poll loop
        // from re-prompting every cycle.
        if let failure = lastFailedLoad,
           now().timeIntervalSince(failure.at) < reloadThrottle {
            throw failure.error
        }
        do {
            let fresh = try load()
            cached = fresh
            loadedAt = now()
            lastFailedLoad = nil
            return fresh
        } catch {
            lastFailedLoad = (now(), error)
            throw error
        }
    }

    /// Called after a 401: reloads credentials, throttled. Returns the
    /// reloaded credentials ONLY if the token actually changed (rotation);
    /// returns nil when throttled or when the reloaded token is identical —
    /// in both cases a retry would be pointless.
    ///
    /// Short-circuit: if `cached?.accessToken` already differs from `tokenUsed`,
    /// another concurrent caller already completed a reload — return the current
    /// cached token immediately without touching the loader or the throttle.
    ///
    /// On a throwing reload, drops the cached token (so the UI shows the
    /// sign-in state instead of flapping between stale/unauthorized) and
    /// negative-caches the failure so the next poll's `credentials()` does
    /// not immediately re-prompt.
    public func reloadAfterUnauthorized(tokenUsed: String) throws -> OAuthCredentials? {
        // Short-circuit: another caller already rotated the token.
        if let current = cached, current.accessToken != tokenUsed {
            return current
        }
        if let last = lastForcedReload, now().timeIntervalSince(last) < reloadThrottle {
            return nil
        }
        lastForcedReload = now()
        let old = cached?.accessToken
        do {
            let fresh = try load()
            cached = fresh
            loadedAt = now()
            lastFailedLoad = nil
            return fresh.accessToken == old ? nil : fresh
        } catch {
            // Drop the poisoned token so the UI shows the sign-in state instead
            // of flapping between stale/unauthorized; negative-cache the failure
            // so the next poll's credentials() doesn't immediately re-prompt.
            cached = nil
            lastFailedLoad = (now(), error)
            throw error
        }
    }
}
