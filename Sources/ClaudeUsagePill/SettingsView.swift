import SwiftUI
import UsageCore

struct SettingsView: View {
    @ObservedObject var store: ThemeStore
    @ObservedObject var previewModel: UsageModel
    @ObservedObject var identity: IdentityModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            preview
            Text("Palette").font(.caption).foregroundStyle(.secondary)
            swatchRow
            colorWells
            Divider()
            Toggle("Show account & plan when expanded", isOn: $store.showIdentity)
                .toggleStyle(.switch)
        }
        .padding(16)
        .frame(width: 320)
    }

    private var preview: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.23, green: 0.25, blue: 0.35),
                         Color(red: 0.53, green: 0.58, blue: 0.72)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            PillView(model: previewModel, theme: store, identity: identity) { _ in }
                .frame(width: 250, height: 50)
                .allowsHitTesting(false)
        }
        .frame(height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var swatchRow: some View {
        HStack(spacing: 10) {
            ForEach(Palette.allCases.filter { $0 != .custom }, id: \.self) { p in
                swatch(for: p)
            }
            customSwatch
        }
    }

    private func swatch(for p: Palette) -> some View {
        // The ForEach filters out .custom, so preset is always present; fall
        // back to Dusk rather than trapping if a preset-less case ever joins.
        let t = p.preset ?? Palette.dusk.preset!
        return VStack(spacing: 3) {
            HStack(spacing: 0) {
                Color(themeHex: t.sessionHex)
                Color(themeHex: t.weekHex)
            }
            .frame(width: 48, height: 26)
            .background(Color.black.opacity(0.5)) // so Mist's translucency reads
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(store.palette == p ? Color.accentColor : .clear, lineWidth: 2)
            )
            Text(p.rawValue.capitalized).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .onTapGesture { store.select(p) }
    }

    private var customSwatch: some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.25))
                .frame(width: 48, height: 26)
                .overlay(Image(systemName: "paintbrush").font(.system(size: 11)).foregroundStyle(.secondary))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(store.palette == .custom ? Color.accentColor : .clear, lineWidth: 2)
                )
            Text("Custom").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    private var colorWells: some View {
        VStack(spacing: 8) {
            ColorPicker("Session bar", selection: Binding(
                get: { Color(themeHex: store.theme.sessionHex) },
                set: { if let hex = $0.themeHex { store.setSessionHex(hex) } }
            ))
            ColorPicker("Week bar", selection: Binding(
                get: { Color(themeHex: store.theme.weekHex) },
                set: { if let hex = $0.themeHex { store.setWeekHex(hex) } }
            ))
        }
    }
}
