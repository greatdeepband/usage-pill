import AppKit

// Single-instance guard: defer to an OLDER running copy (deterministic
// tiebreak by launch date, then PID, so two simultaneous launches can't
// both exit). Note: a debug binary has no bundle id and uses the fallback
// string — if the installed .app is running, the debug binary defers to it;
// kill the installed copy first when developing.
let current = NSRunningApplication.current
let copies = NSRunningApplication.runningApplications(
    withBundleIdentifier: Bundle.main.bundleIdentifier ?? "pl.bbi.usage-pill"
)
// nil launchDate (direct-exec'd binary, e.g. from the build dir) must
// DEFER to any real copy — treat self as newest, not oldest.
let myLaunch = current.launchDate ?? .distantFuture
if copies.contains(where: { other in
    guard other.processIdentifier != current.processIdentifier else { return false }
    let otherLaunch = other.launchDate ?? .distantPast
    return otherLaunch < myLaunch
        || (otherLaunch == myLaunch && other.processIdentifier < current.processIdentifier)
}) {
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon even before bundling
let delegate = AppDelegate()
app.delegate = delegate
app.run()
