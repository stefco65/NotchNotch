import AppKit
import CoreGraphics

@main
@MainActor
enum GeometryChecks {
    static func main() async throws {
        let display = DisplayDescriptor(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 975),
            safeAreaInsets: .init(top: 26, left: 0, bottom: 0, right: 0),
            scaleFactor: 2,
            anchor: .physicalNotch(
                .init(
                    rect: CGRect(x: 400, y: 974, width: 200, height: 26),
                    topInset: 26,
                    leftAuxiliaryArea: CGRect(x: 0, y: 974, width: 400, height: 26),
                    rightAuxiliaryArea: CGRect(x: 600, y: 974, width: 400, height: 26)
                )
            )
        )

        let collapsed = NotchWindowController.frame(for: .collapsed, display: display)
        precondition(collapsed == CGRect(x: 400, y: 974, width: 200, height: 26))
        // Idle body must use the resolved anchor rect — not a re-centered guess.
        precondition(
            DynamicIslandLayout.physicalNotchFrame(display: display) == collapsed
        )
        precondition(collapsed.minX == display.anchor.rect.minX)
        precondition(collapsed.maxX == display.anchor.rect.maxX)
        precondition(NotchWindowController.surfaceRadii(for: .collapsed) == (8, 7))
        precondition(NotchWindowController.surfaceRadii(for: .musicPreview) == (22, 16))

        let playingCollapsed = NotchWindowController.frame(
            for: .collapsed,
            display: display,
            showsNowPlaying: true
        )
        precondition(playingCollapsed == CGRect(x: 350, y: 974, width: 300, height: 26))
        precondition(playingCollapsed.midX == collapsed.midX)
        precondition(
            playingCollapsed.width * NotchWindowController.surfaceHorizontalScale(
                for: .collapsed,
                showsNowPlaying: true
            ) == 280
        )

        let expanded = NotchWindowController.frame(for: .expanded, display: display)
        precondition(expanded == CGRect(x: 120, y: 796, width: 760, height: 204))

        let customExpanded = NotchWindowController.frame(
            for: .expanded,
            display: display,
            expandedWidth: 900
        )
        precondition(customExpanded == CGRect(x: 50, y: 796, width: 900, height: 204))

        let hovered = NotchWindowController.frame(for: .hovered, display: display)
        precondition(hovered == CGRect(x: 360, y: 954, width: 280, height: 46))
        precondition(hovered.width == collapsed.width + DynamicIslandLayout.idleHoverExtraWidth)

        let musicHovered = NotchWindowController.frame(
            for: .hovered,
            display: display,
            showsNowPlaying: true
        )
        precondition(musicHovered == CGRect(x: 350, y: 954, width: 300, height: 46))
        precondition(musicHovered.width == playingCollapsed.width)
        precondition(
            playingCollapsed.minX + NowPlayingLayout.artworkCenterX(
                isPreviewExpanded: false
            )
                == musicHovered.minX + NowPlayingLayout.artworkCenterX(
                    isPreviewExpanded: false
                )
        )
        precondition(
            playingCollapsed.maxX - NowPlayingLayout.playbackRightInset
                == musicHovered.maxX - NowPlayingLayout.playbackRightInset
        )

        let musicPreview = NotchWindowController.frame(
            for: .musicPreview,
            display: display,
            showsNowPlaying: true
        )
        precondition(musicPreview == CGRect(x: 350, y: 910, width: 300, height: 90))
        precondition(musicPreview.maxY == display.frame.maxY)
        precondition(musicPreview.width == playingCollapsed.width)
        precondition(musicPreview.width == musicHovered.width)

        let artworkHoverFrame = NotchWindowController.musicArtworkHoverFrame(
            in: playingCollapsed
        )
        precondition(artworkHoverFrame == CGRect(x: 350, y: 966, width: 46, height: 40))
        precondition(artworkHoverFrame.contains(CGPoint(x: 377, y: 982)))
        precondition(!artworkHoverFrame.contains(CGPoint(x: 500, y: 982)))

        // Idle + DI: same centered capsule; bubble hangs past physical maxX.
        // Music + DI: keep music left overhang, clip right edge to physical.maxX.
        let physical = DynamicIslandLayout.physicalNotchFrame(display: display)
        precondition(physical == collapsed)

        let idleDI = NotchWindowController.frame(
            for: .collapsed,
            display: display,
            showsNowPlaying: false,
            showsLiveActivity: true
        )
        precondition(idleDI == collapsed)
        precondition(idleDI.midX == physical.midX)

        let idleHoverDI = NotchWindowController.frame(
            for: .hovered,
            display: display,
            showsNowPlaying: false,
            showsLiveActivity: true
        )
        precondition(idleHoverDI == hovered)
        precondition(idleHoverDI.midX == physical.midX)
        precondition(idleHoverDI.height == idleDI.height + 20)

