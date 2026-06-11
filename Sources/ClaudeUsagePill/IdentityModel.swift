import Foundation
import UsageCore

/// Plan badge + email for the expanded header strip. Email lives ONLY in this
/// object's memory: never persisted, never logged. Nothing is fetched while
/// the identity toggle is off.
@MainActor
final class IdentityModel: ObservableObject {
    @Published private(set) var planBadge: String?
    @Published private(set) var email: String?

    private let cache: CredentialsCache
    private let fetchProfile: () async throws -> Profile
    private var inFlight = false
    private var lastAttempt: Date?

    init(cache: CredentialsCache, fetchProfile: @escaping () async throws -> Profile) {
        self.cache = cache
        self.fetchProfile = fetchProfile
    }

    /// Retries on later calls (hover / toggle-on) until both fields resolve,
    /// throttled to one attempt per 5 minutes so a hover can't spam the
    /// network. CredentialsCache's own negative caching keeps the keychain
    /// quiet regardless.
    func loadIfNeeded() {
        guard planBadge == nil || email == nil else { return } // fully resolved
        guard !inFlight else { return }
        if let last = lastAttempt, Date().timeIntervalSince(last) < 300 { return }
        inFlight = true
        lastAttempt = Date()
        Task { @MainActor in
            defer { inFlight = false }
            if planBadge == nil, let creds = try? await cache.credentials() {
                planBadge = PlanBadge.text(
                    subscriptionType: creds.subscriptionType,
                    rateLimitTier: creds.rateLimitTier
                )
            }
            if email == nil {
                email = (try? await fetchProfile())?.email
            }
        }
    }
}
