import Foundation

public enum PlanBadge {
    /// "max" + "default_max_20x" → "MAX 20×"; nil/blank subscription → nil.
    public static func text(subscriptionType: String?, rateLimitTier: String?) -> String? {
        guard let sub = subscriptionType?.trimmingCharacters(in: .whitespaces),
              !sub.isEmpty else { return nil }
        var badge = sub.uppercased()
        if let tier = rateLimitTier,
           let last = tier.split(separator: "_").last,
           last.hasSuffix("x"),
           let n = Int(last.dropLast()), n > 1 {
            badge += " \(n)×"
        }
        return badge
    }
}