        let musicDI = NotchWindowController.frame(
            for: .collapsed,
            display: display,
            showsNowPlaying: true,
            showsLiveActivity: true
        )
        precondition(musicDI.minX == playingCollapsed.minX)
        precondition(musicDI.maxX == physical.maxX)
        precondition(musicDI.width == physical.width + DynamicIslandLayout.compactExtraWidth / 2)

        let musicHoverDI = NotchWindowController.frame(
            for: .hovered,
            display: display,
            showsNowPlaying: true,
            showsLiveActivity: true
        )
        precondition(musicHoverDI.maxX == physical.maxX)
        precondition(musicHoverDI.minX == musicDI.minX)
        precondition(musicHoverDI.width == musicDI.width)
        precondition(musicHoverDI.height == musicDI.height + 20)

        let musicPreviewDI = NotchWindowController.frame(
            for: .musicPreview,
            display: display,
            showsNowPlaying: true,
            showsLiveActivity: true
        )
        precondition(musicPreviewDI.maxX == physical.maxX)
        precondition(musicPreviewDI.minX == musicDI.minX)
        precondition(musicPreviewDI.width == musicDI.width)
        precondition(musicPreviewDI.height == musicDI.height + 64)

        // Hover bubble stays pinned to the physical cutout.
        let musicHoverBubble = DynamicIslandLayout.bubbleWindowFrame(
            adjacentTo: musicHoverDI,
            restingHeight: physical.height
        )
        precondition(musicHoverBubble.minX == physical.maxX - DynamicIslandLayout.attachOverlap)

        precondition(
            NotchWindowController.surfaceHorizontalScale(
                for: .collapsed,
                showsNowPlaying: true,
                showsLiveActivity: true
            ) == 1
        )
        let bubbleWindow = DynamicIslandLayout.bubbleWindowFrame(
            adjacentTo: musicDI,
            restingHeight: physical.height
        )
        precondition(bubbleWindow.minX == musicDI.maxX - DynamicIslandLayout.attachOverlap)
        precondition(bubbleWindow.minX == physical.maxX - DynamicIslandLayout.attachOverlap)
        precondition(bubbleWindow.maxY == musicDI.maxY)
        let idleBubble = DynamicIslandLayout.bubbleWindowFrame(
            adjacentTo: idleDI,
            restingHeight: physical.height
        )
        precondition(idleBubble.minX == idleDI.maxX - DynamicIslandLayout.attachOverlap)
        precondition(bubbleWindow.minX == idleBubble.minX)

        let chrome = NotchWindowController.windowFrame(for: .collapsed, display: display)
        let offset = NotchWindowController.contentOffsetX(
            visual: collapsed,
            contentWidth: collapsed.width,
            chrome: chrome
        )
        precondition(abs((chrome.minX + offset + collapsed.width / 2) - collapsed.midX) < 0.5)
        let musicDIOffset = NotchWindowController.contentOffsetX(
            visual: musicDI,
            contentWidth: musicDI.width,
            chrome: chrome,
            pinTrailing: true
        )
        precondition(abs((chrome.minX + musicDIOffset + musicDI.width) - physical.maxX) < 0.5)
        precondition(abs((chrome.minX + musicDIOffset) - musicDI.minX) < 0.5)
        let musicHoverOffset = NotchWindowController.contentOffsetX(
            visual: musicHoverDI,
            contentWidth: musicHoverDI.width,
            chrome: chrome,
            pinTrailing: true
        )
        precondition(musicHoverOffset == musicDIOffset)

        precondition(
            MarqueeMetrics.offset(
                elapsed: 0.9,
                contentWidth: 300,
                viewportWidth: 200
            ) == 0
        )
        precondition(
            MarqueeMetrics.offset(
                elapsed: 2,
                contentWidth: 300,
                viewportWidth: 200
            ) == -24
        )
        precondition(
            MarqueeMetrics.offset(
                elapsed: 2,
                contentWidth: 120,
                viewportWidth: 240
            ) == -24
        )
        precondition(
            MarqueeMetrics.loopSpacing(
                contentWidth: 120,
                viewportWidth: 240
            ) == 154
        )

        precondition(
            NotchWindowController.shouldExpand(
                state: .musicPreview,
                panelFrame: musicPreview,
                pointerLocation: CGPoint(x: 480, y: 940)
            )
        )
        let playbackControl = CGRect(x: 604, y: 964, width: 46, height: 36)
        precondition(
            !NotchWindowController.shouldExpand(
                state: .musicPreview,
                panelFrame: musicPreview,
                excludedControlFrame: playbackControl,
                pointerLocation: CGPoint(x: 630, y: 980)
            )
        )

