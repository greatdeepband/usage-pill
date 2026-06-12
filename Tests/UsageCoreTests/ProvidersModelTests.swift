import Foundation
import Testing
@testable import UsageCore

// MARK: - Helpers

private func makeSpec(
    id: UUID = UUID(),
    displayName: String = "Test",
    visibility: ProviderSpec.Visibility = .pinned
) -> ProviderSpec {
    ProviderSpec(
        id: id,
        displayName: displayName,
        adapter: .generic,
        url: "https://example.com/balance",
        headerName: "Authorization",
        headerTemplate: "Bearer {key}",
        valuePath: "balance",
        subtractPath: nil,
        scale: 1.0,
        valueKind: .currency,
        currencyCode: "USD",
        warnBelow: nil,
        visibility: visibility
    )
}

/// Returns a fresh UserDefaults suite and a defer-able cleanup block.
private func freshDefaults() -> (UserDefaults, () -> Void) {
    let name = "provider-spec-tests-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    return (d, {
        d.removePersistentDomain(forName: name)
        CFPreferencesAppSynchronize(name as CFString)
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appending(components: "Library", "Preferences", "\(name).plist")
        try? FileManager.default.removeItem(at: plist)
    })
}

/// Per-spec invocation counter for the fetch closure (not factory calls).
private final class InvokeCounter: @unchecked Sendable {
    var counts: [UUID: Int] = [:]
    func inc(_ id: UUID) { counts[id] = (counts[id] ?? 0) + 1 }
    func count(for id: UUID) -> Int { counts[id] ?? 0 }
}

private final class PMResultBox: @unchecked Sendable {
    private var items: [Result<Double, Error>]
    init(_ r: [Result<Double, Error>]) {
        precondition(!r.isEmpty)
        items = r
    }
    func next() throws -> Double {
        let r = items.count > 1 ? items.removeFirst() : items[0]
        return try r.get()
    }
}

// MARK: - Tests

@Test @MainActor func buildsRowModelsForVisibleSpecsOnly() {
    let (d, cleanup) = freshDefaults()
    defer { cleanup() }
    let pinnedID   = UUID()
    let expandedID = UUID()
    let hiddenID   = UUID()
    let specs = [
        makeSpec(id: pinnedID,   visibility: .pinned),
        makeSpec(id: expandedID, visibility: .expandedOnly),
        makeSpec(id: hiddenID,   visibility: .hidden),
    ]
    let store = ProviderSpecStore(defaults: d)
    store.save(specs)
    let model = ProvidersModel(
        specStore: store,
        keyLookup: { _ in "sk-test" },
        makeFetch: { _, _ in { 1.0 } }
    )
    #expect(model.rows.count == 2)
    #expect(!model.rows.contains(where: { $0.id == hiddenID }))
    #expect(model.rows.contains(where: { $0.id == pinnedID }))
    #expect(model.rows.contains(where: { $0.id == expandedID }))
}

@Test @MainActor func refreshAllSkipsHiddenAndForwardsForce() async {
    let (d, cleanup) = freshDefaults()
    defer { cleanup() }
    let visibleID = UUID()
    let hiddenID  = UUID()
    let specs = [
        makeSpec(id: visibleID, visibility: .pinned),
        makeSpec(id: hiddenID,  visibility: .hidden),
    ]
    let store = ProviderSpecStore(defaults: d)
    store.save(specs)
    let counter = InvokeCounter()
    let model = ProvidersModel(
        specStore: store,
        keyLookup: { _ in "sk-test" },
        makeFetch: { spec, _ in
            let id = spec.id
            return { counter.inc(id); return 1.0 }
        }
    )

    await model.refreshAll()
    #expect(counter.count(for: visibleID) == 1)
    #expect(counter.count(for: hiddenID) == 0)

    // force: true must reach the visible row again (force bypasses backoff)
    await model.refreshAll(force: true)
    #expect(counter.count(for: visibleID) == 2)
    #expect(counter.count(for: hiddenID) == 0)
}

@Test @MainActor func missingKeyYieldsAuthStateWithoutFetch() async {
    let (d, cleanup) = freshDefaults()
    defer { cleanup() }
    let withKeyID    = UUID()
    let withoutKeyID = UUID()
    let specs = [
        makeSpec(id: withKeyID,    visibility: .pinned),
        makeSpec(id: withoutKeyID, visibility: .pinned),
    ]
    let store = ProviderSpecStore(defaults: d)
    store.save(specs)

    final class FactoryRecord: @unchecked Sendable {
        var createdFor: [UUID] = []
    }
    let record = FactoryRecord()

    let model = ProvidersModel(
        specStore: store,
        keyLookup: { id in id == withKeyID ? "sk-real" : nil },
        makeFetch: { spec, _ in
            record.createdFor.append(spec.id)
            return { 42.0 }
        }
    )

    await model.refreshAll()

    // Factory must NOT have been called for the keyless spec.
    #expect(!record.createdFor.contains(withoutKeyID))

    // The keyless row must be in .stale(.auth).
    let noKeyRow = model.rows.first(where: { $0.id == withoutKeyID })
    #expect(noKeyRow?.model.status == .stale(.auth))

    // The row with a key reaches .ok.
    let okRow = model.rows.first(where: { $0.id == withKeyID })
    #expect(okRow?.model.status == .ok)
}

