import AppKit
import QuartzCore

/// Snapshot of every visual property that must move together during a notch
/// transition — window frame, silhouette radii, music scale and glow opacity.
struct PresentationMetrics: Equatable {
    var frame: CGRect
    var bottomRadius: CGFloat
    var shoulderRadius: CGFloat
    var horizontalScale: CGFloat
    var glowOpacity: CGFloat
}

/// Single timeline for notch geometry. Supersedes any in-flight run from the
/// currently presented values so transitions never stack on top of each other.
@MainActor
final class NotchGeometryAnimator {
    private(set) var presented: PresentationMetrics
    private var timer: Timer?
    private var fromMetrics: PresentationMetrics?
    private var toMetrics: PresentationMetrics?
    private var startTime: CFTimeInterval = 0
    private var duration: TimeInterval = 0

    var onApply: ((PresentationMetrics) -> Void)?

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
            return
        }

        fromMetrics = presented
        toMetrics = target
        startTime = CACurrentMediaTime()
        self.duration = duration

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
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
            frame: CGRect(
                x: lerp(from.frame.origin.x, to.frame.origin.x, progress),
                y: lerp(from.frame.origin.y, to.frame.origin.y, progress),
                width: lerp(from.frame.width, to.frame.width, progress),
                height: lerp(from.frame.height, to.frame.height, progress)
            ),
            bottomRadius: lerp(from.bottomRadius, to.bottomRadius, progress),
            shoulderRadius: lerp(from.shoulderRadius, to.shoulderRadius, progress),
            horizontalScale: lerp(from.horizontalScale, to.horizontalScale, progress),
            glowOpacity: lerp(from.glowOpacity, to.glowOpacity, progress)
        )
    }

    nonisolated private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }
}
