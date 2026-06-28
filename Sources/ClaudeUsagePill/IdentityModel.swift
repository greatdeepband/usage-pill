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
    private var tierConfirmed = false  // the multiplier came from the live profile (server truth)

    init(cache: CredentialsCache, fetchProfile: @escaping () async throws -> Profile) {
        self.cache = cache
        self.fetchProfile = fetchProfile
    }

    /// Retries on later calls (hover / toggle-on) until the live profile is
    /// reached, throttled to one attempt per 5 minutes so a hover can't spam the
    /// network. CredentialsCache's own negative caching keeps the keychain quiet.
    ///
    /// The badge must NOT latch its first value: the credential's rate_limit_tier
    /// is server truth ONLY in `organization.rate_limit_tier` from the profile.
    /// The credential's own copy goes stale after a plan change — observed in the
    /// field: credential read `default_claude_max_5x` while the server said
    /// `default_claude_max_20x` after an upgrade (Claude Code never rewrote the
    /// field). So a fallback shows the base plan WITHOUT a multiplier ("MAX")
    /// rather than a wrong one, and we keep retrying until the profile confirms
    /// the real tier.
    /// ponytail: app-target type, no test bundle — verified against the live
    /// /api/oauth/profile response on rebuild.
    func loadIfNeeded() {
        guard !tierConfirmed else { return } // live profile already gave server truth
        guard !inFlight else { return }
        if let last = lastAttempt, Date().timeIntervalSince(last) < 300 { return }
        inFlight = true
        lastAttempt = Date()
        Task { @MainActor in
            defer { inFlight = false }
            let profile = try? await fetchProfile()
            if email == nil {
                email = profile?.email
            }
            if let creds = try? await cache.credentials() {
                // Server tier only — never the credential's stale copy.
                // No profile yet → "MAX"; once it loads → "MAX 20×", then locked.
                planBadge = PlanBadge.text(
                    subscriptionType: creds.subscriptionType,
                    rateLimitTier: profile?.rateLimitTier
                )
                if profile != nil { tierConfirmed = true }
            }
        }
    }
}
