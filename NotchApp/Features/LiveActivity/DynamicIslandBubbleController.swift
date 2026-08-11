import AppKit
import QuartzCore
import SwiftUI

/// Detached right pill of the Dynamic Island. It sits to the right of the
/// fixed main notch and animates from tucked-under-the-shoulder to a clear
/// gap. Ordered below the notch window so the attach overlap stays hidden.
@MainActor
final class DynamicIslandBubbleController {
    /// Extra travel past the resting hover edge before the settle-back.
    nonisolated static let settleOvershoot: CGFloat = 8
    /// Total overshoot + settle duration after the notch silhouette lands.
    nonisolated static let settleDuration: TimeInterval = 0.34

    private let panel: NSPanel
    private let model = DynamicIslandBubbleModel()
    private var hostingView: PassiveHostingView<DynamicIslandBubbleView>?

    private var settleTimer: Timer?
    private var settleFromX: CGFloat = 0
    private var settlePeakX: CGFloat = 0
    private var settleRestX: CGFloat = 0
    private var settleStart: CFTimeInterval = 0
    private var settleTotalDuration: TimeInterval = 0
    private var lastRestingHeight: CGFloat = 12
    private var lastActivityIdentity: String?
    private var isSettling: Bool { settleTimer != nil }

    init(anchorHeight: CGFloat) {
        panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 120, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
        // Plain view at launch — attach SwiftUI only when an activity is shown.
        let placeholder = NSView(frame: .zero)
        placeholder.wantsLayer = true
        placeholder.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = placeholder

        model.diameter = DynamicIslandLayout.bubbleDiameter(anchorHeight: anchorHeight)
        model.topPadding = max((max(anchorHeight, 12) - model.diameter) / 2, 0)
        model.attachedOffset = DynamicIslandLayout.bubbleAttachedLeadingInset()
        model.restingOffset = DynamicIslandLayout.bubbleRestingLeadingInset(
            envelope: CGRect(x: 0, y: 0, width: 300, height: max(anchorHeight, 12))
        )
    }

    /// Repositions the bubble against the notch's right edge.
    ///
    /// Pass the *live* silhouette edge each animation tick so the pill stays a
    /// constant distance from the growing notch. Optionally play a small
    /// overshoot settle after the silhouette lands.
    func update(
        activity: LiveActivity?,
        notchFrame: CGRect,
        restingHeight: CGFloat,
        notchWindow: NSWindow?,
        isNotchExpanded: Bool,
        animationDuration: TimeInterval,
        settleOvershoot: CGFloat = 0
    ) {
        let shouldShow = activity != nil && !isNotchExpanded
        if !shouldShow {
            cancelSettle()
            model.isVisible = false
            if panel.isVisible {
                panel.orderOut(nil)
            }
            return
        }

        ensureHostingAttached()

        if let activity {
            model.activity = activity
        }

        // Diameter / vertical padding stay locked to the resting physical height
        // so the pill never recenters when the main notch grows downward.
        let diameter = DynamicIslandLayout.bubbleDiameter(anchorHeight: restingHeight)
        let topPadding = max((restingHeight - diameter) / 2, 0)
        let attached = DynamicIslandLayout.bubbleAttachedLeadingInset()
        let resting = DynamicIslandLayout.bubbleRestingLeadingInset(envelope: notchFrame)
        let metricsChanged =
            abs(model.diameter - diameter) > 0.5
            || abs(model.topPadding - topPadding) > 0.5
            || abs(model.attachedOffset - attached) > 0.5
            || abs(model.restingOffset - resting) > 0.5
            || abs(lastRestingHeight - restingHeight) > 0.5
        model.diameter = diameter
        model.topPadding = topPadding
        model.attachedOffset = attached
        model.restingOffset = resting
        lastRestingHeight = restingHeight

        let activityIdentity = activity.map(Self.activityIdentity(for:))
        let activityChanged = activityIdentity != lastActivityIdentity
        if activityChanged {
            lastActivityIdentity = activityIdentity
        }

        let targetFrame = DynamicIslandLayout.bubbleWindowFrame(
            adjacentTo: notchFrame,
            restingHeight: restingHeight
        )

        if settleOvershoot > 0.5 {
            // Land on the live edge first, then drift a touch further and settle.
            applyPanelFrame(targetFrame)
            startSettle(
                restFrame: targetFrame,
                overshoot: settleOvershoot,
                duration: Self.settleDuration
            )
        } else if isSettling {
            // A trailing visibility sync must not cancel an in-flight settle.
            // Only re-target if the notch edge itself moved.
            if abs(targetFrame.origin.x - settleRestX) > 0.5 {
                cancelSettle()
                applyPanelFrame(targetFrame)
            }
        } else {
            applyPanelFrame(targetFrame)
        }

        if let notchWindow {
            panel.order(.below, relativeTo: notchWindow.windowNumber)
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }

        let visibilityChanging = model.isVisible != shouldShow
        // Skip SwiftUI rebuilds on pure follow-ticks — position is panel frame only.
        if metricsChanged || activityChanged || visibilityChanging {
            if let hosting = hostingView {
                hosting.rootView = DynamicIslandBubbleView(model: model)
                hosting.needsDisplay = true
                hosting.displayIfNeeded()
            }
            panel.displayIfNeeded()
        }

        guard visibilityChanging else { return }
        withAnimation(
            animationDuration > 0
                ? .easeInOut(duration: animationDuration)
                : .linear(duration: 0)
        ) {
            model.isVisible = shouldShow
        }
    }

