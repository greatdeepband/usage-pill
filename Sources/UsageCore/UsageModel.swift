import Foundation
import Combine

@MainActor
public final class UsageModel: ObservableObject {
    public enum StaleReason: Equatable, Sendable {
        case noCredentials, unauthorized, network
    }

    public enum Status: Equatable, Sendable {
        case loading                  // never fetched successfully yet
        case ok
        case stale(reason: StaleReason)
    }

    @Published public private(set) var snapshot: UsageSnapshot?
    @Published public private(set) var lastSuccess: Date?
    @Published public private(set) var status: Status = .loading

    private let fetch: () async throws -> UsageSnapshot
    private let now: @Sendable () -> Date
    private var inFlight = false

    public init(
        fetch: @escaping () async throws -> UsageSnapshot,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fetch = fetch
        self.now = now
    }

    public func refresh() async {
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
        } catch is CredentialsError {
            status = .stale(reason: .noCredentials)
        } catch let error as FetchError {
            status = .stale(reason: error == .unauthorized ? .unauthorized : .network)
        } catch {
            status = .stale(reason: .network)
        }
    }

    /// True when the footer should turn amber: no successful fetch in >5 min.
    public var isDataOld: Bool {
        guard let lastSuccess else { return true }
        return now().timeIntervalSince(lastSuccess) > 300
    }

    public func secondsSinceSuccess() -> TimeInterval? {
        lastSuccess.map { now().timeIntervalSince($0) }
    }
}
