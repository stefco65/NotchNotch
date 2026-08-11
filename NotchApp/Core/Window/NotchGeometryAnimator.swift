import AppKit
import QuartzCore

/// Snapshot of every visual property that must move together during a notch
/// transition — window frame, drawn content size, silhouette radii and glow.
struct PresentationMetrics: Equatable {
    /// NSWindow frame. For compact states this is a stable chrome rect so
    /// collapsed ↔ hovered ↔ musicPreview do not resize the window.
    var frame: CGRect
    /// Drawn notch size inside `frame`. Animates on hover.
    var contentWidth: CGFloat
    var contentHeight: CGFloat
    /// Leading inset of the drawn body inside `frame`, so the silhouette
    /// lines up with the screen-space visual rect (hardware notch midX).
    var contentOffsetX: CGFloat
    var bottomRadius: CGFloat
    var shoulderRadius: CGFloat
    /// Trailing (right) shoulder. Music+DI flattens this to 0 so the right
    /// wall sits on `physical.maxX` instead of being pulled inward.
    var trailingShoulderRadius: CGFloat
    var horizontalScale: CGFloat
    var glowOpacity: CGFloat

    /// Screen-space maxX of the drawn black body — the edge DI must track.
    var drawnBodyMaxX: CGFloat {
        frame.minX + contentOffsetX + contentWidth
    }
}

/// Single timeline for notch geometry. Supersedes any in-flight run from the
/// currently presented values so transitions never stack on top of each other.
///
/// Window `frame` is applied in one shot at commit time. Interpolating
/// `NSWindow.setFrame` every tick forces SwiftUI hosting layout into AppKit's
/// fatal "too many Update Constraints in Window" trap on macOS 26.
@MainActor
final class NotchGeometryAnimator {
    private(set) var presented: PresentationMetrics
    private var timer: Timer?
    private var fromMetrics: PresentationMetrics?
    private var toMetrics: PresentationMetrics?
    private var startTime: CFTimeInterval = 0
    private var duration: TimeInterval = 0

    var onApply: ((PresentationMetrics) -> Void)?
    /// Fires once when a commit reaches its target (including duration == 0).
    var onComplete: ((PresentationMetrics) -> Void)?

    init(initial: PresentationMetrics) {
        presented = initial
    }

    /// Commit a new target. If a transition is already running it continues
    /// from the live presented metrics instead of the previous target.
    func commit(_ target: PresentationMetrics, duration: TimeInterval) {
        cancelTimer()

        if duration <= 0 || target == presented {
            presented = target
            onApply?(target)
            onComplete?(target)
            return
        }

        // Snap the window rect immediately, then animate only the silhouette.
        var from = presented
        if !Self.framesEqual(from.frame, target.frame) {
            from.frame = target.frame
            presented = from
            onApply?(from)
        }

        fromMetrics = from
        toMetrics = target
        startTime = CACurrentMediaTime()
        self.duration = duration

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func cancel() {
        cancelTimer()
        fromMetrics = nil
        toMetrics = nil
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let fromMetrics, let toMetrics else { return }

        let elapsed = CACurrentMediaTime() - startTime
        let linear = duration > 0 ? min(max(elapsed / duration, 0), 1) : 1
        let eased = Self.easeInEaseOut(linear)
        let metrics = Self.interpolate(from: fromMetrics, to: toMetrics, progress: eased)
        presented = metrics
        onApply?(metrics)

        if linear >= 1 {
            cancelTimer()
            presented = toMetrics
            onApply?(toMetrics)
            onComplete?(toMetrics)
            self.fromMetrics = nil
            self.toMetrics = nil
        }
    }

    nonisolated private static func easeInEaseOut(_ t: CGFloat) -> CGFloat {
        t < 0.5
            ? 2 * t * t
            : 1 - pow(-2 * t + 2, 2) / 2
    }

    nonisolated private static func interpolate(
        from: PresentationMetrics,
        to: PresentationMetrics,
        progress: CGFloat
    ) -> PresentationMetrics {
        PresentationMetrics(
            frame: to.frame,
            contentWidth: lerp(from.contentWidth, to.contentWidth, progress),
            contentHeight: lerp(from.contentHeight, to.contentHeight, progress),
            contentOffsetX: lerp(from.contentOffsetX, to.contentOffsetX, progress),
            bottomRadius: lerp(from.bottomRadius, to.bottomRadius, progress),
            shoulderRadius: lerp(from.shoulderRadius, to.shoulderRadius, progress),
            trailingShoulderRadius: lerp(
                from.trailingShoulderRadius,
                to.trailingShoulderRadius,
                progress
            ),
            horizontalScale: lerp(from.horizontalScale, to.horizontalScale, progress),
            glowOpacity: lerp(from.glowOpacity, to.glowOpacity, progress)
        )
    }

    nonisolated private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    nonisolated private static func framesEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.05
            && abs(lhs.origin.y - rhs.origin.y) < 0.05
            && abs(lhs.size.width - rhs.size.width) < 0.05
            && abs(lhs.size.height - rhs.size.height) < 0.05
    }
}
