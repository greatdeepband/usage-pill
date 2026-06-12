import Foundation

/// Resolves dot-separated paths ("a.0.b") into a finite Double.
/// Accepts numeric leaves and numeric STRINGS (several providers return
/// balances as strings). Rejects booleans, non-finite values, empty paths.
public enum DotPath {
    public static func resolve(_ path: String, in json: Any) -> Double? {
        guard !path.isEmpty else { return nil }
        var current: Any = json
        for component in path.split(separator: ".", omittingEmptySubsequences: false) {
            // Dict key checked before array index: a numeric component resolves as a dict key when one exists.
            if let dict = current as? [String: Any], let next = dict[String(component)] {
                current = next
            } else if let arr = current as? [Any], let idx = Int(component),
                      idx >= 0, idx < arr.count {
                current = arr[idx]
            } else {
                return nil
            }
        }
        if let n = current as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
            let v = n.doubleValue
            return v.isFinite ? v : nil
        }
        if let s = current as? String, let v = Double(s), v.isFinite {
            return v
        }
        // NOTE: Do NOT add a bare `current as? Double` branch — __NSCFBoolean
        // bridges to Double (true→1.0), which would bypass the boolean guard above.
        return nil
    }
}
