import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
final class NotchWindowController: NSWindowController {
    enum SurfaceState: Equatable {
        case collapsed
        case hovered
        case musicPreview
        case expanded
    }

    let display: DisplayDescriptor
    var onOpenSettings: (() -> Void)?
    /// When true (e.g. settings window is frontmost), outside clicks must not
    /// collapse the expanded notch so the user can preview live changes.
    var isOutsideCollapseSuppressed: (() -> Bool)?

    private let model = OverlayPresentationModel()
    private let settingsStore: SettingsStore
    private let trayStore: TrayStore
    private let spotifyMusicStore: SpotifyMusicStore
    private let taskStore: TaskStore
    private let calendarStore: CalendarStore
    private let agentMonitorStore: AgentMonitorStore
    private let liveActivityCenter: LiveActivityCenter
    private let logger = AppLogger.window
    private var spotifyPlaybackCancellable: AnyCancellable?
    private var liveActivityCancellable: AnyCancellable?
    private var agentMonitorCancellable: AnyCancellable?
    private var surfaceHostView: SolidBlackNotchHostingView<OverlaySurfaceView>?
    private var bubbleController: DynamicIslandBubbleController?
    private var physicalGuide: PhysicalNotchGuideController?
    private var geometryAnimator: NotchGeometryAnimator?
    private(set) var state: SurfaceState = .collapsed

