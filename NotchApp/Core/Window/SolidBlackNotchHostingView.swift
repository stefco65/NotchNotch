import AppKit
import QuartzCore
import SwiftUI

/// Keeps the window transparent outside the notch while guaranteeing an opaque
/// sRGB-black backing layer everywhere inside the rendered notch shape.
///
/// Geometry morphs live on `CAShapeLayer`. SwiftUI sits in a dedicated
/// `contentContainer` that shares the same path mask — never mask
/// `NSHostingView.layer` directly (SwiftUI replaces that layer and drops the mask,
/// which desyncs components from the growing silhouette).
@MainActor
final class SolidBlackNotchHostingView<Content: View>: NSView {
    private let rootView: Content
    private let contentContainer = NSView(frame: .zero)
    private var hostingView: PassiveHostingView<Content>?
    /// Exposed for geometry regression checks.
    let solidBlackLayer = CAShapeLayer()
    private let contentMaskLayer = CAShapeLayer()
    private var bottomRadius: CGFloat = 8
    private var shoulderRadius: CGFloat = 7
    private var contentWidth: CGFloat = 0
    private var contentHeight: CGFloat = 0
    private var didAttachHosting = false

    init(rootView: Content) {
        self.rootView = rootView
        super.init(frame: .zero)
        configureLayers()
        configureContentContainer()
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Attach SwiftUI after the panel is on-screen. Safe to call repeatedly.
    func attachHostingWhenReady() {
        guard !didAttachHosting else { return }
        didAttachHosting = true

        let host = PassiveHostingView(rootView: rootView)
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.layer?.isOpaque = false
        host.frame = contentContainer.bounds
        hostingView = host
        contentContainer.addSubview(host)
        needsLayout = true
    }

    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackingScale()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        if contentContainer.frame != bounds {
            contentContainer.frame = bounds
        }
        if let hostingView, hostingView.superview === contentContainer,
           hostingView.frame != contentContainer.bounds {
            hostingView.frame = contentContainer.bounds
        }
        // Re-assert mask — AppKit/SwiftUI can clear it across layout passes.
        if contentContainer.layer?.mask !== contentMaskLayer {
            contentContainer.layer?.mask = contentMaskLayer
        }
        updateBackingScale()
        commitPathFillingCurrentBounds()
    }

    /// Temporarily remove SwiftUI hosting before an unavoidable window resize.
    func detachHostingForResize() {
        hostingView?.removeFromSuperview()
    }

    func attachHostingAfterResize() {
        guard let hostingView else { return }
        hostingView.frame = contentContainer.bounds
        if hostingView.superview !== contentContainer {
            contentContainer.addSubview(hostingView)
        }
    }

