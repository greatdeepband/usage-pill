import Foundation
import Testing
@testable import UsageCore

private func freshDefaults() -> UserDefaults {
    let name = "theme-tests-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@Test func presetsHaveExpectedColors() {
    #expect(Palette.dusk.preset == Theme(sessionHex: "#C9A283FF", weekHex: "#8FA3C2FF"))
    #expect(Palette.mist.preset == Theme(sessionHex: "#FFFFFFBF", weekHex: "#FFFFFF73"))
    #expect(Palette.sage.preset == Theme(sessionHex: "#9DB39AFF", weekHex: "#A294C4FF"))
    #expect(Palette.custom.preset == nil)
}

@Test func loadDefaultsToDuskWithIdentityOff() {
    let s = ThemeSettings(defaults: freshDefaults())
    let loaded = s.load()
    #expect(loaded.theme == Palette.dusk.preset!)
    #expect(loaded.palette == .dusk)
    #expect(loaded.showIdentity == false)
}

@Test func saveLoadRoundTrip() {
    let d = freshDefaults()
    let s = ThemeSettings(defaults: d)
    let custom = Theme(sessionHex: "#11223344", weekHex: "#55667788")
    s.save(theme: custom, palette: .custom, showIdentity: true)
    let loaded = ThemeSettings(defaults: d).load()
    #expect(loaded.theme == custom)
    #expect(loaded.palette == .custom)
    #expect(loaded.showIdentity == true)
}

@Test func corruptHexFallsBackToDusk() {
    let d = freshDefaults()
    d.set("not-a-color", forKey: "theme.session")
    d.set("#55667788", forKey: "theme.week")
    d.set("custom", forKey: "theme.palette")
    let loaded = ThemeSettings(defaults: d).load()
    #expect(loaded.theme == Palette.dusk.preset!)
    #expect(loaded.palette == .dusk)
}

@Test func unknownPaletteNameFallsBackToDusk() {
    let d = freshDefaults()
    d.set("neon", forKey: "theme.palette")
    #expect(ThemeSettings(defaults: d).load().palette == .dusk)
}

@Test func fallbackPreservesIdentityToggle() {
    let d = freshDefaults()
    d.set("not-a-color", forKey: "theme.session")
    d.set(true, forKey: "identity.show")
    let loaded = ThemeSettings(defaults: d).load()
    #expect(loaded.theme == Palette.dusk.preset!)
    #expect(loaded.showIdentity == true) // fallback must not reset the toggle
}
