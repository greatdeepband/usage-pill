import Foundation

/// In-memory credential cache. The keychain is touched only on first load and
/// when a 401 proves the token rotated — never on a routine poll. Forced
/// reloads are throttled so a denied keychain prompt cannot recur more than
/// once per `reloadThrottle`.
public actor CredentialsCache {
    private let load: @Sendable () throws -> OAuthCredentials
    private let now: @Sendable () -> Date
    private let reloadThrottle: TimeInterval
    private var cached: OAuthCredentials?
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
    public func credentials() throws -> OAuthCredentials {
        if let cached { return cached }
        let fresh = try load()
        cached = fresh
        return fresh
    }

    /// Called after a 401: drops the cache and reloads, throttled. Returns the
    /// reloaded credentials ONLY if the token actually changed (rotation);
    /// returns nil when throttled or when the reloaded token is identical —
    /// in both cases a retry would be pointless.
    public func reloadAfterUnauthorized() throws -> OAuthCredentials? {
        if let last = lastForcedReload, now().timeIntervalSince(last) < reloadThrottle {
            return nil
        }
        lastForcedReload = now()
        let old = cached?.accessToken
        let fresh = try load()
        cached = fresh
        return fresh.accessToken == old ? nil : fresh
    }
}
