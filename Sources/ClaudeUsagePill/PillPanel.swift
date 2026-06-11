import AppKit
import UsageCore

final class PillPanel: NSPanel {
    static let compactSize = NSSize(width: 250, height: 50)
    static let expandedSize = NSSize(width: 250, height: 132)
    private static let originKey = "pillTopLeft"

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
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Grow/shrink downward, keeping the top edge fixed.
    func setExpanded(_ expanded: Bool) {
        let size = expanded ? Self.expandedSize : Self.compactSize
        guard frame.size != size else { return }
        var f = frame
        let top = f.origin.y + f.size.height
        f.size = size
        f.origin.y = top - size.height
        setFrame(f, display: true, animate: true)
    }

    private var topLeft: CGPoint {
        CGPoint(x: frame.origin.x, y: frame.origin.y + frame.height)
    }

    @objc private func saveLocation() {
        UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: Self.originKey)
    }

    private func restoreOrDefaultPosition() {
        let screens = NSScreen.screens.map(\.visibleFrame)
        let saved = UserDefaults.standard.string(forKey: Self.originKey).map(NSPointFromString)
        let fallback: CGPoint = {
            let main = screens.first ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            return CGPoint(x: main.maxX - Self.compactSize.width - 16, y: main.maxY - 16)
        }()
        let clamped = clampTopLeft(saved ?? fallback, pillSize: Self.compactSize, screens: screens)
        setFrameOrigin(CGPoint(x: clamped.x, y: clamped.y - Self.compactSize.height))
    }
}
