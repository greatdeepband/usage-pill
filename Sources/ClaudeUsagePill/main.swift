import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon even before bundling
let delegate = AppDelegate()
app.delegate = delegate
app.run()
