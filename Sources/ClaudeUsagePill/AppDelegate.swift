import AppKit
import SwiftUI
import UsageCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: PillPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = PillPanel()
        panel.contentView = NSHostingView(
            rootView: Text("pill").foregroundStyle(.white)
                .frame(width: 250, height: 44)
                .background(.black.opacity(0.5), in: Capsule())
        )
        panel.orderFrontRegardless()
    }
}
