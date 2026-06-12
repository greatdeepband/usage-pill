import AppKit
import SwiftUI
import UsageCore

/// Settings = native toolbar-tabbed window (NSTabViewController with the
/// .toolbar tab style): AppKit renders the standard settings toolbar tabs and
/// ANIMATES the window frame to each tab's content size on switch, so tabs of
/// different sizes never show blank space. Each tab hosts SwiftUI through an
/// NSHostingController with `.preferredContentSize` sizing so the window hugs
/// the tab's intrinsic content. All chrome is the OS's own — nothing
/// hand-rolled.
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

        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar

        // Appearance: the v1 SettingsView, unchanged (its own 340pt width).
        let appearance = NSHostingController(rootView: SettingsView(store: themeStore))
        appearance.sizingOptions = .preferredContentSize
        let appearanceTab = NSTabViewItem(viewController: appearance)
        appearanceTab.label = "Appearance"
        appearanceTab.image = NSImage(
            systemSymbolName: "paintbrush", accessibilityDescription: "Appearance"
        )

        // Providers: 380pt grouped-form management tab.
        let providers = NSHostingController(rootView: ProvidersTabView(
            themeStore: themeStore,
            providersModel: providersModel,
            specStore: specStore,
            keyStore: keyStore
        ))
        providers.sizingOptions = .preferredContentSize
        let providersTab = NSTabViewItem(viewController: providers)
        providersTab.label = "Providers"
        providersTab.image = NSImage(
            systemSymbolName: "list.bullet", accessibilityDescription: "Providers"
        )

        tabs.addTabViewItem(appearanceTab)
        tabs.addTabViewItem(providersTab)

        let w = NSWindow(contentViewController: tabs)
        w.styleMask = [.titled, .closable] // settings windows aren't resizable
        w.toolbarStyle = .preference       // icon-over-label centered tabs
        w.title = appearanceTab.label
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Keeps the window title in sync with the selected tab — the System
/// Settings convention for toolbar-style tab windows.
private final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let label = tabViewItem?.label, !label.isEmpty {
            view.window?.title = label
        }
    }
}
