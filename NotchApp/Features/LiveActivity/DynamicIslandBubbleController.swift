import AppKit
import SwiftUI

/// A small detached black bubble floating right of the notch, in the spirit
/// of the iOS Dynamic Island split view. It slides out from underneath the
/// notch window (which is ordered above it, so the overlap is invisible on
/// black) and presents the current `LiveActivity`.
@MainActor
final class DynamicIslandBubbleController {
    /// Horizontal overlap between the bubble window and the notch window.
    /// The bubble parks inside this overlap while hidden, so showing it looks
    /// like it detaches from the notch.
    nonisolated static let notchOverlap: CGFloat = 36
    /// Gap between the notch edge and the resting bubble.
    nonisolated static let notchGap: CGFloat = 8
    /// Extra room on the trailing side for multi-digit counts and the
    /// scale-bounce of the show animation.
    nonisolated static let windowWidth: CGFloat = 140
    nonisolated static let windowHeight: CGFloat = 48

    nonisolated static func bubbleDiameter(anchorHeight: CGFloat) -> CGFloat {
        max(min(anchorHeight - 8, 32), 22)
    }

    /// Frame of the bubble window positioned against the notch surface frame.
    /// The window's top edge matches the display top (like the notch panel).
    nonisolated static func windowFrame(nextTo notchFrame: CGRect) -> CGRect {
        CGRect(
            x: notchFrame.maxX - notchOverlap,
            y: notchFrame.maxY - windowHeight,
            width: windowWidth,
            height: windowHeight
        ).integral
    }

    private let panel: NSPanel
    private let model = DynamicIslandBubbleModel()
    private let anchorHeight: CGFloat

    init(anchorHeight: CGFloat) {
        self.anchorHeight = anchorHeight

        panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: Self.windowWidth, height: Self.windowHeight),
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

        model.diameter = Self.bubbleDiameter(anchorHeight: anchorHeight)
        model.topPadding = (max(anchorHeight, 12) - model.diameter) / 2
        model.restingOffset = Self.notchOverlap + Self.notchGap

        let hosting = NSHostingView(rootView: DynamicIslandBubbleView(model: model))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
    }

    /// Repositions the bubble against the notch and shows/hides it with the
    /// detach animation. `notchWindow` keeps the z-order such that the bubble
    /// stays underneath the notch surface while sliding in and out.
    func update(
        activity: LiveActivity?,
        notchFrame: CGRect,
        notchWindow: NSWindow?,
        isNotchExpanded: Bool
    ) {
        // Keep the last content visible during the hide animation instead of
        // blanking the bubble mid-flight.
        if let activity {
            model.activity = activity
        }

        let targetFrame = Self.windowFrame(nextTo: notchFrame)
        if panel.frame != targetFrame {
            if panel.isVisible, model.isVisible {
                // Follow notch width changes (hover / now-playing) smoothly.
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.28
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrame(targetFrame, display: true)
                }
            } else {
                panel.setFrame(targetFrame, display: true)
            }
        }

        if let notchWindow {
            panel.order(.below, relativeTo: notchWindow.windowNumber)
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }

        let shouldShow = activity != nil && !isNotchExpanded
        guard model.isVisible != shouldShow else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(
            reduceMotion
                ? .easeInOut(duration: 0.1)
                : .spring(response: 0.42, dampingFraction: 0.72)
        ) {
            model.isVisible = shouldShow
        }
    }

    func close() {
        panel.close()
    }
}

// MARK: - Model

@MainActor
final class DynamicIslandBubbleModel: ObservableObject {
    @Published var activity: LiveActivity = .tasks(count: 0)
    @Published var isVisible = false
    @Published var diameter: CGFloat = 28
    @Published var topPadding: CGFloat = 4
    @Published var restingOffset: CGFloat = 44
}

// MARK: - View

struct DynamicIslandBubbleView: View {
    @ObservedObject var model: DynamicIslandBubbleModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            bubble
                .padding(.top, model.topPadding)
                .offset(x: model.isVisible ? model.restingOffset : 6)
                .scaleEffect(
                    model.isVisible ? 1 : 0.45,
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
