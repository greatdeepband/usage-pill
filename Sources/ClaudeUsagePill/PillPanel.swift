import AppKit
import UsageCore

final class PillPanel: NSPanel {
    static let compactSize = NSSize(width: 250, height: 50)
    static let expandedSize = NSSize(width: 250, height: 132)
    static let identityExtraHeight: CGFloat = 18
    private static let originKey = "pillTopLeft"

    /// Set by AppDelegate when the identity toggle changes.
    var identityEnabled = false

    private var currentExpandedSize: NSSize {
        var s = Self.expandedSize
        if identityEnabled { s.height += Self.identityExtraHeight }
        return s
    }

    /// When true, `saveLocation()` is a no-op.  Set during any programmatic
    /// reposition so system-induced moves never overwrite the user's saved top-left.
    private var suppressSave = false

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.compactSize),
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
        // This guard is race-free ONLY because setFrame(animate: true) blocks the main
        // thread until the animation completes (verified empirically); if this is ever
        // switched to non-blocking animator() animation, replace the guard with an
        // explicit desired-state flag.
        let size = expanded ? currentExpandedSize : Self.compactSize
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
        guard clampTopLeft(tl, pillSize: Self.compactSize,
                            screens: NSScreen.screens.map(\.visibleFrame)) == tl else { return }
        UserDefaults.standard.set(NSStringFromPoint(tl), forKey: Self.originKey)
    }

    /// Called when the display configuration changes.  Re-reads the user's saved
    /// top-left and re-clamps it against the current screen geometry.
    @objc private func handleScreenChange() {
        restoreOrDefaultPosition()
    }

    private func restoreOrDefaultPosition() {
        let screens = NSScreen.screens.map(\.visibleFrame)
        let saved = UserDefaults.standard.string(forKey: Self.originKey).map(NSPointFromString)
        let fallback: CGPoint = {
            let main = screens.first ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            return CGPoint(x: main.maxX - Self.compactSize.width - 16, y: main.maxY - 16)
        }()
        let clamped = clampTopLeft(saved ?? fallback, pillSize: Self.compactSize, screens: screens)
        suppressSave = true
        defer { suppressSave = false }
        setFrameOrigin(CGPoint(x: clamped.x, y: clamped.y - Self.compactSize.height))
    }
}
