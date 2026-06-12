import SwiftUI
import UsageCore

/// The single settings pane: the Claude plan row plus one row per stored
/// ProviderSpec, each opening a detail sheet (appearance lives in the
/// sheets). Every mutation follows the same path: edit the local specs array
/// → specStore.save → providersModel.reload() — AppDelegate's $rows sink
/// then resizes the pill automatically.
///
/// Reordering: SwiftUI's .onMove has no effect inside a macOS Form (Form is
/// not List-backed on macOS, so ForEach gets no drag affordance). Fallback per
/// plan: a small up/down menu per provider row.
struct ProvidersTabView: View {
    @ObservedObject var themeStore: ThemeStore
    @ObservedObject var providersModel: ProvidersModel
    let specStore: ProviderSpecStore
    let keyStore: ProviderKeyStore

    @State private var specs: [ProviderSpec]
    @State private var showClaudeSheet = false
    @State private var showAddSheet = false
    @State private var editingSpec: ProviderSpec?

    init(themeStore: ThemeStore,
         providersModel: ProvidersModel,
         specStore: ProviderSpecStore,
         keyStore: ProviderKeyStore) {
        self.themeStore = themeStore
        self.providersModel = providersModel
        self.specStore = specStore
        self.keyStore = keyStore
        _specs = State(initialValue: specStore.load())
    }

