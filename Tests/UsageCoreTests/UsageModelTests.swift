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
    init(_ r: [Result<UsageSnapshot, Error>]) {
        precondition(!r.isEmpty, "ResultBox needs at least one result")
        results = r
    }
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
    #expect(model.lastSuccess == Date(timeIntervalSince1970: 1000))
}

@Test @MainActor func unauthorizedKeepsLastGoodData() async {
    let model = makeModel(
        results: [.success(snapA), .failure(FetchError.unauthorized)],
        now: { Date(timeIntervalSince1970: 1000) }
    )
    await model.refresh()
    await model.refresh()
    #expect(model.status == .stale(reason: .unauthorized))
    #expect(model.snapshot == snapA)
    #expect(model.lastSuccess == Date(timeIntervalSince1970: 1000))
}

@Test @MainActor func mapsErrorsToStaleReasons() async {
    for (error, reason): (Error, UsageModel.StaleReason) in [
        (CredentialsError.notFound, .noCredentials),
        (CredentialsError.unreadable, .noCredentials),
        (FetchError.unauthorized, .unauthorized),
        (FetchError.badResponse(500), .network),
        (FetchError.network, .network),
        (FetchError.undecodable, .network),
        (FetchError.rateLimited(retryAfter: nil), .rateLimited),
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

@Test @MainActor func secondsSinceSuccessIsNilBeforeAnyFetch() {
    let model = makeModel(results: [.success(snapA)], now: { Date(timeIntervalSince1970: 1000) })
    #expect(model.secondsSinceSuccess() == nil)
}

@Test @MainActor func secondsSinceSuccessAfterRefresh() async {
    let clock = ClockBox(Date(timeIntervalSince1970: 1000))
    let model = makeModel(results: [.success(snapA)], now: { clock.now })
    await model.refresh()
    clock.now = Date(timeIntervalSince1970: 1042)
    #expect(model.secondsSinceSuccess() == 42)
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

@Test @MainActor func rateLimitedSetsBackoffAndSkipsPolls() async {
    let clock = ClockBox(Date(timeIntervalSince1970: 0))
    let results: [Result<UsageSnapshot, Error>] = [
        .failure(FetchError.rateLimited(retryAfter: 300)),
        .success(snapA)
    ]
    let (model, callCount) = makeModelCounted(results: results, now: { clock.now })

    // t=0: first refresh → rate limited
    await model.refresh()
    #expect(model.status == .stale(reason: .rateLimited))
    #expect(callCount() == 1)

    // t=+100s: backoff window (300s) not elapsed → silently skipped
    clock.now = Date(timeIntervalSince1970: 100)
    await model.refresh()
    #expect(model.status == .stale(reason: .rateLimited))
    #expect(callCount() == 1) // still 1 — fetch NOT called

    // t=+250s: a Retry-After below the 240s floor would have expired here,
    // but 300 > 240 so the window is the header value — still skipped
    clock.now = Date(timeIntervalSince1970: 250)
    await model.refresh()
    #expect(callCount() == 1)

    // t=+301s: backoff elapsed → fetch called → success
    clock.now = Date(timeIntervalSince1970: 301)
    await model.refresh()
    #expect(model.status == .ok)
    #expect(callCount() == 2)
}

@Test @MainActor func rateLimitedDefaultBackoffIs300() async {
    let clock = ClockBox(Date(timeIntervalSince1970: 0))
    let results: [Result<UsageSnapshot, Error>] = [
        .failure(FetchError.rateLimited(retryAfter: nil)), // no Retry-After → default 300s
        .success(snapA)
    ]
    let (model, callCount) = makeModelCounted(results: results, now: { clock.now })

    await model.refresh()
    #expect(model.status == .stale(reason: .rateLimited))

    // +299s: still in backoff
    clock.now = Date(timeIntervalSince1970: 299)
    await model.refresh()
    #expect(model.status == .stale(reason: .rateLimited))
    #expect(callCount() == 1)

    // +301s: backoff expired → success
    clock.now = Date(timeIntervalSince1970: 301)
    await model.refresh()
    #expect(model.status == .ok)
    #expect(callCount() == 2)
}

@Test @MainActor func successClearsBackoff() async {
    let clock = ClockBox(Date(timeIntervalSince1970: 0))
    let results: [Result<UsageSnapshot, Error>] = [
        .failure(FetchError.rateLimited(retryAfter: 300)),
        .success(snapA),
        .success(snapA)
    ]
    let (model, callCount) = makeModelCounted(results: results, now: { clock.now })

    // Get rate limited
    await model.refresh()
    #expect(model.status == .stale(reason: .rateLimited))

    // Wait out backoff, recover
    clock.now = Date(timeIntervalSince1970: 301)
    await model.refresh()
    #expect(model.status == .ok)

    // backoffUntil should be cleared → immediate subsequent refresh works (no skip)
    await model.refresh()
    #expect(model.status == .ok)
    #expect(callCount() == 3) // all 3 fetches happened
}

// MARK: - Private helpers

/// Wraps ResultBox and counts how many times the fetch closure is called.
@MainActor
private func makeModelCounted(
    results: [Result<UsageSnapshot, Error>],
    now: @escaping @Sendable () -> Date
) -> (UsageModel, () -> Int) {
    let box = ResultBox(results)
    var count = 0
    let model = UsageModel(fetch: {
        count += 1
        return try box.next()
    }, now: now)
    return (model, { count })
}

private final class ClockBox: @unchecked Sendable {
    var now: Date
    init(_ d: Date) { now = d }
}

private final class CallCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}

@Test @MainActor func forcedRefreshBypassesBackoff() async {
    let clock = ClockBox(Date(timeIntervalSince1970: 0))
    let model = makeModel(
        results: [.failure(FetchError.rateLimited(retryAfter: 300)), .success(snapA)],
        now: { clock.now }
    )
    await model.refresh()
    #expect(model.status == .stale(reason: .rateLimited))
    clock.now = Date(timeIntervalSince1970: 60) // still inside the window
    await model.refresh()
    #expect(model.status == .stale(reason: .rateLimited)) // auto poll skipped
    await model.refresh(force: true)
    #expect(model.status == .ok) // user intent wins
}

@Test @MainActor func forcedRefreshThat429sReArmsBackoff() async {
    let clock = ClockBox(Date(timeIntervalSince1970: 0))
    let model = makeModel(
        results: [.failure(FetchError.rateLimited(retryAfter: 300)),
                  .failure(FetchError.rateLimited(retryAfter: 300)),
                  .success(snapA)],
        now: { clock.now }
    )
    await model.refresh()                       // arms backoff (t=0..300)
    clock.now = Date(timeIntervalSince1970: 60)
    await model.refresh(force: true)            // hits network, 429s again → re-arms (t=60..360)
    clock.now = Date(timeIntervalSince1970: 320) // inside the RE-ARMED window
    await model.refresh()
    #expect(model.status == .stale(reason: .rateLimited)) // auto poll still skipped
    clock.now = Date(timeIntervalSince1970: 361)
    await model.refresh()
    #expect(model.status == .ok)
}

@Test @MainActor func rateLimitedFloorIs240() async {
    let clock = ClockBox(Date(timeIntervalSince1970: 0))
    let (model, callCount) = makeModelCounted(
        results: [.failure(FetchError.rateLimited(retryAfter: 60)), .success(snapA)],
        now: { clock.now }
    )
    await model.refresh() // Retry-After 60 → floored to 240
    clock.now = Date(timeIntervalSince1970: 100)
    await model.refresh()
    #expect(callCount() == 1) // 60s header must NOT be honored below the floor
    clock.now = Date(timeIntervalSince1970: 241)
    await model.refresh()
    #expect(model.status == .ok)
}
