import AppKit
import ServiceManagement
import UsageCore

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private let model: UsageModel

    init(model: UsageModel) {
        self.model = model
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "gauge.with.needle", accessibilityDescription: "Claude Usage"
        )
        let menu = NSMenu()
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        let quitItem = NSMenuItem(title: "Quit Claude Usage Pill", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func refresh() {
        Task { @MainActor in await model.refresh() }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension MenuBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first { $0.action == #selector(toggleLogin) }?
            .state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
