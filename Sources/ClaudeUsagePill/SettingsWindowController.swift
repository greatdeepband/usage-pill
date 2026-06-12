import AppKit
import SwiftUI
import UsageCore

/// Settings = ONE pane: the provider list (ProvidersTabView) is the whole
/// window — no tabs, no preview (the live pill is the preview). SwiftUI is
/// hosted through an NSHostingController with `.preferredContentSize` sizing
/// so the window hugs the content; per-row appearance lives in each row's
/// detail sheet.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let themeStore: ThemeStore
    private let providersModel: ProvidersModel
    private let specStore: ProviderSpecStore
    private let keyStore: ProviderKeyStore

    init(themeStore: ThemeStore,
         providersModel: ProvidersModel,
         specStore: ProviderSpecStore,
         keyStore: ProviderKeyStore) {
        self.themeStore = themeStore
        self.providersModel = providersModel
        self.specStore = specStore
        self.keyStore = keyStore
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingController(rootView: ProvidersTabView(
            themeStore: themeStore,
            providersModel: providersModel,
            specStore: specStore,
            keyStore: keyStore
        ))
        host.sizingOptions = .preferredContentSize

        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable] // settings windows aren't resizable
        w.title = "Settings"
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
