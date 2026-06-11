import Foundation
import Combine

@MainActor
public final class UsageModel: ObservableObject {
    public enum StaleReason: Equatable, Sendable {
        case noCredentials, unauthorized, network, rateLimited
    }

    public enum Status: Equatable, Sendable {
        case loading                  // never fetched successfully yet
        case ok
        case stale(reason: StaleReason)
    }

    @Published public private(set) var snapshot: UsageSnapshot?
    @Published public private(set) var lastSuccess: Date?
    @Published public private(set) var status: Status = .loading

    private let fetch: @MainActor () async throws -> UsageSnapshot
    private let now: @Sendable () -> Date
    private var inFlight = false
    private var backoffUntil: Date?

    public init(
        fetch: @escaping @MainActor () async throws -> UsageSnapshot,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fetch = fetch
        self.now = now
    }

    /// `force` bypasses the rate-limit backoff window — used by the user's
    /// explicit "Refresh Now"; automatic polls must leave it false.
    public func refresh(force: Bool = false) async {
        // Backoff guard: if we're in the backoff window, silently skip —
        // keeps the existing status unchanged until the window expires.
        if !force, let until = backoffUntil, now() < until { return }

        // Coalesce: a refresh arriving while one is in flight is dropped —
        // the in-flight result is at most seconds old.
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        do {
            let snap = try await fetch()
            snapshot = snap
            lastSuccess = now()
            status = .ok
            backoffUntil = nil  // clear backoff on success
        } catch is CancellationError {
            // Mid-flight cancellation (app teardown): leave state untouched —
            // it is neither fresh data nor a network problem.
        } catch is CredentialsError {
            status = .stale(reason: .noCredentials)
        } catch FetchError.rateLimited(let retryAfter) {
            // Default 5 min, floor 2 min, cap 1 h.
            let delay = min(max(retryAfter ?? 300, 120), 3600)
            backoffUntil = now().addingTimeInterval(delay)
            status = .stale(reason: .rateLimited)
        } catch let error as FetchError {
            status = .stale(reason: error == .unauthorized ? .unauthorized : .network)
        } catch {
            status = .stale(reason: .network)
        }
    }

    /// Data is considered old after 5 minutes without a successful fetch.
    public var isDataOld: Bool {
        guard let lastSuccess else { return true }
        return now().timeIntervalSince(lastSuccess) > 300
    }

    public func secondsSinceSuccess() -> TimeInterval? {
        lastSuccess.map { now().timeIntervalSince($0) }
    }
}
