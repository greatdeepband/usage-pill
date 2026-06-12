import AppKit
import UsageCore

final class PillPanel: NSPanel {
    private static let originKey = "pillTopLeft"

    // Row/section counts, set by AppDelegate via applyRowCounts(...).
    var pinnedClaudeRows = 2
    var pinnedProviderRows = 0
    var expandedClaudeRows = 2
    var expandedProviderRows = 0
    /// Section headers per mode (Task 18a): the Claude section counts when
    /// ≥1 of its rows is visible; each visible provider is its own section.
    var compactSections = 1
    var expandedSections = 1
    /// Set by AppDelegate when the identity toggle changes.
    var identityEnabled = false

    // Constants MEASURED via NSHostingView.fittingSize per row variant
    // (Task 12 review, re-measured for Task 18a sections, re-verified for the
    // height-aware compact paddings): compact row 13pt + 6 spacing = 19/row
    // over a 12pt base AT THE CLASSIC 8pt vertical padding, compact section
    // header 9pt + 6 spacing = 15 each — that classic-padding estimate now
    // lives in CompactGeometry, which swaps in the grown vPad (final height =
    // estimate + 2·(vPad − 8)) and grows hPad/width so content clears the
    // capsule corners. Expanded is UNCHANGED: Claude AND provider rows are
    // both two-line, 22pt + 10 spacing = 32/row over a 38pt base (padding +
    // footer), expanded section header 10pt + 10 spacing = 20 each; the
    // identity strip costs 30 (20 content + 10 section spacing), NOT 18.
    // Re-measured fittingSize with the grown paddings runs ~2 pt UNDER the
    // formula (66/107/148/189 vs 68/108.8/149.6/190.4 for 0–3 providers) with
    // exact per-row deltas — the slack sits below the top-aligned capsule, so
    // the conservative direction is harmless and the constants are kept.
    // Defaults (2 Claude rows + 1 CLAUDE header): compact 260.5×68 (hPad
    // 21.25, vPad 9.5), expanded 250×122.
    private var compactSize: NSSize {
        let m = CompactGeometry.metrics(
            rows: max(pinnedClaudeRows, 0) + max(pinnedProviderRows, 0),
            sections: max(compactSections, 0)
        )
        return NSSize(width: m.width, height: m.height)
    }

    private var currentExpandedSize: NSSize {
        let rows = (max(expandedClaudeRows, 0) + max(expandedProviderRows, 0)) * 32
        var h = max(44, 38 + CGFloat(rows) + CGFloat(max(expandedSections, 0) * 20))
        if identityEnabled { h += 30 }
        return NSSize(width: 250, height: h)
    }

    /// Tracks the last state requested through setExpanded — applyRowCounts
    /// must not fight an expanded panel back down to compact size.
    private var isExpandedNow = false

    /// When true, `saveLocation()` is a no-op.  Set during any programmatic
    /// reposition so system-induced moves never overwrite the user's saved top-left.
    private var suppressSave = false

    init() {
        // Matches compactSize for the default counts (2 Claude rows under
        // 1 section header, no providers); instance properties can't be
        // used before super.init, but the static CompactGeometry can.
        let defaultMetrics = CompactGeometry.metrics(rows: 2, sections: 1)
        super.init(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: defaultMetrics.width, height: defaultMetrics.height)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        restoreOrDefaultPosition()

        NotificationCenter.default.addObserver(
            self, selector: #selector(saveLocation),
            name: NSWindow.didMoveNotification, object: self
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Grow/shrink downward, keeping the top edge fixed.
    func setExpanded(_ expanded: Bool) {
        isExpandedNow = expanded
        // This guard is race-free ONLY because setFrame(animate: true) blocks the main
        // thread until the animation completes (verified empirically); if this is ever
        // switched to non-blocking animator() animation, replace the guard with an
        // explicit desired-state flag.
        let size = expanded ? currentExpandedSize : compactSize
        guard frame.size != size else { return }
        var f = frame
        let top = f.origin.y + f.size.height
        f.size = size
        f.origin.y = top - size.height

        // Clamp bottom edge: if expanding pushes us below the visible area, shift up.
        if expanded {
            let screen = self.screen ?? NSScreen.main
            if let visibleFrame = screen?.visibleFrame, f.origin.y < visibleFrame.minY {
                f.origin.y = visibleFrame.minY
            }
        }

        suppressSave = true
        defer { suppressSave = false }
        setFrame(f, display: true, animate: true)
    }

    /// Sync row counts from AppDelegate. When collapsed, re-applies the
    /// (possibly changed) compact frame, keeping the top edge fixed.  An
    /// expanded panel is left alone — the next hover-out collapses it to the
    /// fresh compact size via setExpanded.
    func applyRowCounts(pinnedClaude: Int, pinnedProviders: Int,
                        expandedClaude: Int, expandedProviders: Int,
                        compactSections: Int, expandedSections: Int, identity: Bool) {
        pinnedClaudeRows = pinnedClaude
        pinnedProviderRows = pinnedProviders
        expandedClaudeRows = expandedClaude
        expandedProviderRows = expandedProviders
        self.compactSections = compactSections
        self.expandedSections = expandedSections
        identityEnabled = identity
        guard !isExpandedNow else { return }
        let size = compactSize
        guard frame.size != size else { return }
        var f = frame
        let top = f.origin.y + f.size.height
        f.size = size
        f.origin.y = top - size.height
        suppressSave = true
        defer { suppressSave = false }
        setFrame(f, display: true)
    }

    private var topLeft: CGPoint {
        CGPoint(x: frame.origin.x, y: frame.origin.y + frame.height)
    }

    @objc private func saveLocation() {
        guard !suppressSave else { return }
        // Ignore moves where the resulting top-left is off-screen — these are
        // system-induced shuffles (e.g., during display reconfiguration), not user
        // drags.  AppKit constrains user drags to always end fully on-screen, so a
        // clamped top-left that differs from the raw one means the system moved us.
        let tl = topLeft
        guard clampTopLeft(tl, pillSize: compactSize,
                            screens: NSScreen.screens.map(\.visibleFrame)) == tl else { return }
        UserDefaults.standard.set(NSStringFromPoint(tl), forKey: Self.originKey)
    }

    /// Called when the display configuration changes.  Re-reads the user's saved
    /// top-left and re-clamps it against the current screen geometry.
    @objc private func handleScreenChange() {
        restoreOrDefaultPosition()
    }

    private func restoreOrDefaultPosition() {
        let size = compactSize
        let screens = NSScreen.screens.map(\.visibleFrame)
        let saved = UserDefaults.standard.string(forKey: Self.originKey).map(NSPointFromString)
        let fallback: CGPoint = {
            let main = screens.first ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            return CGPoint(x: main.maxX - size.width - 16, y: main.maxY - 16)
        }()
        // Clamp the top-left using compactSize (position policy: saved position is
        // always stored/clamped relative to the compact footprint so the pill never
        // falls off-screen when collapsed). Translate the clamped top-left to a
        // frame origin using the CURRENT frame height so that a screen-change while
        // the panel is expanded keeps the top edge where it should be.
        let clamped = clampTopLeft(saved ?? fallback, pillSize: size, screens: screens)
        suppressSave = true
        defer { suppressSave = false }
        setFrameOrigin(CGPoint(x: clamped.x, y: clamped.y - frame.height))
    }
}
