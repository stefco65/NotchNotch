import CoreGraphics
import Foundation

/// Shared geometry for the iOS-style Dynamic Island split:
/// the compact "music-expanded" envelope stays centered, the main notch
/// keeps the left portion (asymmetric), and the right portion detaches
/// into the live-activity bubble.
enum DynamicIslandLayout {
    /// Extra width the compact notch gains for music / live activity
    /// (matches the existing now-playing expansion).
    nonisolated static let compactExtraWidth: CGFloat = 100
    /// Visible gap between the cut notch and the detached bubble.
    nonisolated static let splitGap: CGFloat = 6

    nonisolated static func bubbleDiameter(anchorHeight: CGFloat) -> CGFloat {
        max(min(anchorHeight - 8, 32), 22)
    }

    /// Width reserved for the detached right pill inside the compact envelope.
    nonisolated static func bubbleSlotWidth(surfaceHeight: CGFloat) -> CGFloat {
        bubbleDiameter(anchorHeight: surfaceHeight)
    }

    /// Centered envelope that the music-expanded notch used to occupy.
    /// When the island splits, the main notch and the bubble share this
    /// envelope: main on the left, bubble on the right.
    nonisolated static func compactEnvelope(
        for state: NotchWindowController.SurfaceState,
        display: DisplayDescriptor,
        showsNowPlaying: Bool,
        showsLiveActivity: Bool
    ) -> CGRect {
        let anchor = display.anchor.rect
        let baseWidth = max(anchor.width, 120)
        let needsExtra = showsNowPlaying || showsLiveActivity
        let width: CGFloat
        let height: CGFloat

        switch state {
        case .collapsed:
            width = baseWidth + (needsExtra ? compactExtraWidth : 0)
            height = max(anchor.height, 12)
        case .hovered:
            width = baseWidth + (needsExtra ? compactExtraWidth : 40)
            height = max(anchor.height, 12) + 20
        case .musicPreview:
            width = baseWidth + (needsExtra ? compactExtraWidth : 40)
            height = max(anchor.height, 12) + 64
        case .expanded:
            // Expanded panel is always centered; the island is hidden.
            width = baseWidth
            height = max(anchor.height, 12)
        }

        return CGRect(
            x: display.frame.midX - width / 2,
            y: display.frame.maxY - height,
            width: width,
            height: height
        ).integral
    }

    /// Main notch frame inside the envelope. When the island is split the
    /// left edge stays put and the right edge pulls in — the notch becomes
    /// asymmetric relative to the display center.
    nonisolated static func mainNotchFrame(
        envelope: CGRect,
        showsLiveActivity: Bool
    ) -> CGRect {
        guard showsLiveActivity else { return envelope }
        let slot = bubbleSlotWidth(surfaceHeight: envelope.height)
        let width = max(envelope.width - splitGap - slot, 1)
        return CGRect(
            x: envelope.minX,
            y: envelope.minY,
            width: width,
            height: envelope.height
        ).integral
    }

    /// Screen frame of the bubble window. Sized generously so the capsule
    /// can grow for multi-digit counts; the visible pill is laid out inside
    /// the right slot of the envelope.
    nonisolated static func bubbleWindowFrame(envelope: CGRect) -> CGRect {
        let slot = bubbleSlotWidth(surfaceHeight: envelope.height)
        // Window covers the right slot plus a little leading overlap so the
        // pill can animate from "still attached" to "detached".
        let overlap: CGFloat = 20
        let width = slot + overlap + 48
        return CGRect(
            x: envelope.maxX - slot - overlap,
            y: envelope.maxY - max(envelope.height, 48),
            width: width,
            height: max(envelope.height, 48)
        ).integral
    }

    /// Leading padding inside the bubble window that places the visible
    /// capsule into the envelope's right slot when detached.
    nonisolated static func bubbleRestingLeadingInset(envelope: CGRect) -> CGFloat {
        20 + splitGap
    }

    /// Leading padding when the capsule is still visually attached (under
    /// the notch's right shoulder, before the split finishes).
    nonisolated static func bubbleAttachedLeadingInset() -> CGFloat {
        6
    }
}
