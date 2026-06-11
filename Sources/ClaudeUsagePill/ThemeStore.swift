import AppKit
import SwiftUI
import UsageCore

@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var theme: Theme
    @Published private(set) var palette: Palette
    @Published var showIdentity: Bool { didSet { persist() } }

    private let settings: ThemeSettings

    init(settings: ThemeSettings = ThemeSettings()) {
        self.settings = settings
        let loaded = settings.load()
        theme = loaded.theme
        palette = loaded.palette
        showIdentity = loaded.showIdentity // didSet does not fire during init — no spurious persist()
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
        settings.save(theme: theme, palette: palette, showIdentity: showIdentity)
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
