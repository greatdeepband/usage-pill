import SwiftUI
import UsageCore

enum Dusk {
    static let clay = Color(red: 0xC9 / 255, green: 0xA2 / 255, blue: 0x83 / 255)
    static let dustyBlue = Color(red: 0x8F / 255, green: 0xA3 / 255, blue: 0xC2 / 255)
    static let amber = Color(red: 0xD9 / 255, green: 0xB2 / 255, blue: 0x6B / 255)
    static let softRed = Color(red: 0xC9 / 255, green: 0x83 / 255, blue: 0x83 / 255)
    static let sage = Color(red: 0x9D / 255, green: 0xB3 / 255, blue: 0x9A / 255)

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
    @ObservedObject var theme: ThemeStore
    @ObservedObject var identity: IdentityModel
    @ObservedObject var providers: ProvidersModel
    var onExpandChange: (Bool) -> Void

    @State private var expanded = false
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, tolerance: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.18)) { expanded = hovering }
                onExpandChange(hovering)
                if hovering && theme.showIdentity { identity.loadIfNeeded() }
            }
            .onReceive(tick) { now = $0 }
    }

    /// Visible in the current mode: compact shows pinned only; expanded shows
    /// pinned + expandedOnly (hidden rows are absent everywhere).
    private func isVisible(_ visibility: ProviderSpec.Visibility) -> Bool {
        expanded ? visibility != .hidden : visibility == .pinned
    }

    /// ProvidersModel already drops hidden specs; compact additionally
    /// restricts to pinned. Spec order is preserved.
    private var visibleProviderRows: [ProvidersModel.Row] {
        providers.rows.filter { isVisible($0.spec.visibility) }
    }

    @ViewBuilder private var content: some View {
        let shape: AnyShape = expanded ? AnyShape(RoundedRectangle(cornerRadius: 18)) : AnyShape(Capsule())
        let showSession = isVisible(theme.sessionVisibility)
        let showWeek = isVisible(theme.weekVisibility)
        let providerRows = visibleProviderRows
        VStack(alignment: .leading, spacing: expanded ? 10 : 6) {
            if expanded && theme.showIdentity && (identity.email != nil || identity.planBadge != nil) {
                identityStrip
            }
            // True empty: no rows at all in either mode → prompt user to open Settings.
            // Compact with no pinned rows but expanded has content → quiet ellipsis
            // (hovering reveals the rows); avoids a misleading prompt when the pill
            // is intentionally configured with expanded-only rows.
            // Expanded empty state is unchanged: "open Settings" still shown.
            let noClaudeEver = theme.sessionVisibility == .hidden && theme.weekVisibility == .hidden
            let allRowsEmpty = providers.rows.isEmpty && noClaudeEver
            let compactNothingPinned = !expanded && !showSession && !showWeek && providerRows.isEmpty
            if allRowsEmpty {
                Text("open Settings")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if compactNothingPinned {
                // Content exists but is only visible when expanded — quiet hint.
                Text("…")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                if showSession {
                    barRow(
                        window: model.snapshot?.session, base: Color(themeHex: theme.theme.sessionHex), symbol: "clock",
                        label: "Session",
                        resetText: CountdownFormatter.remaining(until: model.snapshot?.session?.resetsAt, now: now)
                    )
                }
                if showWeek {
                    barRow(
                        window: model.snapshot?.week, base: Color(themeHex: theme.theme.weekHex), symbol: "calendar",
                        label: "Week",
                        resetText: CountdownFormatter.weekReset(model.snapshot?.week?.resetsAt, now: now)
                    )
                }
                ForEach(providerRows) { row in
                    ProviderRow(spec: row.spec, rowModel: row.model, expanded: expanded)
                }
                if expanded { footer }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, expanded ? 13 : 8)
        .background {
            ZStack {
                VisualEffectBlur() // glass: blurs what's behind the window
                Color(red: 28 / 255, green: 30 / 255, blue: 38 / 255)
                    .opacity(0.55) // dark tint over the glass, under the content
            }
        }
        .clipShape(shape)
        .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 1))
        .opacity(model.status == .stale(reason: .unauthorized) ? 0.75 : 1)
    }

    private var identityStrip: some View {
        VStack(spacing: 7) {
            HStack {
                Text(identity.email ?? "")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                if let badge = identity.planBadge {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color(themeHex: theme.theme.sessionHex))
                }
            }
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
        }
    }

    @ViewBuilder
    private func barRow(window: UsageWindow?, base: Color, symbol: String, label: String, resetText: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(base.opacity(0.7))
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
                    Text(window.map { "\(Int($0.utilization.rounded()))%" } ?? "—")
                        .font(.system(size: 10.5, weight: .regular).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 30, alignment: .trailing)
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
        // Claude-specific hints make no sense when both Claude rows are hidden.
        let claudeVisible = isVisible(theme.sessionVisibility) || isVisible(theme.weekVisibility)
        return HStack {
            if claudeVisible, case .stale(let reason) = model.status {
                if reason == .noCredentials {
                    Text("open Claude Code to sign in")
                        .font(.system(size: 9.5)).foregroundStyle(Dusk.amber.opacity(0.9))
                } else if reason == .rateLimited {
                    Text("rate limited — retrying later")
                        .font(.system(size: 9.5)).foregroundStyle(Dusk.amber.opacity(0.9))
                }
            }
            Spacer()
            Text(oldestSuccessSeconds.map(CountdownFormatter.updatedAgo) ?? "no data yet")
                .font(.system(size: 9.5))
                .foregroundStyle(model.isDataOld ? Dusk.amber.opacity(0.9) : .white.opacity(0.4))
        }
    }

    /// Seconds since the OLDEST success across the Claude model (when any
    /// Claude row is visible) and all visible provider rows. nil if NO
    /// considered row has ever succeeded — keeps the "no data yet" semantics.
    ///
    /// Keyless rows (.stale(.auth) with no lastSuccess) are excluded from
    /// consideration: before Milestone C they have no key and will never
    /// succeed, so including them would pin "no data yet" in the footer
    /// forever even when Claude data is fresh.
    private var oldestSuccessSeconds: TimeInterval? {
        var dates: [Date] = []
        if isVisible(theme.sessionVisibility) || isVisible(theme.weekVisibility) {
            guard let d = model.lastSuccess else { return nil }
            dates.append(d)
        }
        for row in visibleProviderRows {
            if let d = row.model.lastSuccess {
                dates.append(d)
            } else if case .stale(let f) = row.model.status, f == .auth {
                // Keyless row: never succeeded and has no key — skip it so it
                // doesn't permanently suppress "updated X ago" for other rows.
                continue
            } else {
                // A row with a key that hasn't returned yet: treat as no data.
                return nil
            }
        }
        guard let oldest = dates.min() else { return nil }
        return now.timeIntervalSince(oldest)
    }
}