    private static func activityIdentity(for activity: LiveActivity) -> String {
        switch activity {
        case .agents(let state, let count):
            return "agents:\(state):\(count)"
        case .tasks(let count):
            return "tasks:\(count)"
        }
    }

    func close() {
        cancelSettle()
        panel.close()
    }

    private func applyPanelFrame(_ targetFrame: CGRect) {
        // Snap only — animated setFrame on an NSHostingView panel hits the same
        // AppKit constraint-update crash as the main notch hover path.
        guard !CGRectEqualToRect(panel.frame, targetFrame) else { return }
        let host = hostingView
        host?.removeFromSuperview()
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        panel.setFrame(targetFrame, display: false)
        NSAnimationContext.endGrouping()
        if let host {
            host.frame = panel.contentView?.bounds ?? .zero
            panel.contentView?.addSubview(host)
        }
    }

    private func startSettle(restFrame: CGRect, overshoot: CGFloat, duration: TimeInterval) {
        cancelSettle()
        guard duration > 0, overshoot > 0 else {
            applyPanelFrame(restFrame)
            return
        }

        settleFromX = panel.frame.origin.x
        settleRestX = restFrame.origin.x
        settlePeakX = restFrame.origin.x + overshoot
        settleStart = CACurrentMediaTime()
        settleTotalDuration = duration

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickSettle(restFrame: restFrame)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
        tickSettle(restFrame: restFrame)
    }

    private func tickSettle(restFrame: CGRect) {
        let elapsed = CACurrentMediaTime() - settleStart
        let linear = settleTotalDuration > 0
            ? min(max(elapsed / settleTotalDuration, 0), 1)
            : 1

        // 0…0.45 → ease out to peak; 0.45…1 → ease back to rest.
        let x: CGFloat
        if linear < 0.45 {
            let t = Self.easeOut(linear / 0.45)
            x = settleFromX + (settlePeakX - settleFromX) * t
        } else {
            let t = Self.easeInOut((linear - 0.45) / 0.55)
            x = settlePeakX + (settleRestX - settlePeakX) * t
        }

        var frame = restFrame
        frame.origin.x = x
        applyPanelFrame(frame)

        if linear >= 1 {
            cancelSettle()
            applyPanelFrame(restFrame)
        }
    }

    private func cancelSettle() {
        settleTimer?.invalidate()
        settleTimer = nil
    }

    nonisolated private static func easeOut(_ t: CGFloat) -> CGFloat {
        1 - pow(1 - t, 3)
    }

    nonisolated private static func easeInOut(_ t: CGFloat) -> CGFloat {
        t < 0.5
            ? 2 * t * t
            : 1 - pow(-2 * t + 2, 2) / 2
    }

    private func ensureHostingAttached() {
        guard hostingView == nil else { return }
        let hosting = PassiveHostingView(rootView: DynamicIslandBubbleView(model: model))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = panel.contentView?.bounds ?? .zero
        panel.contentView?.addSubview(hosting)
        hostingView = hosting
    }
}

// MARK: - Model

@MainActor
final class DynamicIslandBubbleModel: ObservableObject {
    @Published var activity: LiveActivity = .tasks(count: 0)
    @Published var isVisible = false
    @Published var diameter: CGFloat = 28
    @Published var topPadding: CGFloat = 4
    @Published var attachedOffset: CGFloat = 6
    @Published var restingOffset: CGFloat = 26
}

// MARK: - View

struct DynamicIslandBubbleView: View {
    @ObservedObject var model: DynamicIslandBubbleModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            bubble
                .padding(.top, model.topPadding)
                .offset(x: model.isVisible ? model.restingOffset : model.attachedOffset)
                .scaleEffect(
                    model.isVisible ? 1 : 0.92,
                    anchor: .leading
                )
                .opacity(model.isVisible ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityHidden(!model.isVisible)
    }

    private var bubble: some View {
        HStack(spacing: 3) {
            Image(systemName: style.symbol)
                .font(.system(size: 9, weight: .bold))
            Text(style.count.formatted())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(style.color)
        .padding(.horizontal, 7)
        .frame(minWidth: model.diameter)
        .frame(height: model.diameter)
        .background(
            Capsule().fill(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1))
        )
        .overlay {
            Capsule().stroke(style.color.opacity(0.35), lineWidth: 1)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.activity)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.accessibilityLabel)
    }

    private var style: DynamicIslandBubbleStyle {
        DynamicIslandBubbleStyle(activity: model.activity)
    }
}

/// Visual attributes for each activity, matching the agent component colors:
/// stopped = orange, done = green, working = blue.
struct DynamicIslandBubbleStyle {
    let symbol: String
    let color: Color
    let count: Int
    let accessibilityLabel: String

    init(activity: LiveActivity) {
        switch activity {
        case .agents(let state, let count):
            self.count = count
            switch state {
            case .stopped:
                symbol = "pause.fill"
                color = Color(red: 1, green: 0.56, blue: 0.18)
                accessibilityLabel = "Zatrzymani agenci: \(count)"
            case .done:
                symbol = "checkmark"
                color = Color(red: 0.24, green: 0.82, blue: 0.48)
                accessibilityLabel = "Gotowi agenci: \(count)"
            case .working:
                symbol = "bolt.fill"
                color = Color(red: 0.20, green: 0.57, blue: 1)
                accessibilityLabel = "Pracujący agenci: \(count)"
            }
        case .tasks(let count):
            self.count = count
            symbol = "checklist"
            color = Color(red: 0.64, green: 0.57, blue: 1)
            accessibilityLabel = "Otwarte zadania: \(count)"
        }
    }
}
