import AppKit

// Single-instance guard: if another copy of the installed .app is already
// running, defer to it and exit immediately.  Debug binaries have no bundle id
// so Bundle.main.bundleIdentifier is nil; the fallback literal won't match a
// bare debug binary, so this guard is a no-op in development.
let runningCopies = NSRunningApplication.runningApplications(
    withBundleIdentifier: Bundle.main.bundleIdentifier ?? "pl.bbi.claude-usage-pill"
)
if runningCopies.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    exit(0) // another pill is already on screen; this launch defers to it
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon even before bundling
let delegate = AppDelegate()
app.delegate = delegate
app.run()
