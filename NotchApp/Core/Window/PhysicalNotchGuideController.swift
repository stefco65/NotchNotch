import AppKit
import CoreGraphics

/// Always-on outline of the hardware / virtual notch cutout — development
/// reference for aligning Music / DI compact frames to the real Mac cutout.
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
