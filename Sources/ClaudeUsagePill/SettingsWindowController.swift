import AppKit
import SwiftUI
import UsageCore

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: ThemeStore
    private let identity: IdentityModel
    private let previewModel: UsageModel

    init(store: ThemeStore, identity: IdentityModel) {
        self.store = store
        self.identity = identity
        // Fixed fake data for the preview; countdowns tick from "now".
        let snapshot = UsageSnapshot(
            session: UsageWindow(utilization: 62, resetsAt: Date().addingTimeInterval(2 * 3600 + 13 * 60)),
            week: UsageWindow(utilization: 38, resetsAt: Date().addingTimeInterval(3 * 24 * 3600))
        )
        previewModel = UsageModel(fetch: { snapshot })
        Task { @MainActor [previewModel] in await previewModel.refresh() }
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        w.title = "Claude Usage Pill Settings"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(
            rootView: SettingsView(store: store, previewModel: previewModel, identity: identity)
        )
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
