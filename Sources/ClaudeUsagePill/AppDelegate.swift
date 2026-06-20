import AppKit
import Combine
import SwiftUI
import UsageCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: PillPanel!
    private var providersModel: ProvidersModel!
    private var providerTimer: Timer?
    private var menuBar: MenuBarController!
    private var themeStore: ThemeStore!
    private var settingsController: SettingsWindowController!
    private var cancellables = Set<AnyCancellable>()

    // The Claude credential path is compiled OUT of the MAS (sandboxed,
    // providers-only) build: App Sandbox cannot read Claude Code's keychain
    // item. Everything Claude-specific lives behind `#if !MAS_BUILD`.
    #if !MAS_BUILD
    private var model: UsageModel!
    private var timer: Timer?
    private var identityModel: IdentityModel!
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
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if !MAS_BUILD
        let provider = KeychainCredentialsProvider()
        let cache = CredentialsCache(load: { try provider.load() })
        // The two synchronous main-thread presence probes below (:first-run
        // smart default, walkthrough claudeCheck) use a SHORT-timeout reader so
        // a hung `security` subprocess can never beachball launch or the
        // walkthrough — bounded ≤ ~2 s worst case (1.5 s SIGTERM + 0.5 s SIGKILL
        // grace). The cache's `provider` above deliberately keeps the default
        // 5 s reader: it runs OFF the main thread inside the CredentialsCache
        // actor and is cached/rare, so the longer window is fine there.
        let probeProvider = KeychainCredentialsProvider(
            reader: SecurityToolReader(timeout: 1.5, killGrace: 0.5))
        let fetcher = UsageFetcher(cache: cache)
        model = UsageModel(fetch: { try await fetcher.fetch() })
        #endif

        let keyStore = ProviderKeyStore()
        let specStore = ProviderSpecStore()
        let engine = ProviderEngine()
        let spendAdapter = OpenAISpendAdapter()
        providersModel = ProvidersModel(
            specStore: specStore,
            keyLookup: { keyStore.loadKey(for: $0) },
            makeFetch: { spec, key in
                // Native adapters route here; everything else through the engine.
                // (ProviderEngine itself refuses non-generic specs — defense in depth.)
                switch spec.adapter {
                case .openAISpend: return { try await spendAdapter.fetchValue(spec: spec, key: key) }
                default: return { try await engine.fetchValue(spec: spec, key: key) }
                }
            }
        )

        // Smart first-launch default (plan Task 3): decide whether this is the
        // very first run BEFORE importLegacyIfNeeded — that call sets the
        // didImportV1 marker, so the capture must precede it.
        let wasFirstRun = UserDefaults.standard.object(forKey: ThemeSettings.didImportV1Key) == nil
        // One-shot import of the v1 app's appearance settings, BEFORE the
        // store reads our domain. Read-only against the legacy domain.
        ThemeSettings.importLegacyIfNeeded(
            from: UserDefaults(suiteName: ThemeSettings.legacyV1Domain),
            into: .standard
        )
        #if !MAS_BUILD
        if wasFirstRun {
            // One-shot synchronous credential presence check via the SAME
            // read-only loader CredentialsCache wraps — this is the launch
            // keychain read 1.0 already performs (one documented Always Allow
            // at most; absence throws CredentialsError). Token found → write
            // nothing, the defaults already mean .pinned. Not found/unreadable
            // → start with both Claude rows hidden, persisted through
            // ThemeSettings' own key constants BEFORE ThemeStore loads them,
            // so a non-Claude user gets the empty-capsule hint instead of two
            // dead bars.
            // Use the SHORT-timeout probeProvider so a hung `security` can't
            // beachball first-run launch. A timeout/error → load() throws →
            // treated as "absent" here (hides both Claude rows). That is a
            // benign cosmetic default on the rare first-run hang — the user can
            // unpin/repin in Settings — and never a beachball.
            if (try? probeProvider.load()) == nil {
                let hidden = ProviderSpec.Visibility.hidden.rawValue
                UserDefaults.standard.set(hidden, forKey: ThemeSettings.sessionVisibilityKey)
                UserDefaults.standard.set(hidden, forKey: ThemeSettings.weekVisibilityKey)
            }
        }
        #else
        _ = wasFirstRun // first-run is Claude-only; nothing to default in MAS
        #endif
        themeStore = ThemeStore()

        #if !MAS_BUILD
        let profileFetcher = ProfileFetcher(cache: cache)
        identityModel = IdentityModel(cache: cache, fetchProfile: { try await profileFetcher.fetch() })
        settingsController = SettingsWindowController(
            themeStore: themeStore,
            providersModel: providersModel,
            specStore: specStore,
            keyStore: keyStore,
            // Walkthrough credential check: presence only, nothing retained,
            // via the SHORT-timeout probeProvider so the walkthrough can't
            // beachball. A timeout/error → load() throws → returns false ("no
            // sign-in found yet", the walkthrough's existing benign state);
            // bounded ≤ ~2 s.
            claudeCheck: { (try? probeProvider.load()) != nil }
        )
        #else
        settingsController = SettingsWindowController(
            themeStore: themeStore,
            providersModel: providersModel,
            specStore: specStore,
            keyStore: keyStore
        )
        #endif

        panel = PillPanel()
        // MAS build: the panel is providers-only — no Claude model, no identity.
        #if MAS_BUILD
        let claudeModel: UsageModel? = nil
        let claudeIdentity: IdentityModel? = nil
        #else
        let claudeModel: UsageModel? = model
        let claudeIdentity: IdentityModel? = identityModel
        #endif
        panel.contentView = NSHostingView(
            rootView: PillView(
                model: claudeModel, theme: themeStore, identity: claudeIdentity, providers: providersModel
            ) { [weak self] expanded in
                self?.panel.setExpanded(expanded)
            }
        )
        panel.orderFrontRegardless()
        syncPanelLayout()

        #if !MAS_BUILD
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
        #endif

        // Any rows change (settings add/remove/visibility → reload()) resizes
        // the pill — future reload() call sites need no manual sync call.
        providersModel.$rows
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncPanelLayout() }
            .store(in: &cancellables)

        #if !MAS_BUILD
        if anyClaudeRowVisible {
            Task { @MainActor in await self.model.refresh() }
        }
        #endif
        Task { @MainActor in await self.providersModel.refreshAll() }

        #if !MAS_BUILD
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
        #endif

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
                #if !MAS_BUILD
                if self.anyClaudeRowVisible { await self.model.refresh() }
                #endif
                await self.providersModel.refreshAll()
            }
        }
        // Also refresh after the displays themselves wake (separate from system wake).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                #if !MAS_BUILD
                if self.anyClaudeRowVisible { await self.model.refresh() }
                #endif
                await self.providersModel.refreshAll()
            }
        }
        #if !MAS_BUILD
        menuBar = MenuBarController(
            model: model,
            onForceRefreshProviders: { [weak self] in
                Task { @MainActor in await self?.providersModel.refreshAll(force: true) }
            },
            onOpenSettings: { [weak self] in self?.settingsController.show() }
        )
        #else
        menuBar = MenuBarController(
            onForceRefreshProviders: { [weak self] in
                Task { @MainActor in await self?.providersModel.refreshAll(force: true) }
            },
            onOpenSettings: { [weak self] in self?.settingsController.show() }
        )
        #endif
    }

    /// Recompute row/section counts for the panel's dynamic heights from the
    /// Claude visibilities + provider specs.  Call after anything that changes
    /// which rows are visible (theme settings, provider reload, identity state).
    /// Sections (Task 18a): the Claude section header counts when ≥1 Claude
    /// row is visible in that mode; each visible provider is its own section.
    private func syncPanelLayout() {
        let rows = providersModel.rows
        let pinnedProviders = rows.filter { $0.spec.visibility == .pinned }.count
        // MAS build is providers-only: no Claude rows, no identity strip.
        #if MAS_BUILD
        let pinnedClaude = 0
        let expandedClaude = 0
        let identity = false
        #else
        let claudeVis = [themeStore.sessionVisibility, themeStore.weekVisibility]
        let pinnedClaude = claudeVis.filter { $0 == .pinned }.count
        let expandedClaude = claudeVis.filter { $0 != .hidden }.count
        // Identity lives INSIDE the Claude section now — both Claude rows
        // hidden ⇒ no strip, so it must not add height either.
        let identity = expandedClaude > 0 && themeStore.showIdentity
            && (identityModel.email != nil || identityModel.planBadge != nil)
        #endif
        panel.applyRowCounts(
            pinnedClaude: pinnedClaude,
            pinnedProviders: pinnedProviders,
            expandedClaude: expandedClaude,
            expandedProviders: rows.count, // hidden specs never get a row
            compactSections: (pinnedClaude > 0 ? 1 : 0) + pinnedProviders,
            expandedSections: (expandedClaude > 0 ? 1 : 0) + rows.count,
            identity: identity
        )
    }
}
