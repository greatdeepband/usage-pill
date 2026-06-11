import Foundation

public enum BarTone: Equatable, Sendable {
    case normal, warning, critical

    public static func tone(forUtilization u: Double) -> BarTone {
        if u >= 95 { return .critical }
        if u >= 80 { return .warning }
        return .normal
    }
}

public enum CountdownFormatter {
    // Cached: the hover ticker calls weekReset every second. DateFormatter is
    // thread-safe and read-only after init.
    // en_US_POSIX locale locks the hour format to HH regardless of the user's
    // 12/24-hour system preference (Apple QA1480). Timezone is captured per
    // format-call from the formatter's current default; a system timezone change
    // mid-run may show stale weekday text until restart (accepted limitation).
    private static let weekResetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE HH:mm"
        return f
    }()

    /// "resets in 2h 13m" / "resets in 45m" / "resets in <1m" / "resetting…" / "—"
    public static func remaining(until reset: Date?, now: Date) -> String {
        guard let reset else { return "—" }
        let raw = reset.timeIntervalSince(now)
        guard !raw.isNaN else { return "—" }
        // Cap at ~1 year to prevent Int overflow for absurd far-future dates.
        let s = min(raw, 366 * 24 * 3600)
        if s < 0 { return "resetting…" }
        if s < 60 { return "resets in <1m" }
        let totalMinutes = Int(s / 60)
        let h = totalMinutes / 60, m = totalMinutes % 60
        return h > 0 ? "resets in \(h)h \(m)m" : "resets in \(m)m"
    }

    /// "resets Thu 09:00" when >24h away, countdown style otherwise.
    public static func weekReset(_ reset: Date?, now: Date) -> String {
        guard let reset else { return "—" }
        if reset.timeIntervalSince(now) <= 24 * 3600 {
            return remaining(until: reset, now: now)
        }
        return "resets \(weekResetFormatter.string(from: reset))"
    }

    public static func updatedAgo(seconds: TimeInterval) -> String {
        // Negative values (clock skew) deliberately fall into "just now".
        if seconds < 10 { return "updated just now" }
        if seconds < 60 { return "updated \(Int(seconds))s ago" }
        if seconds < 3600 { return "updated \(Int(seconds / 60))m ago" }
        return "updated \(Int(seconds / 3600))h ago"
    }
}