    init(
        display: DisplayDescriptor,
        settingsStore: SettingsStore,
        trayStore: TrayStore,
        spotifyMusicStore: SpotifyMusicStore,
        taskStore: TaskStore,
        calendarStore: CalendarStore,
        agentMonitorStore: AgentMonitorStore,
        liveActivityCenter: LiveActivityCenter
    ) {
        self.display = display
        self.settingsStore = settingsStore
        self.trayStore = trayStore
        self.spotifyMusicStore = spotifyMusicStore
        self.taskStore = taskStore
        self.calendarStore = calendarStore
        self.agentMonitorStore = agentMonitorStore
        self.liveActivityCenter = liveActivityCenter

        let initialFrame = Self.windowFrame(for: .collapsed, display: display)
        let panel = NotchPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 1
        panel.colorSpace = .sRGB
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        let hostingView = SolidBlackNotchHostingView(
            rootView: OverlaySurfaceView(
                model: model,
                settingsStore: settingsStore,
                trayStore: trayStore,
                spotifyMusicStore: spotifyMusicStore,
                taskStore: taskStore,
                calendarStore: calendarStore,
                agentMonitorStore: agentMonitorStore
            )
        )
        let collapsedRadii = Self.surfaceRadii(for: .collapsed)
        let initialVisual = Self.frame(for: .collapsed, display: display)
        let initialChrome = Self.windowFrame(
            for: .collapsed,
            display: display
        )
        let initialOffsetX = Self.contentOffsetX(
            visual: initialVisual,
            contentWidth: initialVisual.width,
            chrome: initialChrome
        )
        hostingView.setSurfaceAppearance(
            bottomRadius: collapsedRadii.bottom,
            shoulderRadius: collapsedRadii.shoulder,
            trailingShoulderRadius: collapsedRadii.shoulder,
            contentWidth: initialVisual.width,
            contentHeight: initialVisual.height,
            contentOffsetX: initialOffsetX
        )
        panel.contentView = hostingView

        super.init(window: panel)
        surfaceHostView = hostingView
        let initialMetrics = PresentationMetrics(
            frame: initialChrome,
            contentWidth: initialVisual.width,
            contentHeight: initialVisual.height,
            contentOffsetX: initialOffsetX,
            bottomRadius: collapsedRadii.bottom,
            shoulderRadius: collapsedRadii.shoulder,
            trailingShoulderRadius: collapsedRadii.shoulder,
            horizontalScale: 1,
            glowOpacity: 0
        )
        let animator = NotchGeometryAnimator(initial: initialMetrics)
        animator.onApply = { [weak self] metrics in
            self?.applyPresentedMetrics(metrics)
        }
        animator.onComplete = { [weak self] metrics in
            self?.handleGeometryAnimationCompleted(metrics)
        }
        geometryAnimator = animator
        model.bottomRadius = collapsedRadii.bottom
        model.shoulderRadius = collapsedRadii.shoulder
        model.trailingShoulderRadius = collapsedRadii.shoulder
        model.horizontalScale = 1
        model.glowOpacity = 0
        model.contentWidth = initialVisual.width
        model.contentHeight = initialVisual.height
        model.contentOffsetX = initialOffsetX
        model.onToggle = { [weak self] in self?.toggle() }
        model.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        spotifyPlaybackCancellable = spotifyMusicStore.$hasActiveTrack
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] hasActiveTrack in
                guard let self else { return }
                self.logger.debug(
                    "Spotify compact source changed: \(hasActiveTrack, privacy: .public)"
                )
                if !hasActiveTrack, self.state == .musicPreview {
                    self.transition(to: .collapsed)
                } else {
                    self.refreshGeometry(showsNowPlaying: hasActiveTrack)
                }
            }

        bubbleController = DynamicIslandBubbleController(
            anchorHeight: display.anchor.rect.height
        )
        physicalGuide = PhysicalNotchGuideController()
        liveActivityCancellable = liveActivityCenter.$activity
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] activity in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let shouldShow = activity != nil && self.state != .expanded
                    let presenceChanged = self.model.showsLiveActivity != shouldShow
                    self.model.showsLiveActivity = shouldShow
                    // Activity color/count changes must update the bubble without
                    // waiting for a hover-driven geometry pass.
                    if presenceChanged {
                        self.refreshGeometry()
                    } else {
                        self.updateBubble(activity: activity, duration: 0.22)
                    }
                    self.surfaceHostView?.needsDisplay = true
                    self.surfaceHostView?.displayIfNeeded()
                }
            }

        agentMonitorCancellable = agentMonitorStore.$renderEpoch
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Expanded agents counters live in PassiveHostingView — kick a
                    // display pass so numbers refresh without pointer motion.
                    self.surfaceHostView?.needsDisplay = true
                    self.surfaceHostView?.layer?.setNeedsDisplay()
                    self.surfaceHostView?.displayIfNeeded()
                    self.window?.contentView?.needsDisplay = true
                    self.window?.displayIfNeeded()
                }
            }
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showCollapsed() {
        transition(to: .collapsed)
        window?.orderFrontRegardless()
        physicalGuide?.show(
            physicalFrame: DynamicIslandLayout.physicalNotchFrame(display: display),
            relativeTo: window
        )
        // Attach SwiftUI after several display cycles so AppKit's constraint
        // flush at launch cannot see an NSHostingView yet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.surfaceHostView?.attachHostingWhenReady()
        }
    }

    override func close() {
        physicalGuide?.close()
        bubbleController?.close()
        super.close()
    }

    private var showsLiveActivity: Bool {
        liveActivityCenter.activity != nil && state != .expanded
    }

    /// Parks the DI bubble on the physical cutout — fixed screen position.
    private func updateBubble(activity: LiveActivity?, duration: TimeInterval) {
        let physical = DynamicIslandLayout.physicalNotchFrame(display: display)
        // Always park against the hardware maxX / resting height so Music hover
        // and preview never drag the pill around the menu bar.
        let parkFrame = CGRect(
            x: physical.minX,
            y: physical.minY,
            width: physical.width,
            height: physical.height
        )
        bubbleController?.update(
            activity: activity,
            notchFrame: parkFrame,
            restingHeight: max(physical.height, 12),
            notchWindow: window,
            isNotchExpanded: state == .expanded,
            animationDuration: duration
        )
        physicalGuide?.show(
            physicalFrame: physical,
            relativeTo: window
        )
    }

    func showExpanded() {
        transition(to: .expanded)
        window?.orderFrontRegardless()
    }

    func toggle() {
        transition(to: state == .expanded ? .collapsed : .expanded)
        window?.orderFrontRegardless()
    }

    func refreshGeometry(showsNowPlaying: Bool? = nil) {
        commitPresentation(to: state, showsNowPlaying: showsNowPlaying)
    }

    func handlePointerDown(at point: CGPoint) {
        guard let window else { return }

        if state != .expanded,
           Self.shouldExpand(
               state: state,
               panelFrame: Self.frame(
                   for: state,
                   display: display,
                   expandedWidth: settingsStore.expandedWidth,
                   showsNowPlaying: spotifyMusicStore.hasActiveTrack,
                   showsLiveActivity: showsLiveActivity
               ),
               excludedControlFrame: playbackControlFrame(in: window.frame),
               pointerLocation: point
           ) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state != .expanded else { return }
                self.showExpanded()
            }
            return
        }

        if Self.shouldCollapse(
            state: state,
            isTrayMode: model.selectedTab == .tray,
            suppressOutsideCollapse: isOutsideCollapseSuppressed?() ?? false,
            panelFrame: window.frame,
            pointerLocation: point
        ) {
            showCollapsed()
        }
    }

    static func shouldExpand(
        state: SurfaceState,
        panelFrame: CGRect,
        excludedControlFrame: CGRect? = nil,
        pointerLocation: CGPoint
    ) -> Bool {
        state != .expanded
            && panelFrame.contains(pointerLocation)
            && !(excludedControlFrame?.contains(pointerLocation) ?? false)
    }

    static func shouldCollapse(
        state: SurfaceState,
        isTrayMode: Bool = false,
        suppressOutsideCollapse: Bool = false,
        panelFrame: CGRect,
        pointerLocation: CGPoint
    ) -> Bool {
        state == .expanded
            && !isTrayMode
            && !suppressOutsideCollapse
            && !panelFrame.contains(pointerLocation)
    }

    var interactionZone: InteractionZone {
        InteractionZone(
            collapsedRect: Self.frame(
                for: .collapsed,
                display: display,
                showsNowPlaying: false,
                showsLiveActivity: showsLiveActivity
            )
                .insetBy(dx: -10, dy: -8),
            hoverRect: Self.frame(
                for: .hovered,
                display: display,
                showsNowPlaying: spotifyMusicStore.hasActiveTrack,
                showsLiveActivity: showsLiveActivity
            )
                .insetBy(dx: -12, dy: -10)
        )
    }

    func containsHoverPoint(_ point: CGPoint) -> Bool {
        switch state {
        case .collapsed:
            interactionZone.collapsedRect.contains(point)
        case .hovered:
            interactionZone.hoverRect.contains(point)
        case .musicPreview:
            Self.frame(
                for: .musicPreview,
                display: display,
                showsNowPlaying: true,
                showsLiveActivity: showsLiveActivity
            )
            .insetBy(dx: -12, dy: -10)
            .contains(point)
        case .expanded:
            false
        }
    }

    static func musicArtworkHoverFrame(in collapsedFrame: CGRect) -> CGRect {
        let slot = NowPlayingLayout.sideSlotWidth
        return CGRect(
            x: collapsedFrame.minX,
            y: collapsedFrame.maxY - max(slot + 8, 40),
            width: slot,
            height: max(slot + 8, 40)
        )
    }

    private func containsMusicArtworkPoint(_ point: CGPoint) -> Bool {
        let artworkSurfaceState: SurfaceState = state == .hovered ? .hovered : .collapsed
        let artworkSurfaceFrame = Self.frame(
            for: artworkSurfaceState,
            display: display,
            showsNowPlaying: true,
            showsLiveActivity: showsLiveActivity
        )
        return Self.musicArtworkHoverFrame(in: artworkSurfaceFrame).contains(point)
    }

    private func playbackControlFrame(in panelFrame: CGRect) -> CGRect? {
        // When the island is split the right slot belongs to the live-activity
        // bubble, so there is no in-notch playback hit target.
        guard spotifyMusicStore.hasActiveTrack,
              !showsLiveActivity,
              state == .collapsed || state == .musicPreview else { return nil }
        return CGRect(
            x: panelFrame.maxX - 46,
            y: panelFrame.maxY - 36,
            width: 46,
            height: 36
        )
    }

    /// Returns true only for a new pointer entry, so haptics fire once per entry.
    @discardableResult
    func setHoverActive(_ isActive: Bool, at point: CGPoint = .zero) -> Bool {
        switch (state, isActive) {
        case (.collapsed, true):
            if spotifyMusicStore.hasActiveTrack {
                transition(
                    to: containsMusicArtworkPoint(point)
                        ? .musicPreview
                        : .hovered
                )
                return true
            }
            transition(to: .hovered)
            return true
        case (.hovered, true):
            if spotifyMusicStore.hasActiveTrack, containsMusicArtworkPoint(point) {
                transition(to: .musicPreview)
            }
        case (.hovered, false), (.musicPreview, false):
            transition(to: .collapsed)
        default:
            break
        }
        return false
    }

    private func transition(to newState: SurfaceState) {
        guard newState != state || window?.isVisible != true else { return }
        commitPresentation(to: newState)
        logger.debug(
            "Surface transitioned to \(String(describing: newState), privacy: .public)"
        )
    }

    /// Single entry point for every geometry / silhouette change. Always
    /// supersedes any in-flight animation from the currently presented metrics.
    private func commitPresentation(
        to newState: SurfaceState,
        showsNowPlaying: Bool? = nil
    ) {
        let showsNowPlaying = showsNowPlaying ?? spotifyMusicStore.hasActiveTrack
        let liveActivity = liveActivityCenter.activity != nil && newState != .expanded
        let target = presentationMetrics(
            for: newState,
            showsNowPlaying: showsNowPlaying,
            showsLiveActivity: liveActivity
        )

        state = newState
        let previousSurface = model.surfaceState
        let openingExpanded = newState == .expanded && previousSurface != .expanded
        let closingExpanded = previousSurface == .expanded && newState != .expanded

        let surfaceState = newState
        let liveActivityFlag = liveActivity
        let swiftUIMetrics = target

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = AnimationSpring.windowFrameDuration(
            for: newState,
            reduceMotion: reduceMotion
        )

        if openingExpanded {
            // Prepare expanded UI immediately but keep it invisible; the shared
            // CALayer mask grows with the black shell, then we fade content in
            // over the same duration so components don't outrun the frame.
            surfaceHostView?.setContentAlpha(0, animated: false)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.model.surfaceState = surfaceState
                self.model.showsLiveActivity = liveActivityFlag
                self.syncSwiftUIMetrics(swiftUIMetrics)
            }
            pendingSwiftUIReveal = PendingSwiftUIReveal(
                surfaceState: surfaceState,
                showsLiveActivity: liveActivityFlag,
                metrics: swiftUIMetrics,
                fadeIn: true,
                fadeDuration: duration
            )
        } else if closingExpanded {
            // Hide expanded components at once, swap to compact, shrink shell,
            // then fade compact content back in.
            surfaceHostView?.setContentAlpha(0, animated: false)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.model.surfaceState = surfaceState
                self.model.showsLiveActivity = liveActivityFlag
                self.syncSwiftUIMetrics(swiftUIMetrics)
            }
            pendingSwiftUIReveal = PendingSwiftUIReveal(
                surfaceState: surfaceState,
                showsLiveActivity: liveActivityFlag,
                metrics: swiftUIMetrics,
                fadeIn: true,
                fadeDuration: min(0.14, duration)
            )
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.model.surfaceState != surfaceState {
                    self.model.surfaceState = surfaceState
                }
                if self.model.showsLiveActivity != liveActivityFlag {
                    self.model.showsLiveActivity = liveActivityFlag
                }
                self.syncSwiftUIMetrics(swiftUIMetrics)
                self.surfaceHostView?.setContentAlpha(1, animated: false)
            }
            pendingSwiftUIReveal = nil
        }

        if let animator = geometryAnimator {
            animator.commit(target, duration: duration)
        } else {
            applyPresentedMetrics(target)
            handleGeometryAnimationCompleted(target)
        }

        if openingExpanded {
            // Start the fade in parallel with the silhouette morph.
            surfaceHostView?.setContentAlpha(1, animated: duration > 0, duration: duration)
            pendingSwiftUIReveal = nil
        }

        updateBubble(activity: liveActivityCenter.activity, duration: duration)
    }

    private struct PendingSwiftUIReveal {
        var surfaceState: SurfaceState
        var showsLiveActivity: Bool
        var metrics: PresentationMetrics
        var fadeIn: Bool
        var fadeDuration: TimeInterval
    }

    private var pendingSwiftUIReveal: PendingSwiftUIReveal?

    private func handleGeometryAnimationCompleted(_ metrics: PresentationMetrics) {
        applyPresentedMetrics(metrics)
        guard let pending = pendingSwiftUIReveal else { return }
        pendingSwiftUIReveal = nil

        let reveal = pending
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.model.surfaceState != reveal.surfaceState {
                self.model.surfaceState = reveal.surfaceState
            }
            if self.model.showsLiveActivity != reveal.showsLiveActivity {
                self.model.showsLiveActivity = reveal.showsLiveActivity
            }
            self.syncSwiftUIMetrics(reveal.metrics)
            self.surfaceHostView?.setContentAlpha(
                1,
                animated: reveal.fadeIn && reveal.fadeDuration > 0,
                duration: reveal.fadeDuration
            )
        }
    }

    private func syncSwiftUIMetrics(_ metrics: PresentationMetrics) {
        if abs(model.bottomRadius - metrics.bottomRadius) > 0.05 {
            model.bottomRadius = metrics.bottomRadius
        }
        if abs(model.shoulderRadius - metrics.shoulderRadius) > 0.05 {
            model.shoulderRadius = metrics.shoulderRadius
        }
        if abs(model.trailingShoulderRadius - metrics.trailingShoulderRadius) > 0.05 {
            model.trailingShoulderRadius = metrics.trailingShoulderRadius
        }
        if abs(model.horizontalScale - metrics.horizontalScale) > 0.01 {
            model.horizontalScale = metrics.horizontalScale
        }
        if abs(model.glowOpacity - metrics.glowOpacity) > 0.05 {
            model.glowOpacity = metrics.glowOpacity
        }
        if abs(model.contentWidth - metrics.contentWidth) > 0.5 {
            model.contentWidth = metrics.contentWidth
        }
        if abs(model.contentHeight - metrics.contentHeight) > 0.5 {
            model.contentHeight = metrics.contentHeight
        }
        if abs(model.contentOffsetX - metrics.contentOffsetX) > 0.5 {
            model.contentOffsetX = metrics.contentOffsetX
        }
    }

    private func presentationMetrics(
        for state: SurfaceState,
        showsNowPlaying: Bool,
        showsLiveActivity: Bool
    ) -> PresentationMetrics {
        let radii = Self.surfaceRadii(for: state)
        let showsGlow = state == .hovered || state == .musicPreview
        let visual = Self.frame(
            for: state,
            display: display,
            expandedWidth: settingsStore.expandedWidth,
            showsNowPlaying: showsNowPlaying,
            showsLiveActivity: showsLiveActivity
        )
        let chrome = Self.windowFrame(
            for: state,
            display: display,
            expandedWidth: settingsStore.expandedWidth,
            showsNowPlaying: showsNowPlaying,
            showsLiveActivity: showsLiveActivity
        )
        let scale = Self.surfaceHorizontalScale(
            for: state,
            showsNowPlaying: showsNowPlaying,
            showsLiveActivity: showsLiveActivity
        )
        let drawnWidth = visual.width * scale
        let pinTrailing = showsLiveActivity && showsNowPlaying
        let musicStable = showsNowPlaying && state != .expanded
        let stableShoulder = DynamicIslandLayout.musicStableShoulder
        // Keep music side shoulders fixed so artwork / playback stay visually
        // centered in the overhang while the notch only grows downward.
        let leadingShoulder = musicStable ? stableShoulder : radii.shoulder
        let trailingShoulder = pinTrailing
            ? 0
            : (musicStable ? stableShoulder : radii.shoulder)
        return PresentationMetrics(
            frame: chrome,
            contentWidth: drawnWidth,
            contentHeight: visual.height,
            contentOffsetX: Self.contentOffsetX(
                visual: visual,
                contentWidth: drawnWidth,
                chrome: chrome,
                pinTrailing: pinTrailing
            ),
            bottomRadius: radii.bottom,
            shoulderRadius: leadingShoulder,
            trailingShoulderRadius: trailingShoulder,
            horizontalScale: scale,
            glowOpacity: showsGlow ? 1 : 0
        )
    }

    private func applyPresentedMetrics(_ metrics: PresentationMetrics) {
        guard let window else { return }

        // Window chrome is normally stable (expanded size). Prefer skipping
        // setFrame entirely — even a no-op-ish resize re-enters constraint
        // updates when any NSHostingView is (or was) in the hierarchy.
        if !framesEqual(window.frame, metrics.frame) {
            surfaceHostView?.detachHostingForResize()
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            NSAnimationContext.current.allowsImplicitAnimation = false
            window.setFrame(metrics.frame, display: false)
            NSAnimationContext.endGrouping()
            surfaceHostView?.attachHostingAfterResize()
        }

        surfaceHostView?.setSurfaceAppearance(
            bottomRadius: metrics.bottomRadius,
            shoulderRadius: metrics.shoulderRadius,
            trailingShoulderRadius: metrics.trailingShoulderRadius,
            contentWidth: metrics.contentWidth,
            contentHeight: metrics.contentHeight,
            contentOffsetX: metrics.contentOffsetX
        )
        // SwiftUI metrics are synced once per transition in commitPresentation.
        // Do not publish per-tick sizes/radii here.
    }

    private func framesEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.05
            && abs(lhs.origin.y - rhs.origin.y) < 0.05
            && abs(lhs.size.width - rhs.size.width) < 0.05
            && abs(lhs.size.height - rhs.size.height) < 0.05
    }

    /// Leading inset of the drawn body inside the chrome window.
    ///
    /// - Default: center the drawn width inside `visual` (music scale 280/300).
    /// - `pinTrailing`: lock the drawn body's maxX to `visual.maxX` so Music+DI
    ///   stays flush with the physical notch's right edge through animation.
    static func contentOffsetX(
        visual: CGRect,
        contentWidth: CGFloat,
        chrome: CGRect,
        pinTrailing: Bool = false
    ) -> CGFloat {
        let drawnWidth = max(contentWidth, 1)
        let drawnMinX: CGFloat
        if pinTrailing {
            drawnMinX = visual.maxX - drawnWidth
        } else {
            drawnMinX = visual.midX - drawnWidth / 2
        }
        return drawnMinX - chrome.minX
    }

    /// Window chrome for a state. Always uses the expanded rect so compact
    /// hover / click-to-open never resize the NSWindow. Resizing a SwiftUI
    /// hosting surface on macOS 26 fatally re-enters Update Constraints.
    static func windowFrame(
        for state: SurfaceState,
        display: DisplayDescriptor,
        expandedWidth: Double = 760,
        showsNowPlaying: Bool = false,
        showsLiveActivity: Bool = false
    ) -> CGRect {
        _ = state
        _ = showsNowPlaying
        _ = showsLiveActivity
        return frame(
            for: .expanded,
            display: display,
            expandedWidth: expandedWidth,
            showsNowPlaying: false,
            showsLiveActivity: false
        )
    }

    static func frame(
        for state: SurfaceState,
        display: DisplayDescriptor,
        expandedWidth: Double = 760,
        showsNowPlaying: Bool = false,
        showsLiveActivity: Bool = false
    ) -> CGRect {
        if state == .expanded {
            let baseWidth = min(
                max(CGFloat(expandedWidth), CGFloat(SettingsStore.minimumExpandedWidth)),
                display.frame.width - 48
            )
            return CGRect(
                x: display.frame.midX - baseWidth / 2,
                y: display.frame.maxY - 204,
                width: baseWidth,
                height: 204
            ).integral
        }

        let envelope = DynamicIslandLayout.compactEnvelope(
            for: state,
            display: display,
            showsNowPlaying: showsNowPlaying,
            showsLiveActivity: showsLiveActivity
        )
        return DynamicIslandLayout.mainNotchFrame(
            envelope: envelope,
            display: display,
            showsLiveActivity: showsLiveActivity,
            showsNowPlaying: showsNowPlaying
        )
    }

    nonisolated static func surfaceRadii(for state: SurfaceState) -> (bottom: CGFloat, shoulder: CGFloat) {
        switch state {
        case .collapsed:
            (8, 7)
        case .hovered:
            (13, 11)
        case .musicPreview:
            (22, 16)
        case .expanded:
            (30, 18)
        }
    }

    static func surfaceHorizontalScale(
        for state: SurfaceState,
        showsNowPlaying: Bool,
        showsLiveActivity: Bool = false
    ) -> CGFloat {
        // The classic music capsule slightly under-fills the window. When the
        // island is split the window already matches the shortened body, so
        // keep scale at 1 to avoid double-shrinking the right edge.
        guard state == .collapsed, showsNowPlaying, !showsLiveActivity else { return 1 }
        return 280 / 300
    }
}

