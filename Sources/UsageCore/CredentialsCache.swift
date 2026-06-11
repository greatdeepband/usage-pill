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
    private var cached: OAuthCredentials?
    private var lastFailedLoad: (at: Date, error: Error)?  // negative cache
    private var lastForcedReload: Date?

    public init(
        load: @escaping @Sendable () throws -> OAuthCredentials,
        reloadThrottle: TimeInterval = 600,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.load = load
        self.reloadThrottle = reloadThrottle
        self.now = now
    }

    /// Returns cached credentials, loading from the underlying provider only
    /// when nothing is cached yet.
    ///
    /// If the most recent load attempt failed within the throttle window,
    /// the cached error is rethrown immediately — no second call to the
    /// loader, no second keychain prompt.
    public func credentials() throws -> OAuthCredentials {
        if let cached { return cached }
        // Negative cache: a failed load (e.g. denied keychain prompt) is not
        // retried within the throttle window — this is what stops a 60s poll
        // from re-prompting every cycle.
        if let failure = lastFailedLoad,
           now().timeIntervalSince(failure.at) < reloadThrottle {
            throw failure.error
        }
        do {
            let fresh = try load()
            cached = fresh
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