@Test @MainActor func reloadPreservesStateForUnchangedSpecs() async {
    let (d, cleanup) = freshDefaults()
    defer { cleanup() }
    let id   = UUID()
    let spec = makeSpec(id: id, displayName: "Original", visibility: .pinned)
    let store = ProviderSpecStore(defaults: d)
    store.save([spec])

    let model = ProvidersModel(
        specStore: store,
        keyLookup: { _ in "sk-test" },
        makeFetch: { _, _ in { 99.0 } }
    )

    // Bring the row to .ok
    await model.refreshAll()
    let originalRow = model.rows.first(where: { $0.id == id })!
    #expect(originalRow.model.status == .ok)

    // Reload with IDENTICAL specs → same Row model instance (identity preserved)
    model.reload()
    let sameRow = model.rows.first(where: { $0.id == id })!
    #expect(sameRow.model === originalRow.model)
    #expect(sameRow.model.status == .ok)

    // Change the displayName → row must be rebuilt (status back to .loading)
    var mutated = spec
    mutated.displayName = "Changed"
    store.save([mutated])
    model.reload()
    let newRow = model.rows.first(where: { $0.id == id })!
    #expect(newRow.model !== originalRow.model)
    #expect(newRow.model.status == .loading)
}

@Test @MainActor func reloadPicksUpNewAndRemovedSpecs() {
    let (d, cleanup) = freshDefaults()
    defer { cleanup() }
    let id1 = UUID()
    let id2 = UUID()
    let store = ProviderSpecStore(defaults: d)
    store.save([makeSpec(id: id1, visibility: .pinned)])

    let model = ProvidersModel(
        specStore: store,
        keyLookup: { _ in "sk-test" },
        makeFetch: { _, _ in { 1.0 } }
    )
    #expect(model.rows.count == 1)
    #expect(model.rows[0].id == id1)

    // Add a second spec
    store.save([makeSpec(id: id1, visibility: .pinned),
                makeSpec(id: id2, visibility: .expandedOnly)])
    model.reload()
    #expect(model.rows.count == 2)
    #expect(model.rows.contains(where: { $0.id == id2 }))

    // Remove the first spec
    store.save([makeSpec(id: id2, visibility: .expandedOnly)])
    model.reload()
    #expect(model.rows.count == 1)
    #expect(model.rows[0].id == id2)
    #expect(!model.rows.contains(where: { $0.id == id1 }))
}

// refreshAll must run rows CONCURRENTLY: both gated fetchers must be in-flight
// before either is released. A serial implementation never starts row 2 while
// row 1 is gated, so `started` would stall at 1 and this test would fail at
// the deadline (rather than hang — the gates are then released regardless).
@Test @MainActor func refreshAllRunsRowsConcurrently() async {
    let (defaults, cleanup) = freshDefaults()
    defer { cleanup() }
    let store = ProviderSpecStore(defaults: defaults)
    store.save([makeSpec(displayName: "A"), makeSpec(displayName: "B")])

    nonisolated(unsafe) var started = 0
    nonisolated(unsafe) var gates: [CheckedContinuation<Void, Never>] = []

    let model = ProvidersModel(
        specStore: store,
        keyLookup: { _ in "k" },
        makeFetch: { _, _ in
            {
                started += 1
                await withCheckedContinuation { gates.append($0) }
                return 1.0
            }
        }
    )

    let refreshTask = Task { @MainActor in await model.refreshAll() }
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while started < 2 && ContinuousClock.now < deadline {
        await Task.yield()
    }
    let overlapped = (started == 2)
    // Release every gate that opened so the refresh task can finish either way.
    while gates.isEmpty == false || refreshTask.isCancelled == false {
        for gate in gates { gate.resume() }
        gates.removeAll()
        if started >= 2 || ContinuousClock.now >= deadline { break }
        await Task.yield()
    }
    for gate in gates { gate.resume() }
    gates.removeAll()
    await refreshTask.value
    #expect(overlapped) // both fetchers were in flight simultaneously
}
