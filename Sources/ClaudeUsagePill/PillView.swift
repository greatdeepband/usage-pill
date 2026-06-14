import SwiftUI
import UsageCore

enum Dusk {
    static let clay = Color(red: 0xC9 / 255, green: 0xA2 / 255, blue: 0x83 / 255)
    static let dustyBlue = Color(red: 0x8F / 255, green: 0xA3 / 255, blue: 0xC2 / 255)
    static let amber = Color(red: 0xD9 / 255, green: 0xB2 / 255, blue: 0x6B / 255)
    static let softRed = Color(red: 0xC9 / 255, green: 0x83 / 255, blue: 0x83 / 255)
    static let sage = Color(red: 0x9D / 255, green: 0xB3 / 255, blue: 0x9A / 255)

    static func color(for tone: BarTone, base: Color) -> Color {
        switch tone {
        case .normal: return base
        case .warning: return amber
        case .critical: return softRed
        }
    }

    static func barColor(utilization: Double, base: Color) -> Color {
        color(for: BarTone.tone(forUtilization: utilization), base: base)
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

    /// Compact paddings are height-aware (the capsule's side radius grows
    /// with the pill, so the content must move inward with it). Shared with
    /// PillPanel via CompactGeometry — counts here MUST mirror
    /// AppDelegate.syncPanelLayout's pinned-row/compact-section math.
    private var compactMetrics: CompactGeometry.Metrics {
        let claudeRows = [theme.sessionVisibility, theme.weekVisibility]
            .filter { $0 == .pinned }.count
        let providerRows = providers.rows.filter { $0.spec.visibility == .pinned }.count
        return CompactGeometry.metrics(
            rows: claudeRows + providerRows,
            sections: (claudeRows > 0 ? 1 : 0) + providerRows
        )
    }

    @ViewBuilder private var content: some View {
        let shape: AnyShape = expanded ? AnyShape(RoundedRectangle(cornerRadius: 18)) : AnyShape(Capsule())
        let showSession = isVisible(theme.sessionVisibility)
        let showWeek = isVisible(theme.weekVisibility)
        let providerRows = visibleProviderRows
        VStack(alignment: .leading, spacing: expanded ? 10 : 6) {
            // True empty: no rows at all in either mode → prompt user to open
            // Settings (one branch — it renders in compact AND expanded).
            // Compact with no pinned rows but expanded has content → quiet ellipsis
            // (hovering reveals the rows); avoids a misleading prompt when the pill
            // is intentionally configured with expanded-only rows.
            let noClaudeEver = theme.sessionVisibility == .hidden && theme.weekVisibility == .hidden
            let allRowsEmpty = providers.rows.isEmpty && noClaudeEver
            let compactNothingPinned = !expanded && !showSession && !showWeek && providerRows.isEmpty
            if allRowsEmpty {
                Text("open Settings to connect a provider")
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
                // Claude section: header + (identity strip) + visible Claude
                // rows. Header and identity render only when ≥1 Claude row is
                // visible in the current mode (hidden-Claude carve-out).
                if showSession || showWeek {
                    // Red alert at 90% weekly: tones for BOTH Claude bars come
                    // from one place, so the session bar flares with the week.
                    let tones = BarTone.claudeTones(
                        session: model.snapshot?.session?.utilization,
                        week: model.snapshot?.week?.utilization,
                        redAlert90: theme.redAlert90
                    )
                    sectionHeader("Claude")
                    if expanded && theme.showIdentity && (identity.email != nil || identity.planBadge != nil) {
                        identityStrip
                    }
                    if showSession {
                        barRow(
                            window: model.snapshot?.session, base: Color(themeHex: theme.theme.sessionHex),
                            tone: tones.session, symbol: "clock",
                            label: "Session",
                            resetText: CountdownFormatter.remaining(until: model.snapshot?.session?.resetsAt, now: now)
                        )
                    }
                    if showWeek {
                        barRow(
                            window: model.snapshot?.week, base: Color(themeHex: theme.theme.weekHex),
                            tone: tones.week, symbol: "calendar",
                            label: "Week",
                            resetText: CountdownFormatter.weekReset(model.snapshot?.week?.resetsAt, now: now)
                        )
                    }
                }
                // One section per provider: uppercased name header + its row.
                ForEach(providerRows) { row in
                    sectionHeader(row.spec.displayName)
                    ProviderRow(spec: row.spec, rowModel: row.model, expanded: expanded)
                }
                if expanded { footer }
            }
        }
        // Expanded paddings are fixed (declared perfect); compact paddings
        // scale with the pill's height so content clears the capsule corners.
        .padding(.horizontal, expanded ? 16 : compactMetrics.hPad)
        .padding(.vertical, expanded ? 13 : compactMetrics.vPad)
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

    /// Uppercased micro-caption above each section. Identity-strip caption
    /// styling (bold, wide tracking, dim white); 8.5pt expanded, 7.5pt compact.
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: expanded ? 8.5 : 7.5, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(.white.opacity(0.38))
            .lineLimit(1)
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
    private func barRow(window: UsageWindow?, base: Color, tone: BarTone, symbol: String, label: String, resetText: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 9) {
                // Icons are a compact-only device; expanded rows lead with
                // their text label under the section header (Task 18a).
                if expanded {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 4)
                    Text(window == nil ? "—" : resetText)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(base.opacity(0.7))
                        .frame(width: 12)
                    bar(window: window, base: base, tone: tone)
                    Text(window.map { "\(Int($0.utilization.rounded()))%" } ?? "—")
                        .font(.system(size: 10.5, weight: .regular).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 30, alignment: .trailing)
                }
            }
            if expanded { bar(window: window, base: base, tone: tone) }
        }
    }

    private func bar(window: UsageWindow?, base: Color, tone: BarTone) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                if let window {
                    Capsule()
                        .fill(Dusk.color(for: tone, base: base))
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
///
/// Renders under the provider's section header (drawn by PillView):
/// expanded = two-line "Credits" row with value-of-baseline + drain bar;
/// compact = chisel glyph + drain bar + value, column-aligned with the
/// Claude rows (icon 12pt slot, flexible bar, trailing value).
private struct ProviderRow: View {
    let spec: ProviderSpec
    @ObservedObject var rowModel: ProviderRowModel
    let expanded: Bool

    /// Spend rows (OpenAI month-to-date): the value GROWS, so there is no
    /// baseline, no drain bar and no "of" text — value only, with the warn
    /// comparison flipped (amber at/ABOVE the threshold).
    private var isSpend: Bool { spec.adapter == .openAISpend }

    var body: some View {
        if expanded {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 9) {
                    Text(isSpend ? "This Month" : "Credits")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 4)
                    if let (caption, color) = staleCaption {
                        Text(caption)
                            .font(.system(size: 9))
                            .foregroundStyle(color)
                    }
                    Text(expandedValueText)
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(rowTint.opacity(isStale ? 0.6 : 1))
                }
                if !isSpend { drainBar }
            }
        } else {
            HStack(spacing: 9) {
                ChiselIcon()
                    .fill(rowTint.opacity(0.7))
                    .frame(width: 10, height: 10)
                    .frame(width: 12)
                if isSpend {
                    // Name fills the bar's slot; the Spacer keeps the value
                    // trailing-aligned with the other compact rows.
                    Text(spec.displayName)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                } else {
                    drainBar
                }
                Text(valueText)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(rowTint)
                    .frame(minWidth: 30, alignment: .trailing)
            }
        }
    }

    /// Per-launch credit drain: full at baseline, empties as value falls.
    /// Empty track when no fraction yet (pre-first-success or zero baseline).
    private var drainBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                if let fraction = rowModel.fraction {
                    Capsule()
                        .fill(rowTint)
                        .frame(width: max(geo.size.width * fraction, fraction > 0 ? 4 : 0))
                }
            }
        }
        .frame(height: 5)
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

    /// Below the warn threshold → amber; otherwise sage green. Spend rows
    /// FLIP the comparison (warnBelow stores a warn-ABOVE amount): amber at
    /// or over the threshold. Only this adapter flips — generic rows keep
    /// the 1.0 semantics.
    private var rowTint: Color {
        if let value = rowModel.value, let warn = spec.warnBelow,
           isSpend ? value >= warn : value <= warn {
            return Dusk.amber // warn always overrides the accent
        }
        if let hex = spec.accentHex { return Color(themeHex: hex) }
        return Dusk.sage
    }

    private var valueText: String {
        guard let value = rowModel.value else { return "—" }
        return formatted(value)
    }

    /// "$37.25 of $50.00" — always shows the baseline once one exists (it is
    /// set on every success, so the plain-value fallback is defensive only).
    /// Spend rows never show "of": the row model still tracks a baseline,
    /// but a growing monthly total has no meaningful "full" to drain from.
    private var expandedValueText: String {
        guard let value = rowModel.value else { return "—" }
        guard !isSpend, let baseline = rowModel.baseline else { return formatted(value) }
        return "\(formatted(value)) of \(formatted(baseline))"
    }

    private func formatted(_ value: Double) -> String {
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

/// A chisel at provider-row scale: round-capped handle on the upper-right
/// diagonal, blade widening to its cutting edge at the lower-left. Bounding
/// metrics match the Claude rows' SF icons — draw at 10×10 inside the shared
/// 12pt-wide leading column so compact rows stay exactly aligned.
struct ChiselIcon: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        // Blade: trapezoid along the diagonal, flaring to the flat edge.
        path.move(to: pt(0.644, 0.484))
        path.addLine(to: pt(0.232, 0.952))
        path.addLine(to: pt(0.048, 0.768))
        path.addLine(to: pt(0.516, 0.356))
        path.closeSubpath()
        // Handle: thick round-capped bar on the same diagonal.
        let handle = Path { p in
            p.move(to: pt(0.62, 0.38))
            p.addLine(to: pt(0.84, 0.16))
        }.strokedPath(StrokeStyle(lineWidth: 0.30 * min(rect.width, rect.height), lineCap: .round))
        path.addPath(handle)
        return path
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
