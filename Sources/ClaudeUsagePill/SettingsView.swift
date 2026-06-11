import SwiftUI
import UsageCore

struct SettingsView: View {
    @ObservedObject var store: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            preview

            VStack(alignment: .leading, spacing: 8) {
                Text("Palette")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                swatchRow
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Custom colors")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                // Full-width rows: label leading, control flush right —
                // aligned with the preview's right edge.
                VStack(spacing: 8) {
                    HStack {
                        Text("Session bar")
                        Spacer()
                        ColorPicker("", selection: binding(\.sessionHex, set: store.setSessionHex))
                            .labelsHidden()
                    }
                    HStack {
                        Text("Week bar")
                        Spacer()
                        ColorPicker("", selection: binding(\.weekHex, set: store.setWeekHex))
                            .labelsHidden()
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Show account & plan")
                    Spacer()
                    Toggle("", isOn: $store.showIdentity)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Text("Appears only in the hover-expanded card.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func binding(
        _ keyPath: KeyPath<Theme, String>,
        set: @escaping (String) -> Void
    ) -> Binding<Color> {
        Binding(
            get: { Color(themeHex: store.theme[keyPath: keyPath]) },
            set: { if let hex = $0.themeHex { set(hex) } }
        )
    }

    private var preview: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.23, green: 0.25, blue: 0.35),
                         Color(red: 0.53, green: 0.58, blue: 0.72)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            PreviewPill(theme: store.theme)
        }
        .frame(height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var swatchRow: some View {
        // First swatch flush left, Custom flush right (matching the preview's
        // borders), the rest distributed evenly between.
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
        // The ForEach filters out .custom, so preset is always present; fall
        // back to Dusk rather than trapping if a preset-less case ever joins.
        let t = p.preset ?? Palette.dusk.preset!
        return VStack(spacing: 3) {
            ZStack {
                Color(red: 28 / 255, green: 30 / 255, blue: 38 / 255) // so Mist's translucency reads
                VStack(spacing: 5) {
                    Capsule().fill(Color(themeHex: t.sessionHex)).frame(width: 38, height: 5)
                    Capsule().fill(Color(themeHex: t.weekHex)).frame(width: 38, height: 5)
                }
            }
            .frame(width: 60, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(store.palette == p ? Color.accentColor : Color.primary.opacity(0.1),
                            lineWidth: store.palette == p ? 2 : 1)
            )
            Text(p.rawValue.capitalized).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .onTapGesture { store.select(p) }
    }

    private var customSwatch: some View {
        VStack(spacing: 3) {
            ZStack {
                Color(red: 28 / 255, green: 30 / 255, blue: 38 / 255)
                Image(systemName: "paintbrush")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(width: 60, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(store.palette == .custom ? Color.accentColor : Color.primary.opacity(0.1),
                            lineWidth: store.palette == .custom ? 2 : 1)
            )
            Text("Custom").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

/// Static, timer-free rendering of the compact pill for the settings preview.
/// Mirrors PillView's compact metrics; fixed 62/38 sample data.
private struct PreviewPill: View {
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(symbol: "clock", hex: theme.sessionHex, fraction: 0.62, percent: "62%")
            row(symbol: "calendar", hex: theme.weekHex, fraction: 0.38, percent: "38%")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(width: 250)
        .background(Color(red: 28 / 255, green: 30 / 255, blue: 38 / 255).opacity(0.8))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
    }

    private func row(symbol: String, hex: String, fraction: Double, percent: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(Color(themeHex: hex).opacity(0.7))
                .frame(width: 12)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(Color(themeHex: hex))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 5)
            Text(percent)
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 30, alignment: .trailing)
        }
    }
}
