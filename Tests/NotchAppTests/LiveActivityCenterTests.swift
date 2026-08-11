import Foundation
import XCTest
@testable import NotchNook

final class LiveActivityCenterTests: XCTestCase {
    private func summary(
        _ source: AgentSource,
        working: Int = 0,
        stopped: Int = 0,
        done: Int = 0,
        isRunning: Bool = true
    ) -> AgentSourceSummary {
        AgentSourceSummary(
            source: source,
            counts: AgentCounts(working: working, stopped: stopped, done: done),
            isApplicationRunning: isRunning
        )
    }

    func testAgentHighlightPrefersStoppedThenWorkingThenDone() {
        XCTAssertEqual(
            LiveActivityCenter.agentHighlight(from: [
                summary(.codex, working: 2, stopped: 1, done: 3)
            ]),
            .agents(state: .stopped, count: 1)
        )
        XCTAssertEqual(
            LiveActivityCenter.agentHighlight(from: [
                summary(.codex, working: 2, done: 3)
            ]),
            .agents(state: .working, count: 2)
        )
        XCTAssertEqual(
            LiveActivityCenter.agentHighlight(from: [
                summary(.codex, done: 3)
            ]),
            .agents(state: .done, count: 3)
        )
    }

    func testAgentHighlightSumsAcrossRunningSourcesOnly() {
        let highlight = LiveActivityCenter.agentHighlight(from: [
            summary(.codex, working: 1),
            summary(.cursor, working: 2),
            summary(.antigravity, working: 9, isRunning: false)
        ])
        XCTAssertEqual(highlight, .agents(state: .working, count: 3))
    }

    func testAgentHighlightOrangeBeatsBlueAcrossSources() {
        let highlight = LiveActivityCenter.agentHighlight(from: [
            summary(.codex, working: 4),
            summary(.cursor, stopped: 1)
        ])
        XCTAssertEqual(highlight, .agents(state: .stopped, count: 1))
    }

    func testAgentHighlightIsNilWithoutAnyAgents() {
        XCTAssertNil(LiveActivityCenter.agentHighlight(from: [
            summary(.codex),
            summary(.cursor, isRunning: false)
        ]))
    }

    func testInitialOwnerPrefersAgentsOverTasksAndMusic() {
        XCTAssertEqual(
            LiveActivityCenter.initialOwner(
                agentHighlight: .agents(state: .working, count: 1),
                openTaskCount: 5,
                isMusicPlaying: true
            ),
            .agents
        )
        XCTAssertEqual(
            LiveActivityCenter.initialOwner(
                agentHighlight: nil,
                openTaskCount: 5,
                isMusicPlaying: true
            ),
            .tasks
        )
        XCTAssertEqual(
            LiveActivityCenter.initialOwner(
                agentHighlight: nil,
                openTaskCount: 0,
                isMusicPlaying: true
            ),
            .music
        )
        XCTAssertEqual(
            LiveActivityCenter.initialOwner(
                agentHighlight: nil,
                openTaskCount: 0,
                isMusicPlaying: false
            ),
            .none
        )
    }

    func testResolveFollowsOwnerLastUpdateWins() {
        XCTAssertEqual(
            LiveActivityCenter.resolve(
                owner: .agents,
                agentHighlight: .agents(state: .working, count: 2),
                openTaskCount: 5
            ),
            .agents(state: .working, count: 2)
        )
        XCTAssertEqual(
            LiveActivityCenter.resolve(
                owner: .tasks,
                agentHighlight: .agents(state: .working, count: 2),
                openTaskCount: 5
            ),
            .tasks(count: 5)
        )
        XCTAssertNil(
            LiveActivityCenter.resolve(
                owner: .music,
                agentHighlight: .agents(state: .working, count: 2),
                openTaskCount: 5
            )
        )
        XCTAssertEqual(
            LiveActivityCenter.resolve(
                owner: .agents,
                agentHighlight: .agents(state: .done, count: 2),
                openTaskCount: 5
            ),
            .agents(state: .done, count: 2)
        )
    }

