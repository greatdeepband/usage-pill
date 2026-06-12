import SwiftUI
import UsageCore

/// Add-provider flow (plan Task 16, now a PUSHED page per Task 18c): preset
/// picker + dead-simple custom discovery. One enum-driven state machine; ALL
/// field state lives on the flow itself so its internal Back always preserves
/// entries. Nothing persists until the final "Add to Pill" — Cancel anywhere
/// returns to the list (no keychain writes, no spec writes).
///
/// PRIVACY: the pasted key lives only in @State and flows only to
/// ProviderProbe.discover and ProviderKeyStore.save. Never logged, never in
/// error text, never in the spec.
struct AddProviderFlow: View {
    let specStore: ProviderSpecStore
    let keyStore: ProviderKeyStore
    @ObservedObject var providersModel: ProvidersModel
    /// Navigates back to the settings list (replaces the sheet's dismiss).
    let onClose: () -> Void

    /// ④ pickSource → ④b presetForm | ⑤ customForm → ⑤b probing →
    /// ⑥ pickField → ⑦ finish.
    private enum Step {
        case pickSource
        case presetForm(ProviderPresets.Preset)
        case customForm
        case probing
        case pickField([DiscoveredField])
        case finish(DiscoveredField)
    }

    @State private var step: Step = .pickSource

    // ④b preset path. pickedPresetName lets a re-pick of the SAME preset
    // keep the user's entries while a different preset starts fresh.
    @State private var pickedPresetName: String?
    @State private var presetName = ""
    @State private var presetKey = ""

    // ⑤ custom path — kept here (not per-screen) so Back preserves entries.
    @State private var urlText = ""
    @State private var keyText = ""
    @State private var headerName = "Authorization"
    @State private var headerTemplate = "Bearer {key}"
    @State private var probeError: String?
    @State private var probeTask: Task<Void, Never>?

    // ⑥ + ⑦
    @State private var discovered: [DiscoveredField] = []
    @State private var selected: DiscoveredField?
    @State private var customName = ""
    @State private var showAs: ProviderSpec.ValueKind = .currency
    @State private var warnText = ""
    @State private var saveErrorText: String?
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
         onClose: @escaping () -> Void) {
        self.specStore = specStore
        self.keyStore = keyStore
        self.providersModel = providersModel
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
            }
        }
        .onDisappear { probeTask?.cancel() }
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
        }
    }

    // MARK: ④ source picker

    @ViewBuilder
    private var sourcePicker: some View {
        SettingsCard {
            ForEach(ProviderPresets.all, id: \.name) { preset in
                sourceRow(
                    title: preset.name,
                    subtitle: "verified preset — just needs your key"
                ) {
                    if pickedPresetName != preset.name {
                        // Fresh preset: prefill from the template.
                        pickedPresetName = preset.name
                        presetName = preset.make().displayName
                        presetKey = ""
                    }
                    step = .presetForm(preset)
                }
                CardDivider()
            }
            sourceRow(
                title: "Custom…",
                subtitle: "any provider with a JSON endpoint"
            ) {
                step = .customForm
            }
        }
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

    // MARK: ④b preset form

    @ViewBuilder
    private func presetForm(_ preset: ProviderPresets.Preset) -> some View {
        CardHeader(preset.name)
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

    private func addPreset(_ preset: ProviderPresets.Preset) {
        var spec = preset.make()
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
            DisclosureGroup("Advanced (auth header)") {
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
                .padding(.top, 2)
            }
            .padding(.vertical, 7)
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
            currencyCode: showAs == .currency ? "USD" : nil,
            // Empty or unparseable → nil (warning off). Accept a comma decimal.
            warnBelow: Double(
                trimmed(warnText).replacingOccurrences(of: ",", with: ".")
            ).flatMap { $0 > 0 ? $0 : nil },
            visibility: .pinned,
            accentHex: accentHex
        )
        finishAdd(spec: spec, key: keyText)
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
