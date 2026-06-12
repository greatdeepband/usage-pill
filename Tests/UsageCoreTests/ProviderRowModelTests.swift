import Foundation
import Testing
@testable import UsageCore

// MARK: - Local helpers (suffixed PR to avoid collisions)

private final class PRClockBox: @unchecked Sendable {
    var now: Date
    init(_ d: Date) { now = d }
}

private final class PRCallCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}

/// Hands out queued Double results; final result repeats forever.
private final class PRResultBox: @unchecked Sendable {
    private var results: [Result<Double, Error>]
    init(_ r: [Result<Double, Error>]) {
        precondition(!r.isEmpty, "PRResultBox needs at least one result")
        results = r
    }
    func next() throws -> Double {
        let r = results.count > 1 ? results.removeFirst() : results[0]
        return try r.get()
    }
}

@MainActor
private func makeRowModel(
    results: [Result<Double, Error>],
    now: @escaping @Sendable () -> Date
) -> ProviderRowModel {
    let box = PRResultBox(results)
    return ProviderRowModel(fetch: { try box.next() }, now: now)
}

@MainActor
private func makeRowModelCounted(
    results: [Result<Double, Error>],
    now: @escaping @Sendable () -> Date
) -> (ProviderRowModel, () -> Int) {
    let box = PRResultBox(results)
    var count = 0
    let model = ProviderRowModel(fetch: {
        count += 1
        return try box.next()
    }, now: now)
    return (model, { count })
}

// MARK: - Tests

@Test @MainActor func successPublishesValue() async {
    let t0 = Date(timeIntervalSince1970: 1000)
    let model = makeRowModel(results: [.success(12.34)], now: { t0 })
    #expect(model.status == .loading)
    await model.refresh()
    #expect(model.status == .ok)
    #expect(model.value == 12.34)
    #expect(model.lastSuccess == t0)
}

@Test @MainActor func authFailureSetsCheckKeyAndRetainsValue() async {
    let t0 = Date(timeIntervalSince1970: 1000)
    // .unauthorized maps to .auth
    let model = makeRowModel(
        results: [.success(12.34), .failure(FetchError.unauthorized)],
        now: { t0 }
    )
    await model.refresh()
    await model.refresh()
    #expect(model.status == .stale(.auth))
    #expect(model.value == 12.34)
    #expect(model.lastSuccess == t0)

    // 403 also maps to .auth (separate model instance)
    let model403 = makeRowModel(
        results: [.success(12.34), .failure(FetchError.badResponse(403))],
        now: { t0 }
    )
    await model403.refresh()
    await model403.refresh()
    #expect(model403.status == .stale(.auth))
    #expect(model403.value == 12.34)
}

@Test @MainActor func rateLimitBacksOffWithFloor240() async {
    let clock = PRClockBox(Date(timeIntervalSince1970: 0))
    let (model, callCount) = makeRowModelCounted(
        results: [.failure(FetchError.rateLimited(retryAfter: 60)), .success(99.0)],
        now: { clock.now }
    )
    // t=0: rateLimited with retryAfter:60 → floored to 240
    await model.refresh()
    #expect(model.status == .stale(.rateLimited))
    #expect(callCount() == 1)

    // t=+100: inside the 240s window → skipped
    clock.now = Date(timeIntervalSince1970: 100)
    await model.refresh()
    #expect(callCount() == 1)

    // t=+239: still inside window → skipped
    clock.now = Date(timeIntervalSince1970: 239)
    await model.refresh()
    #expect(callCount() == 1)

    // t=+241: window expired → fetch called → success
    clock.now = Date(timeIntervalSince1970: 241)
    await model.refresh()
    #expect(model.status == .ok)
    #expect(callCount() == 2)
}

@Test @MainActor func forceBypassesBackoffAndReArmsOn429() async {
    let clock = PRClockBox(Date(timeIntervalSince1970: 0))
    let model = makeRowModel(
        results: [
            .failure(FetchError.rateLimited(retryAfter: 300)),
            .failure(FetchError.rateLimited(retryAfter: 300)),
            .success(42.0)
        ],
        now: { clock.now }
    )
    // t=0: rateLimited → arms backoff t=0..300
    await model.refresh()
    #expect(model.status == .stale(.rateLimited))

    // t=+60: force bypass → hits network → 429 again → re-arms from t60 (t=60..360)
    clock.now = Date(timeIntervalSince1970: 60)
    await model.refresh(force: true)
    #expect(model.status == .stale(.rateLimited))

    // t=+320: inside re-armed window → auto poll skipped
    clock.now = Date(timeIntervalSince1970: 320)
    await model.refresh()
    #expect(model.status == .stale(.rateLimited))

    // t=+361: re-armed window expired → success
    clock.now = Date(timeIntervalSince1970: 361)
    await model.refresh()
    #expect(model.status == .ok)
}

@Test @MainActor func networkKeepsLastValueDimmed() async {
    let t0 = Date(timeIntervalSince1970: 500)
    let model = makeRowModel(
        results: [.success(12.34), .failure(FetchError.network)],
        now: { t0 }
    )
    await model.refresh()
    await model.refresh()
    #expect(model.status == .stale(.network))
    #expect(model.value == 12.34)
    #expect(model.lastSuccess == t0)
}

