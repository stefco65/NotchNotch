import Foundation
import XCTest
@testable import NotchNook

final class AgentStatusScannerTests: XCTestCase {
    func testCodexUsesLastTaskEvent() {
        let rollout = Data(
            (#"{"type":"event_msg","payload":{"type":"task_started"}}"# + "\n"
             + #"{"type":"event_msg","payload":{"type":"task_complete"}}"#).utf8
        )

        XCTAssertEqual(AgentStatusScanner.codexState(in: rollout), .done)
    }

    func testCodexTreatsRecentLogActivityAsWorking() {
        let rollout = Data(#"{"payload":{"type":"agent_message"}}"#.utf8)

        XCTAssertEqual(
            AgentStatusScanner.codexState(
                in: rollout,
                lastModified: Date(timeIntervalSince1970: 995),
                now: Date(timeIntervalSince1970: 1_000)
            ),
            .working
        )
    }

    func testCursorStatusMapping() {
        XCTAssertEqual(AgentStatusScanner.cursorState(status: "generating"), .working)
        XCTAssertEqual(AgentStatusScanner.cursorState(status: "blocked"), .stopped)
        XCTAssertEqual(AgentStatusScanner.cursorState(status: "none"), .done)
    }

    func testAntigravityStatusMapping() {
        XCTAssertEqual(AgentStatusScanner.antigravityState(status: 1), .working)
        XCTAssertEqual(AgentStatusScanner.antigravityState(status: 7), .stopped)
        XCTAssertEqual(AgentStatusScanner.antigravityState(status: 3), .done)
    }
}
