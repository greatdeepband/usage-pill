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
    // Build expected string with en_US_POSIX to match the formatter's locked locale.
    let weekday = DateFormatter()
    weekday.locale = Locale(identifier: "en_US_POSIX")
    weekday.dateFormat = "EEE HH:mm"
    #expect(text == "resets \(weekday.string(from: far))")
    // within 24h falls back to countdown style
    let near = now.addingTimeInterval(5 * 3600)
    #expect(CountdownFormatter.weekReset(near, now: now).hasPrefix("resets in"))
    // nil
    #expect(CountdownFormatter.weekReset(nil, now: now) == "—")
}

@Test func remainingSurvivesAbsurdDates() {
    let absurdNow = Date(timeIntervalSince1970: 1_781_100_000)
    let absurd = Date(timeIntervalSince1970: 1e25)
    _ = CountdownFormatter.remaining(until: absurd, now: absurdNow) // must not trap
    // Date(timeIntervalSince1970: .nan) produces a date whose timeIntervalSince returns NaN.
    #expect(CountdownFormatter.remaining(until: Date(timeIntervalSince1970: .nan), now: absurdNow) == "—")
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

@Test func claudeTonesRedAlertBoundaryAt90() {
    // 89.99: red alert NOT triggered — per-bar tones (week ≥80 → warning).
    let below = BarTone.claudeTones(session: 10, week: 89.99, redAlert90: true)
    #expect(below.session == .normal)
    #expect(below.week == .warning)
    // 90 exactly: BOTH bars critical, regardless of the session's own tone.
    let at = BarTone.claudeTones(session: 10, week: 90, redAlert90: true)
    #expect(at.session == .critical)
    #expect(at.week == .critical)
}

@Test func claudeTonesDisabledFlagFollowsPerBarTones() {
    let t = BarTone.claudeTones(session: 96, week: 92, redAlert90: false)
    #expect(t.session == .critical) // its own ≥95 rule, not the red alert
    #expect(t.week == .warning)     // 92 stays warning when the alert is off
}

@Test func claudeTonesNilUtilizations() {
    let none = BarTone.claudeTones(session: nil, week: nil, redAlert90: true)
    #expect(none.session == .normal)
    #expect(none.week == .normal)
    // nil week can never trip the alert; nil session still goes red with it.
    let nilWeek = BarTone.claudeTones(session: 50, week: nil, redAlert90: true)
    #expect(nilWeek.session == .normal)
    #expect(nilWeek.week == .normal)
    let nilSession = BarTone.claudeTones(session: nil, week: 95, redAlert90: true)
    #expect(nilSession.session == .critical)
    #expect(nilSession.week == .critical)
}