// MARK: - Spring animation parameters

struct AnimationSpring {
    /// CASpringAnimation damping ratio (0..1, 1 = critically damped)
    let dampingRatio: Double
    /// Angular frequency of the spring
    let stiffness: Double
    let mass: Double

    /// Fixed window-frame durations from the product spec — hover grows
    /// sideways/down in ~0.14s, music preview ~0.22s, open ~0.28s.
    /// Every silhouette property (radii, scale, glow) shares this duration.
    static func windowFrameDuration(
        for state: NotchWindowController.SurfaceState,
        reduceMotion: Bool
    ) -> TimeInterval {
        if reduceMotion { return 0.1 }
        switch state {
        case .collapsed, .hovered:
            return 0.14
        case .musicPreview:
            return 0.22
        case .expanded:
            return 0.28
        }
    }

    static func forState(_ state: NotchWindowController.SurfaceState) -> AnimationSpring {
        switch state {
        case .expanded:
            return AnimationSpring(dampingRatio: 0.72, stiffness: 380, mass: 1.0)
        case .collapsed:
            return AnimationSpring(dampingRatio: 0.90, stiffness: 560, mass: 1.0)
        case .hovered:
            return AnimationSpring(dampingRatio: 0.82, stiffness: 460, mass: 1.0)
        case .musicPreview:
            return AnimationSpring(dampingRatio: 0.78, stiffness: 420, mass: 1.0)
        }
    }
}

