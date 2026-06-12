import Foundation

/// Test-suite UserDefaults helper. Per-use cleanup is BEST-EFFORT (cfprefsd
/// writes async and can recreate the plist after we delete it); the startup
/// sweep below guarantees convergence: every run deletes strays from previous
/// runs, so accumulation is bounded at one run's worth.
enum TestDefaults {
    static let prefixes = ["theme-tests-", "provider-spec-tests-", "usage-pill-tests-"]

    private static let sweepOnce: Void = {
        let prefsDir = FileManager.default.homeDirectoryForCurrentUser
            .appending(components: "Library", "Preferences")
        if let files = try? FileManager.default.contentsOfDirectory(at: prefsDir, includingPropertiesForKeys: nil) {
            for url in files where prefixes.contains(where: { url.lastPathComponent.hasPrefix($0) }) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }()

    static func withFresh<T>(prefix: String = "usage-pill-tests-", _ body: (UserDefaults) throws -> T) rethrows -> T {
        _ = sweepOnce
        let name = prefix + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer {
            defaults.removePersistentDomain(forName: name)
            CFPreferencesAppSynchronize(name as CFString)
            let plist = FileManager.default.homeDirectoryForCurrentUser
                .appending(components: "Library", "Preferences", "\(name).plist")
            try? FileManager.default.removeItem(at: plist)
        }
        return try body(defaults)
    }
}
