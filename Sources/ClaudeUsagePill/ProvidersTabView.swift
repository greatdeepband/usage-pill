import SwiftUI
import UsageCore

/// Settings root: ONE window, PUSHED pages (no sheets — the sheet
/// first-responder chain was eating keystrokes in text fields). A Page enum
/// drives a single view with slide transitions; the window title follows the
/// page via `onTitle`. Every mutation still follows the same path: edit the
/// local specs array → specStore.save → providersModel.reload() —
/// AppDelegate's $rows sink then resizes the pill automatically.
///
/// Back/Done semantics (bottom-right on every pushed page): Back returns
/// WITHOUT applying the page's pending edits, Done applies and returns. The
/// provider page drafts locally so Back is naturally a discard; the Claude
/// page edits ThemeStore LIVE (the pill is the preview), so it snapshots the
/// full theme state on entry and Back restores the snapshot.
///
/// Reordering: SwiftUI's .onMove has no effect outside a List on macOS;
/// fallback per plan: a small up/down menu per provider row.
struct ProvidersTabView: View {
    @ObservedObject var themeStore: ThemeStore
    @ObservedObject var providersModel: ProvidersModel
    let specStore: ProviderSpecStore
    let keyStore: ProviderKeyStore
    /// Window-title relay: fires on appearance and on every page change.
    var onTitle: (String) -> Void = { _ in }

    enum Page: Equatable {
        case list
        case claude
        case provider(ProviderSpec)
        case addFlow
    }

    @State private var page: Page = .list
    @State private var specs: [ProviderSpec]

    init(themeStore: ThemeStore,
         providersModel: ProvidersModel,
         specStore: ProviderSpecStore,
         keyStore: ProviderKeyStore,
         onTitle: @escaping (String) -> Void = { _ in }) {
        self.themeStore = themeStore
        self.providersModel = providersModel
        self.specStore = specStore
        self.keyStore = keyStore
        self.onTitle = onTitle
        _specs = State(initialValue: specStore.load())
    }

    var body: some View {
        ZStack(alignment: .top) {
            switch page {
            case .list:
                listPage
                    .transition(Self.rootTransition)
            case .claude:
                ClaudeSettingsPage(themeStore: themeStore) {
                    navigate(to: .list)
                }
                .transition(Self.detailTransition)
            case .provider(let spec):
                ProviderSettingsPage(
                    spec: spec,
                    keyStore: keyStore,
                    onSave: { updated, keyReplaced in
                        if let i = specs.firstIndex(where: { $0.id == updated.id }) {
                            specs[i] = updated
                            keyReplaced ? persistInvalidating(updated.id) : persist()
                        }
                    },
                    onDelete: {
                        keyStore.deleteKey(for: spec.id)
                        specs.removeAll { $0.id == spec.id }
                        persist()
                    },
                    onClose: { navigate(to: .list) }
                )
                .transition(Self.detailTransition)
            case .addFlow:
                AddProviderFlow(
                    specStore: specStore,
                    keyStore: keyStore,
                    providersModel: providersModel,
                    onClose: { navigate(to: .list) }
                )
                .transition(Self.detailTransition)
            }
        }
        .frame(width: SettingsStyle.pageWidth)
        .fixedSize(horizontal: false, vertical: true)
        .clipped() // slide transitions must not draw outside the window
        .onAppear { onTitle(Self.title(for: page)) }
    }

    // MARK: navigation

