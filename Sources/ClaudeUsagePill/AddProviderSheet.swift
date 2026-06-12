import AppKit
import SwiftUI
import UsageCore

/// Add-provider flow (plan Task 16, now a PUSHED page per Task 18c): grouped
/// template catalog + dead-simple custom discovery. One enum-driven state
/// machine; ALL field state lives on the flow itself so its internal Back
/// always preserves entries. Nothing persists until the final "Add to Pill" —
/// Cancel anywhere returns to the list (no keychain writes, no spec writes).
/// Exception by design: the Claude walkthrough writes nothing either — its
/// "add" is just the two visibility setters (path-A facade).
///
/// PRIVACY: the pasted key lives only in @State and flows only to
/// ProviderProbe.discover / OpenAISpendAdapter.fetchValue (verification) and
/// ProviderKeyStore.save. Never logged, never in error text, never in the
/// spec.
struct AddProviderFlow: View {
    let specStore: ProviderSpecStore
    let keyStore: ProviderKeyStore
    @ObservedObject var providersModel: ProvidersModel
    /// Live "both Claude rows hidden" from ProvidersTabView — the catalog
    /// offers the Claude entry only while it is removed.
    let claudeRemoved: () -> Bool
    /// Read-only Claude Code credential presence check, injected from the
    /// AppDelegate wiring (the SAME loader the smart first-launch default
    /// uses — this view builds no keychain machinery of its own).
    let claudeCheck: () -> Bool
    /// Path-A "add": flips both Claude visibilities back to .pinned.
    let onClaudeConnected: () -> Void
    /// Navigates back to the settings list (replaces the sheet's dismiss).
    let onClose: () -> Void

    /// ④ pickSource → ④b presetForm | ⑤ customForm → ⑤b probing →
    /// ⑥ pickField → ⑦ finish. Side paths off ④: claudeWalkthrough
    /// (path-A facade) and spendForm (OpenAI native adapter).
    private enum Step {
        case pickSource
        case presetForm(ProviderTemplate)
        case customForm
        case probing
        case pickField([DiscoveredField])
        case finish(DiscoveredField)
        case claudeWalkthrough
        case spendForm(ProviderTemplate)
    }

    @State private var step: Step = .pickSource

    // ④b preset path. pickedPresetName lets a re-pick of the SAME preset
    // keep the user's entries while a different preset starts fresh.
    @State private var pickedPresetName: String?
    @State private var presetName = ""
    @State private var presetKey = ""

    // ⑤ custom path — kept here (not per-screen) so Back preserves entries.
    // pickedGuidedName mirrors pickedPresetName: re-picking the same guided
    // template keeps the user's entries; a different one re-applies its
    // prefill, and "Custom…" after a guided pick starts blank.
    @State private var urlText = ""
    @State private var keyText = ""
    @State private var headerName = "Authorization"
    @State private var headerTemplate = "Bearer {key}"
    @State private var probeError: String?
    @State private var probeTask: Task<Void, Never>?
    @State private var pickedGuidedName: String?
    @State private var guidedCurrencyCode: String?

    // OpenAI spend path (④ → spendForm). The admin key flows ONLY to the
    // verification fetch and keyStore.save.
    @State private var spendName = "OpenAI"
    @State private var spendKey = ""
    @State private var spendWarnText = ""
    @State private var spendVerifying = false
    @State private var spendError: String?
    @State private var spendTask: Task<Void, Never>?

    // ⑥ + ⑦
    @State private var discovered: [DiscoveredField] = []
    @State private var selected: DiscoveredField?
    @State private var customName = ""
    @State private var showAs: ProviderSpec.ValueKind = .currency
    @State private var warnText = ""
    @State private var saveErrorText: String?
    @State private var advancedExpanded = false
    @State private var accent: ProviderAccent = .sage // default proposition
    @State private var color: Color
    /// Round-tripped initial color; if Add lands on .custom with this same
    /// hex the user never actually moved the picker and accentHex stays nil
    /// (row follows the default sage) — same pattern as ProviderSettingsPage.
    private let initialHex: String?