    func testResolveHidesWhenOwnerHasNothingToShow() {
        XCTAssertNil(
            LiveActivityCenter.resolve(
                owner: .agents,
                agentHighlight: nil,
                openTaskCount: 3
            )
        )
        XCTAssertNil(
            LiveActivityCenter.resolve(
                owner: .tasks,
                agentHighlight: .agents(state: .done, count: 1),
                openTaskCount: 0
            )
        )
        XCTAssertNil(
            LiveActivityCenter.resolve(
                owner: .none,
                agentHighlight: .agents(state: .working, count: 1),
                openTaskCount: 2
            )
        )
    }

    func testMusicDIClipsRightEdgeToPhysicalNotch() {
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
                    leftAuxiliaryArea: .zero,
                    rightAuxiliaryArea: .zero
                )
            )
        )

        let physical = DynamicIslandLayout.physicalNotchFrame(display: display)
        XCTAssertEqual(physical, CGRect(x: 400, y: 974, width: 200, height: 26))

        let playingNoDI = DynamicIslandLayout.centeredCapsule(
            for: .collapsed,
            display: display,
            showsNowPlaying: true
        )
        XCTAssertEqual(playingNoDI, CGRect(x: 350, y: 974, width: 300, height: 26))

        let musicDI = DynamicIslandLayout.compactEnvelope(
            for: .collapsed,
            display: display,
            showsNowPlaying: true,
            showsLiveActivity: true
        )
        XCTAssertEqual(musicDI.minX, playingNoDI.minX)
        XCTAssertEqual(musicDI.maxX, physical.maxX)
        XCTAssertEqual(musicDI, CGRect(x: 350, y: 974, width: 250, height: 26))

        let musicHoverDI = DynamicIslandLayout.compactEnvelope(
            for: .hovered,
            display: display,
            showsNowPlaying: true,
            showsLiveActivity: true
        )
        XCTAssertEqual(musicHoverDI.minX, musicDI.minX)
        XCTAssertEqual(musicHoverDI.maxX, physical.maxX)
        XCTAssertEqual(musicHoverDI.width, musicDI.width)
        XCTAssertEqual(musicHoverDI.height, musicDI.height + DynamicIslandLayout.idleHoverExtraHeight)

        let musicPreviewDI = DynamicIslandLayout.compactEnvelope(
            for: .musicPreview,
            display: display,
            showsNowPlaying: true,
            showsLiveActivity: true
        )
        XCTAssertEqual(musicPreviewDI.minX, musicDI.minX)
        XCTAssertEqual(musicPreviewDI.maxX, physical.maxX)
        XCTAssertEqual(musicPreviewDI.width, musicDI.width)
        XCTAssertEqual(musicPreviewDI.height, musicDI.height + 44)

        let idleHoverDI = DynamicIslandLayout.compactEnvelope(
            for: .hovered,
            display: display,
            showsNowPlaying: false,
            showsLiveActivity: true
        )
        XCTAssertEqual(idleHoverDI.midX, physical.midX)
        XCTAssertEqual(
            idleHoverDI.width,
            physical.width + DynamicIslandLayout.idleHoverExtraWidth
        )
        XCTAssertEqual(
            idleHoverDI.height,
            physical.height + DynamicIslandLayout.idleHoverExtraHeight
        )

        let musicBubble = DynamicIslandLayout.bubbleWindowFrame(
            adjacentTo: musicDI,
            restingHeight: physical.height
        )
        let idleBubble = DynamicIslandLayout.bubbleWindowFrame(
            adjacentTo: physical,
            restingHeight: physical.height
        )
        XCTAssertEqual(musicBubble.minX, physical.maxX - DynamicIslandLayout.attachOverlap)
        XCTAssertEqual(idleBubble.minX, physical.maxX - DynamicIslandLayout.attachOverlap)
        XCTAssertEqual(musicBubble.minX, idleBubble.minX)

        XCTAssertEqual(DynamicIslandLayout.bubbleDiameter(anchorHeight: 37), 29)
        XCTAssertEqual(DynamicIslandLayout.bubbleDiameter(anchorHeight: 12), 22)
        XCTAssertEqual(DynamicIslandLayout.bubbleDiameter(anchorHeight: 38), 30)
    }
}