    /// Fade SwiftUI content without touching `@Published` / Auto Layout.
    func setContentAlpha(_ alpha: CGFloat, animated: Bool, duration: TimeInterval = 0.12) {
        let clamped = min(max(alpha, 0), 1)
        if animated, duration > 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                contentContainer.animator().alphaValue = clamped
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                contentContainer.alphaValue = clamped
            }
        }
    }

    /// Clicks / hovers outside the drawn notch must fall through to apps below.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let path = solidBlackLayer.path else {
            return super.hitTest(point)
        }
        let local = convert(point, from: superview)
        guard path.contains(local) else { return nil }
        return super.hitTest(point)
    }

    /// Apply silhouette metrics. `contentWidth` / `contentHeight` describe the
    /// drawn notch inside a potentially larger stable chrome window.
    func setSurfaceAppearance(
        bottomRadius: CGFloat,
        shoulderRadius: CGFloat,
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        targetWindowFrame: CGRect? = nil,
        springParams: AnimationSpring? = nil,
        reduceMotion: Bool = false
    ) {
        _ = targetWindowFrame
        _ = springParams
        _ = reduceMotion

        let width = max(contentWidth, 1)
        let height = max(contentHeight, 1)
        let radiiChanged = self.bottomRadius != bottomRadius
            || self.shoulderRadius != shoulderRadius
        let sizeChanged = abs(self.contentWidth - width) > 0.05
            || abs(self.contentHeight - height) > 0.05

        guard radiiChanged || sizeChanged else { return }

        self.bottomRadius = bottomRadius
        self.shoulderRadius = shoulderRadius
        self.contentWidth = width
        self.contentHeight = height
        commitPathFillingCurrentBounds()
    }

    // MARK: - Private helpers

    private func configureContentContainer() {
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor
        contentContainer.layer?.isOpaque = false
        contentContainer.layer?.mask = contentMaskLayer
        contentContainer.translatesAutoresizingMaskIntoConstraints = true
        contentContainer.autoresizingMask = [.width, .height]
        contentContainer.frame = bounds
        addSubview(contentContainer)
    }

    private func commitPathFillingCurrentBounds() {
        let width = contentWidth > 1 ? contentWidth : bounds.width
        let height = contentHeight > 1 ? contentHeight : bounds.height
        let rect = CGRect(
            x: (bounds.width - width) / 2,
            y: bounds.height - height,
            width: width,
            height: height
        )
        let path = Self.surfacePath(
            in: rect,
            bottomRadius: bottomRadius,
            shoulderRadius: shoulderRadius
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        solidBlackLayer.frame = bounds
        solidBlackLayer.path = path
        contentMaskLayer.frame = bounds
        contentMaskLayer.path = path
        if contentContainer.layer?.mask !== contentMaskLayer {
            contentContainer.layer?.mask = contentMaskLayer
        }
        CATransaction.commit()
    }

    private func configureLayers() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false

        solidBlackLayer.fillColor = NSColor(
            srgbRed: 0,
            green: 0,
            blue: 0,
            alpha: 1
        ).cgColor
        solidBlackLayer.strokeColor = nil
        solidBlackLayer.isOpaque = true
        solidBlackLayer.allowsEdgeAntialiasing = true
        solidBlackLayer.actions = [
            "bounds": NSNull(),
            "frame": NSNull(),
            "position": NSNull(),
            "path": NSNull(),
            "transform": NSNull()
        ]
        layer?.insertSublayer(solidBlackLayer, at: 0)

        contentMaskLayer.fillColor = NSColor.black.cgColor
        contentMaskLayer.actions = solidBlackLayer.actions
    }

    private func updateBackingScale() {
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        solidBlackLayer.contentsScale = scale
        contentMaskLayer.contentsScale = scale
    }

    /// Notch silhouette: flat top edge flush with the window top, concave
    /// shoulders into the menu bar, rounded bottom corners.
    private static func surfacePath(
        in rect: CGRect,
        bottomRadius: CGFloat,
        shoulderRadius: CGFloat
    ) -> CGPath {
        let shoulder = min(shoulderRadius, rect.width / 4, rect.height / 2)
        let leftEdge = rect.minX + shoulder
        let rightEdge = rect.maxX - shoulder
        let lowerRadius = min(
            bottomRadius,
            (rightEdge - leftEdge) / 2,
            max(rect.height - shoulder, 0)
        )

        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rightEdge, y: rect.maxY - shoulder),
            control1: CGPoint(x: rect.maxX - shoulder * 0.25, y: rect.maxY),
            control2: CGPoint(x: rightEdge, y: rect.maxY - shoulder * 0.5)
        )
        path.addLine(to: CGPoint(x: rightEdge, y: rect.minY + lowerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rightEdge - lowerRadius, y: rect.minY),
            control: CGPoint(x: rightEdge, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: leftEdge + lowerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: leftEdge, y: rect.minY + lowerRadius),
            control: CGPoint(x: leftEdge, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: leftEdge, y: rect.maxY - shoulder))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY),
            control1: CGPoint(x: leftEdge, y: rect.maxY - shoulder * 0.5),
            control2: CGPoint(x: rect.minX + shoulder * 0.25, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