@MainActor
private final class OverlayPresentationModel: ObservableObject {
    enum ExpandedTab: Equatable {
        case notch
        case tray
    }

    @Published var surfaceState: NotchWindowController.SurfaceState = .collapsed
    @Published var selectedTab: ExpandedTab = .notch
    /// True while the right Dynamic Island pill is detached — the compact
    /// music surface hides its right-side playback indicator so that slot
    /// belongs to the live-activity bubble.
    @Published var showsLiveActivity = false
    /// Live silhouette metrics driven by `NotchGeometryAnimator` so SwiftUI
    /// clip / glow stay locked to the native black body.
    @Published var bottomRadius: CGFloat = 8
    @Published var shoulderRadius: CGFloat = 7
    @Published var trailingShoulderRadius: CGFloat = 7
    @Published var horizontalScale: CGFloat = 1
    @Published var glowOpacity: CGFloat = 0
    /// Drawn compact silhouette size inside the always-expanded window chrome.
    @Published var contentWidth: CGFloat = 120
    @Published var contentHeight: CGFloat = 32
    @Published var contentOffsetX: CGFloat = 0
    var onToggle: (() -> Void)?
    var onOpenSettings: (() -> Void)?
}

private struct OverlaySurfaceView: View {
    @ObservedObject var model: OverlayPresentationModel
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var trayStore: TrayStore
    @ObservedObject var spotifyMusicStore: SpotifyMusicStore
    @ObservedObject var taskStore: TaskStore
    @ObservedObject var calendarStore: CalendarStore
    @ObservedObject var agentMonitorStore: AgentMonitorStore