    var body: some View {
        // +1 for the built-in Claude row, +1 for addRow.
        let totalRows = specs.count + 2
        let scrolls = totalRows > 10
        return Form {
            Section {
                claudeRow
                ForEach(specs) { spec in
                    providerRow(spec)
                }
                addRow
            } footer: {
                Text("Rows appear in the pill in this order. Use a row's arrows to rearrange.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(!scrolls)
        .frame(width: 380, height: scrolls ? 480 : nil)
        .fixedSize(horizontal: false, vertical: !scrolls)
        .sheet(isPresented: $showClaudeSheet) {
            ClaudeDetailSheet(themeStore: themeStore)
        }
        .sheet(isPresented: $showAddSheet, onDismiss: {
            // AddProviderSheet persists the new spec itself (key first, then
            // spec → reload + refreshAll); re-sync the local copy. Harmless
            // on cancel — the store is unchanged.
            specs = specStore.load()
        }) {
            AddProviderSheet(
                specStore: specStore,
                keyStore: keyStore,
                providersModel: providersModel
            )
        }
        .sheet(item: $editingSpec) { spec in
            ProviderDetailSheet(
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
                }
            )
        }
    }

    // MARK: rows

    private var claudeRow: some View {
        Button {
            showClaudeSheet = true
        } label: {
            HStack(spacing: 8) {
                rowText(title: "Claude plan", subtitle: "via Claude Code")
                Spacer(minLength: 12)
                Text(claudeSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                chevron
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func providerRow(_ spec: ProviderSpec) -> some View {
        HStack(spacing: 8) {
            Button {
                editingSpec = spec
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
    }

    private var addRow: some View {
        Button {
            showAddSheet = true
        } label: {
            Label("Add Provider…", systemImage: "plus")
        }
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

// MARK: - Claude detail sheet

/// Appearance + visibility for the two built-in Claude rows: palette
/// swatches, custom color wells and the identity toggle (relocated from the
/// removed Appearance tab — same rendering and semantics), then the
/// visibility pickers. Bindings write straight to ThemeStore (live;
/// AppDelegate's sinks restyle/resize the pill immediately), so the only
/// button is Done.
struct ClaudeDetailSheet: View {
    @ObservedObject var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    swatchRow
                } header: {
                    Text("Palette")
                }
                Section {
                    ColorPicker(
                        "Session bar",
                        selection: binding(\.sessionHex, set: themeStore.setSessionHex)
                    )
                    ColorPicker(
                        "Week bar",
                        selection: binding(\.weekHex, set: themeStore.setWeekHex)
                    )
                } header: {
                    Text("Custom colors")
                }
                Section {
                    Toggle("Show account & plan", isOn: $themeStore.showIdentity)
                        .toggleStyle(.switch)
                } footer: {
                    Text("Appears only in the hover-expanded card.")
                }
                Section {
                    Picker("Session", selection: Binding(
                        get: { themeStore.sessionVisibility },
                        set: { themeStore.setSessionVisibility($0) }
                    )) {
                        visibilityOptions
                    }
                    .pickerStyle(.menu)
                    Picker("Week", selection: Binding(
                        get: { themeStore.weekVisibility },
                        set: { themeStore.setWeekVisibility($0) }
                    )) {
                        visibilityOptions
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Claude plan")
                } footer: {
                    Text("\u{201C}On Hover\u{201D} rows appear only in the hover-expanded card.")
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
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
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(themeStore.palette == p ? Color.accentColor : Color.primary.opacity(0.1),
                            lineWidth: themeStore.palette == p ? 2 : 1)
            )
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
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(themeStore.palette == .custom ? Color.accentColor : Color.primary.opacity(0.1),
                            lineWidth: themeStore.palette == .custom ? 2 : 1)
            )
            Text("Custom").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

/// Pill-dark tile background shared by every swatch, so translucent colors
/// (Mist) read the way they do in the pill.
private var swatchBackdrop: Color {
    Color(red: 28 / 255, green: 30 / 255, blue: 38 / 255)
}

@ViewBuilder
private var visibilityOptions: some View {
    Text("Pinned").tag(ProviderSpec.Visibility.pinned)
    Text("On Hover").tag(ProviderSpec.Visibility.expandedOnly)
    Text("Hidden").tag(ProviderSpec.Visibility.hidden)
}

// MARK: - Provider accent palette

/// Single-accent propositions for provider rows — one per theme family,
/// each using its family's SESSION color (exact Palette.preset hexes from
/// Theme.swift). Sage's session color IS the default sage, so Sage doubles
/// as the default proposition and writes accentHex nil; Custom is the free
/// ColorPicker.
enum ProviderAccent: Equatable {
    case sage   // default — accentHex nil (#9DB39AFF rendered)
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

/// The "Palette" form row shared by ProviderDetailSheet and the add flow's
/// finish step: one single-bar capsule tile per proposition + a Custom tile,
/// with the same selection-ring styling as the Claude swatches. Tapping a
/// proposition selects it (and parks the custom well on its color); Custom
/// is selected by touching the ColorPicker below, exactly like the Claude
/// pane's semantics.
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
        .padding(.vertical, 2)
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
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(selectionRing(selected: accent == p))
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
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(selectionRing(selected: accent == .custom))
            Text("Custom").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    private func selectionRing(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(selected ? Color.accentColor : Color.primary.opacity(0.1),
                    lineWidth: selected ? 2 : 1)
    }
}

// MARK: - Provider detail sheet

/// Edits one ProviderSpec. All fields are local state until Done; Cancel
/// discards. The SecureField's content flows ONLY to keyStore.save (never
/// logged, never echoed back — the placeholder shows the masked stored key).
struct ProviderDetailSheet: View {
    let spec: ProviderSpec
    let keyStore: ProviderKeyStore
    /// (updated spec, keyReplaced) — keyReplaced is a Bool, never the key.
    let onSave: (ProviderSpec, Bool) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
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
         onDelete: @escaping () -> Void) {
        self.spec = spec
        self.keyStore = keyStore
        self.onSave = onSave
        self.onDelete = onDelete
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
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name)
                    SecureField(
                        "API Key", text: $keyField,
                        prompt: Text(maskedKey.map { "\($0) — paste to replace" } ?? "paste key")
                    )
                } footer: {
                    if let keySaveError {
                        Text(keySaveError)
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    LabeledContent("Warn Below") {
                        HStack(spacing: 2) {
                            Text(currencySymbol(spec.currencyCode))
                                .foregroundStyle(.secondary)
                            TextField("none", text: $warnText)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                        }
                    }
                    ProviderAccentSwatchRow(accent: $accent, color: $color)
                    ColorPicker("Custom", selection: customColorBinding, supportsOpacity: true) // alpha: Mist (#FFFFFFBF) must stay editable
                    Picker("Show in Pill", selection: $visibility) {
                        visibilityOptions
                    }
                    .pickerStyle(.menu)
                } footer: {
                    Text("Below the warning amount, this row turns amber regardless of its color.")
                }
                Section {
                    Button(role: .destructive) {
                        confirmRemove = true
                    } label: {
                        Text("Remove Provider…")
                            .frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Done") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog(
            "Remove \u{201C}\(spec.displayName)\u{201D}?",
            isPresented: $confirmRemove
        ) {
            Button("Remove Provider", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("This also deletes its API key from your keychain.")
        }
    }

    /// Touching the custom well IS choosing Custom (mirrors the Claude
    /// pane, where moving a color well switches the palette to .custom).
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
        dismiss()
    }
}

// MARK: - shared helpers

/// Mirrors the pill's value formatting (PillView.valueText) for known codes.
private func currencySymbol(_ code: String?) -> String {
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
private func trimmedNumber(_ value: Double) -> String {
    String(format: "%g", value)
}
