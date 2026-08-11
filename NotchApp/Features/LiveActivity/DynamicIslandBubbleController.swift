import AppKit
import SwiftUI

/// Detached right pill of the Dynamic Island. It sits to the right of the
/// fixed main notch and animates from tucked-under-the-shoulder to a clear
/// gap. Ordered below the notch window so the attach overlap stays hidden.
@MainActor
final class DynamicIslandBubbleController {
    private let panel: NSPanel
    private let model = DynamicIslandBubbleModel()
    private var hostingView: PassiveHostingView<DynamicIslandBubbleView>?

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

    /// Repositions the bubble against the notch's right edge and runs the
    /// detach / reattach animation on the same duration as the notch geometry.
    func update(
        activity: LiveActivity?,
        notchFrame: CGRect,
        restingHeight: CGFloat,
        notchWindow: NSWindow?,
        isNotchExpanded: Bool,
        animationDuration: TimeInterval
    ) {
        let shouldShow = activity != nil && !isNotchExpanded
        if !shouldShow {
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
        model.diameter = DynamicIslandLayout.bubbleDiameter(anchorHeight: restingHeight)
        model.topPadding = max((restingHeight - model.diameter) / 2, 0)
        model.attachedOffset = DynamicIslandLayout.bubbleAttachedLeadingInset()
        model.restingOffset = DynamicIslandLayout.bubbleRestingLeadingInset(envelope: notchFrame)

        let targetFrame = DynamicIslandLayout.bubbleWindowFrame(
            adjacentTo: notchFrame,
            restingHeight: restingHeight
        )
        // Snap only — animated setFrame on an NSHostingView panel hits the same
        // AppKit constraint-update crash as the main notch hover path.
        if !CGRectEqualToRect(panel.frame, targetFrame) {
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

        if let notchWindow {
            panel.order(.below, relativeTo: notchWindow.windowNumber)
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }

        guard model.isVisible != shouldShow else { return }
        withAnimation(
            animationDuration > 0
                ? .easeInOut(duration: animationDuration)
                : .linear(duration: 0)
        ) {
            model.isVisible = shouldShow
        }
    }

    func close() {
        panel.close()
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
