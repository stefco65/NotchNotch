import AppKit
import QuartzCore
import SwiftUI

/// Keeps the window transparent outside the notch while guaranteeing an opaque
/// sRGB-black backing layer everywhere inside the rendered notch shape.
///
/// Size and radii are driven by `NotchGeometryAnimator` — this view always
/// paints the path for the *current* bounds and the *current* radii/scale
/// without its own independent spring timeline.
@MainActor
final class SolidBlackNotchHostingView<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>
    /// Exposed for geometry regression checks.
    let solidBlackLayer = CAShapeLayer()
    private var bottomRadius: CGFloat = 8
    private var shoulderRadius: CGFloat = 7
    private var horizontalScale: CGFloat = 1

    init(rootView: Content) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        configureLayers()
        configureHostingView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackingScale()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        updateBackingScale()
        commitPathFillingCurrentBounds()
    }

    /// Apply radii / horizontal scale immediately. Interpolation belongs to
    /// `NotchGeometryAnimator` so the black body, glow and window stay locked.
    func setSurfaceAppearance(
        bottomRadius: CGFloat,
        shoulderRadius: CGFloat,
        horizontalScale: CGFloat = 1,
        targetWindowFrame: CGRect? = nil,
        springParams: AnimationSpring? = nil,
        reduceMotion: Bool = false
    ) {
        _ = targetWindowFrame
        _ = springParams
        _ = reduceMotion

        let radiiChanged = self.bottomRadius != bottomRadius
            || self.shoulderRadius != shoulderRadius
        let scaleChanged = abs(self.horizontalScale - horizontalScale) > 0.0001

        guard radiiChanged || scaleChanged else { return }

        self.bottomRadius = bottomRadius
        self.shoulderRadius = shoulderRadius
        self.horizontalScale = horizontalScale

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        solidBlackLayer.setValue(horizontalScale, forKeyPath: "transform.scale.x")
        CATransaction.commit()

        if radiiChanged {
            commitPathFillingCurrentBounds()
        }
    }

    // MARK: - Private helpers

    private func commitPathFillingCurrentBounds() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        solidBlackLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        solidBlackLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        solidBlackLayer.path = Self.surfacePath(
            in: solidBlackLayer.bounds,
            bottomRadius: bottomRadius,
            shoulderRadius: shoulderRadius
        )
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
    }

    private func configureHostingView() {
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func updateBackingScale() {
        solidBlackLayer.contentsScale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
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
            rect.height - shoulder
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
