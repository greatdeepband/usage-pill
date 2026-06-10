import Foundation

public struct UsageWindow: Equatable, Sendable {
    public let utilization: Double // clamped to 0...100
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public let session: UsageWindow? // "five_hour"
    public let week: UsageWindow?    // "seven_day"

    public init(session: UsageWindow?, week: UsageWindow?) {
        self.session = session
        self.week = week
    }
}

public enum UsageDecodingError: Error, Equatable {
    case invalidJSON
}

public extension UsageSnapshot {
    static func decode(from data: Data) throws -> UsageSnapshot {
        guard let any = try? JSONSerialization.jsonObject(with: data),
              let root = any as? [String: Any] else {
            throw UsageDecodingError.invalidJSON
        }
        return UsageSnapshot(
            session: UsageWindow(json: root["five_hour"]),
            week: UsageWindow(json: root["seven_day"])
        )
    }
}

extension UsageWindow {
    init?(json: Any?) {
        guard let dict = json as? [String: Any],
              let raw = (dict["utilization"] as? NSNumber)?.doubleValue else { return nil }
        self.init(
            utilization: min(max(raw, 0), 100),
            resetsAt: Self.flexibleDate(dict["resets_at"])
        )
    }

    /// Accepts ISO8601 strings with any number of fractional digits (incl. microseconds),
    /// or epoch seconds/milliseconds as a number.
    static func flexibleDate(_ value: Any?) -> Date? {
        guard let value = value else { return nil }

        // Numeric: epoch seconds or epoch milliseconds
        if let number = value as? NSNumber {
            let interval = number.doubleValue
            guard interval > 0 else { return nil }
            // Values > 1e11 are interpreted as milliseconds (year ~5138 in seconds)
            if interval > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: interval / 1000)
            } else {
                return Date(timeIntervalSince1970: interval)
            }
        }

        guard let str = value as? String else { return nil }

        // Attempt 1: standard ISO8601 without fractional seconds
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: str) {
            return date
        }

        // Attempt 2: ISO8601 with fractional seconds (works for exactly 3 digits)
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFrac.date(from: str) {
            return date
        }

        // Attempt 3: normalize fractional digits to exactly 3, then re-parse.
        // Handles microseconds (6 digits), nanoseconds (9 digits), or any count.
        // Pattern: matches a dot followed by 1+ digits before timezone offset or Z.
        let normalized = normalizeFractionalSeconds(str)
        if let date = withFrac.date(from: normalized) {
            return date
        }
        // Also try plain formatter on normalized (in case fraction was stripped)
        if let date = plain.date(from: normalized) {
            return date
        }

        return nil
    }

    /// Trims or pads the fractional-seconds part of an ISO8601 string to exactly 3 digits.
    private static func normalizeFractionalSeconds(_ str: String) -> String {
        // Match: <digits>.<fraction><offset> where offset is Z, +HH:MM, -HH:MM etc.
        // We replace the fractional part with exactly 3 digits.
        var result = str
        // Find the dot that starts the fraction
        if let dotRange = result.range(of: ".") {
            let afterDot = result[dotRange.upperBound...]
            // Collect digit characters after the dot
            var digitCount = 0
            var digitEnd = afterDot.startIndex
            for ch in afterDot {
                if ch.isNumber {
                    digitCount += 1
                    digitEnd = afterDot.index(after: digitEnd)
                } else {
                    break
                }
            }
            if digitCount > 0 {
                let fracRange = dotRange.upperBound..<digitEnd
                let digits = String(result[fracRange])
                let truncated: String
                if digits.count >= 3 {
                    truncated = String(digits.prefix(3))
                } else {
                    truncated = digits.padding(toLength: 3, withPad: "0", startingAt: 0)
                }
                result.replaceSubrange(fracRange, with: truncated)
            }
        }
        return result
    }
}
