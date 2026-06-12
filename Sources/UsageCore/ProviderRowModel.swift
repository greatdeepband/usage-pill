import Foundation
import Combine

/// Per-provider state machine for scalar values (balances/spend). One
/// instance per visible ProviderSpec. Failures here never touch any other
/// row — no shared state beyond the injected fetch closure.
///
/// Mirrors UsageModel's hard-won discipline: single-flight, force-refresh
/// for explicit user intent, Retry-After-aware backoff with a 240 s floor
/// (the floor sits above the typical per-token throttle window so a retry
/// doesn't land straight back inside it).
@MainActor
public final class ProviderRowModel: ObservableObject {
    public enum RowFailure: Equatable, Sendable { case auth, rateLimited, network }
    public enum Status: Equatable, Sendable { case loading, ok, stale(RowFailure) }

    @Published public private(set) var value: Double?
    @Published public private(set) var lastSuccess: Date?
    @Published public private(set) var status: Status = .loading

    /// Per-LAUNCH high-water mark for the drain bar (Task 18a). Deliberately
    /// NOT persisted: relaunch = bar reads full again. Raised whenever a fresh
    /// value exceeds it (top-up ⇒ new "full"); failures leave it untouched.
    @Published public private(set) var baseline: Double?

    /// value / baseline, clamped 0…1. nil when either side is missing or the
    /// baseline is non-positive (a zero balance can't define "full").
    public var fraction: Double? {
        guard let value, let baseline, baseline > 0 else { return nil }
        return min(max(value / baseline, 0), 1)
    }

    private let fetch: @MainActor () async throws -> Double
    private let now: @Sendable () -> Date
    private var inFlight = false
    private var backoffUntil: Date?

    public init(fetch: @escaping @MainActor () async throws -> Double,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.fetch = fetch
        self.now = now
    }

    /// `force` bypasses the backoff window (explicit user intent); automatic
    /// polls must leave it false.
    public func refresh(force: Bool = false) async {
        if !force, let until = backoffUntil, now() < until { return }
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        do {
            let newValue = try await fetch()
            value = newValue
            if baseline == nil || newValue > baseline! {
                baseline = newValue
            }
            lastSuccess = now()
            status = .ok
            backoffUntil = nil
        } catch is CancellationError {
            // Mid-flight teardown: leave state untouched.
        } catch FetchError.unauthorized {
            status = .stale(.auth)
        } catch FetchError.badResponse(403) {
            // Scope/permission refusal reads as a key problem to the user.
            status = .stale(.auth)
        } catch FetchError.rateLimited(let retryAfter) {
            backoffUntil = now().addingTimeInterval(min(max(retryAfter ?? 300, 240), 3600))
            status = .stale(.rateLimited)
        } catch {
            status = .stale(.network)
        }
    }
}
