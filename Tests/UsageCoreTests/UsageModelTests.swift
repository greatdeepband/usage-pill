import Foundation
import Testing
@testable import UsageCore

private let snapA = UsageSnapshot(
    session: UsageWindow(utilization: 62, resetsAt: nil),
    week: UsageWindow(utilization: 38, resetsAt: nil)
)

@MainActor
private func makeModel(
    results: [Result<UsageSnapshot, Error>],
    now: @escaping @Sendable () -> Date
) -> UsageModel {
    let box = ResultBox(results)
    return UsageModel(fetch: { try box.next() }, now: now)
}

/// Hands out queued results; final result repeats forever.
private final class ResultBox: @unchecked Sendable {
    private var results: [Result<UsageSnapshot, Error>]
    init(_ r: [Result<UsageSnapshot, Error>]) { results = r }
    func next() throws -> UsageSnapshot {
        let r = results.count > 1 ? results.removeFirst() : results[0]
        return try r.get()
    }
}

@Test @MainActor func startsLoadingThenOk() async {
    let model = makeModel(results: [.success(snapA)], now: { Date(timeIntervalSince1970: 1000) })
    #expect(model.status == .loading)
    await model.refresh()
    #expect(model.status == .ok)
    #expect(model.snapshot == snapA)
    #expect(model.lastSuccess == Date(timeIntervalSince1970: 1000))
}

@Test @MainActor func keepsLastGoodDataWhenFetchFails() async {
    let model = makeModel(
        results: [.success(snapA), .failure(FetchError.network)],
        now: { Date(timeIntervalSince1970: 1000) }
    )
    await model.refresh()
    await model.refresh()
    #expect(model.status == .stale(reason: .network))
    #expect(model.snapshot == snapA) // old data retained
}

@Test @MainActor func mapsErrorsToStaleReasons() async {
    for (error, reason): (Error, UsageModel.StaleReason) in [
        (CredentialsError.notFound, .noCredentials),
        (CredentialsError.unreadable, .noCredentials),
        (FetchError.unauthorized, .unauthorized),
        (FetchError.badResponse(500), .network),
        (FetchError.network, .network),
        (FetchError.undecodable, .network),
    ] {
        let model = makeModel(results: [.failure(error)], now: { Date(timeIntervalSince1970: 0) })
        await model.refresh()
        #expect(model.status == .stale(reason: reason))
    }
}

@Test @MainActor func recoversFromStale() async {
    let model = makeModel(
        results: [.failure(FetchError.network), .success(snapA)],
        now: { Date(timeIntervalSince1970: 0) }
    )
    await model.refresh()
    await model.refresh()
    #expect(model.status == .ok)
    #expect(model.snapshot == snapA)
}

@Test @MainActor func dataIsOldAfterFiveMinutes() async {
    let clock = ClockBox(Date(timeIntervalSince1970: 0))
    let model = makeModel(results: [.success(snapA)], now: { clock.now })
    await model.refresh()
    #expect(model.isDataOld == false)
    clock.now = Date(timeIntervalSince1970: 300)
    #expect(model.isDataOld == false) // strictly greater-than 300s
    clock.now = Date(timeIntervalSince1970: 301)
    #expect(model.isDataOld == true)
}

@Test @MainActor func dataIsOldWhenNeverFetched() {
    let model = makeModel(results: [.success(snapA)], now: { Date(timeIntervalSince1970: 0) })
    #expect(model.isDataOld == true)
}

@Test @MainActor func overlappingRefreshIsCoalesced() async {
    // Two async continuations: fetchStarted fires when fetch() begins,
    // fetchRelease fires when the test lets it proceed.  This guarantees the
    // first refresh is genuinely suspended when the second one is started.
    let counter = CallCounter()
    var fetchStartedCont: CheckedContinuation<Void, Never>?
    var fetchReleaseCont: CheckedContinuation<Void, Never>?

    let model = UsageModel(
        fetch: {
            counter.increment()
            // Signal that fetch has started, then wait for the test to release.
            await withCheckedContinuation { cont in fetchStartedCont = cont }
            await withCheckedContinuation { cont in fetchReleaseCont = cont }
            return snapA
        },
        now: { Date(timeIntervalSince1970: 0) }
    )

    // Launch first refresh.  It will run until it stores fetchStartedCont.
    async let a: Void = model.refresh()
    // Yield until the fetch has stored fetchStartedCont.
    while fetchStartedCont == nil { await Task.yield() }
    fetchStartedCont!.resume()          // let fetch proceed to fetchReleaseCont
    fetchStartedCont = nil

    // Wait until fetch is blocked on fetchReleaseCont.
    while fetchReleaseCont == nil { await Task.yield() }

    // At this point the first refresh is definitely in-flight and suspended.
    // Launch the second refresh — it must see inFlight==true and return without
    // calling fetch().
    async let b: Void = model.refresh()
    _ = await b                         // second refresh must complete immediately

    // Release the first refresh.
    fetchReleaseCont!.resume()
    fetchReleaseCont = nil
    _ = await a

    #expect(model.status == .ok)
    #expect(counter.count == 1)         // second refresh dropped while first was in flight
}

@Test @MainActor func cancellationLeavesStateUntouched() async {
    // fetch blocks until released; after cancel() the check throws CancellationError.
    // After the gated pass, `gated` is switched off so the SAME model can refresh again.
    var fetchReleaseCont: CheckedContinuation<Void, Never>?
    var fetchStartedCont: CheckedContinuation<Void, Never>?
    let gateActive = CallCounter() // count == 0 → gated; incremented to disable the gate

    let model = UsageModel(
        fetch: {
            if gateActive.count == 0 {
                await withCheckedContinuation { cont in fetchStartedCont = cont }
                await withCheckedContinuation { cont in fetchReleaseCont = cont }
                try Task.checkCancellation()
            }
            return snapA
        },
        now: { Date(timeIntervalSince1970: 0) }
    )
    #expect(model.status == .loading)

    let t = Task { await model.refresh() }

    // Wait until the fetch has stored fetchStartedCont.
    while fetchStartedCont == nil { await Task.yield() }
    fetchStartedCont!.resume()
    fetchStartedCont = nil

    // Wait until fetch is blocked on fetchReleaseCont.
    while fetchReleaseCont == nil { await Task.yield() }

    // Cancel the task, then open the gate — checkCancellation() will throw.
    t.cancel()
    fetchReleaseCont!.resume()
    fetchReleaseCont = nil
    await t.value

    // CancellationError must not flip state to .stale
    #expect(model.status == .loading)

    // Prove inFlight was released on the SAME model: disable the gate and
    // refresh again — it must run and reach .ok.
    gateActive.increment()
    await model.refresh()
    #expect(model.status == .ok)
}

private final class ClockBox: @unchecked Sendable {
    var now: Date
    init(_ d: Date) { now = d }
}

private final class CallCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}
