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
    private var surfaceHostView: SolidBlackNotchHostingView<OverlaySurfaceView>?
    private var bubbleController: DynamicIslandBubbleController?
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

        let initialFrame = Self.frame(for: .collapsed, display: display)
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
        hostingView.setSurfaceAppearance(
            bottomRadius: collapsedRadii.bottom,
            shoulderRadius: collapsedRadii.shoulder,
            horizontalScale: 1
        )
        panel.contentView = hostingView

        super.init(window: panel)
        surfaceHostView = hostingView
        model.onToggle = { [weak self] in self?.toggle() }
        model.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        model.onMusicArtworkHover = { [weak self] in
            guard let self,
                  self.spotifyMusicStore.hasActiveTrack,
                  self.state == .collapsed || self.state == .hovered else { return }
            self.transition(to: .musicPreview)
        }
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
        liveActivityCancellable = liveActivityCenter.$activity
            .removeDuplicates()
            .sink { [weak self] activity in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Activity visibility changes the main notch width
                    // (right side cuts off into the bubble), so refresh
                    // geometry together with the bubble.
                    self.model.showsLiveActivity = activity != nil && self.state != .expanded
                    self.refreshGeometry()
                }
            }
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showCollapsed() {
        transition(to: .collapsed)
        window?.orderFrontRegardless()
        updateBubble(activity: liveActivityCenter.activity)
    }

    override func close() {
        bubbleController?.close()
        super.close()
    }

    private var showsLiveActivity: Bool {
        liveActivityCenter.activity != nil && state != .expanded
    }

    /// Repositions the dynamic-island bubble in the right slot of the compact
    /// envelope (the part cut off from the asymmetric main notch).
    private func updateBubble(activity: LiveActivity?) {
        let envelope = DynamicIslandLayout.compactEnvelope(
            for: state,
            display: display,
            showsNowPlaying: spotifyMusicStore.hasActiveTrack,
            showsLiveActivity: showsLiveActivity
        )
        bubbleController?.update(
            activity: activity,
            envelope: envelope,
            notchWindow: window,
            isNotchExpanded: state == .expanded
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
        guard let window else { return }
        let showsNowPlaying = showsNowPlaying ?? spotifyMusicStore.hasActiveTrack
        let liveActivity = showsLiveActivity
        model.showsLiveActivity = liveActivity
        let radii = Self.surfaceRadii(for: state)
        let targetFrame = Self.frame(
            for: state,
            display: display,
            expandedWidth: settingsStore.expandedWidth,
            showsNowPlaying: showsNowPlaying,
            showsLiveActivity: liveActivity
        )
        surfaceHostView?.setSurfaceAppearance(
            bottomRadius: radii.bottom,
            shoulderRadius: radii.shoulder,
            horizontalScale: Self.surfaceHorizontalScale(
                for: state,
                showsNowPlaying: showsNowPlaying,
                showsLiveActivity: liveActivity
            ),
            targetWindowFrame: targetFrame,
            springParams: AnimationSpring.forState(state),
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        let params = AnimationSpring.forState(state)
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? 0.1 : params.settlingDuration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(targetFrame, display: true)
        }
        updateBubble(activity: liveActivityCenter.activity)
    }

    func handlePointerDown(at point: CGPoint) {
        guard let window else { return }

        if state != .expanded,
           Self.shouldExpand(
               state: state,
               panelFrame: window.frame,
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
        CGRect(
            x: collapsedFrame.minX,
            y: collapsedFrame.maxY - 34,
            width: 46,
            height: 40
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
        guard let window, newState != state || !window.isVisible else { return }
        state = newState

        let liveActivity = liveActivityCenter.activity != nil && newState != .expanded
        let radii = Self.surfaceRadii(for: newState)
        let targetFrame = Self.frame(
            for: newState,
            display: display,
            expandedWidth: settingsStore.expandedWidth,
            showsNowPlaying: spotifyMusicStore.hasActiveTrack,
            showsLiveActivity: liveActivity
        )
        model.surfaceState = newState
        model.showsLiveActivity = liveActivity

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let params = AnimationSpring.forState(newState)

        // Animuj kształt CAShapeLayer zsynchronizowany z oknem
        surfaceHostView?.setSurfaceAppearance(
            bottomRadius: radii.bottom,
            shoulderRadius: radii.shoulder,
            horizontalScale: Self.surfaceHorizontalScale(
                for: newState,
                showsNowPlaying: spotifyMusicStore.hasActiveTrack,
                showsLiveActivity: liveActivity
            ),
            targetWindowFrame: targetFrame,
            springParams: params,
            reduceMotion: reduceMotion
        )

        let duration = reduceMotion ? 0.1 : params.settlingDuration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(targetFrame, display: true)
        }
        updateBubble(activity: liveActivityCenter.activity)

        logger.debug("Surface transitioned to \(String(describing: newState), privacy: .public), frame=\(String(describing: targetFrame), privacy: .public)")
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
            showsLiveActivity: showsLiveActivity
        )
    }

    static func surfaceRadii(for state: SurfaceState) -> (bottom: CGFloat, shoulder: CGFloat) {
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
        // island is split the window already matches the asymmetric body, so
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

    /// Approximate settling duration (95% threshold).
    var settlingDuration: TimeInterval {
        // heuristic: 3 * (2*mass / (dampingRatio * 2 * sqrt(stiffness*mass)))
        let criticalDamping = 2 * sqrt(stiffness * mass)
        let beta = dampingRatio * criticalDamping
        guard beta > 0 else { return 0.4 }
        return TimeInterval(min(6.0 / beta, 2.0))
    }

    static func forState(_ state: NotchWindowController.SurfaceState) -> AnimationSpring {
        switch state {
        case .expanded:
            // Miękkie otwarcie – spring z lekkim odbiciem
            return AnimationSpring(dampingRatio: 0.72, stiffness: 380, mass: 1.0)
        case .collapsed:
            // Szybkie zamknięcie bez odbicia
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
    var onToggle: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onMusicArtworkHover: (() -> Void)?
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
        let radii = NotchWindowController.surfaceRadii(for: model.surfaceState)
        let horizontalScale = NotchWindowController.surfaceHorizontalScale(
            for: model.surfaceState,
            showsNowPlaying: spotifyMusicStore.hasActiveTrack,
            showsLiveActivity: model.showsLiveActivity
        )
        let shape = NotchSurfaceShape(
            bottomRadius: radii.bottom,
            shoulderRadius: radii.shoulder
        )

        ZStack(alignment: .top) {
            shape
                .fill(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1))
                .scaleEffect(x: horizontalScale, y: 1, anchor: .center)
                .animation(.spring(response: 0.36, dampingFraction: 0.82), value: horizontalScale)
            surfaceContent

            if settingsStore.rainbowGlowEnabled,
               model.surfaceState == .hovered || model.surfaceState == .musicPreview {
                RainbowNotchOutline(
                    bottomRadius: radii.bottom,
                    shoulderRadius: radii.shoulder
                )
                .scaleEffect(x: horizontalScale, y: 1, anchor: .center)
                .animation(.spring(response: 0.36, dampingFraction: 0.82), value: horizontalScale)
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .gesture(
            TapGesture().onEnded {
                guard model.surfaceState != .expanded else { return }
                model.onToggle?()
            },
            including: model.surfaceState == .expanded || usesMusicTapZones
                ? .subviews
                : .all
        )
        .ignoresSafeArea()
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
                        onOpen: { model.onToggle?() },
                        onArtworkHover: { model.onMusicArtworkHover?() }
                    )
                    .transition(.opacity)
                }
            }
            .animation(
                .spring(response: 0.38, dampingFraction: 0.85),
                value: spotifyMusicStore.hasActiveTrack
            )
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
    let onArtworkHover: () -> Void

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
                    .onHover { isHovering in
                        if isHovering { onArtworkHover() }
                    }
                    .onContinuousHover { phase in
                        if case .active = phase { onArtworkHover() }
                    }
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
                            cornerRadius: isPreviewExpanded ? 8 : 6,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: isPreviewExpanded ? 8 : 6,
                            style: .continuous
                        )
                        .stroke(.white.opacity(0.18), lineWidth: 0.8)
                    }
                    .position(
                        x: NowPlayingLayout.artworkCenterX(
                            isPreviewExpanded: isPreviewExpanded
                        ),
                        y: (isPreviewExpanded ? 18 : 2)
                            + NowPlayingLayout.artworkSize(
                                isPreviewExpanded: isPreviewExpanded
                            ) / 2
                    )
                    .animation(
                        .spring(response: 0.34, dampingFraction: 0.8),
                        value: isPreviewExpanded
                    )
                    .allowsHitTesting(false)

                if !showsLiveActivity {
                    CompactPlaybackIndicator(isPlaying: store.track.isPlaying)
                        .frame(width: 24, height: 24)
                        .position(
                            x: geometry.size.width - NowPlayingLayout.playbackRightInset,
                            y: 14
                        )
                        .animation(
                            .easeInOut(duration: 0.22),
                            value: isPreviewExpanded
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
                            geometry.size.width - (isPreviewExpanded ? 44 : 28),
                            1
                        ),
                        alignment: .leading
                    )
                    .offset(
                        x: isPreviewExpanded ? 22 : 14,
                        y: isPreviewExpanded ? 60 : 30
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
    static func artworkSize(isPreviewExpanded: Bool) -> CGFloat {
        isPreviewExpanded ? 28 : 24
    }

    static func artworkCenterX(
        isPreviewExpanded: Bool
    ) -> CGFloat {
        if isPreviewExpanded { return 34 }
        return 32
    }

    static let playbackRightInset: CGFloat = 32
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
    let shoulderRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hueRotation = 0.0

    var body: some View {
        NotchGlowEdgeShape(
            bottomRadius: bottomRadius,
            shoulderRadius: shoulderRadius
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
    let shoulderRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let shoulder = min(shoulderRadius, rect.width / 4, rect.height / 2)
        let leftEdge = rect.minX + shoulder
        let rightEdge = rect.maxX - shoulder
        let lowerRadius = min(bottomRadius, (rightEdge - leftEdge) / 2, rect.height - shoulder)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: leftEdge, y: rect.minY + shoulder),
            control1: CGPoint(x: rect.minX + shoulder * 0.25, y: rect.minY),
            control2: CGPoint(x: leftEdge, y: rect.minY + shoulder * 0.5)
        )
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
        path.addLine(to: CGPoint(x: rightEdge, y: rect.minY + shoulder))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rightEdge, y: rect.minY + shoulder * 0.5),
            control2: CGPoint(x: rect.maxX - shoulder * 0.25, y: rect.minY)
        )
        return path
    }
}

private struct NotchSurfaceShape: Shape {
    let bottomRadius: CGFloat
    let shoulderRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let shoulder = min(shoulderRadius, rect.width / 4, rect.height / 2)
        let leftEdge = rect.minX + shoulder
        let rightEdge = rect.maxX - shoulder
        let lowerRadius = min(bottomRadius, (rightEdge - leftEdge) / 2, rect.height - shoulder)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rightEdge, y: rect.minY + shoulder),
            control1: CGPoint(x: rect.maxX - shoulder * 0.25, y: rect.minY),
            control2: CGPoint(x: rightEdge, y: rect.minY + shoulder * 0.5)
        )
        path.addLine(to: CGPoint(x: rightEdge, y: rect.maxY - lowerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rightEdge - lowerRadius, y: rect.maxY),
            control: CGPoint(x: rightEdge, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: leftEdge + lowerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: leftEdge, y: rect.maxY - lowerRadius),
            control: CGPoint(x: leftEdge, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: leftEdge, y: rect.minY + shoulder))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(x: leftEdge, y: rect.minY + shoulder * 0.5),
            control2: CGPoint(x: rect.minX + shoulder * 0.25, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
