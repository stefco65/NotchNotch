import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settingsStore = SettingsStore()
    let trayStore = TrayStore()
    let spotifyMusicStore = SpotifyMusicStore()
    let taskStore = TaskStore()
    let calendarStore = CalendarStore()
    let agentMonitorStore = AgentMonitorStore()

    private var statusItem: NSStatusItem?
    private var displayInfoMenuItem: NSMenuItem?
    private var windowControllers: [CGDirectDisplayID: NotchWindowController] = [:]
    private var pointerMonitors: [CGDirectDisplayID: PointerMonitor] = [:]
    private var screenParametersObserver: NSObjectProtocol?
    private var settingsWindowController: SettingsWindowController?
    private let hapticService: HapticProviding = HapticService()
    private let logger = AppLogger.app

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        spotifyMusicStore.startMonitoring()
        agentMonitorStore.startMonitoring()
        settingsStore.refreshInstalledShortcuts()

        settingsStore.onGeometryChange = { [weak self] in
            self?.windowControllers.values.forEach { $0.refreshGeometry() }
        }
        settingsStore.onDisplayPolicyChange = { [weak self] in
            self?.rebuildOverlays()
        }
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildOverlays()
            }
        }

        rebuildOverlays()
        installStatusItem()
        updateDisplaySummary()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak spotifyMusicStore] in
            spotifyMusicStore?.requestAutomationAccessAndRefresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        spotifyMusicStore.stopMonitoring()
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        pointerMonitors.values.forEach { $0.stop() }
        windowControllers.values.forEach { $0.close() }
    }

    private var primaryDisplayID: CGDirectDisplayID? {
        guard let screen = primaryMacScreen else { return nil }
        return displayID(for: screen)
    }

    private var primaryMacScreen: NSScreen? {
        NSScreen.screens.first { screen in
            CGDisplayIsBuiltin(displayID(for: screen)) != 0
        } ?? NSScreen.screens.first
    }

    private var primaryController: NotchWindowController? {
        if let primaryDisplayID, let controller = windowControllers[primaryDisplayID] {
            return controller
        }
        return windowControllers.values.first
    }

    private func rebuildOverlays() {
        let screens = NSScreen.screens
        guard let primaryScreen = primaryMacScreen else {
            logger.error("No display is available; overlays were removed")
            removeAllOverlays()
            return
        }

        let desiredScreens = settingsStore.showOnExternalDisplays ? screens : [primaryScreen]
        let desiredDescriptors = desiredScreens.map { NotchGeometryResolver().resolve(screen: $0) }
        let desiredIDs = Set(desiredDescriptors.map(\.id))

        for displayID in Array(windowControllers.keys) where !desiredIDs.contains(displayID) {
            removeOverlay(displayID: displayID)
        }

        for descriptor in desiredDescriptors {
            if let existing = windowControllers[descriptor.id], existing.display == descriptor {
                existing.refreshGeometry()
                continue
            }

            removeOverlay(displayID: descriptor.id)
            installOverlay(for: descriptor)
        }

        updateDisplaySummary()
        logger.notice(
            "Active overlays: \(self.windowControllers.count, privacy: .public), external enabled: \(self.settingsStore.showOnExternalDisplays, privacy: .public)"
        )
    }

    private func installOverlay(for descriptor: DisplayDescriptor) {
        let controller = NotchWindowController(
            display: descriptor,
            settingsStore: settingsStore,
            trayStore: trayStore,
            spotifyMusicStore: spotifyMusicStore,
            taskStore: taskStore,
            calendarStore: calendarStore,
            agentMonitorStore: agentMonitorStore
        )
        controller.onOpenSettings = { [weak self] in
            self?.showSettingsWindow()
        }

        windowControllers[descriptor.id] = controller
        controller.showCollapsed()
        installPointerMonitor(for: controller)

        logger.notice(
            "Overlay started on display \(descriptor.id, privacy: .public), anchor=\(descriptor.anchor.logDescription, privacy: .public)"
        )
    }

    private func removeOverlay(displayID: CGDirectDisplayID) {
        pointerMonitors.removeValue(forKey: displayID)?.stop()
        windowControllers.removeValue(forKey: displayID)?.close()
    }

    private func removeAllOverlays() {
        for displayID in Array(windowControllers.keys) {
            removeOverlay(displayID: displayID)
        }
        updateDisplaySummary()
    }

    private func installPointerMonitor(for controller: NotchWindowController) {
        let monitor = PointerMonitor(
            hitTest: { [weak controller] point in
                controller?.containsHoverPoint(point) ?? false
            },
            onHoverChanged: { [weak controller, hapticService] isHovering, point in
                guard let controller else { return }
                let didEnter = controller.setHoverActive(isHovering, at: point)
                if didEnter {
                    hapticService.performHoverFeedback()
                }
            },
            onPointerDown: { [weak controller] point in
                controller?.handlePointerDown(at: point)
            }
        )
        pointerMonitors[controller.display.id] = monitor
        monitor.start()
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "NotchNook"
        )

        let menu = NSMenu()
        menu.addItem(withTitle: "Expand", action: #selector(toggleOverlay), keyEquivalent: "e").target = self
        menu.addItem(withTitle: "Collapse", action: #selector(collapseOverlays), keyEquivalent: "c").target = self
        menu.addItem(.separator())

        let displayItem = NSMenuItem(title: "Main display", action: nil, keyEquivalent: "")
        displayItem.isEnabled = false
        menu.addItem(displayItem)
        displayInfoMenuItem = displayItem

        menu.addItem(withTitle: "Copy Display Diagnostics", action: #selector(copyDiagnostics), keyEquivalent: "d").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NotchNook", action: #selector(quit), keyEquivalent: "q").target = self

        item.menu = menu
        statusItem = item
    }

    private func updateDisplaySummary() {
        guard let primaryController else {
            displayInfoMenuItem?.title = "No active display"
            return
        }
        displayInfoMenuItem?.title = "Main: \(primaryController.display.anchor.menuDescription) · Active: \(windowControllers.count)"
    }

    @objc private func toggleOverlay() {
        primaryController?.toggle()
    }

    @objc private func collapseOverlays() {
        windowControllers.values.forEach { $0.showCollapsed() }
    }

    @objc private func copyDiagnostics() {
        guard let diagnostics = primaryController?.display.diagnostics else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
    }

    @objc private func openSettings() {
        showSettingsWindow()
    }

    private func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(store: settingsStore)
        }
        settingsWindowController?.present()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
