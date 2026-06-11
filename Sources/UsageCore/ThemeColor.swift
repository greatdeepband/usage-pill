import Foundation

/// Color components 0...1, sRGB. No SwiftUI/AppKit here — app code bridges.
public struct RGBA: Equatable, Sendable {
    public let r, g, b, a: Double
    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

public enum ThemeColor {
    /// Accepts "#RRGGBB", "#RRGGBBAA", case-insensitive, leading '#' optional.
    public static func parse(_ hex: String) -> RGBA? {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6 || s.count == 8,
              s.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
        if s.count == 6 { s += "FF" }
        var v: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&v) else { return nil }
        return RGBA(
            r: Double((v >> 24) & 0xFF) / 255,
            g: Double((v >> 16) & 0xFF) / 255,
            b: Double((v >> 8) & 0xFF) / 255,
            a: Double(v & 0xFF) / 255
        )
    }

    /// Always "#RRGGBBAA" uppercase.
    public static func format(_ c: RGBA) -> String {
        func b(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X%02X", b(c.r), b(c.g), b(c.b), b(c.a))
    }
}
