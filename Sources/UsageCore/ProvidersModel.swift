import Foundation
import Combine

/// Aggregates ProviderSpecs into live row models. Hidden specs get no row
/// model and are never fetched. Pure coordination — transport lives in the
/// injected fetcher factory, persistence in the injected stores. A missing
/// key yields an auth-state row WITHOUT invoking any fetcher.
@MainActor
public final class ProvidersModel: ObservableObject {
    public struct Row: Identifiable {
        public let spec: ProviderSpec
        public let model: ProviderRowModel
        public var id: UUID { spec.id }
    }

    @Published public private(set) var rows: [Row] = []

    private let specStore: ProviderSpecStore
    private let keyLookup: @Sendable (UUID) -> String?
    private let makeFetch: (ProviderSpec, String) -> @MainActor () async throws -> Double
    private let now: @Sendable () -> Date

    public init(specStore: ProviderSpecStore,
                keyLookup: @escaping @Sendable (UUID) -> String?,
                makeFetch: @escaping (ProviderSpec, String) -> @MainActor () async throws -> Double,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.specStore = specStore
        self.keyLookup = keyLookup
        self.makeFetch = makeFetch
        self.now = now
        reload()
    }

    /// Rebuild rows from persisted specs (call after settings mutations).
    /// Row models for UNCHANGED specs are preserved (keeps value/status).
    public func reload() {
        let specs = specStore.load().filter { $0.visibility != .hidden }
        var existing = Dictionary(rows.map { ($0.spec.id, $0) }, uniquingKeysWith: { a, _ in a })
        rows = specs.map { spec in
            if let old = existing.removeValue(forKey: spec.id), old.spec == spec {
                return old
            }
            let model: ProviderRowModel
            if let key = keyLookup(spec.id) {
                model = ProviderRowModel(fetch: makeFetch(spec, key), now: now)
            } else {
                // No key on file: surface as a key problem; never build a fetcher.
                model = ProviderRowModel(fetch: { throw FetchError.unauthorized }, now: now)
            }
            return Row(spec: spec, model: model)
        }
    }

    public func refreshAll(force: Bool = false) async {
        // Concurrent, not serial: a slow/offline provider must not delay the
        // others (5 rows × 10 s timeout would make a 50 s serial cycle).
        // Unstructured same-actor tasks keep @MainActor isolation without
        // requiring ProviderRowModel to be Sendable; their fetches overlap
        // at the network layer while state mutations stay on the main actor.
        let tasks = rows.map { row in
            Task { @MainActor in await row.model.refresh(force: force) }
        }
        for task in tasks { await task.value }
    }
}
