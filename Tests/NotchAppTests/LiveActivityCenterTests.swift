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

    func testAgentHighlightPrefersStoppedThenDoneThenWorking() {
        // Orange (stopped) wins over everything.
        XCTAssertEqual(
            LiveActivityCenter.agentHighlight(from: [
                summary(.codex, working: 2, stopped: 1, done: 3)
            ]),
            .agents(state: .stopped, count: 1)
        )

        // Green (done) wins over blue (working).
        XCTAssertEqual(
            LiveActivityCenter.agentHighlight(from: [
                summary(.codex, working: 2, done: 3)
            ]),
            .agents(state: .done, count: 3)
        )

        XCTAssertEqual(
            LiveActivityCenter.agentHighlight(from: [
                summary(.codex, working: 2)
            ]),
            .agents(state: .working, count: 2)
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

    func testAgentHighlightIsNilWithoutAnyAgents() {
        XCTAssertNil(LiveActivityCenter.agentHighlight(from: [
            summary(.codex),
            summary(.cursor, isRunning: false)
        ]))
    }

    func testResolvePrefersAgentTakeoverOverTasks() {
        XCTAssertEqual(
            LiveActivityCenter.resolve(
                agentHighlight: .agents(state: .stopped, count: 2),
                agentTakeoverActive: true,
                openTaskCount: 5
            ),
            .agents(state: .stopped, count: 2)
        )
    }

    func testResolveFallsBackToTasksAfterTakeover() {
        XCTAssertEqual(
            LiveActivityCenter.resolve(
                agentHighlight: .agents(state: .done, count: 2),
                agentTakeoverActive: false,
                openTaskCount: 5
            ),
            .tasks(count: 5)
        )
    }

    func testResolveHidesBubbleWithNothingToShow() {
        XCTAssertNil(
            LiveActivityCenter.resolve(
                agentHighlight: nil,
                agentTakeoverActive: true,
                openTaskCount: 0
            )
        )
        XCTAssertNil(
            LiveActivityCenter.resolve(
                agentHighlight: .agents(state: .working, count: 1),
                agentTakeoverActive: false,
                openTaskCount: 0
            )
        )
    }

    func testSplitGeometryCutsRightSlotFromEnvelope() {
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

        let envelope = DynamicIslandLayout.compactEnvelope(
            for: .collapsed,
            display: display,
            showsNowPlaying: true,
            showsLiveActivity: true
        )
        XCTAssertEqual(envelope, CGRect(x: 350, y: 974, width: 300, height: 26))

        let main = DynamicIslandLayout.mainNotchFrame(
            envelope: envelope,
            showsLiveActivity: true
        )
        let slot = DynamicIslandLayout.bubbleSlotWidth(surfaceHeight: envelope.height)
        XCTAssertEqual(main.minX, envelope.minX)
        XCTAssertEqual(
            main.width,
            envelope.width - DynamicIslandLayout.splitGap - slot
        )
        // Asymmetric: centroid shifts left of the display center.
        XCTAssertLessThan(main.midX, display.frame.midX)

        let bubbleWindow = DynamicIslandLayout.bubbleWindowFrame(envelope: envelope)
        XCTAssertGreaterThanOrEqual(bubbleWindow.maxX, envelope.maxX - 1)
        XCTAssertEqual(bubbleWindow.maxY, envelope.maxY)

        XCTAssertEqual(DynamicIslandLayout.bubbleDiameter(anchorHeight: 37), 29)
        XCTAssertEqual(DynamicIslandLayout.bubbleDiameter(anchorHeight: 12), 22)
    }
}
