import AppKit
import Combine
import SwiftUI
import UsageCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: PillPanel!
    private var model: UsageModel!
    private var providersModel: ProvidersModel!
    private var timer: Timer?
    private var providerTimer: Timer?
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

        let keyStore = ProviderKeyStore()
        let engine = ProviderEngine()
        providersModel = ProvidersModel(
            specStore: ProviderSpecStore(),
            keyLookup: { keyStore.loadKey(for: $0) },
            makeFetch: { spec, key in { try await engine.fetchValue(spec: spec, key: key) } }
        )

        themeStore = ThemeStore()
        let profileFetcher = ProfileFetcher(cache: cache)
        identityModel = IdentityModel(cache: cache, fetchProfile: { try await profileFetcher.fetch() })
        settingsController = SettingsWindowController(store: themeStore)

        panel = PillPanel()
        panel.contentView = NSHostingView(
            rootView: PillView(
                model: model, theme: themeStore, identity: identityModel, providers: providersModel
            ) { [weak self] expanded in
                self?.panel.setExpanded(expanded)
            }
        )
        panel.orderFrontRegardless()
        syncPanelLayout()

        themeStore.$showIdentity
            .combineLatest(identityModel.$email, identityModel.$planBadge)
            .receive(on: RunLoop.main)
            .sink { [weak self] on, _, _ in
                self?.syncPanelLayout()
                if on { self?.identityModel.loadIfNeeded() }
            }
            .store(in: &cancellables)

        // Claude row visibility changes resize the (collapsed) pill immediately.
        themeStore.$sessionVisibility
            .combineLatest(themeStore.$weekVisibility)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.syncPanelLayout() }
            .store(in: &cancellables)

        Task { @MainActor in await self.model.refresh() }
        Task { @MainActor in await self.providersModel.refreshAll() }

        // Create timer and add to .common so it fires even while menus or drags
        // are tracking (which run the RunLoop in a tracking mode, not .default).
        // 360s: two pills may run side-by-side (the frozen v1.x app polls at 180s);
        // combined Claude polling must stay under the endpoint's ~30 req/h tolerance
        // — see plan Task 0.
        let t = Timer(timeInterval: 360, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.refresh() }
        }
        t.tolerance = 30 // let the OS coalesce wake-ups
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // Provider scheduler: separate cadence from the Claude poll — these are
        // the user's OWN keys against third-party endpoints, 300 s is polite.
        let pt = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.providersModel.refreshAll() }
        }
        pt.tolerance = 30
        RunLoop.main.add(pt, forMode: .common)
        providerTimer = pt

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.model.refresh()
                await self?.providersModel.refreshAll()
            }
        }
        // Also refresh after the displays themselves wake (separate from system wake).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.model.refresh()
                await self?.providersModel.refreshAll()
            }
        }
        menuBar = MenuBarController(
            model: model,
            onForceRefreshProviders: { [weak self] in
                Task { @MainActor in await self?.providersModel.refreshAll(force: true) }
            },
            onOpenSettings: { [weak self] in self?.settingsController.show() }
        )
    }

    /// Recompute row counts for the panel's dynamic heights from the Claude
    /// visibilities + provider specs.  Call after anything that changes which
    /// rows are visible (theme settings, provider reload, identity state).
    private func syncPanelLayout() {
        let claudeVis = [themeStore.sessionVisibility, themeStore.weekVisibility]
        let rows = providersModel.rows
        panel.applyRowCounts(
            pinnedClaude: claudeVis.filter { $0 == .pinned }.count,
            pinnedProviders: rows.filter { $0.spec.visibility == .pinned }.count,
            expandedClaude: claudeVis.filter { $0 != .hidden }.count,
            expandedProviders: rows.count, // hidden specs never get a row
            identity: themeStore.showIdentity
                && (identityModel.email != nil || identityModel.planBadge != nil)
        )
    }
}
