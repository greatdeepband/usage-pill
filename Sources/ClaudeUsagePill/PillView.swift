import SwiftUI
import UsageCore

enum Dusk {
    static let clay = Color(red: 0xC9 / 255, green: 0xA2 / 255, blue: 0x83 / 255)
    static let dustyBlue = Color(red: 0x8F / 255, green: 0xA3 / 255, blue: 0xC2 / 255)
    static let amber = Color(red: 0xD9 / 255, green: 0xB2 / 255, blue: 0x6B / 255)
    static let softRed = Color(red: 0xC9 / 255, green: 0x83 / 255, blue: 0x83 / 255)

    static func barColor(utilization: Double, base: Color) -> Color {
        switch BarTone.tone(forUtilization: utilization) {
        case .normal: return base
        case .warning: return amber
        case .critical: return softRed
        }
    }
}

struct PillView: View {
    @ObservedObject var model: UsageModel
    var onExpandChange: (Bool) -> Void

    @State private var expanded = false
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.18)) { expanded = hovering }
                onExpandChange(hovering)
            }
            .onReceive(tick) { now = $0 }
    }

    @ViewBuilder private var content: some View {
        let shape: AnyShape = expanded ? AnyShape(RoundedRectangle(cornerRadius: 18)) : AnyShape(Capsule())
        VStack(alignment: .leading, spacing: expanded ? 10 : 6) {
            barRow(
                window: model.snapshot?.session, base: Dusk.clay, symbol: "clock",
                label: "Session",
                resetText: CountdownFormatter.remaining(until: model.snapshot?.session?.resetsAt, now: now)
            )
            barRow(
                window: model.snapshot?.week, base: Dusk.dustyBlue, symbol: "calendar",
                label: "Week",
                resetText: CountdownFormatter.weekReset(model.snapshot?.week?.resetsAt, now: now)
            )
            if expanded { footer }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, expanded ? 13 : 9)
        .background(VisualEffectBlur())
        .background(Color(red: 28 / 255, green: 30 / 255, blue: 38 / 255).opacity(0.55))
        .clipShape(shape)
        .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 1))
        .opacity(model.status == .stale(reason: .unauthorized) ? 0.75 : 1)
    }

    @ViewBuilder
    private func barRow(window: UsageWindow?, base: Color, symbol: String, label: String, resetText: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(base.opacity(0.9))
                    .frame(width: 12)
                if expanded {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 4)
                    Text(window == nil ? "—" : resetText)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    bar(window: window, base: base)
                    Text(window.map { "\(Int($0.utilization.rounded()))" } ?? "—")
                        .font(.system(size: 10.5, weight: .regular).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 24, alignment: .trailing)
                }
            }
            if expanded { bar(window: window, base: base) }
        }
    }

    private func bar(window: UsageWindow?, base: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                if let window {
                    Capsule()
                        .fill(Dusk.barColor(utilization: window.utilization, base: base))
                        .frame(width: max(geo.size.width * window.utilization / 100, window.utilization > 0 ? 4 : 0))
                }
            }
        }
        .frame(height: 5)
    }

    private var footer: some View {
        HStack {
            if case .stale(let reason) = model.status, reason == .noCredentials {
                Text("open Claude Code to sign in")
                    .font(.system(size: 9.5)).foregroundStyle(Dusk.amber.opacity(0.9))
            }
            Spacer()
            Text(model.secondsSinceSuccess().map(CountdownFormatter.updatedAgo) ?? "no data yet")
                .font(.system(size: 9.5))
                .foregroundStyle(model.isDataOld ? Dusk.amber.opacity(0.9) : .white.opacity(0.4))
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
