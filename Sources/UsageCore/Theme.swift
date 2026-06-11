import Foundation

public struct Theme: Equatable, Sendable {
    public var sessionHex: String
    public var weekHex: String
    public init(sessionHex: String, weekHex: String) {
        self.sessionHex = sessionHex
        self.weekHex = weekHex
    }
}

public enum Palette: String, CaseIterable, Sendable {
    case dusk, mist, sage, custom

    /// nil for .custom — custom has no fixed colors.
    public var preset: Theme? {
        switch self {
        case .dusk: return Theme(sessionHex: "#C9A283FF", weekHex: "#8FA3C2FF")
        case .mist: return Theme(sessionHex: "#FFFFFFBF", weekHex: "#FFFFFF73")
        case .sage: return Theme(sessionHex: "#9DB39AFF", weekHex: "#A294C4FF")
        case .custom: return nil
        }
    }
}

/// UserDefaults persistence with Dusk fallback on any corruption.
public struct ThemeSettings {
    public static let sessionKey = "theme.session"
    public static let weekKey = "theme.week"
    public static let paletteKey = "theme.palette"
    public static let identityKey = "identity.show"

    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> (theme: Theme, palette: Palette, showIdentity: Bool) {
        let showIdentity = defaults.bool(forKey: Self.identityKey) // default false
        let palette = defaults.string(forKey: Self.paletteKey).flatMap(Palette.init(rawValue:))
        let session = defaults.string(forKey: Self.sessionKey)
        let week = defaults.string(forKey: Self.weekKey)
        if let palette, let session, let week,
           ThemeColor.parse(session) != nil, ThemeColor.parse(week) != nil {
            return (Theme(sessionHex: session, weekHex: week), palette, showIdentity)
        }
        return (Palette.dusk.preset!, .dusk, showIdentity)
    }

    public func save(theme: Theme, palette: Palette, showIdentity: Bool) {
        defaults.set(theme.sessionHex, forKey: Self.sessionKey)
        defaults.set(theme.weekHex, forKey: Self.weekKey)
        defaults.set(palette.rawValue, forKey: Self.paletteKey)
        defaults.set(showIdentity, forKey: Self.identityKey)
    }
}