/// One provider line. Separate view so each row observes its OWN
/// ProviderRowModel — a slow provider invalidates only its row.
private struct ProviderRow: View {
    let spec: ProviderSpec
    @ObservedObject var rowModel: ProviderRowModel
    let expanded: Bool

    var body: some View {
        HStack(spacing: 9) {
            Text(String(spec.displayName.prefix(1)))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(rowTint)
                .frame(width: 12)
            Text(spec.displayName)
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            Spacer(minLength: 4)
            if expanded, let (caption, color) = staleCaption {
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(color)
            }
            Text(valueText)
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(rowTint.opacity(expanded && isStale ? 0.6 : 1))
        }
    }

    private var isStale: Bool {
        if case .stale = rowModel.status { return true }
        return false
    }

    private var staleCaption: (String, Color)? {
        guard case .stale(let failure) = rowModel.status else { return nil }
        switch failure {
        case .auth: return ("check key", Dusk.amber)
        case .rateLimited: return ("rate limited", Dusk.amber)
        case .network: return ("offline", Color.white.opacity(0.4))
        }
    }

    /// Below the warn threshold → amber; otherwise sage green.
    private var rowTint: Color {
        if let value = rowModel.value, let warn = spec.warnBelow, value <= warn {
            return Dusk.amber
        }
        return Dusk.sage
    }

    private var valueText: String {
        guard let value = rowModel.value else { return "—" }
        let number = String(format: "%.2f", value)
        guard spec.valueKind == .currency, let code = spec.currencyCode?.uppercased() else {
            return number
        }
        switch code {
        case "USD": return "$" + number
        case "EUR": return "€" + number
        case "GBP": return "£" + number
        case "JPY", "CNY": return "¥" + number
        default: return code + " " + number
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
