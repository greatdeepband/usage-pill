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
    private var loaded = false

    init(cache: CredentialsCache, fetchProfile: @escaping () async throws -> Profile) {
        self.cache = cache
        self.fetchProfile = fetchProfile
    }

    /// Idempotent per launch; call when the toggle is (or becomes) on.
    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        Task { @MainActor in
            if let creds = try? await cache.credentials() {
                planBadge = PlanBadge.text(
                    subscriptionType: creds.subscriptionType,
                    rateLimitTier: creds.rateLimitTier
                )
            }
            email = (try? await fetchProfile())?.email
        }
    }
}
