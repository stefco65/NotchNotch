import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private enum Metrics {
        static let defaultSize = NSSize(width: 560, height: 520)
        static let minSize = NSSize(width: 480, height: 400)
        /// Keep the title bar clear of the menu bar / notch strip.
        static let topClearance: CGFloat = 36
        /// Bias the window downward so it sits lower on the desktop.
        static let downwardBias: CGFloat = 64
        static let horizontalInset: CGFloat = 40
        static let bottomInset: CGFloat = 24
    }

    /// Fires when the settings window is hidden or closed.
    var onDismiss: (() -> Void)?

    init(store: SettingsStore) {
        let hostingView = PassiveHostingView(rootView: SettingsRootView(store: store))
        hostingView.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Metrics.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ustawienia NotchNook"
        window.contentView = hostingView
        hostingView.frame = window.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        window.setContentSize(Metrics.defaultSize)
        window.minSize = Metrics.minSize
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        repositionBelowMenuBar()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        repositionBelowMenuBar()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onDismiss?()
    }

    /// Places the window inside `visibleFrame` (below the menu bar / notch)
    /// and biases it downward so the title bar stays readable while the
    /// expanded notch remains open above.
    private func repositionBelowMenuBar() {
        guard let window else { return }
        guard let screen = window.screen ?? NSScreen.main else {
            window.center()
            return
        }

        let visible = screen.visibleFrame
        var frame = window.frame
        frame.size.width = min(
            max(frame.size.width, Metrics.minSize.width),
            max(visible.width - Metrics.horizontalInset, Metrics.minSize.width)
        )
        frame.size.height = min(
            max(frame.size.height, Metrics.minSize.height),
            max(visible.height - Metrics.topClearance - Metrics.bottomInset, Metrics.minSize.height)
        )

        frame.origin.x = visible.midX - frame.size.width / 2
        let biasedY = visible.midY - frame.size.height / 2 - Metrics.downwardBias
        let maxOriginY = visible.maxY - frame.size.height - Metrics.topClearance
        let minOriginY = visible.minY + Metrics.bottomInset
        frame.origin.y = min(max(biasedY, minOriginY), maxOriginY)

        window.setFrame(frame, display: false)
    }
}