    /// nil accentHex renders as the default sage (#9DB39A) in the pill.
    private static let defaultAccent = "#9DB39A"

    init(specStore: ProviderSpecStore,
         keyStore: ProviderKeyStore,
         providersModel: ProvidersModel,
         claudeRemoved: @escaping () -> Bool,
         claudeCheck: @escaping () -> Bool,
         onClaudeConnected: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        self.specStore = specStore
        self.keyStore = keyStore
        self.providersModel = providersModel
        self.claudeRemoved = claudeRemoved
        self.claudeCheck = claudeCheck
        self.onClaudeConnected = onClaudeConnected
        self.onClose = onClose
        let c = Color(themeHex: Self.defaultAccent)
        _color = State(initialValue: c)
        initialHex = c.themeHex
    }

    var body: some View {
        Group {
            switch step {
            case .pickSource:
                SettingsPage { sourcePicker } buttons: { buttons }
            case .presetForm(let preset):
                SettingsPage { presetForm(preset) } buttons: { buttons }
            case .customForm:
                SettingsPage { customForm } buttons: { buttons }
            case .probing:
                SettingsPage { probingView } buttons: { buttons }
            case .pickField(let fields):
                SettingsPage(scrolls: fields.count > 8, scrollHeight: 380) {
                    fieldPicker(fields)
                } buttons: { buttons }
            case .finish:
                SettingsPage { finishForm } buttons: { buttons }
            case .claudeWalkthrough:
                SettingsPage {
                    ClaudeWalkthroughPage(
                        claudeCheck: claudeCheck,
                        onConnected: onClaudeConnected,
                        onClose: onClose
                    )
                } buttons: { buttons }
            case .spendForm(let template):
                SettingsPage { spendForm(template) } buttons: { buttons }
            }
        }
        .onDisappear {
            probeTask?.cancel()
            spendTask?.cancel()
        }
    }

    // MARK: buttons (trailing capsules; primary = default action)

