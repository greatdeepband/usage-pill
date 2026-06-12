import AppKit
import SwiftUI
import UsageCore

/// Settings = ONE window with PUSHED pages: ProvidersTabView's Page enum is
/// the whole navigation — no tabs, no sheets, no preview (the live pill is
/// the preview). SwiftUI is hosted through an NSHostingController with
/// `.preferredContentSize` sizing so the window hugs the current page; the
/// window title follows the page via the onTitle relay.
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
            // Fresh content every open: a window closed mid-page would
            // otherwise keep that page's state alive — including a stale
            // Claude-page entry snapshot whose Back would revert edits the
            // user already kept by closing the window (Task 18c review).
            window.contentViewController = makeHost()
            window.title = "Settings"
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = makeHost()

        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable] // settings windows aren't resizable
        w.title = "Settings"
        w.isReleasedWhenClosed = false
        // Direction-2 ("soft like the pill"): the white-6% cards and
        // black-30% capsule fields are designed against the pill's dark
        // palette — pin the content to dark so the design reads in any
        // system appearance. Chrome style itself stays the OS's.
        w.appearance = NSAppearance(named: .darkAqua)
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeHost() -> NSHostingController<ProvidersTabView> {
        let host = NSHostingController(rootView: ProvidersTabView(
            themeStore: themeStore,
            providersModel: providersModel,
            specStore: specStore,
            keyStore: keyStore,
            onTitle: { [weak self] title in self?.window?.title = title }
        ))
        host.sizingOptions = .preferredContentSize
        return host
    }
}