        precondition(
            NotchWindowController.shouldCollapse(
                state: .expanded,
                panelFrame: expanded,
                pointerLocation: CGPoint(x: 30, y: 300)
            )
        )
        precondition(
            !NotchWindowController.shouldCollapse(
                state: .expanded,
                panelFrame: expanded,
                pointerLocation: CGPoint(x: 500, y: 900)
            )
        )
        precondition(
            !NotchWindowController.shouldCollapse(
                state: .hovered,
                panelFrame: hovered,
                pointerLocation: CGPoint(x: 30, y: 300)
            )
        )
        precondition(
            !NotchWindowController.shouldCollapse(
                state: .expanded,
                isTrayMode: true,
                panelFrame: expanded,
                pointerLocation: CGPoint(x: 30, y: 300)
            )
        )
        precondition(
            !NotchWindowController.shouldCollapse(
                state: .expanded,
                suppressOutsideCollapse: true,
                panelFrame: expanded,
                pointerLocation: CGPoint(x: 30, y: 300)
            )
        )

        let narrowDisplay = DisplayDescriptor(
            id: 2,
            frame: CGRect(x: -800, y: 200, width: 600, height: 900),
            visibleFrame: CGRect(x: -800, y: 200, width: 600, height: 875),
            safeAreaInsets: .init(),
            scaleFactor: 1,
            anchor: .virtualHandler(.init(rect: CGRect(x: -590, y: 1088, width: 180, height: 12)))
        )
        let narrowExpanded = NotchWindowController.frame(for: .expanded, display: narrowDisplay)
        precondition(narrowExpanded.width == 552)
        precondition(narrowExpanded.midX == narrowDisplay.frame.midX)
        precondition(narrowExpanded.maxY == narrowDisplay.frame.maxY)

        let suiteName = "com.notchnook.geometry-checks"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let firstShortcut = ShortcutButtonConfiguration(shortcutName: "Pierwszy")
        let secondShortcut = ShortcutButtonConfiguration(shortcutName: "Drugi")
        defaults.set(
            try JSONEncoder().encode([firstShortcut, secondShortcut]),
            forKey: "shortcuts.buttons"
        )

        let settings = SettingsStore(defaults: defaults)
        precondition(
            settings.expandedWidth
                == SettingsStore.requiredExpandedWidth(for: settings.components)
        )
        precondition(settings.components.count == 6)
        precondition(settings.components[1].kind == .shortcuts)
        precondition(settings.components[2].kind == .tasks)
        precondition(settings.components[3].kind == .agents)
        let fourComponents = Array(settings.components.prefix(4)).map {
            PanelComponentConfiguration(kind: $0.kind, widthWeight: 1)
        }
        let fiveComponents = fourComponents + [
            PanelComponentConfiguration(kind: .systemStatus, widthWeight: 1)
        ]
        precondition(
            SettingsStore.requiredExpandedWidth(for: fiveComponents)
                > SettingsStore.requiredExpandedWidth(for: fourComponents)
        )
        precondition(settings.shortcutButtons.map(\.shortcutName) == ["Pierwszy", "Drugi"])
        precondition(!settings.showOnExternalDisplays)
        precondition(settings.rainbowGlowEnabled)
        settings.setRainbowGlowEnabled(false)
        var displayPolicyChanges = 0
        settings.onDisplayPolicyChange = { displayPolicyChanges += 1 }
        settings.setShowOnExternalDisplays(true)
        settings.setShowOnExternalDisplays(true)
        precondition(settings.showOnExternalDisplays)
        precondition(displayPolicyChanges == 1)
        settings.setExpandedWidth(900)
        precondition(settings.expandedWidth == settings.requiredExpandedWidth)
        settings.setExpandedWidth(1_700)
        precondition(settings.expandedWidth == 1_700)
        let widthBeforeAddingComponent = settings.expandedWidth
        settings.add(.mirror)
        precondition(settings.components.last?.kind == .mirror)
        precondition(settings.expandedWidth >= widthBeforeAddingComponent)

        let left = settings.components[0]
        let right = settings.components[1]
        let combinedWeight = left.widthWeight + right.widthWeight
        settings.adjustDivider(leftID: left.id, rightID: right.id, deltaWeight: 0.2)
        precondition(settings.components[0].widthWeight == left.widthWeight + 0.2)
        precondition(settings.components[0].widthWeight + settings.components[1].widthWeight == combinedWeight)

