import AppKit
import Combine
import SwiftUI
import UsageCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: PillPanel!
    private var model: UsageModel!
    private var timer: Timer?
    private var menuBar: MenuBarController!
    private var themeStore: ThemeStore!
    private var identityModel: IdentityModel!
    private var settingsController: SettingsWindowController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let provider = KeychainCredentialsProvider()
        let cache = CredentialsCache(load: { try provider.load() })
        let fetcher = UsageFetcher(cache: cache)
        model = UsageModel(fetch: { try await fetcher.fetch() })

        themeStore = ThemeStore()
        let profileFetcher = ProfileFetcher(cache: cache)
        identityModel = IdentityModel(cache: cache, fetchProfile: { try await profileFetcher.fetch() })
        settingsController = SettingsWindowController(store: themeStore)

        panel = PillPanel()
        panel.contentView = NSHostingView(
            rootView: PillView(model: model, theme: themeStore, identity: identityModel) { [weak self] expanded in
                self?.panel.setExpanded(expanded)
            }
        )
        panel.orderFrontRegardless()

        themeStore.$showIdentity
            .combineLatest(identityModel.$email, identityModel.$planBadge)
            .receive(on: RunLoop.main)
            .sink { [weak self] on, email, badge in
                self?.panel.identityEnabled = on && (email != nil || badge != nil)
                if on { self?.identityModel.loadIfNeeded() }
            }
            .store(in: &cancellables)

        Task { @MainActor in await self.model.refresh() }

        // Create timer and add to .common so it fires even while menus or drags
        // are tracking (which run the RunLoop in a tracking mode, not .default).
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.refresh() }
        }
        t.tolerance = 10 // let the OS coalesce wake-ups
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.model.refresh() }
        }
        // Also refresh after the displays themselves wake (separate from system wake).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.model.refresh() }
        }
        menuBar = MenuBarController(model: model, onOpenSettings: { [weak self] in self?.settingsController.show() })
    }
}