    @ViewBuilder
    private var buttons: some View {
        switch step {
        case .pickSource:
            Button("Cancel") { onClose() }
                .buttonStyle(CapsuleButtonStyle())
        case .presetForm(let preset):
            Button("Back") { step = .pickSource }
                .buttonStyle(CapsuleButtonStyle())
            Button("Add to Pill") { addPreset(preset) }
                .buttonStyle(AccentCapsuleButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed(presetKey).isEmpty)
        case .customForm:
            Button("Cancel") { onClose() }
                .buttonStyle(CapsuleButtonStyle())
            Button("Continue") { startProbe() }
                .buttonStyle(AccentCapsuleButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed(urlText).isEmpty || trimmed(keyText).isEmpty)
        case .probing:
            Button("Cancel") {
                probeTask?.cancel()
                onClose()
            }
            .buttonStyle(CapsuleButtonStyle())
        case .pickField:
            Button("Back") { step = .customForm }
                .buttonStyle(CapsuleButtonStyle())
            Button("Continue") {
                guard let selected else { return }
                if trimmed(customName).isEmpty {
                    customName = Self.defaultName(from: urlText)
                }
                step = .finish(selected)
            }
            .buttonStyle(AccentCapsuleButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(selected == nil)
        case .finish(let field):
            Button("Back") { step = .pickField(discovered) }
                .buttonStyle(CapsuleButtonStyle())
            Button("Add to Pill") { addCustom(field) }
                .buttonStyle(AccentCapsuleButtonStyle())
                .keyboardShortcut(.defaultAction)
        case .claudeWalkthrough:
            Button("Back") { step = .pickSource }
                .buttonStyle(CapsuleButtonStyle())
        case .spendForm(let template):
            Button("Back") {
                spendTask?.cancel()
                spendVerifying = false
                step = .pickSource
            }
            .buttonStyle(CapsuleButtonStyle())
            Button("Add to Pill") { addSpend(template) }
                .buttonStyle(AccentCapsuleButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed(spendKey).isEmpty || spendVerifying)
        }
    }

    // MARK: ④ source picker (grouped catalog)

    /// Plans group, minus the Claude entry while Claude is already present
    /// (path-A: the catalog offers Claude only after Remove).
    private var planTemplates: [ProviderTemplate] {
        TemplateCatalog.all.filter { template in
            guard template.group == .plans else { return false }
            if case .claudePlan = template.kind { return claudeRemoved() }
            return true
        }
    }

    private var balanceTemplates: [ProviderTemplate] {
        TemplateCatalog.all.filter { $0.group == .balances }
    }

    @ViewBuilder
    private var sourcePicker: some View {
        CardHeader("PLANS")
        SettingsCard { catalogRows(planTemplates) }
        CardHeader("API BALANCES & SPEND")
        SettingsCard { catalogRows(balanceTemplates) }
        SettingsCard {
            sourceRow(
                title: "Custom…",
                subtitle: "any provider with a JSON endpoint"
            ) {
                pickCustom()
            }
        }
    }

    @ViewBuilder
    private func catalogRows(_ templates: [ProviderTemplate]) -> some View {
        ForEach(Array(templates.enumerated()), id: \.element.name) { i, template in
            catalogRow(template)
            if i < templates.count - 1 {
                CardDivider()
            }
        }
    }

    /// Catalog row: the navigation tap covers name/subtitle/chevron only —
    /// the key-link icon is its own tap target (NOT nested in the row button).
    private func catalogRow(_ template: ProviderTemplate) -> some View {
        HStack(spacing: 8) {
            sourceRow(title: template.name, subtitle: template.subtitle) {
                pick(template)
            }
            if let url = template.keyURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Get your key")
                .accessibilityLabel("Get your key for \(template.name)")
            }
        }
    }

    private func pick(_ template: ProviderTemplate) {
        switch template.kind {
        case .full(let make):
            if pickedPresetName != template.name {
                // Fresh template: prefill display name from spec.
                pickedPresetName = template.name
                presetName = make().displayName
                presetKey = ""
                saveErrorText = nil
            }
            step = .presetForm(template)
        case .guided(let prefill):
            if pickedGuidedName != template.name {
                pickedGuidedName = template.name
                applyGuidedPrefill(prefill)
            }
            step = .customForm
        case .claudePlan:
            step = .claudeWalkthrough
        case .openAISpend:
            saveErrorText = nil
            spendError = nil
            step = .spendForm(template)
        }
    }

    /// Guided templates ride the EXISTING custom flow (probe → pick-a-number
    /// → finish) with the fields pre-filled but fully editable.
    private func applyGuidedPrefill(_ p: ProviderTemplate.GuidedPrefill) {
        urlText = p.url
        headerName = p.headerName
        headerTemplate = p.headerTemplate
        customName = p.suggestedName
        showAs = p.valueKind
        guidedCurrencyCode = p.currencyCode
        keyText = ""
        warnText = ""
        probeError = nil
        saveErrorText = nil
        discovered = []
        selected = nil
        // Non-default auth is the template's whole trick (z.ai raw token) —
        // open Advanced so the user sees what will be sent.
        advancedExpanded = p.headerName != "Authorization"
            || p.headerTemplate != "Bearer {key}"
    }

    /// "Custom…" after a guided pick starts blank; re-entering plain custom
    /// keeps the user's entries (existing Back-preserves semantics).
    private func pickCustom() {
        if pickedGuidedName != nil {
            pickedGuidedName = nil
            urlText = ""
            keyText = ""
            headerName = "Authorization"
            headerTemplate = "Bearer {key}"
            customName = ""
            showAs = .currency
            guidedCurrencyCode = nil
            warnText = ""
            probeError = nil
            saveErrorText = nil
            discovered = []
            selected = nil
            advancedExpanded = false
        }
        step = .customForm
    }

