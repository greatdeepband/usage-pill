import Foundation
import Testing
@testable import UsageCore

private let now = Date(timeIntervalSince1970: 1_781_100_000) // fixed reference

@Test func sessionCountdownFormats() {
    #expect(CountdownFormatter.remaining(until: now.addingTimeInterval(2 * 3600 + 13 * 60), now: now) == "resets in 2h 13m")
    #expect(CountdownFormatter.remaining(until: now.addingTimeInterval(45 * 60), now: now) == "resets in 45m")
    #expect(CountdownFormatter.remaining(until: now.addingTimeInterval(30), now: now) == "resets in <1m")
    #expect(CountdownFormatter.remaining(until: now.addingTimeInterval(-60), now: now) == "resetting…")
    #expect(CountdownFormatter.remaining(until: nil, now: now) == "—")
}

@Test func weekResetUsesWeekdayWhenFarAway() {
    let far = now.addingTimeInterval(3 * 24 * 3600)
    let text = CountdownFormatter.weekReset(far, now: now)
    let weekday = DateFormatter()
    weekday.dateFormat = "EEE HH:mm"
    #expect(text == "resets \(weekday.string(from: far))")
    // within 24h falls back to countdown style
    let near = now.addingTimeInterval(5 * 3600)
    #expect(CountdownFormatter.weekReset(near, now: now).hasPrefix("resets in"))
    // nil
    #expect(CountdownFormatter.weekReset(nil, now: now) == "—")
}

@Test func updatedAgoFormats() {
    #expect(CountdownFormatter.updatedAgo(seconds: 5) == "updated just now")
    #expect(CountdownFormatter.updatedAgo(seconds: 42) == "updated 42s ago")
    #expect(CountdownFormatter.updatedAgo(seconds: 200) == "updated 3m ago")
    #expect(CountdownFormatter.updatedAgo(seconds: 7300) == "updated 2h ago")
}

@Test func barToneThresholds() {
    #expect(BarTone.tone(forUtilization: 0) == .normal)
    #expect(BarTone.tone(forUtilization: 79.9) == .normal)
    #expect(BarTone.tone(forUtilization: 80) == .warning)
    #expect(BarTone.tone(forUtilization: 94.9) == .warning)
    #expect(BarTone.tone(forUtilization: 95) == .critical)
    #expect(BarTone.tone(forUtilization: 100) == .critical)
}
