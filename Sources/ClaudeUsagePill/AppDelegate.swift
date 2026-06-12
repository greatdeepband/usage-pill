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
    /// Tracks the visibility-sink's last "any Claude row visible" state so a
    /// both-hidden → any-visible flip can trigger an immediate catch-up fetch.
    private var claudeWasVisible = false

    /// Hidden Claude rows are not fetched at all (carried hostile finding):
    /// scheduled and wake refreshes skip while BOTH rows are .hidden.
    /// Refresh Now (menu bar) calls model.refresh(force:) directly and is
    /// deliberately not gated.
    private var anyClaudeRowVisible: Bool {
        themeStore.sessionVisibility != .hidden || themeStore.weekVisibility != .hidden
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let provider = KeychainCredentialsProvider()
        let cache = CredentialsCache(load: { try provider.load() })
        let fetcher = UsageFetcher(cache: cache)
        model = UsageModel(fetch: { try await fetcher.fetch() })

        let keyStore = ProviderKeyStore()
        let specStore = ProviderSpecStore()
        let engine = ProviderEngine()
        providersModel = ProvidersModel(
            specStore: specStore,
            keyLookup: { keyStore.loadKey(for: $0) },
            makeFetch: { spec, key in { try await engine.fetchValue(spec: spec, key: key) } }
        )

        // One-shot import of the v1 app's appearance settings, BEFORE the
        // store reads our domain. Read-only against the legacy domain.
        ThemeSettings.importLegacyIfNeeded(
            from: UserDefaults(suiteName: ThemeSettings.legacyV1Domain),
            into: .standard
        )
        themeStore = ThemeStore()
        let profileFetcher = ProfileFetcher(cache: cache)
        identityModel = IdentityModel(cache: cache, fetchProfile: { try await profileFetcher.fetch() })
        settingsController = SettingsWindowController(
            themeStore: themeStore,
            providersModel: providersModel,
            specStore: specStore,
            keyStore: keyStore
        )

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
        // A both-hidden → any-visible flip also fetches right away: scheduled
        // refreshes were skipped while hidden, so the rows would otherwise show
        // stale (or no) data until the next timer tick.
        claudeWasVisible = anyClaudeRowVisible
        themeStore.$sessionVisibility
            .combineLatest(themeStore.$weekVisibility)
            .receive(on: RunLoop.main)
            .sink { [weak self] session, week in
                guard let self else { return }
                let visible = session != .hidden || week != .hidden
                if visible && !self.claudeWasVisible {
                    Task { @MainActor in await self.model.refresh() }
                }
                self.claudeWasVisible = visible
                self.syncPanelLayout()
            }
            .store(in: &cancellables)

        // Any rows change (settings add/remove/visibility → reload()) resizes
        // the pill — future reload() call sites need no manual sync call.
        providersModel.$rows
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncPanelLayout() }
            .store(in: &cancellables)

        if anyClaudeRowVisible {
            Task { @MainActor in await self.model.refresh() }
        }
        Task { @MainActor in await self.providersModel.refreshAll() }

        // Create timer and add to .common so it fires even while menus or drags
        // are tracking (which run the RunLoop in a tracking mode, not .default).
        // 360s: two pills may run side-by-side (the frozen v1.x app polls at 180s);
        // combined Claude polling must stay under the endpoint's ~30 req/h tolerance
        // — see plan Task 0.
        let t = Timer(timeInterval: 360, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.anyClaudeRowVisible else { return }
                await self.model.refresh()
            }
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
                guard let self else { return }
                if self.anyClaudeRowVisible { await self.model.refresh() }
                await self.providersModel.refreshAll()
            }
        }
        // Also refresh after the displays themselves wake (separate from system wake).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.anyClaudeRowVisible { await self.model.refresh() }
                await self.providersModel.refreshAll()
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

    /// Recompute row/section counts for the panel's dynamic heights from the
    /// Claude visibilities + provider specs.  Call after anything that changes
    /// which rows are visible (theme settings, provider reload, identity state).
    /// Sections (Task 18a): the Claude section header counts when ≥1 Claude
    /// row is visible in that mode; each visible provider is its own section.
    private func syncPanelLayout() {
        let claudeVis = [themeStore.sessionVisibility, themeStore.weekVisibility]
        let rows = providersModel.rows
        let pinnedClaude = claudeVis.filter { $0 == .pinned }.count
        let pinnedProviders = rows.filter { $0.spec.visibility == .pinned }.count
        let expandedClaude = claudeVis.filter { $0 != .hidden }.count
        panel.applyRowCounts(
            pinnedClaude: pinnedClaude,
            pinnedProviders: pinnedProviders,
            expandedClaude: expandedClaude,
            expandedProviders: rows.count, // hidden specs never get a row
            compactSections: (pinnedClaude > 0 ? 1 : 0) + pinnedProviders,
            expandedSections: (expandedClaude > 0 ? 1 : 0) + rows.count,
            // Identity lives INSIDE the Claude section now — both Claude rows
            // hidden ⇒ no strip, so it must not add height either.
            identity: expandedClaude > 0 && themeStore.showIdentity
                && (identityModel.email != nil || identityModel.planBadge != nil)
        )
    }
}