        settings.setShortcutButtonWidth(id: firstShortcut.id, value: 2.25)
        settings.moveShortcutButton(id: firstShortcut.id, offset: 1)
        precondition(settings.shortcutButtons.map(\.shortcutName) == ["Drugi", "Pierwszy"])
        precondition(settings.shortcutButtons[1].widthWeight == 2.25)
        settings.removeShortcutButton(id: secondShortcut.id)
        let restoredSettings = SettingsStore(defaults: defaults)
        precondition(restoredSettings.shortcutButtons.map(\.shortcutName) == ["Pierwszy"])
        precondition(restoredSettings.shortcutButtons[0].widthWeight == 2.25)
        precondition(!restoredSettings.rainbowGlowEnabled)
        defaults.removePersistentDomain(forName: suiteName)

        let workingRollout = Data(#"{"payload":{"type":"task_started"}}"#.utf8)
        let doneRollout = Data(
            (#"{"payload":{"type":"task_started"}}"# + "\n"
             + #"{"payload":{"type":"task_complete"}}"#).utf8
        )
        let stoppedRollout = Data(#"{"payload":{"type":"turn_aborted"}}"#.utf8)
        precondition(AgentStatusScanner.codexState(in: workingRollout) == .working)
        precondition(AgentStatusScanner.codexState(in: doneRollout) == .done)
        precondition(AgentStatusScanner.codexState(in: stoppedRollout) == .stopped)
        precondition(
            AgentStatusScanner.codexState(
                in: Data(#"{"payload":{"type":"agent_message"}}"#.utf8),
                lastModified: Date(timeIntervalSince1970: 995),
                now: Date(timeIntervalSince1970: 1_000)
            ) == .working
        )
        precondition(AgentStatusScanner.cursorState(status: "generating") == .working)
        precondition(AgentStatusScanner.cursorState(status: "blocked") == .stopped)
        precondition(AgentStatusScanner.cursorState(status: "none") == .done)
        precondition(AgentStatusScanner.antigravityState(status: 1) == .working)
        precondition(AgentStatusScanner.antigravityState(status: 2) == .working)
        precondition(AgentStatusScanner.antigravityState(status: 3) == .done)
        precondition(AgentStatusScanner.antigravityState(status: 4) == .stopped)
        precondition(AgentStatusScanner.antigravityState(status: 7) == .stopped)
        precondition(
            AgentStatusScanner.antigravityConversationState(lastStatus: 3, hasWorkingStep: true)
                == .working
        )
        precondition(
            AgentStatusScanner.codexEventState(type: "exec_approval_request") == .stopped
        )

        let taskStore = TaskStore(
            defaults: defaults,
            completionDelay: .milliseconds(10)
        )
        precondition(taskStore.add(title: "   ") == nil)
        guard let task = taskStore.add(title: "  Pierwsze zadanie  ") else {
            preconditionFailure("A non-empty task should be created")
        }
        precondition(task.title == "Pierwsze zadanie")
        taskStore.update(id: task.id, title: "Zmienione zadanie")
        precondition(taskStore.items.first?.title == "Zmienione zadanie")
        let restoredTaskStore = TaskStore(defaults: defaults)
        precondition(restoredTaskStore.items.first?.title == "Zmienione zadanie")
        taskStore.complete(id: task.id)
        precondition(taskStore.items.first?.isCompleted == true)
        try await Task.sleep(for: .milliseconds(30))
        precondition(taskStore.items.isEmpty)
        precondition(TaskStore(defaults: defaults).items.isEmpty)
        defaults.removePersistentDomain(forName: suiteName)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let selectedDate = ISO8601DateFormatter().date(
            from: "2026-08-09T12:00:00Z"
        )!
        let visibleDates = CalendarStore.centeredDates(
            containing: selectedDate,
            calendar: calendar
        )
        precondition(visibleDates.count == 7)
        precondition(calendar.isDate(visibleDates[3], inSameDayAs: selectedDate))
        precondition(
            calendar.dateComponents([.day], from: visibleDates[0], to: visibleDates[6]).day == 6
        )

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchnook-tray-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )

        let sourceFile = temporaryRoot.appendingPathComponent("fixture.txt")
        try Data("tray fixture".utf8).write(to: sourceFile)
        let trayStorage = TrayFileStorage(
            rootURL: temporaryRoot.appendingPathComponent("storage", isDirectory: true)
        )
        let trayItem = try await trayStorage.ingest(sourceFile)
        precondition(FileManager.default.fileExists(atPath: trayItem.storedURL.path))
        precondition(trayItem.displayName == "fixture.txt")
        precondition(trayStorage.isManagedURL(trayItem.storedURL))
        precondition(!trayStorage.isManagedURL(sourceFile))
        try trayStorage.persist([trayItem])
        precondition(trayStorage.loadItems() == [trayItem])
        try trayStorage.remove(trayItem)
        precondition(!FileManager.default.fileExists(atPath: trayItem.storedURL.path))

        print("PASS: 90 overlay, reference music capsule, responsive sizing, settings, Agents, Calendar, Tasks, Shortcuts, displays, music, Tray, and dismissal assertions")
    }
}
