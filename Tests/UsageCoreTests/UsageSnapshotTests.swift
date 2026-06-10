import Foundation
import Testing
@testable import UsageCore

@Test func decodesLiveFixture() throws {
    let snap = try UsageSnapshot.decode(from: Data(Fixtures.liveUsageResponse.utf8))
    #expect(snap.session != nil)
    #expect(snap.week != nil)
    let s = try #require(snap.session)
    #expect((0...100).contains(s.utilization))
    #expect(s.resetsAt != nil)
}

@Test func decodesKnownShape() throws {
    let json = #"{"five_hour":{"utilization":62.5,"resets_at":"2026-06-10T21:00:00Z"},"seven_day":{"utilization":38,"resets_at":"2026-06-11T07:00:00+00:00"}}"#
    let snap = try UsageSnapshot.decode(from: Data(json.utf8))
    #expect(snap.session?.utilization == 62.5)
    #expect(snap.week?.utilization == 38)
    #expect(snap.session?.resetsAt == ISO8601DateFormatter().date(from: "2026-06-10T21:00:00Z"))
}

@Test func parsesMicrosecondFractionalSeconds() throws {
    let json = #"{"five_hour":{"utilization":77.0,"resets_at":"2026-06-11T00:49:59.764212+00:00"}}"#
    let snap = try UsageSnapshot.decode(from: Data(json.utf8))
    let date = try #require(snap.session?.resetsAt)
    // Must land within 1s of the whole-second time (fraction may be truncated).
    let whole = try #require(ISO8601DateFormatter().date(from: "2026-06-11T00:49:59Z"))
    #expect(abs(date.timeIntervalSince(whole)) < 1.0)
}

@Test func toleratesMissingBucketsAndUnknownFields() throws {
    let json = #"{"seven_day":{"utilization":10,"resets_at":"2026-06-11T07:00:00Z","extra":true},"future_bucket":{}}"#
    let snap = try UsageSnapshot.decode(from: Data(json.utf8))
    #expect(snap.session == nil)
    #expect(snap.week?.utilization == 10)
}

@Test func toleratesEpochMillisAndSecondsResetTimes() throws {
    let json = #"{"five_hour":{"utilization":5,"resets_at":1781200000000},"seven_day":{"utilization":5,"resets_at":1781200000}}"#
    let snap = try UsageSnapshot.decode(from: Data(json.utf8))
    let expected = Date(timeIntervalSince1970: 1_781_200_000)
    #expect(snap.session?.resetsAt == expected)
    #expect(snap.week?.resetsAt == expected)
}

@Test func clampsUtilizationTo0Through100() throws {
    let json = #"{"five_hour":{"utilization":140,"resets_at":null},"seven_day":{"utilization":-3}}"#
    let snap = try UsageSnapshot.decode(from: Data(json.utf8))
    #expect(snap.session?.utilization == 100)
    #expect(snap.week?.utilization == 0)
    #expect(snap.session?.resetsAt == nil)
}

@Test func throwsOnGarbage() {
    #expect(throws: UsageDecodingError.self) {
        _ = try UsageSnapshot.decode(from: Data("not json".utf8))
    }
    #expect(throws: UsageDecodingError.self) {
        _ = try UsageSnapshot.decode(from: Data("[1,2,3]".utf8))
    }
}

@Test func parsesShortFractionalSeconds() throws {
    let json = #"{"five_hour":{"utilization":1,"resets_at":"2026-06-11T00:49:59.7+00:00"}}"#
    let snap = try UsageSnapshot.decode(from: Data(json.utf8))
    let date = try #require(snap.session?.resetsAt)
    let whole = try #require(ISO8601DateFormatter().date(from: "2026-06-11T00:49:59Z"))
    #expect(abs(date.timeIntervalSince(whole)) < 1.0)
}

@Test func rejectsBooleanNumbers() throws {
    let json = #"{"five_hour":{"utilization":true,"resets_at":"2026-06-11T00:49:59Z"},"seven_day":{"utilization":10,"resets_at":true}}"#
    let snap = try UsageSnapshot.decode(from: Data(json.utf8))
    #expect(snap.session == nil)          // boolean utilization -> window rejected
    #expect(snap.week?.utilization == 10)
    #expect(snap.week?.resetsAt == nil)   // boolean resets_at -> nil date
}
