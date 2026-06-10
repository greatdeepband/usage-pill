import AppKit
import SwiftUI
import UsageCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: PillPanel!
    private var model: UsageModel!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let provider = KeychainCredentialsProvider()
        let fetcher = UsageFetcher(loadCredentials: { try provider.load() })
        model = UsageModel(fetch: { try await fetcher.fetch() })

        panel = PillPanel()
        panel.contentView = NSHostingView(
            rootView: PillView(model: model) { [weak self] expanded in
                self?.panel.setExpanded(expanded)
            }
        )
        panel.orderFrontRegardless()

        Task { @MainActor in await self.model.refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.model.refresh() }
        }
    }
}
