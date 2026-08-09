import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(store: SettingsStore) {
        let hostingController = NSHostingController(
            rootView: SettingsRootView(store: store)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Ustawienia NotchNook"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 720))
        window.minSize = NSSize(width: 640, height: 620)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
