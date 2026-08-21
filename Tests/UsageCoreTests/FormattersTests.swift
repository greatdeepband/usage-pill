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
    let below = BarTone.claudeTones(session: 10, week: 89.99, fable: 10, redAlert90: true)
    #expect(below.session == .normal)
    #expect(below.week == .warning)
    #expect(below.fable == .normal)
    // 90 exactly: ALL bars critical, regardless of their own tones.
    let at = BarTone.claudeTones(session: 10, week: 90, fable: 10, redAlert90: true)
    #expect(at.session == .critical)
    #expect(at.week == .critical)
    #expect(at.fable == .critical)
}

@Test func claudeTonesDisabledFlagFollowsPerBarTones() {
    let t = BarTone.claudeTones(session: 96, week: 92, fable: 81, redAlert90: false)
    #expect(t.session == .critical) // its own ≥95 rule, not the red alert
    #expect(t.week == .warning)     // 92 stays warning when the alert is off
    #expect(t.fable == .warning)    // its own ≥80 rule
}

@Test func claudeTonesNilUtilizations() {
    let none = BarTone.claudeTones(session: nil, week: nil, fable: nil, redAlert90: true)
    #expect(none.session == .normal)
    #expect(none.week == .normal)
    #expect(none.fable == .normal)
    // nil week can never trip the alert; nil session/fable still go red with it.
    let nilWeek = BarTone.claudeTones(session: 50, week: nil, fable: 50, redAlert90: true)
    #expect(nilWeek.session == .normal)
    #expect(nilWeek.week == .normal)
    #expect(nilWeek.fable == .normal)
    let nilSession = BarTone.claudeTones(session: nil, week: 95, fable: nil, redAlert90: true)
    #expect(nilSession.session == .critical)
    #expect(nilSession.week == .critical)
    #expect(nilSession.fable == .critical)
}

@Test func claudeTonesFableAloneNeverTripsTheAlert() {
    // The alert watches the WEEK budget only — a 95% Fable stays on its own
    // per-bar tone and must not flare the other bars.
    let t = BarTone.claudeTones(session: 10, week: 40, fable: 95, redAlert90: true)
    #expect(t.session == .normal)
    #expect(t.week == .normal)
    #expect(t.fable == .critical)
}
