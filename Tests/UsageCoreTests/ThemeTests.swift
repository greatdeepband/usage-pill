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
               sessionVisibility: .pinned, weekVisibility: .pinned, redAlert90: true)
        let loaded = ThemeSettings(defaults: d).load()
        #expect(loaded.theme == custom)
        #expect(loaded.palette == .custom)
        #expect(loaded.showIdentity == true)
    }
}

@Test func redAlert90DefaultsTrue() {
    TestDefaults.withFresh(prefix: "theme-tests-") { d in
        #expect(ThemeSettings(defaults: d).load().redAlert90 == true)
    }
}

@Test func redAlert90RoundTripsOff() {
    TestDefaults.withFresh(prefix: "theme-tests-") { d in
        let s = ThemeSettings(defaults: d)
        s.save(theme: Palette.dusk.preset!, palette: .dusk, showIdentity: false,
               sessionVisibility: .pinned, weekVisibility: .pinned, redAlert90: false)
        #expect(ThemeSettings(defaults: d).load().redAlert90 == false)
    }
}

@Test func corruptRedAlert90FallsBackToTrue() {
    TestDefaults.withFresh(prefix: "theme-tests-") { d in
        d.set("sometimes", forKey: "claude.redAlert90")
        #expect(ThemeSettings(defaults: d).load().redAlert90 == true)
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
               sessionVisibility: .expandedOnly, weekVisibility: .hidden, redAlert90: true)
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

// MARK: - First-run import from the v1 app's defaults domain (plan Task 18)

@Test func importCopiesLegacyThemeAndIdentity() {
    TestDefaults.withFresh(prefix: "theme-tests-") { legacy in
        TestDefaults.withFresh(prefix: "theme-tests-") { ours in
            legacy.set("#11223344", forKey: ThemeSettings.sessionKey)
            legacy.set("#55667788", forKey: ThemeSettings.weekKey)
            legacy.set("custom", forKey: ThemeSettings.paletteKey)
            legacy.set(true, forKey: ThemeSettings.identityKey)
            ThemeSettings.importLegacyIfNeeded(from: legacy, into: ours)
            let loaded = ThemeSettings(defaults: ours).load()
            #expect(loaded.theme == Theme(sessionHex: "#11223344", weekHex: "#55667788"))
            #expect(loaded.palette == .custom)
            #expect(loaded.showIdentity == true)
            #expect(ours.bool(forKey: ThemeSettings.didImportV1Key) == true)
        }
    }
}

@Test func importSecondCallIsNoOp() {
    TestDefaults.withFresh(prefix: "theme-tests-") { legacy in
        TestDefaults.withFresh(prefix: "theme-tests-") { ours in
            legacy.set("#11223344", forKey: ThemeSettings.sessionKey)
            legacy.set("#55667788", forKey: ThemeSettings.weekKey)
            legacy.set("custom", forKey: ThemeSettings.paletteKey)
            ThemeSettings.importLegacyIfNeeded(from: legacy, into: ours)
            // User re-themes after the import; legacy changes too.
            ThemeSettings(defaults: ours).save(
                theme: Palette.sage.preset!, palette: .sage, showIdentity: false,
                sessionVisibility: .pinned, weekVisibility: .pinned, redAlert90: true)
            legacy.set("#AABBCCDD", forKey: ThemeSettings.sessionKey)
            ThemeSettings.importLegacyIfNeeded(from: legacy, into: ours)
            let loaded = ThemeSettings(defaults: ours).load()
            #expect(loaded.theme == Palette.sage.preset!)
            #expect(loaded.palette == .sage)
        }
    }
}

@Test func importAbsentLegacyDomainNoOpsButMarksDone() {
    TestDefaults.withFresh(prefix: "theme-tests-") { ours in
        ThemeSettings.importLegacyIfNeeded(from: nil, into: ours)
        #expect(ours.bool(forKey: ThemeSettings.didImportV1Key) == true)
        #expect(ours.string(forKey: ThemeSettings.sessionKey) == nil)
        let loaded = ThemeSettings(defaults: ours).load()
        #expect(loaded.theme == Palette.dusk.preset!) // untouched defaults
    }
}

@Test func importEmptyLegacyDomainCopiesNothingButMarksDone() {
    TestDefaults.withFresh(prefix: "theme-tests-") { legacy in
        TestDefaults.withFresh(prefix: "theme-tests-") { ours in
            ThemeSettings.importLegacyIfNeeded(from: legacy, into: ours)
            #expect(ours.bool(forKey: ThemeSettings.didImportV1Key) == true)
            #expect(ours.string(forKey: ThemeSettings.sessionKey) == nil)
            #expect(ours.object(forKey: ThemeSettings.identityKey) == nil)
        }
    }
}

@Test func importSkipsWhenAlreadyMarkedDone() {
    TestDefaults.withFresh(prefix: "theme-tests-") { legacy in
        TestDefaults.withFresh(prefix: "theme-tests-") { ours in
            ours.set(true, forKey: ThemeSettings.didImportV1Key)
            ThemeSettings(defaults: ours).save(
                theme: Palette.mist.preset!, palette: .mist, showIdentity: false,
                sessionVisibility: .pinned, weekVisibility: .pinned, redAlert90: true)
            legacy.set("#11223344", forKey: ThemeSettings.sessionKey)
            legacy.set("#55667788", forKey: ThemeSettings.weekKey)
            legacy.set("custom", forKey: ThemeSettings.paletteKey)
            ThemeSettings.importLegacyIfNeeded(from: legacy, into: ours)
            let loaded = ThemeSettings(defaults: ours).load()
            #expect(loaded.theme == Palette.mist.preset!)
            #expect(loaded.palette == .mist)
        }
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

// MARK: - authMode

@Test func authModeDefaultsToAuto() {
    TestDefaults.withFresh(prefix: "theme-tests-") { d in
        #expect(ThemeSettings(defaults: d).load().authMode == "auto")
    }
}

@Test func authModeRoundTripsToken() {
    TestDefaults.withFresh(prefix: "theme-tests-") { d in
        let s = ThemeSettings(defaults: d)
        s.save(theme: Palette.dusk.preset!, palette: .dusk, showIdentity: false,
               sessionVisibility: .pinned, weekVisibility: .pinned, redAlert90: true,
               authMode: "token")
        #expect(ThemeSettings(defaults: d).load().authMode == "token")
    }
}

@Test func corruptAuthModeFallsBackToAuto() {
    TestDefaults.withFresh(prefix: "theme-tests-") { d in
        d.set("banana", forKey: ThemeSettings.authModeKey)
        #expect(ThemeSettings(defaults: d).load().authMode == "auto")
    }
}
