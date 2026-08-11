import AppKit
import CoreGraphics

/// Dev-only outline of the hardware / virtual notch cutout. Gated by
/// `PhysicalNotchGuideSettings.isEnabled` — agents turn it on while aligning
/// geometry and must turn it off before commit / push / pull.
@MainActor
enum PhysicalNotchGuideSettings {
    /// Agent workflow: `true` during Notch/Music/DI work; `false` before git.
    static var isEnabled = false
}

@MainActor
final class PhysicalNotchGuideController {
    private let panel: NSPanel
    private let shapeLayer = CAShapeLayer()

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none

        let root = NSView(frame: .zero)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = root

        shapeLayer.fillColor = NSColor.clear.cgColor
        shapeLayer.strokeColor = NSColor.systemPink.withAlphaComponent(0.95).cgColor
        shapeLayer.lineWidth = 1.5
        shapeLayer.lineDashPattern = [4, 3]
        shapeLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        root.layer?.addSublayer(shapeLayer)
    }

    func show(physicalFrame: CGRect, relativeTo notchWindow: NSWindow?) {
        guard PhysicalNotchGuideSettings.isEnabled else {
            // Always hide — do not leave a stale pink outline on screen.
            panel.orderOut(nil)
            return
        }

        let padded = physicalFrame.insetBy(dx: -1, dy: -1)
        panel.setFrame(padded, display: false)
        shapeLayer.frame = panel.contentView?.bounds ?? .zero
        shapeLayer.path = CGPath(rect: shapeLayer.bounds.insetBy(dx: 1, dy: 1), transform: nil)
        shapeLayer.contentsScale = panel.backingScaleFactor

        if let notchWindow {
            panel.order(.above, relativeTo: notchWindow.windowNumber)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func close() {
        panel.close()
    }
}