    private func sourceRow(title: String, subtitle: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "Get your key →" link shown above preset/spend forms.
    private func keyLink(_ url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label("Get your key", systemImage: "arrow.up.right.square")
                .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .padding(.leading, 14)
    }

    // MARK: ④b preset form

    @ViewBuilder
    private func presetForm(_ preset: ProviderTemplate) -> some View {
        CardHeader(preset.name)
        if let url = preset.keyURL {
            keyLink(url)
        }
        SettingsCard {
            labeledRow("Name") {
                TextField("Name", text: $presetName)
                    .capsuleField()
                    .frame(maxWidth: 200)
            }
            CardDivider()
            labeledRow("API Key") {
                SecureField("API Key", text: $presetKey, prompt: Text("paste key"))
                    .capsuleField()
                    .frame(maxWidth: 200)
            }
        }
        // Keychain write failures must be visible here too, not only in
        // the custom flow (1.0 final review, finding 1).
        if let saveErrorText {
            CardFooter(text: saveErrorText, color: .red)
        }
    }

    private func addPreset(_ preset: ProviderTemplate) {
        guard case .full(let make) = preset.kind else { return }
        var spec = make()
        let name = trimmed(presetName)
        if !name.isEmpty { spec.displayName = name }
        finishAdd(spec: spec, key: presetKey)
    }

    // MARK: ⑤ custom form

    @ViewBuilder
    private var customForm: some View {
        SettingsCard {
            labeledRow("Endpoint URL") {
                TextField("Endpoint URL", text: $urlText, prompt: Text("https://…"))
                    .autocorrectionDisabled()
                    .capsuleField()
                    .frame(maxWidth: 220)
            }
            CardDivider()
            labeledRow("API Key") {
                SecureField("API Key", text: $keyText, prompt: Text("paste key"))
                    .capsuleField()
                    .frame(maxWidth: 220)
            }
            CardDivider()
            // Not DisclosureGroup: on macOS only its tiny triangle is
            // clickable, which reads as a dead control. Whole row toggles.
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { advancedExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(advancedExpanded ? 90 : 0))
                    Text("Advanced (auth header)")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 7)
            if advancedExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    labeledRow("Header Name") {
                        TextField("Header Name", text: $headerName)
                            .capsuleField()
                            .frame(maxWidth: 180)
                    }
                    labeledRow("Header Template") {
                        TextField("Header Template", text: $headerTemplate)
                            .capsuleField()
                            .frame(maxWidth: 180)
                    }
                    Text("{key} is replaced with your key")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 7)
            }
        }
        if let probeError {
            CardFooter(text: probeError, color: .red)
        }
    }

    // MARK: ⑤b probing

    private var probingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Checking that endpoint…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func startProbe() {
        // Re-entry guard: a fast double-Continue must not spawn two probes.
        // Guard first so a second tap while already probing is a true no-op;
        // only then cancel any lingering task (e.g. a Back→re-Continue path).
        guard case .customForm = step else { return }
        probeTask?.cancel()
        probeError = nil
        step = .probing
        // Snapshot effective values; blank advanced fields fall back to the
        // defaults so the saved spec always matches what the probe used.
        let url = trimmed(urlText)
        let key = trimmed(keyText)
        let hName = effectiveHeaderName
        let hTemplate = effectiveHeaderTemplate
        probeTask = Task {
            do {
                let fields = try await ProviderProbe().discover(
                    url: url, key: key, headerName: hName, headerTemplate: hTemplate
                )
                guard !Task.isCancelled else { return }
                if fields.isEmpty {
                    probeError = "No numbers were found at that endpoint."
                    step = .customForm
                } else {
                    discovered = fields
                    // A re-probe may return a different shape; drop a stale pick.
                    if let s = selected, !fields.contains(s) { selected = nil }
                    step = .pickField(fields)
                }
            } catch is CancellationError {
                // User cancelled; the page is already gone.
            } catch let error as FetchError {
                guard !Task.isCancelled else { return }
                probeError = Self.message(for: error)
                step = .customForm
            } catch {
                guard !Task.isCancelled else { return }
                probeError = "Could not reach that URL."
                step = .customForm
            }
        }
    }

    /// Plain-language probe errors. NEVER includes the key or the response.
    private static func message(for error: FetchError) -> String {
        switch error {
        case .unauthorized, .badResponse(403):
            return "The key was rejected."
        case .network:
            return "Could not reach that URL."
        case .rateLimited:
            return "That endpoint is rate-limiting — try again in a minute."
        case .undecodable:
            return "That endpoint didn't return JSON."
        case .badResponse(let code):
            return "That endpoint returned an error (HTTP \(code))."
        }
    }

    // MARK: ⑥ field picker

    @ViewBuilder
    private func fieldPicker(_ fields: [DiscoveredField]) -> some View {
        // Content-hugging up to 8 rows; beyond that the page would outgrow
        // the screen (probe cap is 50 fields), so the list scrolls instead.
        CardHeader("Numbers found at that endpoint")
        SettingsCard {
            ForEach(Array(fields.enumerated()), id: \.element.path) { i, field in
                fieldRow(field)
                if i < fields.count - 1 {
                    CardDivider()
                }
            }
        }
        CardFooter(text: "These are live values from that endpoint — pick the one that's your balance.")
    }

    private func fieldRow(_ field: DiscoveredField) -> some View {
        Button {
            selected = field
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.2f", field.value))
                        .font(.system(size: 15, weight: .semibold))
                    Text(field.path)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if selected == field {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selected == field ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }

    // MARK: ⑦ finish

    @ViewBuilder
    private var finishForm: some View {
        SettingsCard {
            labeledRow("Name") {
                TextField("Name", text: $customName)
                    .capsuleField()
                    .frame(maxWidth: 200)
            }
            CardDivider()
            labeledRow("Show As") {
                CapsulePicker(options: [
                    ("Currency ($)", ProviderSpec.ValueKind.currency),
                    ("Number", ProviderSpec.ValueKind.number),
                ], selection: $showAs)
            }
            CardDivider()
            labeledRow("Warn Below") {
                HStack(spacing: 4) {
                    if showAs == .currency {
                        Text("$").foregroundStyle(.secondary)
                    }
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
        }
        if let saveErrorText {
            CardFooter(text: saveErrorText, color: .red)
        } else {
            CardFooter(text: "Below the warning amount, this row turns amber regardless of its color.")
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

    private func addCustom(_ field: DiscoveredField) {
        let name = trimmed(customName)
        var accentHex: String?
        switch accent {
        case .sage:
            accentHex = nil // default — row follows the default sage
        case .clay, .mist:
            accentHex = accent.accentHex
        case .custom:
            // initialHex guard: a .custom landed on without ever moving the
            // picker stays nil (follows the default sage).
            if let hex = color.themeHex, hex != initialHex { accentHex = hex }
        }
        let spec = ProviderSpec(
            id: UUID(),
            displayName: name.isEmpty
                ? fallbackName(Self.defaultName(from: urlText))
                : name,
            adapter: .generic,
            url: trimmed(urlText),
            headerName: effectiveHeaderName,
            headerTemplate: effectiveHeaderTemplate,
            valuePath: field.path,
            subtractPath: nil,
            scale: 1,
            valueKind: showAs,
            // Guided templates may carry their own currency; plain custom
            // keeps the 1.0 USD default.
            currencyCode: showAs == .currency ? (guidedCurrencyCode ?? "USD") : nil,
            // Empty or unparseable → nil (warning off). Accept a comma decimal.
            warnBelow: Double(
                trimmed(warnText).replacingOccurrences(of: ",", with: ".")
            ).flatMap { $0 > 0 ? $0 : nil },
            visibility: .pinned,
            accentHex: accentHex
        )
        finishAdd(spec: spec, key: keyText)
    }

    // MARK: spend form (OpenAI month-to-date, native adapter)

    @ViewBuilder
    private func spendForm(_ template: ProviderTemplate) -> some View {
        CardHeader(template.name)
        if let url = template.keyURL {
            keyLink(url)
        }
        SettingsCard {
            labeledRow("Name") {
                TextField("Name", text: $spendName)
                    .capsuleField()
                    .frame(maxWidth: 200)
            }
            CardDivider()
            labeledRow("Admin Key") {
                SecureField("Admin Key", text: $spendKey, prompt: Text("paste key"))
                    .capsuleField()
                    .frame(maxWidth: 200)
            }
            CardDivider()
            labeledRow("Warn Above") {
                HStack(spacing: 4) {
                    Text("$").foregroundStyle(.secondary)
                    TextField("none", text: $spendWarnText)
                        .multilineTextAlignment(.trailing)
                        .capsuleField()
                        .frame(width: 80)
                }
            }
        }
        if spendVerifying {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking that key with OpenAI…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 14)
        } else if let errorText = saveErrorText ?? spendError {
            CardFooter(text: errorText, color: .red)
        } else {
            CardFooter(text: "At or above the warning amount, this row turns amber.")
        }
    }

    /// Live verification = one adapter fetch with the final spec; nothing
    /// persists unless it succeeds. PRIVACY: the admin key flows ONLY to
    /// OpenAISpendAdapter.fetchValue and (on success) keyStore.save.
    private func addSpend(_ template: ProviderTemplate) {
        guard !spendVerifying else { return }
        spendError = nil
        saveErrorText = nil
        let key = trimmed(spendKey)
        let name = trimmed(spendName)
        let spec = ProviderSpec(
            id: UUID(),
            displayName: name.isEmpty ? "OpenAI" : name,
            adapter: .openAISpend,
            // The adapter builds its own request; url/header/valuePath are
            // carried for bookkeeping only.
            url: "https://api.openai.com/v1/organization/costs",
            headerName: "Authorization",
            headerTemplate: "Bearer {key}",
            valuePath: "",
            subtractPath: nil,
            scale: 1,
            valueKind: .currency,
            currencyCode: "USD",
            // Warn-ABOVE for this adapter (the pill flips the comparison);
            // empty/unparseable/non-positive → off, same clamp as elsewhere.
            warnBelow: Double(
                trimmed(spendWarnText).replacingOccurrences(of: ",", with: ".")
            ).flatMap { $0 > 0 ? $0 : nil },
            visibility: .pinned
        )
        spendVerifying = true
        spendTask = Task {
            defer { spendVerifying = false }
            do {
                _ = try await OpenAISpendAdapter().fetchValue(spec: spec, key: key)
                guard !Task.isCancelled else { return }
                finishAdd(spec: spec, key: key)
            } catch is CancellationError {
                // User backed out mid-verify; nothing persisted.
            } catch let error as FetchError {
                guard !Task.isCancelled else { return }
                spendError = Self.spendMessage(for: error)
            } catch {
                guard !Task.isCancelled else { return }
                spendError = "Could not reach that URL."
            }
        }
    }

    /// Spend-path errors: the Costs API needs an ORGANIZATION ADMIN key, and
    /// a regular project key fails with 401 — say so. Everything else reuses
    /// the shared message table. Never includes the key or the response.
    private static func spendMessage(for error: FetchError) -> String {
        switch error {
        case .unauthorized, .badResponse(403):
            return "The key was rejected — note this needs an ORGANIZATION ADMIN key."
        default:
            return message(for: error)
        }
    }

    // MARK: shared add path

    /// The ONLY place anything persists. Key first (so reload's keyLookup
    /// finds it and builds a real fetcher), then the spec, then the standard
    /// persist→reload + refreshAll path from ProvidersTabView.
    private func finishAdd(spec: ProviderSpec, key: String) {
        do {
            try keyStore.save(key: key, for: spec.id)
        } catch {
            saveErrorText = "Could not store the key in your keychain — the provider was not added."
            return
        }
        var specs = specStore.load()
        specs.append(spec)
        specStore.save(specs)
        providersModel.reload()
        // Fetch the new row now rather than waiting for the 5-minute tick;
        // unchanged rows keep their backoff state.
        Task { await providersModel.refreshAll() }
        onClose()
    }

    // MARK: helpers

    private var effectiveHeaderName: String {
        let t = trimmed(headerName)
        return t.isEmpty ? "Authorization" : t
    }

    private var effectiveHeaderTemplate: String {
        let t = trimmed(headerTemplate)
        return t.isEmpty ? "Bearer {key}" : t
    }

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fallbackName(_ name: String) -> String {
        name.isEmpty ? "Provider" : name
    }

    /// Host of the URL minus www/api prefixes, first label capitalized:
    /// "https://api.acme.ai/balance" → "Acme". Internal for tests.
    static func defaultName(from urlString: String) -> String {
        guard var host = URL(string: urlString)?.host?.lowercased() else {
            return ""
        }
        var stripped = true
        while stripped {
            stripped = false
            for prefix in ["www.", "api."] where host.hasPrefix(prefix) {
                host.removeFirst(prefix.count)
                stripped = true
            }
        }
        let base = host.split(separator: ".").first.map(String.init) ?? host
        return base.capitalized
    }
}

// MARK: - Claude walkthrough (path-A facade)

/// The Claude catalog entry's "add" page. No keychain machinery here: the
/// injected `claudeCheck` is the same read-only credential-presence loader
/// the smart first-launch default uses. Found (now or on a later check) →
/// `onConnected` pins both Claude rows, a brief confirmation shows, and the
/// flow closes. While visible the page re-checks every 5 s; the `.task`
/// loop is cancelled by SwiftUI the moment the page leaves the hierarchy.
private struct ClaudeWalkthroughPage: View {
    let claudeCheck: () -> Bool
    let onConnected: () -> Void
    let onClose: () -> Void

    @State private var connected = false
    @State private var manualCheckFailed = false
    @State private var dismissTask: Task<Void, Never>?

    /// Verified 2026-06-13: responds 200 (redirects to
    /// claude.com/product/claude-code), so no docs fallback needed.
    private static let claudeCodeURL = URL(string: "https://claude.com/claude-code")!

    var body: some View {
        Group {
            if connected {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Color.accentColor)
                    Text("Connected — Claude is in your pill.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                CardHeader("Claude plan")
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Usage Pill reads the sign-in that Claude Code already has — it never sees your password and never writes anything.")
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button("Get Claude Code") {
                                NSWorkspace.shared.open(Self.claudeCodeURL)
                            }
                            .buttonStyle(CapsuleButtonStyle())
                            Button("Check again") { check(manual: true) }
                                .buttonStyle(AccentCapsuleButtonStyle())
                        }
                    }
                    .padding(.vertical, 9)
                }
                if manualCheckFailed {
                    CardFooter(text: "No Claude Code sign-in found yet.")
                }
            }
        }
        .onAppear { check(manual: false) } // already signed in → instant add
        // NO polling loop here: a denied keychain ACL re-prompts on every
        // SecItemCopyMatching call against another app's item, so automatic
        // rechecks are a prompt-storm vector (the v1.0 failure class).
        // The "Check again" button above gives the user explicit one-shot
        // control; the 1 s success-dismiss task below is the only timer.
        .onDisappear { dismissTask?.cancel() }
    }

    /// Auto checks are silent on failure; only an explicit "Check again"
    /// earns the inline "not found yet" note.
    private func check(manual: Bool) {
        guard !connected else { return }
        if claudeCheck() {
            connected = true
            onConnected() // both Claude rows → .pinned (instant data)
            dismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                onClose()
            }
        } else if manual {
            manualCheckFailed = true
        }
    }
}
