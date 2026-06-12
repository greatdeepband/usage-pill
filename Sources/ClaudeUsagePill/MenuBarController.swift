import AppKit
import ServiceManagement
import UsageCore

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private let model: UsageModel
    private let onForceRefreshProviders: () -> Void
    private let onOpenSettings: () -> Void

    init(model: UsageModel,
         onForceRefreshProviders: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void) {
        self.model = model
        self.onForceRefreshProviders = onForceRefreshProviders
        self.onOpenSettings = onOpenSettings
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "gauge.with.needle", accessibilityDescription: "Usage Pill"
        )
        let menu = NSMenu()
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        let quitItem = NSMenuItem(title: "Quit Usage Pill", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(loginItem)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func refresh() {
        // Explicit user intent overrides the rate-limit backoff window —
        // for BOTH the Claude model and every provider row.
        Task { @MainActor in await model.refresh(force: true) }
        onForceRefreshProviders()
    }

    @objc private func toggleLogin() {
        // Launch at Login only works reliably when the app lives in /Applications.
        guard Bundle.main.bundlePath.hasPrefix("/Applications") else {
            let alert = NSAlert()
            alert.messageText = "Move to Applications first"
            alert.informativeText = "Launch at Login needs the app to live in /Applications so it can be found at login. Copy \"Usage Pill.app\" there and toggle this again."
            alert.alertStyle = .informational
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }

        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    @objc private func openSettings() { onOpenSettings() }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension MenuBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first { $0.action == #selector(toggleLogin) }?
            .state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