    var body: some View {
        let shape = NotchSurfaceShape(
            bottomRadius: model.bottomRadius,
            leadingShoulderRadius: model.shoulderRadius,
            trailingShoulderRadius: model.trailingShoulderRadius
        )

        // Window chrome stays at expanded size; compact UI is laid out in a
        // top-centered content rect so click-to-expand never resizes NSHosting*.
        Group {
            if model.surfaceState == .expanded {
                expandedChrome(shape: shape)
            } else {
                compactChrome(shape: shape)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    private func expandedChrome(shape: NotchSurfaceShape) -> some View {
        ZStack(alignment: .top) {
            surfaceContent
            if settingsStore.rainbowGlowEnabled, model.glowOpacity > 0.01 {
                RainbowNotchOutline(
                    bottomRadius: model.bottomRadius,
                    leadingShoulderRadius: model.shoulderRadius,
                    trailingShoulderRadius: model.trailingShoulderRadius
                )
                .opacity(model.glowOpacity)
            }
        }
        .clipShape(shape)
        .contentShape(shape)
    }

    private func compactChrome(shape: NotchSurfaceShape) -> some View {
        // Layout snaps to the transition target; CALayer mask morphs the
        // visible silhouette. Avoid clipShape/size animation driven each tick.
        let body = ZStack(alignment: .top) {
            surfaceContent

            if settingsStore.rainbowGlowEnabled, model.glowOpacity > 0.01 {
                RainbowNotchOutline(
                    bottomRadius: model.bottomRadius,
                    leadingShoulderRadius: model.shoulderRadius,
                    trailingShoulderRadius: model.trailingShoulderRadius
                )
                .scaleEffect(x: model.horizontalScale, y: 1, anchor: .center)
                .opacity(model.glowOpacity)
            }
        }
        .frame(
            width: max(model.contentWidth, 1),
            height: max(model.contentHeight, 1)
        )
        .contentShape(shape)
        .gesture(
            TapGesture().onEnded {
                model.onToggle?()
            },
            including: usesMusicTapZones ? .subviews : .all
        )

        return HStack(spacing: 0) {
            Spacer()
                .frame(width: max(model.contentOffsetX, 0))
            body
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var usesMusicTapZones: Bool {
        spotifyMusicStore.hasActiveTrack
            && !model.showsLiveActivity
            && (model.surfaceState == .collapsed || model.surfaceState == .musicPreview)
    }

    @ViewBuilder
    private var surfaceContent: some View {
        if model.surfaceState == .expanded {
            expandedSurface
        } else {
            ZStack {
                if spotifyMusicStore.hasActiveTrack {
                    NowPlayingSurface(
                        store: spotifyMusicStore,
                        isPreviewExpanded: model.surfaceState == .musicPreview,
                        showsLiveActivity: model.showsLiveActivity,
                        onOpen: { model.onToggle?() }
                    )
                }
            }
        }
    }

    private var expandedSurface: some View {
        ZStack(alignment: .topTrailing) {
            expandedContent

            VStack(alignment: .trailing, spacing: 3) {
                Button {
                    model.onOpenSettings?()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Otwórz ustawienia")

                if model.selectedTab == .tray {
                    Button {
                        model.onToggle?()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                            Text("Close")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .offset(y: -2)
                    .accessibilityLabel("Zamknij Tray")
                }
            }
            .padding(.top, 14)
            .padding(.trailing, 18)
        }
    }

    private var expandedContent: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(.white.opacity(0.16))
                .frame(width: 76, height: 4)

            HStack(spacing: 4) {
                tabButton(title: "Notch", tab: .notch)
                tabButton(title: "Tray", tab: .tray)
                Spacer()
            }
            .padding(.trailing, 42)

            Group {
                switch model.selectedTab {
                case .notch:
                    configuredComponents
                case .tray:
                    TrayView(store: trayStore)
                }
            }
            .transition(.opacity)

        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private func tabButton(
        title: String,
        tab: OverlayPresentationModel.ExpandedTab
    ) -> some View {
        let isSelected = model.selectedTab == tab

        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                model.selectedTab = tab
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.48))
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(
                    isSelected ? .white.opacity(0.12) : .clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var configuredComponents: some View {
        GeometryReader { geometry in
            let components = settingsStore.components
            let dividerWidth: CGFloat = 17
            let totalDividerWidth = dividerWidth * CGFloat(max(components.count - 1, 0))
            let availableWidth = max(geometry.size.width - totalDividerWidth, 1)
            let totalWeight = max(components.reduce(0) { $0 + $1.widthWeight }, 0.5)

            HStack(spacing: 0) {
                ForEach(Array(components.enumerated()), id: \.element.id) { index, component in
                    componentCard(component)
                        .frame(
                            width: availableWidth * CGFloat(component.widthWeight / totalWeight)
                        )

                    if index < components.count - 1 {
                        PanelComponentDivider()
                            .frame(width: dividerWidth)
                    }
                }
            }
        }
        .frame(height: 112)
    }

    @ViewBuilder
    private func componentCard(_ component: PanelComponentConfiguration) -> some View {
        if component.kind == .media {
            MusicComponentView(store: spotifyMusicStore)
        } else if component.kind == .shortcuts {
            ShortcutsComponentView(buttons: settingsStore.shortcutButtons)
        } else if component.kind == .tasks {
            TaskComponentView(store: taskStore)
        } else if component.kind == .calendar {
            CalendarComponentView(store: calendarStore)
        } else if component.kind == .agents {
            AgentMonitorComponentView(store: agentMonitorStore)
        } else {
            HStack(spacing: 10) {
                Image(systemName: component.kind.iconName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(red: 0.64, green: 0.57, blue: 1))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.kind.title).font(.system(size: 13, weight: .semibold))
                    Text(component.kind.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            }
        }
    }
}

private struct NowPlayingSurface: View {
    @ObservedObject var store: SpotifyMusicStore
    let isPreviewExpanded: Bool
    let showsLiveActivity: Bool
    let onOpen: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    Button(action: onOpen) {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 46)
                    .frame(maxHeight: .infinity)
                    .accessibilityLabel("Otwórz pełny notch")

                    Button(action: onOpen) {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Otwórz pełny notch")

                    if !showsLiveActivity {
                        VStack(spacing: 0) {
                            Button {
                                store.perform(.playPause)
                            } label: {
                                Color.clear
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(height: 36)
                            .accessibilityLabel(store.track.isPlaying ? "Wstrzymaj" : "Odtwórz")

                            Button(action: onOpen) {
                                Color.clear
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(maxHeight: .infinity)
                            .accessibilityHidden(true)
                        }
                        .frame(width: 46)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(2)

                artwork
                    .frame(
                        width: NowPlayingLayout.artworkSize(isPreviewExpanded: isPreviewExpanded),
                        height: NowPlayingLayout.artworkSize(isPreviewExpanded: isPreviewExpanded)
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: isPreviewExpanded ? 10 : 6,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: isPreviewExpanded ? 10 : 6,
                            style: .continuous
                        )
                        .stroke(.white.opacity(0.18), lineWidth: 0.8)
                    }
                    // Fixed X in the left overhang slot; grows downward from a
                    // fixed top inset so hover-only height growth never shifts it.
                    .position(
                        x: NowPlayingLayout.artworkCenterX,
                        y: NowPlayingLayout.artworkCenterY(
                            isPreviewExpanded: isPreviewExpanded
                        )
                    )
                    .animation(
                        .spring(response: 0.34, dampingFraction: 0.8),
                        value: isPreviewExpanded
                    )
                    .allowsHitTesting(false)

                if !showsLiveActivity {
                    CompactPlaybackIndicator(isPlaying: store.track.isPlaying)
                        .frame(width: 24, height: 24)
                        // Anchored to the right overhang — position stays put
                        // while the notch grows down on hover / preview.
                        .position(
                            x: geometry.size.width - NowPlayingLayout.playbackRightInset,
                            y: NowPlayingLayout.playbackCenterY
                        )
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                MarqueeTrackInfo(
                    text: trackSummary,
                    isActive: isPreviewExpanded
                )
                    .frame(
                        width: max(
                            geometry.size.width - NowPlayingLayout.marqueeHorizontalInset * 2,
                            1
                        ),
                        alignment: .leading
                    )
                    .offset(
                        x: NowPlayingLayout.marqueeHorizontalInset,
                        y: NowPlayingLayout.marqueeTop(
                            isPreviewExpanded: isPreviewExpanded
                        )
                    )
                    .opacity(isPreviewExpanded ? 1 : 0)
                    .animation(
                        .easeOut(duration: 0.18).delay(isPreviewExpanded ? 0.08 : 0),
                        value: isPreviewExpanded
                    )
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Mini odtwarzacz: \(store.track.title), album \(store.track.album), autor \(store.track.artist)"
        )
    }

    private var trackSummary: String {
        [store.track.title, store.track.album, store.track.artist]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "   •   ")
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = store.track.artworkData,
           let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .id(store.track.artworkURL)
                .transition(.opacity)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.1))
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
        }
    }
}

enum NowPlayingLayout {
    /// Music expands by `compactExtraWidth` centered on the physical notch, so
    /// each side slot is `compactExtraWidth / 2`.
    static var sideSlotWidth: CGFloat {
        DynamicIslandLayout.compactExtraWidth / 2
    }

    /// Leading shoulder stays at the collapsed music value, so the visible
    /// left wall is inset by this amount from the rendered frame.
    static var leadingShoulder: CGFloat {
        DynamicIslandLayout.musicStableShoulder
    }

    /// Center of the visible left overhang: between the black body's left wall
    /// (after the shoulder) and the physical cutout's left edge.
    static var sideSlotCenterInset: CGFloat {
        leadingShoulder + (sideSlotWidth - leadingShoulder) / 2
    }

    static let artworkTopInset: CGFloat = 3
    static let collapsedArtworkSize: CGFloat = 24
    /// Slight bump on artwork hover — must stay inside the visible left slot.
    static let previewArtworkSize: CGFloat = 30
    static let playbackCenterY: CGFloat = 14
    /// Full-bleed marquee under the artwork — small inset from both edges.
    static let marqueeHorizontalInset: CGFloat = 10

    static func artworkSize(isPreviewExpanded: Bool) -> CGFloat {
        isPreviewExpanded ? previewArtworkSize : collapsedArtworkSize
    }

    static var artworkCenterX: CGFloat {
        sideSlotCenterInset
    }

    static func artworkCenterX(isPreviewExpanded: Bool) -> CGFloat {
        _ = isPreviewExpanded
        return artworkCenterX
    }

    static func artworkCenterY(isPreviewExpanded: Bool) -> CGFloat {
        artworkTopInset + artworkSize(isPreviewExpanded: isPreviewExpanded) / 2
    }

    static var playbackRightInset: CGFloat {
        // Mirror of the left slot center, measured from the trailing edge.
        // With a flat trailing shoulder (Music+DI) this is sideSlotWidth/2;
        // with a stable music shoulder it's the same formula from the right.
        leadingShoulder + (sideSlotWidth - leadingShoulder) / 2
    }

    /// Marquee sits just under the (possibly expanded) artwork.
    static func marqueeTop(isPreviewExpanded: Bool) -> CGFloat {
        artworkTopInset
            + artworkSize(isPreviewExpanded: isPreviewExpanded)
            + 8
    }
}

private struct MarqueeTrackInfo: View {
    let text: String
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cycleStartedAt = Date()

    var body: some View {
        GeometryReader { geometry in
            TimelineView(
                .animation(
                    minimumInterval: 1 / 30,
                    paused: !isActive || reduceMotion
                )
            ) { timeline in
                let contentWidth = MarqueeMetrics.contentWidth(for: text)
                let loopSpacing = MarqueeMetrics.loopSpacing(
                    contentWidth: contentWidth,
                    viewportWidth: geometry.size.width
                )
                let elapsed = timeline.date.timeIntervalSince(cycleStartedAt)
                let offset = MarqueeMetrics.offset(
                    elapsed: elapsed,
                    contentWidth: contentWidth,
                    viewportWidth: geometry.size.width
                )

                ZStack(alignment: .leading) {
                    HStack(spacing: loopSpacing) {
                        marqueeLabel
                        marqueeLabel
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .clipped()
            }
        }
        .frame(height: 16)
        .onAppear { resetCycle() }
        .onChange(of: isActive) { _, _ in resetCycle() }
        .onChange(of: text) { _, _ in resetCycle() }
        .accessibilityLabel(text)
    }

    private var marqueeLabel: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
    }

    private func resetCycle() {
        cycleStartedAt = Date()
    }
}

enum MarqueeMetrics {
    static let delay: TimeInterval = 1
    static let speed: CGFloat = 24
    static let gap: CGFloat = 34

    static func contentWidth(for text: String) -> CGFloat {
        ceil(
            (text as NSString).size(
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
                ]
            ).width
        )
    }

    static func offset(
        elapsed: TimeInterval,
        contentWidth: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        guard contentWidth > 0, viewportWidth > 0, elapsed > delay else { return 0 }
        let travel = contentWidth + loopSpacing(
            contentWidth: contentWidth,
            viewportWidth: viewportWidth
        )
        let travelled = CGFloat(elapsed - delay) * speed
        return -travelled.truncatingRemainder(dividingBy: travel)
    }

    static func loopSpacing(
        contentWidth: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        max(gap, viewportWidth - contentWidth + gap)
    }
}

private struct CompactPlaybackIndicator: View {
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isPlaying {
                TimelineView(.animation(minimumInterval: 0.08, paused: reduceMotion)) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(.white.opacity(0.78))
                                .frame(
                                    width: 2,
                                    height: reduceMotion
                                        ? CGFloat(8 + index * 2)
                                        : 7 + abs(sin(phase * 5 + Double(index) * 1.7)) * 8
                                )
                        }
                    }
                }
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
    }
}

private struct PanelComponentDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.16))
            .frame(width: 1, height: 88)
            .accessibilityHidden(true)
    }
}