@Test @MainActor func singleFlightCoalesces() async {
    let counter = PRCallCounter()
    var fetchStartedCont: CheckedContinuation<Void, Never>?
    var fetchReleaseCont: CheckedContinuation<Void, Never>?

    let model = ProviderRowModel(
        fetch: {
            counter.increment()
            await withCheckedContinuation { cont in fetchStartedCont = cont }
            await withCheckedContinuation { cont in fetchReleaseCont = cont }
            return 7.0
        },
        now: { Date(timeIntervalSince1970: 0) }
    )

    async let a: Void = model.refresh()
    while fetchStartedCont == nil { await Task.yield() }
    fetchStartedCont!.resume()
    fetchStartedCont = nil

    while fetchReleaseCont == nil { await Task.yield() }

    // Second refresh during in-flight first → must be dropped
    async let b: Void = model.refresh()
    _ = await b

    fetchReleaseCont!.resume()
    fetchReleaseCont = nil
    _ = await a

    #expect(model.status == .ok)
    #expect(counter.count == 1)
}

@Test @MainActor func prCancellationLeavesStateUntouched() async {
    var fetchStartedCont: CheckedContinuation<Void, Never>?
    var fetchReleaseCont: CheckedContinuation<Void, Never>?
    let gateActive = PRCallCounter()

    let model = ProviderRowModel(
        fetch: {
            if gateActive.count == 0 {
                await withCheckedContinuation { cont in fetchStartedCont = cont }
                await withCheckedContinuation { cont in fetchReleaseCont = cont }
                try Task.checkCancellation()
            }
            return 5.0
        },
        now: { Date(timeIntervalSince1970: 0) }
    )
    #expect(model.status == .loading)

    let t = Task { await model.refresh() }

    while fetchStartedCont == nil { await Task.yield() }
    fetchStartedCont!.resume()
    fetchStartedCont = nil

    while fetchReleaseCont == nil { await Task.yield() }

    t.cancel()
    fetchReleaseCont!.resume()
    fetchReleaseCont = nil
    await t.value

    // CancellationError must not flip state
    #expect(model.status == .loading)

    // Disable gate; same model must reach .ok on next refresh
    gateActive.increment()
    await model.refresh()
    #expect(model.status == .ok)
}

// MARK: - Drain-bar baseline (Task 18a)

@Test @MainActor func firstSuccessSetsBaselineAndFullFraction() async {
    let t0 = Date(timeIntervalSince1970: 0)
    let model = makeRowModel(results: [.success(50.0)], now: { t0 })
    #expect(model.baseline == nil)
    #expect(model.fraction == nil)
    await model.refresh()
    #expect(model.baseline == 50.0)
    #expect(model.fraction == 1.0)
}

@Test @MainActor func drainLowersFraction() async throws {
    let t0 = Date(timeIntervalSince1970: 0)
    let model = makeRowModel(
        results: [.success(50.0), .success(37.25)], now: { t0 }
    )
    await model.refresh()
    await model.refresh()
    #expect(model.baseline == 50.0)
    #expect(model.value == 37.25)
    let f = try #require(model.fraction)
    #expect(abs(f - 0.745) < 0.0001) // 37.25 / 50
}

@Test @MainActor func topUpRaisesBaselineToNewFull() async {
    let t0 = Date(timeIntervalSince1970: 0)
    let model = makeRowModel(
        results: [.success(50.0), .success(37.25), .success(60.0)], now: { t0 }
    )
    await model.refresh()
    await model.refresh()
    await model.refresh()
    #expect(model.baseline == 60.0)
    #expect(model.fraction == 1.0)
}

@Test @MainActor func zeroBaselineYieldsNilFraction() async {
    let t0 = Date(timeIntervalSince1970: 0)
    let model = makeRowModel(results: [.success(0.0)], now: { t0 })
    await model.refresh()
    #expect(model.baseline == 0.0)
    #expect(model.fraction == nil)
}

@Test @MainActor func failureKeepsBaseline() async throws {
    let t0 = Date(timeIntervalSince1970: 0)
    let model = makeRowModel(
        results: [.success(50.0), .failure(FetchError.network)], now: { t0 }
    )
    await model.refresh()
    await model.refresh()
    #expect(model.status == .stale(.network))
    #expect(model.baseline == 50.0)
    let f = try #require(model.fraction)
    #expect(f == 1.0)
}

@Test @MainActor func prSuccessClearsBackoff() async {
    let clock = PRClockBox(Date(timeIntervalSince1970: 0))
    let (model, callCount) = makeRowModelCounted(
        results: [
            .failure(FetchError.rateLimited(retryAfter: 300)),
            .success(1.0),
            .success(2.0)
        ],
        now: { clock.now }
    )

    // Get rate limited
    await model.refresh()
    #expect(model.status == .stale(.rateLimited))

    // Wait out backoff, recover
    clock.now = Date(timeIntervalSince1970: 301)
    await model.refresh()
    #expect(model.status == .ok)

    // backoffUntil cleared → immediate subsequent refresh fetches again
    await model.refresh()
    #expect(model.status == .ok)
    #expect(callCount() == 3)
}
