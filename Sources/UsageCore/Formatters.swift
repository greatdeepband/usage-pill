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
    /// "resets in 2h 13m" / "resets in 45m" / "resets in <1m" / "resetting…" / "—"
    public static func remaining(until reset: Date?, now: Date) -> String {
        guard let reset else { return "—" }
        let s = reset.timeIntervalSince(now)
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
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return "resets \(f.string(from: reset))"
    }

    public static func updatedAgo(seconds: TimeInterval) -> String {
        if seconds < 10 { return "updated just now" }
        if seconds < 60 { return "updated \(Int(seconds))s ago" }
        if seconds < 3600 { return "updated \(Int(seconds / 60))m ago" }
        return "updated \(Int(seconds / 3600))h ago"
    }
}
