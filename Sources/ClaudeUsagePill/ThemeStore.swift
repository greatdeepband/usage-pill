import AppKit
import SwiftUI
import UsageCore

@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var theme: Theme
    @Published private(set) var palette: Palette
    @Published var showIdentity: Bool { didSet { persist() } }
    @Published var redAlert90: Bool { didSet { persist() } }
    @Published private(set) var sessionVisibility: ProviderSpec.Visibility
    @Published private(set) var weekVisibility: ProviderSpec.Visibility

    private let settings: ThemeSettings

    init(settings: ThemeSettings = ThemeSettings()) {
        self.settings = settings
        let loaded = settings.load()
        theme = loaded.theme
        palette = loaded.palette
        sessionVisibility = loaded.sessionVisibility
        weekVisibility = loaded.weekVisibility
        // didSet does not fire during init — no spurious persist()
        showIdentity = loaded.showIdentity
        redAlert90 = loaded.redAlert90
    }

    // MARK: snapshot / restore (Claude settings page Back semantics)

    /// Everything the Claude page can touch, captured on page entry so Back
    /// can undo live-previewed edits in one shot.
    struct Snapshot {
        let theme: Theme
        let palette: Palette
        let showIdentity: Bool
        let sessionVisibility: ProviderSpec.Visibility
        let weekVisibility: ProviderSpec.Visibility
        let redAlert90: Bool
    }

    func snapshot() -> Snapshot {
        Snapshot(theme: theme, palette: palette, showIdentity: showIdentity,
                 sessionVisibility: sessionVisibility, weekVisibility: weekVisibility,
                 redAlert90: redAlert90)
    }

    func restore(_ s: Snapshot) {
        theme = s.theme
        palette = s.palette
        sessionVisibility = s.sessionVisibility
        weekVisibility = s.weekVisibility
        // These two persist via didSet; set them last so the persisted state
        // already contains the restored theme/palette/visibilities.
        showIdentity = s.showIdentity
        redAlert90 = s.redAlert90
        persist() // belt-and-braces if neither didSet fired a change
    }

    func setSessionVisibility(_ v: ProviderSpec.Visibility) {
        sessionVisibility = v
        persist()
    }

    func setWeekVisibility(_ v: ProviderSpec.Visibility) {
        weekVisibility = v
        persist()
    }

    func select(_ p: Palette) {
        guard let preset = p.preset else { return } // .custom is not directly selectable
        theme = preset
        palette = p
        persist()
    }

    func setSessionHex(_ hex: String) {
        guard ThemeColor.parse(hex) != nil else { return }
        theme.sessionHex = hex
        palette = .custom
        persist()
    }

    func setWeekHex(_ hex: String) {
        guard ThemeColor.parse(hex) != nil else { return }
        theme.weekHex = hex
        palette = .custom
        persist()
    }

    private func persist() {
        settings.save(theme: theme, palette: palette, showIdentity: showIdentity,
                      sessionVisibility: sessionVisibility, weekVisibility: weekVisibility,
                      redAlert90: redAlert90)
    }
}

extension Color {
    init(rgba: RGBA) {
        self.init(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }

    init(themeHex: String) {
        self.init(rgba: ThemeColor.parse(themeHex) ?? RGBA(r: 1, g: 1, b: 1, a: 1))
    }

    /// Hex via NSColor sRGB conversion (for ColorPicker → store).
    var themeHex: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return ThemeColor.format(RGBA(
            r: Double(c.redComponent), g: Double(c.greenComponent),
            b: Double(c.blueComponent), a: Double(c.alphaComponent)
        ))
    }
}
