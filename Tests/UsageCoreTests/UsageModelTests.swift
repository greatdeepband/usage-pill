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
    clock.now = Date(timeIntervalSince1970: 301)
    #expect(model.isDataOld == true)
}

@Test @MainActor func dataIsOldWhenNeverFetched() {
    let model = makeModel(results: [.failure(FetchError.network)], now: { Date(timeIntervalSince1970: 0) })
    #expect(model.isDataOld == true)
}

@Test @MainActor func overlappingRefreshIsCoalesced() async {
    let model = makeModel(results: [.success(snapA)], now: { Date(timeIntervalSince1970: 0) })
    async let a: Void = model.refresh()
    async let b: Void = model.refresh()
    _ = await (a, b)
    #expect(model.status == .ok)
}

private final class ClockBox: @unchecked Sendable {
    var now: Date
    init(_ d: Date) { now = d }
}
