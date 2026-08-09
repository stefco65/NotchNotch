import AppKit
import QuartzCore
import SwiftUI

/// Keeps the window transparent outside the notch while guaranteeing an opaque
/// sRGB-black backing layer everywhere inside the rendered notch shape.
/// Path morphing (shape animation) is driven by CASpringAnimation so it stays
/// in lock-step with the window-frame spring animation.
@MainActor
final class SolidBlackNotchHostingView<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>
    private let solidBlackLayer = CAShapeLayer()
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

        // Only update without animation when no spring animation is in flight.
        // This prevents layout() from stomping over an in-progress path animation.
        if solidBlackLayer.animation(forKey: "notch.path") == nil {
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
        } else {
            // Keep bounds/position in sync silently; path is handled by the animation.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            solidBlackLayer.bounds = CGRect(origin: .zero, size: bounds.size)
            solidBlackLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.commit()
        }
    }

    /// Update the notch shape and optionally animate it using a spring that
    /// matches the window-frame spring so both finish at the same time.
    func setSurfaceAppearance(
        bottomRadius: CGFloat,
        shoulderRadius: CGFloat,
        horizontalScale: CGFloat = 1,
        targetWindowFrame: CGRect? = nil,
        springParams: AnimationSpring? = nil,
        reduceMotion: Bool = false
    ) {
        let radiiChanged = self.bottomRadius != bottomRadius
            || self.shoulderRadius != shoulderRadius
        let scaleChanged = abs(self.horizontalScale - horizontalScale) > 0.0001

        guard radiiChanged || scaleChanged else { return }

        let oldBottomRadius = self.bottomRadius
        let oldShoulderRadius = self.shoulderRadius
        self.bottomRadius = bottomRadius
        self.shoulderRadius = shoulderRadius

        // --- Path animation ---
        if radiiChanged {
            let currentBounds = solidBlackLayer.bounds.isEmpty
                ? bounds
                : solidBlackLayer.bounds

            let fromPath = Self.surfacePath(
                in: currentBounds,
                bottomRadius: oldBottomRadius,
                shoulderRadius: oldShoulderRadius
            )
            let toPath = Self.surfacePath(
                in: currentBounds,
                bottomRadius: bottomRadius,
                shoulderRadius: shoulderRadius
            )

            // Set model value immediately (no implicit animation).
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            solidBlackLayer.path = toPath
            CATransaction.commit()

            if let spring = springParams, !reduceMotion {
                let anim = makeSpringAnimation(
                    keyPath: "path",
                    from: fromPath,
                    to: toPath,
                    spring: spring
                )
                solidBlackLayer.add(anim, forKey: "notch.path")
            }
        }

        // --- Horizontal scale animation ---
        if scaleChanged {
            let previousScale = solidBlackLayer.presentation()?
                .value(forKeyPath: "transform.scale.x") as? CGFloat
                ?? self.horizontalScale
            self.horizontalScale = horizontalScale

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            solidBlackLayer.setValue(horizontalScale, forKeyPath: "transform.scale.x")
            CATransaction.commit()

            if let spring = springParams, !reduceMotion {
                let anim = makeSpringAnimation(
                    keyPath: "transform.scale.x",
                    from: previousScale,
                    to: horizontalScale,
                    spring: spring
                )
                solidBlackLayer.add(anim, forKey: "notch.horizontalScale")
            }
        }

        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    // MARK: - Private helpers

    private func makeSpringAnimation(
        keyPath: String,
        from: Any,
        to: Any,
        spring: AnimationSpring
    ) -> CASpringAnimation {
        let anim = CASpringAnimation(keyPath: keyPath)
        anim.fromValue = from
        anim.toValue = to
        // Convert our logical spring params to CA spring params.
        // stiffness = mass * ω₀², damping = dampingRatio * 2 * sqrt(stiffness * mass)
        anim.mass = spring.mass
        anim.stiffness = spring.stiffness
        anim.damping = spring.dampingRatio * 2 * sqrt(spring.stiffness * spring.mass)
        anim.duration = anim.settlingDuration
        anim.isRemovedOnCompletion = true
        return anim
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
        // Only suppress the automatic implicit animations for layout properties;
        // path and scale get explicit spring animations above.
        solidBlackLayer.actions = [
            "bounds": NSNull(),
            "frame": NSNull(),
            "position": NSNull()
        ]
        layer?.insertSublayer(solidBlackLayer, at: 0)
    }

    private func configureHostingView() {
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
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