private struct RainbowNotchOutline: View {
    let bottomRadius: CGFloat
    let leadingShoulderRadius: CGFloat
    let trailingShoulderRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hueRotation = 0.0

    var body: some View {
        NotchGlowEdgeShape(
            bottomRadius: bottomRadius,
            leadingShoulderRadius: leadingShoulderRadius,
            trailingShoulderRadius: trailingShoulderRadius
        )
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        .red,
                        .orange,
                        .yellow,
                        .green,
                        .cyan,
                        .blue,
                        .purple,
                        .red
                    ]),
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
            .hueRotation(.degrees(hueRotation))
            .opacity(0.68)
            .padding(0.75)
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    hueRotation = 360
                }
            }
    }
}

private struct NotchGlowEdgeShape: Shape {
    let bottomRadius: CGFloat
    let leadingShoulderRadius: CGFloat
    let trailingShoulderRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        // Open path: left side + bottom + right side — never the top edge,
        // so the rainbow glow doesn't draw along the menu-bar / cutout top.
        Path(
            NotchSilhouette.glowPath(
                in: rect,
                bottomRadius: bottomRadius,
                leadingShoulderRadius: leadingShoulderRadius,
                trailingShoulderRadius: trailingShoulderRadius
            )
        )
    }
}

private struct NotchSurfaceShape: Shape {
    let bottomRadius: CGFloat
    let leadingShoulderRadius: CGFloat
    let trailingShoulderRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(
            NotchSilhouette.path(
                in: rect,
                bottomRadius: bottomRadius,
                leadingShoulderRadius: leadingShoulderRadius,
                trailingShoulderRadius: trailingShoulderRadius,
                topOriginAtMinY: true
            )
        )
    }
}

