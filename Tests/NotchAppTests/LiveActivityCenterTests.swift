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

    func testBubbleGeometry() {
        // Bubble stays smaller than the notch and clamps for tiny anchors.
        XCTAssertEqual(DynamicIslandBubbleController.bubbleDiameter(anchorHeight: 37), 29)
        XCTAssertEqual(DynamicIslandBubbleController.bubbleDiameter(anchorHeight: 12), 22)
        XCTAssertEqual(DynamicIslandBubbleController.bubbleDiameter(anchorHeight: 60), 32)

        // Window overlaps the notch's right edge and shares its top edge.
        let notch = CGRect(x: 100, y: 900, width: 300, height: 37)
        let frame = DynamicIslandBubbleController.windowFrame(nextTo: notch)
        XCTAssertEqual(frame.minX, notch.maxX - DynamicIslandBubbleController.notchOverlap)
        XCTAssertEqual(frame.maxY, notch.maxY)
        XCTAssertEqual(frame.width, DynamicIslandBubbleController.windowWidth)
    }
}
