import Foundation
import Testing
@testable import UsageCore


@Test func presetsHaveExpectedColors() {
    #expect(Palette.dusk.preset == Theme(sessionHex: "#C9A283FF", weekHex: "#8FA3C2FF"))
    #expect(Palette.mist.preset == Theme(sessionHex: "#FFFFFFBF", weekHex: "#FFFFFF73"))
    #expect(Palette.sage.preset == Theme(sessionHex: "#9DB39AFF", weekHex: "#A294C4FF"))
    #expect(Palette.custom.preset == nil)
}

@Test func loadDefaultsToDuskWithIdentityOff() {
    TestDefaults.withFresh(prefix: "theme-tests-") { d in
        let s = ThemeSettings(defaults: d)
        let loaded = s.load()
        #expect(loaded.theme == Palette.dusk.preset!)
        #expect(loaded.palette == .dusk)
        #expect(loaded.showIdentity == false)
    }
}

@Test func saveLoadRoundTrip() {
    TestDefaults.withFresh(prefix: "theme-tests-") { d in
        let s = ThemeSettings(defaults: d)
        let custom = Theme(sessionHex: "#11223344", weekHex: "#55667788")
        s.save(theme: custom, palette: .custom, showIdentity: true,
               sessionVisibility: .pinned, weekVisibility: .pinned)
        let loaded = ThemeSettings(defaults: d).load()
        #expect(loaded.theme == custom)
        #expect(loaded.palette == .custom)
        #expect(loaded.showIdentity == true)
    }
}

@Test func claudeVisibilityDefaultsToPinned() {
    TestDefaults.withFresh(prefix: "theme-tests-") { d in
        let loaded = ThemeSettings(defaults: d).load()
        #expect(loaded.sessionVisibility == .pinned)
        #expect(loaded.weekVisibility == .pinned)
    }
}

@Test func claudeVisibilityRoundTrips() {
    TestDefaults.withFresh(prefix: "theme-tests-") { d in
        let s = ThemeSettings(defaults: d)
        s.save(theme: Palette.dusk.preset!, palette: .dusk, showIdentity: false,
               sessionVisibility: .expandedOnly, weekVisibility: .hidden)
        let loaded = ThemeSettings(defaults: d).load()
        #expect(loaded.sessionVisibility == .expandedOnly)
        #expect(loaded.weekVisibility == .hidden)
    }
}

@Test func garbageClaudeVisibilityFallsBackToPinned() {
    TestDefaults.withFresh(prefix: "theme-tests-") { d in
        d.set("sometimes", forKey: "claude.sessionVisibility")
        d.set(42, forKey: "claude.weekVisibility")
        let loaded = ThemeSettings(defaults: d).load()
        #expect(loaded.sessionVisibility == .pinned)
        #expect(loaded.weekVisibility == .pinned)
    }
}

@Test func corruptHexFallsBackToDusk() {
    TestDefaults.withFresh(prefix: "theme-tests-") { d in
        d.set("not-a-color", forKey: "theme.session")
        d.set("#55667788", forKey: "theme.week")
        d.set("custom", forKey: "theme.palette")
        let loaded = ThemeSettings(defaults: d).load()
        #expect(loaded.theme == Palette.dusk.preset!)
        #expect(loaded.palette == .dusk)
    }
}

@Test func unknownPaletteNameFallsBackToDusk() {
    TestDefaults.withFresh(prefix: "theme-tests-") { d in
        d.set("neon", forKey: "theme.palette")
        #expect(ThemeSettings(defaults: d).load().palette == .dusk)
    }
}

@Test func fallbackPreservesIdentityToggle() {
    TestDefaults.withFresh(prefix: "theme-tests-") { d in
        d.set("not-a-color", forKey: "theme.session")
        d.set(true, forKey: "identity.show")
        let loaded = ThemeSettings(defaults: d).load()
        #expect(loaded.theme == Palette.dusk.preset!)
        #expect(loaded.showIdentity == true) // fallback must not reset the toggle
    }
}