/// Shared notch outline used by the native CAShapeLayer and SwiftUI clips.
enum NotchSilhouette {
    nonisolated static func path(
        in rect: CGRect,
        bottomRadius: CGFloat,
        leadingShoulderRadius: CGFloat,
        trailingShoulderRadius: CGFloat,
        topOriginAtMinY: Bool
    ) -> CGPath {
        let leading = min(leadingShoulderRadius, rect.width / 4, rect.height / 2)
        let trailing = min(trailingShoulderRadius, rect.width / 4, rect.height / 2)
        let leftEdge = rect.minX + leading
        let rightEdge = rect.maxX - trailing
        let lowerRadius = min(
            bottomRadius,
            (rightEdge - leftEdge) / 2,
            max(rect.height - max(leading, trailing), 0)
        )

        let topY = topOriginAtMinY ? rect.minY : rect.maxY
        let bottomY = topOriginAtMinY ? rect.maxY : rect.minY
        let down: CGFloat = topOriginAtMinY ? 1 : -1

        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: topY))
        path.addLine(to: CGPoint(x: rect.maxX, y: topY))

        if trailing > 0.05 {
            path.addCurve(
                to: CGPoint(x: rightEdge, y: topY + down * trailing),
                control1: CGPoint(x: rect.maxX - trailing * 0.25, y: topY),
                control2: CGPoint(x: rightEdge, y: topY + down * trailing * 0.5)
            )
        }

        path.addLine(to: CGPoint(x: rightEdge, y: bottomY - down * lowerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rightEdge - lowerRadius, y: bottomY),
            control: CGPoint(x: rightEdge, y: bottomY)
        )
        path.addLine(to: CGPoint(x: leftEdge + lowerRadius, y: bottomY))
        path.addQuadCurve(
            to: CGPoint(x: leftEdge, y: bottomY - down * lowerRadius),
            control: CGPoint(x: leftEdge, y: bottomY)
        )
        path.addLine(to: CGPoint(x: leftEdge, y: topY + down * leading))

        if leading > 0.05 {
            path.addCurve(
                to: CGPoint(x: rect.minX, y: topY),
                control1: CGPoint(x: leftEdge, y: topY + down * leading * 0.5),
                control2: CGPoint(x: rect.minX + leading * 0.25, y: topY)
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: topY))
        }

        path.closeSubpath()
        return path
    }

    /// Rainbow stroke path in SwiftUI coords (top = minY): sides + bottom only.
    nonisolated static func glowPath(
        in rect: CGRect,
        bottomRadius: CGFloat,
        leadingShoulderRadius: CGFloat,
        trailingShoulderRadius: CGFloat
    ) -> CGPath {
        let leading = min(leadingShoulderRadius, rect.width / 4, rect.height / 2)
        let trailing = min(trailingShoulderRadius, rect.width / 4, rect.height / 2)
        let leftEdge = rect.minX + leading
        let rightEdge = rect.maxX - trailing
        let lowerRadius = min(
            bottomRadius,
            (rightEdge - leftEdge) / 2,
            max(rect.height - max(leading, trailing), 0)
        )

        let path = CGMutablePath()
        // Start at the top-left corner, walk down the left, across the bottom,
        // and up the right — leave the top edge undrawn.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        if leading > 0.05 {
            path.addCurve(
                to: CGPoint(x: leftEdge, y: rect.minY + leading),
                control1: CGPoint(x: rect.minX + leading * 0.25, y: rect.minY),
                control2: CGPoint(x: leftEdge, y: rect.minY + leading * 0.5)
            )
        }
        path.addLine(to: CGPoint(x: leftEdge, y: rect.maxY - lowerRadius))
        path.addQuadCurve(
            to: CGPoint(x: leftEdge + lowerRadius, y: rect.maxY),
            control: CGPoint(x: leftEdge, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rightEdge - lowerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rightEdge, y: rect.maxY - lowerRadius),
            control: CGPoint(x: rightEdge, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rightEdge, y: rect.minY + trailing))
        if trailing > 0.05 {
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control1: CGPoint(x: rightEdge, y: rect.minY + trailing * 0.5),
                control2: CGPoint(x: rect.maxX - trailing * 0.25, y: rect.minY)
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        return path
    }
}
