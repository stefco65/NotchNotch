import CoreGraphics
import Foundation

/// Shared geometry for the Dynamic Island split.
///
/// The idle notch always matches `display.anchor.rect` (the real hardware /
/// virtual cutout). Music and hover expand symmetrically around that anchor's
/// midX — except Music + Live Activity, where the left edge keeps the music
/// capsule overhang and the right edge snaps to the physical notch's maxX so
/// the DI bubble can detach from the hardware cutout.
enum DynamicIslandLayout {
    nonisolated static let compactExtraWidth: CGFloat = 100
    /// Idle hover growth on a ~220pt hardware notch (~+36%) so the slide-out
    /// reads as a real expansion, not a thin downward drip.
    nonisolated static let idleHoverExtraWidth: CGFloat = 80
    nonisolated static let splitGap: CGFloat = 2
    nonisolated static let attachOverlap: CGFloat = 10

    nonisolated static func bubbleDiameter(anchorHeight: CGFloat) -> CGFloat {
        max(min(anchorHeight - 8, 32), 22)
    }

    nonisolated static func bubbleSlotWidth(display: DisplayDescriptor) -> CGFloat {
        bubbleDiameter(anchorHeight: max(display.anchor.rect.height, 12))
    }

    nonisolated static func bubbleSlotWidth(surfaceHeight: CGFloat) -> CGFloat {
        bubbleDiameter(anchorHeight: surfaceHeight)
    }

    nonisolated static func physicalNotchWidth(display: DisplayDescriptor) -> CGFloat {
        max(display.anchor.rect.width, 120)
    }

    nonisolated static func compactHeight(
        for state: NotchWindowController.SurfaceState,
        display: DisplayDescriptor
    ) -> CGFloat {
        let base = max(display.anchor.rect.height, 12)
        switch state {
        case .collapsed, .expanded:
            return base
        case .hovered:
            return base + 20
        case .musicPreview:
            return base + 64
        }
    }

    /// Exact resting frame of the physical / virtual notch. Uses the resolved
    /// anchor rect so the black body lines up with the hardware cutout — not a
    /// re-centered guess from `display.frame.midX`.
    nonisolated static func physicalNotchFrame(display: DisplayDescriptor) -> CGRect {
        let anchor = display.anchor.rect
        let height = max(anchor.height, 12)
        let width = max(anchor.width, 120)
        if anchor.width >= 120 {
            return CGRect(
                x: anchor.minX,
                y: display.frame.maxY - height,
                width: anchor.width,
                height: height
            ).integral
        }
        // Tiny anchors: grow to the 120pt minimum around the real cutout center.
        return CGRect(
            x: anchor.midX - width / 2,
            y: display.frame.maxY - height,
            width: width,
            height: height
        ).integral
    }

    /// Centered capsule expanded around the physical notch midX.
    nonisolated static func centeredCapsule(
        for state: NotchWindowController.SurfaceState,
        display: DisplayDescriptor,
        showsNowPlaying: Bool
    ) -> CGRect {
        let physical = physicalNotchFrame(display: display)
        let height = compactHeight(for: state, display: display)
        let extra: CGFloat
        switch state {
        case .collapsed:
            extra = showsNowPlaying ? compactExtraWidth : 0
        case .hovered, .musicPreview:
            extra = showsNowPlaying ? compactExtraWidth : idleHoverExtraWidth
        case .expanded:
            extra = 0
        }
        let width = physical.width + extra
        return CGRect(
            x: physical.midX - width / 2,
            y: display.frame.maxY - height,
            width: width,
            height: height
        ).integral
    }

    /// Compact visual frame.
    ///
    /// - Without DI: centered capsule on the physical notch.
    /// - Idle + DI: same centered capsule; bubble hangs past `maxX`.
    /// - Music + DI: left keeps the music overhang, right snaps to
    ///   `physical.maxX`. The trailing shoulder is flattened so the visible
    ///   right wall sits on the hardware cutout (DI parks there).
    nonisolated static func compactEnvelope(
        for state: NotchWindowController.SurfaceState,
        display: DisplayDescriptor,
        showsNowPlaying: Bool,
        showsLiveActivity: Bool
    ) -> CGRect {
        guard showsLiveActivity, showsNowPlaying else {
            return centeredCapsule(
                for: state,
                display: display,
                showsNowPlaying: showsNowPlaying
            )
        }

        let physical = physicalNotchFrame(display: display)
        let height = compactHeight(for: state, display: display)
        let musicLeft = centeredCapsule(
            for: .collapsed,
            display: display,
            showsNowPlaying: true
        ).minX

        return snapRightEdge(
            left: musicLeft,
            right: physical.maxX,
            y: display.frame.maxY - height,
            height: height
        )
    }

    /// Build a rect whose maxX lands exactly on `right` after integral rounding.
    nonisolated static func snapRightEdge(
        left: CGFloat,
        right: CGFloat,
        y: CGFloat,
        height: CGFloat
    ) -> CGRect {
        let provisional = CGRect(
            x: left,
            y: y,
            width: max(right - left, 1),
            height: height
        ).integral
        return CGRect(
            x: provisional.origin.x,
            y: provisional.origin.y,
            width: max(right - provisional.origin.x, 1),
            height: provisional.height
        )
    }

    nonisolated static func mainNotchFrame(
        envelope: CGRect,
        display: DisplayDescriptor,
        showsLiveActivity: Bool,
        showsNowPlaying: Bool = false
    ) -> CGRect {
        _ = display
        _ = showsLiveActivity
        _ = showsNowPlaying
        return envelope
    }

    /// Bubble window parked against the notch's right shoulder.
    /// Diameter is locked to the resting (physical) height so hover growth
    /// only recenters the pill — it must not widen the cut mid-animation.
    nonisolated static func bubbleWindowFrame(
        adjacentTo notchFrame: CGRect,
        restingHeight: CGFloat
    ) -> CGRect {
        let diameter = bubbleDiameter(anchorHeight: restingHeight)
        let width = attachOverlap + splitGap + diameter + 48
        return CGRect(
            x: notchFrame.maxX - attachOverlap,
            y: notchFrame.maxY - max(notchFrame.height, 48),
            width: width,
            height: max(notchFrame.height, 48)
        ).integral
    }

    nonisolated static func bubbleWindowFrame(adjacentTo notchFrame: CGRect) -> CGRect {
        bubbleWindowFrame(
            adjacentTo: notchFrame,
            restingHeight: max(notchFrame.height, 12)
        )
    }

    nonisolated static func bubbleWindowFrame(
        adjacentTo notchFrame: CGRect,
        display: DisplayDescriptor
    ) -> CGRect {
        bubbleWindowFrame(
            adjacentTo: notchFrame,
            restingHeight: max(display.anchor.rect.height, 12)
        )
    }

    nonisolated static func bubbleWindowFrame(envelope: CGRect) -> CGRect {
        bubbleWindowFrame(adjacentTo: envelope)
    }

    nonisolated static func bubbleRestingLeadingInset(envelope: CGRect) -> CGFloat {
        _ = envelope
        return attachOverlap + splitGap
    }

    nonisolated static func bubbleAttachedLeadingInset() -> CGFloat {
        3
    }
}