    /// Root slides out/in on the leading edge, detail pages on the trailing
    /// edge — together they read as push (root exits left, detail enters from
    /// the right) and pop (the reverse).
    private static let rootTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .leading), removal: .move(edge: .leading)
    ).combined(with: .opacity)

    private static let detailTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing), removal: .move(edge: .trailing)
    ).combined(with: .opacity)

    private func navigate(to newPage: Page) {
        if newPage == .list {
            // Add flow persists its spec itself; edits go through onSave.
            // Re-sync the local copy either way — harmless when unchanged.
            specs = specStore.load()
        }
        withAnimation(.easeInOut(duration: 0.28)) { page = newPage }
        onTitle(Self.title(for: newPage))
    }

    static func title(for page: Page) -> String {
        switch page {
        case .list: return "Settings"
        case .claude: return "Claude plan"
        case .provider(let spec): return spec.displayName
        case .addFlow: return "Add Provider"
        }
    }

    // MARK: list page

    /// Path-A "removed" semantics: both Claude visibilities hidden ⇒ the row
    /// disappears from the list (and the catalog offers Claude again, Task 4).
    private var claudeRemoved: Bool {
        themeStore.sessionVisibility == .hidden && themeStore.weekVisibility == .hidden
    }

    private var listPage: some View {
        // +1 for the built-in Claude row (when present), +1 for addRow.
        let totalRows = specs.count + (claudeRemoved ? 1 : 2)
        let scrolls = totalRows > 10
        return SettingsPage(scrolls: scrolls) {
            SettingsCard {
                if !claudeRemoved {
                    claudeRow
                    CardDivider()
                }
                ForEach(specs) { spec in
                    providerRow(spec)
                    CardDivider()
                }
                addRow
            }
            CardFooter(text: "Rows appear in the pill in this order. Use a row's arrows to rearrange.")
        } buttons: {
            EmptyView() // root page: the window's close button is the exit
        }
    }

    // MARK: rows

    private var claudeRow: some View {
        Button {
            navigate(to: .claude)
        } label: {
            HStack(spacing: 8) {
                rowText(title: "Claude plan", subtitle: "via Claude Code")
                Spacer(minLength: 12)
                Text(claudeSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                chevron
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func providerRow(_ spec: ProviderSpec) -> some View {
        HStack(spacing: 8) {
            Button {
                navigate(to: .provider(spec))
            } label: {
                HStack(spacing: 8) {
                    rowText(title: spec.displayName, subtitle: subtitle(for: spec))
                    Spacer(minLength: 12)
                    Text(visibilityRowLabel(spec.visibility))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    chevron
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            moveMenu(for: spec)
        }
        .padding(.vertical, 9)
    }

    private var addRow: some View {
        Button {
            navigate(to: .addFlow)
        } label: {
            Label("Add Provider…", systemImage: "plus")
                .padding(.vertical, 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private func rowText(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
    }

    private func moveMenu(for spec: ProviderSpec) -> some View {
        let index = specs.firstIndex { $0.id == spec.id } ?? 0
        return Menu {
            Button("Move Up") {
                specs.swapAt(index, index - 1)
                persist()
            }
            .disabled(index == 0)
            Button("Move Down") {
                specs.swapAt(index, index + 1)
                persist()
            }
            .disabled(index == specs.count - 1)
        } label: {
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .fixedSize()
        .accessibilityLabel("Reorder \(spec.displayName)")
    }

    // MARK: row text helpers

    private var claudeSummary: String {
        let s = themeStore.sessionVisibility
        let w = themeStore.weekVisibility
        if s == w {
            switch s {
            case .pinned: return "Session & Week pinned"
            case .expandedOnly: return "Session & Week on hover"
            case .hidden: return "Hidden"
            }
        }
        return "Session \(shortLabel(s)) · Week \(shortLabel(w))"
    }

    private func shortLabel(_ v: ProviderSpec.Visibility) -> String {
        switch v {
        case .pinned: return "pinned"
        case .expandedOnly: return "on hover"
        case .hidden: return "hidden"
        }
    }

    private func visibilityRowLabel(_ v: ProviderSpec.Visibility) -> String {
        switch v {
        case .pinned: return "Pinned"
        case .expandedOnly: return "On hover"
        case .hidden: return "Hidden"
        }
    }

    /// e.g. "balance · warn under $5 · key ••••a4e6". Only the keychain's
    /// MASKED form ever reaches the UI.
    private func subtitle(for spec: ProviderSpec) -> String {
        var parts = [spec.valueKind == .currency ? "balance" : "number"]
        if let warn = spec.warnBelow {
            parts.append("warn under \(currencySymbol(spec.currencyCode))\(trimmedNumber(warn))")
        }
        if let key = keyStore.loadKey(for: spec.id) {
            parts.append("key \(ProviderKeyStore.masked(key))")
        } else {
            parts.append("no key")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: persistence

    private func persist() {
        specStore.save(specs)
        providersModel.reload()
        // Changed specs got fresh row models showing "—"; fetch them now
        // rather than waiting for the 5-minute tick. Unchanged rows keep
        // their backoff state, so rows in backoff stay throttled; healthy rows refetch once per user action.
        Task { await providersModel.refreshAll() }
    }

    /// Force-rebuild the row for `id` even though its spec is unchanged: the
    /// user replaced only the API key, but reload() preserves rows whose spec
    /// compares equal — keeping a fetcher that captured the OLD key. Saving
    /// once without the spec drops the row, then the normal persist() path
    /// rebuilds it through a fresh keyLookup. App-side workaround; UsageCore
    /// stays untouched per plan.
    private func persistInvalidating(_ id: UUID) {
        specStore.save(specs.filter { $0.id != id })
        providersModel.reload()
        persist()
    }
}

// MARK: - Claude settings page

/// Appearance + visibility for the two built-in Claude rows: palette
/// swatches, custom color wells, the red-alert and identity toggles, then
/// the visibility pop-ups. Bindings write straight to ThemeStore (live; the
/// pill IS the preview) — so the page snapshots the store on entry and Back
/// restores it wholesale, while Done simply returns.
struct ClaudeSettingsPage: View {
    @ObservedObject var themeStore: ThemeStore
    let onClose: () -> Void

    /// Captured ONCE on page entry (@State keeps the first value across
    /// parent re-renders, which re-init this struct mid-edit).
    @State private var entrySnapshot: ThemeStore.Snapshot
    @State private var confirmRemove = false

    init(themeStore: ThemeStore, onClose: @escaping () -> Void) {
        self.themeStore = themeStore
        self.onClose = onClose
        _entrySnapshot = State(initialValue: themeStore.snapshot())
    }

    var body: some View {
        SettingsPage {
            CardHeader("Palette")
            SettingsCard {
                swatchRow
                    .padding(.vertical, 10)
                CardDivider()
                labeledRow("Session bar") {
                    ColorPicker("", selection: binding(\.sessionHex, set: themeStore.setSessionHex))
                        .labelsHidden()
                }
                CardDivider()
                labeledRow("Week bar") {
                    ColorPicker("", selection: binding(\.weekHex, set: themeStore.setWeekHex))
                        .labelsHidden()
                }
            }
            SettingsCard {
                Toggle("Red Alert at 90% Weekly", isOn: $themeStore.redAlert90)
                    .toggleStyle(.switch)
                    .padding(.vertical, 7)
            }
            CardFooter(text: "both bars turn dusk red when the week crosses 90%")
            SettingsCard {
                Toggle("Show account & plan", isOn: $themeStore.showIdentity)
                    .toggleStyle(.switch)
                    .padding(.vertical, 7)
            }
            CardFooter(text: "Appears only in the hover-expanded card.")
            CardHeader("Claude plan")
            SettingsCard {
                labeledRow("Session") {
                    CapsulePicker(options: visibilityOptions, selection: Binding(
                        get: { themeStore.sessionVisibility },
                        set: { themeStore.setSessionVisibility($0) }
                    ))
                }
                CardDivider()
                labeledRow("Week") {
                    CapsulePicker(options: visibilityOptions, selection: Binding(
                        get: { themeStore.weekVisibility },
                        set: { themeStore.setWeekVisibility($0) }
                    ))
                }
            }
            CardFooter(text: "\u{201C}On Hover\u{201D} rows appear only in the hover-expanded card.")
            SettingsCard {
                Button {
                    confirmRemove = true
                } label: {
                    Text("Remove Provider…")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } buttons: {
            Button("Back") {
                themeStore.restore(entrySnapshot) // undo everything since entry
                onClose()
            }
            .buttonStyle(CapsuleButtonStyle())
            Button("Done") { onClose() }
                .buttonStyle(AccentCapsuleButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .confirmationDialog(
            "Hide Claude from the pill?",
            isPresented: $confirmRemove
        ) {
            // Path-A facade: "remove" just hides both built-in rows — nothing
            // is deleted, no keychain item is touched, and re-adding from the
            // catalog flips them back.
            Button("Remove Provider", role: .destructive) {
                themeStore.setSessionVisibility(.hidden)
                themeStore.setWeekVisibility(.hidden)
                onClose() // straight back to the list; no snapshot restore
            }
        } message: {
            Text("Your Claude Code sign-in is untouched.")
        }
    }

    private func binding(
        _ keyPath: KeyPath<Theme, String>,
        set: @escaping (String) -> Void
    ) -> Binding<Color> {
        Binding(
            get: { Color(themeHex: themeStore.theme[keyPath: keyPath]) },
            set: { if let hex = $0.themeHex { set(hex) } }
        )
    }

    private var swatchRow: some View {
        // First swatch flush left, Custom flush right, the rest distributed
        // evenly between.
        HStack(spacing: 0) {
            swatch(for: .dusk)
            Spacer()
            swatch(for: .mist)
            Spacer()
            swatch(for: .sage)
            Spacer()
            customSwatch
        }
    }

    private func swatch(for p: Palette) -> some View {
        // Callers pass only preset palettes; fall back to Dusk rather than
        // trapping if a preset-less case ever arrives.
        let t = p.preset ?? Palette.dusk.preset!
        return VStack(spacing: 3) {
            ZStack {
                swatchBackdrop // so Mist's translucency reads
                VStack(spacing: 5) {
                    Capsule().fill(Color(themeHex: t.sessionHex)).frame(width: 38, height: 5)
                    Capsule().fill(Color(themeHex: t.weekHex)).frame(width: 38, height: 5)
                }
            }
            .frame(width: 60, height: 28)
            .clipShape(Capsule())
            .overlay(swatchRing(selected: themeStore.palette == p))
            Text(p.rawValue.capitalized).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .onTapGesture { themeStore.select(p) }
    }

    private var customSwatch: some View {
        VStack(spacing: 3) {
            ZStack {
                swatchBackdrop
                Image(systemName: "paintbrush")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(width: 60, height: 28)
            .clipShape(Capsule())
            .overlay(swatchRing(selected: themeStore.palette == .custom))
            Text("Custom").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

/// Capsule swatch selection ring (Direction-2: tiles are capsules, like the
/// pill itself).
func swatchRing(selected: Bool) -> some View {
    Capsule()
        .stroke(selected ? Color.accentColor : Color.primary.opacity(0.1),
                lineWidth: selected ? 2 : 1)
}

/// Label-left / control-right card row (Form-row replacement).
func labeledRow<Control: View>(
    _ label: String, @ViewBuilder control: () -> Control
) -> some View {
    HStack {
        Text(label)
        Spacer(minLength: 12)
        control()
    }
    .padding(.vertical, 7)
}

/// Pill-dark tile background shared by every swatch, so translucent colors
/// (Mist) read the way they do in the pill.
var swatchBackdrop: Color {
    Color(red: 28 / 255, green: 30 / 255, blue: 38 / 255)
}

let visibilityOptions: [(label: String, value: ProviderSpec.Visibility)] = [
    ("Pinned", .pinned),
    ("On Hover", .expandedOnly),
    ("Hidden", .hidden),
]

// MARK: - Provider accent palette

/// Single-accent propositions for provider rows — one per theme family,
/// each using its family's SESSION color (exact Palette.preset hexes from
/// Theme.swift). Sage's session color IS the default sage, so Sage doubles
/// as the default proposition and writes accentHex nil; Custom is the free
/// ColorPicker.
enum ProviderAccent: Equatable {
    case sage   // default — accentHex nil (#9DB39A rendered)
    case clay   // Dusk family session color #C9A283FF
    case mist   // Mist family session color #FFFFFFBF
    case custom // free pick via the ColorPicker

    /// What Done/Add writes to accentHex. nil for sage (the default) and for
    /// custom (the sheet writes the picker's hex instead).
    var accentHex: String? {
        switch self {
        case .sage, .custom: return nil
        case .clay: return Palette.dusk.preset!.sessionHex
        case .mist: return Palette.mist.preset!.sessionHex
        }
    }

    /// Tile color; nil for custom (it shows the paintbrush glyph).
    var swatchHex: String? {
        switch self {
        case .sage: return Palette.sage.preset!.sessionHex
        case .clay, .mist: return accentHex
        case .custom: return nil
        }
    }

    var label: String {
        switch self {
        case .sage: return "Sage"
        case .clay: return "Clay"
        case .mist: return "Mist"
        case .custom: return "Custom"
        }
    }

    /// Which proposition a stored accentHex represents. Compares parsed
    /// components, not strings, so 6- and 8-digit spellings of the same
    /// color match. A hex equal to the default sage maps to .sage — it
    /// renders identically.
    static func from(accentHex: String?) -> ProviderAccent {
        guard let hex = accentHex, let rgba = ThemeColor.parse(hex) else { return .sage }
        for accent: ProviderAccent in [.sage, .clay, .mist]
        where ThemeColor.parse(accent.swatchHex!) == rgba {
            return accent
        }
        return .custom
    }
}

/// The "Palette" card row shared by ProviderSettingsPage and the add flow's
/// finish step: one single-bar capsule tile per proposition + a Custom tile,
/// with the same selection-ring styling as the Claude swatches. Tapping a
/// proposition selects it (and parks the custom well on its color); Custom
/// is selected by touching the ColorPicker below, exactly like the Claude
/// page's semantics.
struct ProviderAccentSwatchRow: View {
    @Binding var accent: ProviderAccent
    @Binding var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Palette")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 0) {
                swatch(for: .sage)
                Spacer()
                swatch(for: .clay)
                Spacer()
                swatch(for: .mist)
                Spacer()
                customSwatch
            }
        }
        .padding(.vertical, 9)
    }

    private func swatch(for p: ProviderAccent) -> some View {
        VStack(spacing: 3) {
            ZStack {
                swatchBackdrop // so Mist's translucency reads
                Capsule()
                    .fill(Color(themeHex: p.swatchHex ?? "#FFFFFFFF"))
                    .frame(width: 38, height: 5)
            }
            .frame(width: 60, height: 28)
            .clipShape(Capsule())
            .overlay(swatchRing(selected: accent == p))
            Text(p.label).font(.system(size: 9)).foregroundStyle(.secondary)
            if p == .sage {
                Text("default").font(.system(size: 8)).foregroundStyle(.tertiary)
            }
        }
        .onTapGesture {
            accent = p
            if let hex = p.swatchHex { color = Color(themeHex: hex) }
        }
    }

    private var customSwatch: some View {
        VStack(spacing: 3) {
            ZStack {
                swatchBackdrop
                Image(systemName: "paintbrush")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(width: 60, height: 28)
            .clipShape(Capsule())
            .overlay(swatchRing(selected: accent == .custom))
            Text("Custom").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Provider settings page

/// Edits one ProviderSpec. All fields are local state until Done; Back
/// discards. The SecureField's content flows ONLY to keyStore.save (never
/// logged, never echoed back — the placeholder shows the masked stored key).
struct ProviderSettingsPage: View {
    let spec: ProviderSpec
    let keyStore: ProviderKeyStore
    /// (updated spec, keyReplaced) — keyReplaced is a Bool, never the key.
    let onSave: (ProviderSpec, Bool) -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var name: String
    @State private var keyField = ""
    @State private var warnText: String
    @State private var accent: ProviderAccent
    @State private var color: Color
    @State private var visibility: ProviderSpec.Visibility
    @State private var confirmRemove = false
    @State private var keySaveError: String?
    private let maskedKey: String?
    /// Round-tripped initial color; if Done lands on .custom with this same
    /// hex the user never actually moved the picker, so accentHex is kept
    /// as-is (nil stays nil → the row keeps following the default sage).
    private let initialHex: String?

    /// nil accentHex renders as the default sage (#9DB39A) in the pill.
    private static let defaultAccent = "#9DB39A"

    init(spec: ProviderSpec,
         keyStore: ProviderKeyStore,
         onSave: @escaping (ProviderSpec, Bool) -> Void,
         onDelete: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        self.spec = spec
        self.keyStore = keyStore
        self.onSave = onSave
        self.onDelete = onDelete
        self.onClose = onClose
        _name = State(initialValue: spec.displayName)
        _warnText = State(initialValue: spec.warnBelow.map { trimmedNumber($0) } ?? "")
        _accent = State(initialValue: ProviderAccent.from(accentHex: spec.accentHex))
        let c = Color(themeHex: spec.accentHex ?? Self.defaultAccent)
        _color = State(initialValue: c)
        _visibility = State(initialValue: spec.visibility)
        maskedKey = keyStore.loadKey(for: spec.id).map(ProviderKeyStore.masked)
        initialHex = c.themeHex
    }

    var body: some View {
        SettingsPage {
            SettingsCard {
                labeledRow("Name") {
                    TextField("Name", text: $name)
                        .capsuleField()
                        .frame(maxWidth: 200)
                }
                CardDivider()
                labeledRow("API Key") {
                    SecureField(
                        "API Key", text: $keyField,
                        prompt: Text(maskedKey.map { "\($0) — paste to replace" } ?? "paste key")
                    )
                    .capsuleField()
                    .frame(maxWidth: 200)
                }
            }
            if let keySaveError {
                CardFooter(text: keySaveError, color: .red)
            }
            SettingsCard {
                labeledRow("Warn Below") {
                    HStack(spacing: 4) {
                        Text(currencySymbol(spec.currencyCode))
                            .foregroundStyle(.secondary)
                        TextField("none", text: $warnText)
                            .multilineTextAlignment(.trailing)
                            .capsuleField()
                            .frame(width: 80)
                    }
                }
                CardDivider()
                ProviderAccentSwatchRow(accent: $accent, color: $color)
                CardDivider()
                labeledRow("Custom") {
                    // alpha: Mist (#FFFFFFBF) must stay editable
                    ColorPicker("", selection: customColorBinding, supportsOpacity: true)
                        .labelsHidden()
                }
                CardDivider()
                labeledRow("Show in Pill") {
                    CapsulePicker(options: visibilityOptions, selection: $visibility)
                }
            }
            CardFooter(text: "Below the warning amount, this row turns amber regardless of its color.")
            SettingsCard {
                Button {
                    confirmRemove = true
                } label: {
                    Text("Remove Provider…")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } buttons: {
            Button("Back") { onClose() } // discard pending edits
                .buttonStyle(CapsuleButtonStyle())
            Button("Done") { save() }
                .buttonStyle(AccentCapsuleButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .confirmationDialog(
            "Remove \u{201C}\(spec.displayName)\u{201D}?",
            isPresented: $confirmRemove
        ) {
            Button("Remove Provider", role: .destructive) {
                onDelete()
                onClose()
            }
        } message: {
            Text("This also deletes its API key from your keychain.")
        }
    }

    /// Touching the custom well IS choosing Custom (mirrors the Claude
    /// page, where moving a color well switches the palette to .custom).
    private var customColorBinding: Binding<Color> {
        Binding(
            get: { color },
            set: { color = $0; accent = .custom }
        )
    }

    private func save() {
        var updated = spec
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty { updated.displayName = trimmedName }
        // Empty or unparseable → nil (warning off). Accept a comma decimal.
        // Negative thresholds can never fire — treat them as off too.
        updated.warnBelow = Double(
            warnText.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: ".")
        ).flatMap { $0 > 0 ? $0 : nil }
        updated.visibility = visibility
        switch accent {
        case .sage:
            updated.accentHex = nil // default — row follows the default sage
        case .clay, .mist:
            updated.accentHex = accent.accentHex
        case .custom:
            // initialHex guard: a .custom landed on without ever moving the
            // picker (or moved back to the start) keeps accentHex as-is.
            if let hex = color.themeHex, hex != initialHex {
                updated.accentHex = hex
            }
        }
        var keyReplaced = false
        if !keyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                try keyStore.save(key: keyField, for: spec.id)
                keyReplaced = true
                keyField = ""
                keySaveError = nil
            } catch {
                // Update-first ensures the old key is still in the keychain.
                keySaveError = "Could not store the key in your keychain — the old key is unchanged."
                return
            }
        }
        onSave(updated, keyReplaced)
        onClose()
    }
}

// MARK: - shared helpers

/// Mirrors the pill's value formatting (PillView.valueText) for known codes.
func currencySymbol(_ code: String?) -> String {
    switch code?.uppercased() {
    case "USD": return "$"
    case "EUR": return "€"
    case "GBP": return "£"
    case "JPY", "CNY": return "¥"
    case let other?: return other + " "
    default: return ""
    }
}

/// 5.0 → "5", 4.25 → "4.25" — for subtitles and the warn field.
func trimmedNumber(_ value: Double) -> String {
    String(format: "%g", value)
}
