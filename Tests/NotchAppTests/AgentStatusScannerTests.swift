import Foundation
import SQLite3
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

    func testCodexApprovalAndWaitingEventsAreStopped() {
        XCTAssertEqual(
            AgentStatusScanner.codexEventState(type: "exec_approval_request"),
            .stopped
        )
        XCTAssertEqual(
            AgentStatusScanner.codexEventState(type: "request_user_input"),
            .stopped
        )
        XCTAssertEqual(
            AgentStatusScanner.codexEventState(type: "turn_started"),
            .working
        )

        let waiting = Data(
            (#"{"payload":{"type":"task_started"}}"# + "\n"
             + #"{"payload":{"type":"exec_approval_request"}}"#).utf8
        )
        XCTAssertEqual(AgentStatusScanner.codexState(in: waiting), .stopped)
    }

    func testCursorStatusMapping() {
        XCTAssertEqual(AgentStatusScanner.cursorState(status: "generating"), .working)
        XCTAssertEqual(AgentStatusScanner.cursorState(status: "blocked"), .stopped)
        XCTAssertEqual(AgentStatusScanner.cursorState(status: "aborted"), .done)
        XCTAssertEqual(AgentStatusScanner.cursorState(status: "completed"), .done)
        XCTAssertEqual(AgentStatusScanner.cursorState(status: "none"), .done)
    }

    func testCursorGeneratingBubbleIdsCountAsWorking() {
        // Cursor keeps status as "aborted" in some races while bubbles are
        // still generating — bubble count must win so working stays blue.
        XCTAssertEqual(
            AgentStatusScanner.cursorState(
                .init(status: "aborted", generatingBubbleCount: 2)
            ),
            .working
        )
        XCTAssertEqual(
            AgentStatusScanner.cursorState(
                .init(status: "none", generatingBubbleCount: 1)
            ),
            .working
        )
        XCTAssertEqual(
            AgentStatusScanner.cursorState(
                .init(status: "completed", isContinuationInProgress: true)
            ),
            .working
        )
        XCTAssertEqual(
            AgentStatusScanner.cursorState(
                .init(status: "aborted", generatingBubbleCount: 0)
            ),
            .done
        )
    }

    func testCursorUnfinishedRunCountsAsWorkingDespiteAbortedStatus() {
        // Live Cursor agent turns often persist status="aborted" while
        // unfinishedRunAt is still set — that must stay in the blue bucket.
        XCTAssertEqual(
            AgentStatusScanner.cursorState(
                .init(status: "aborted", hasUnfinishedRun: true)
            ),
            .working
        )
        // Explicit completed/none win over a stale unfinishedRunAt.
        XCTAssertEqual(
            AgentStatusScanner.cursorState(
                .init(status: "none", hasUnfinishedRun: true)
            ),
            .done
        )
        XCTAssertEqual(
            AgentStatusScanner.cursorState(
                .init(status: "completed", hasUnfinishedRun: true)
            ),
            .done
        )
    }

    func testCursorBlockingPendingActionsAreOrange() {
        // Waiting for user approval / decision beats an unfinished run.
        XCTAssertEqual(
            AgentStatusScanner.cursorState(
                .init(
                    status: "aborted",
                    hasUnfinishedRun: true,
                    hasBlockingPendingActions: true
                )
            ),
            .stopped
        )
        XCTAssertEqual(
            AgentStatusScanner.cursorState(
                .init(status: "completed", hasPendingPlan: true)
            ),
            .stopped
        )
        XCTAssertEqual(
            AgentStatusScanner.cursorState(status: "waiting"),
            .stopped
        )
    }

    func testCursorRecencyFilter() {
        let now = Date(timeIntervalSince1970: 100_000)

        // Working agents are always included, even with no timestamp.
        XCTAssertTrue(AgentStatusScanner.cursorShouldInclude(
            state: .working, lastUpdatedAt: nil, now: now
        ))

        // Waiting-for-user agents are always included (permission prompts).
        XCTAssertTrue(AgentStatusScanner.cursorShouldInclude(
            state: .stopped, lastUpdatedAt: nil, now: now
        ))

        // Finished agents count only within the recency window.
        XCTAssertTrue(AgentStatusScanner.cursorShouldInclude(
            state: .done,
            lastUpdatedAt: now.addingTimeInterval(-AgentStatusScanner.recencyWindow + 1),
            now: now
        ))
        XCTAssertFalse(AgentStatusScanner.cursorShouldInclude(
            state: .done,
            lastUpdatedAt: now.addingTimeInterval(-AgentStatusScanner.recencyWindow - 1),
            now: now
        ))
    }

    func testAntigravityStatusMapping() {
        XCTAssertEqual(AgentStatusScanner.antigravityState(status: 1), .working)
        XCTAssertEqual(AgentStatusScanner.antigravityState(status: 2), .working)
        XCTAssertEqual(AgentStatusScanner.antigravityState(status: 3), .done)
        XCTAssertEqual(AgentStatusScanner.antigravityState(status: 4), .stopped) // WaitingForUser
        XCTAssertEqual(AgentStatusScanner.antigravityState(status: 5), .stopped) // Error
        XCTAssertEqual(AgentStatusScanner.antigravityState(status: 7), .stopped)
    }

    func testAntigravityConversationState() {
        // In-progress steps win over a stale terminal last status.
        XCTAssertEqual(
            AgentStatusScanner.antigravityConversationState(lastStatus: 3, hasWorkingStep: true),
            .working
        )
        XCTAssertEqual(
            AgentStatusScanner.antigravityConversationState(lastStatus: 7, hasWorkingStep: false),
            .stopped
        )
        XCTAssertEqual(
            AgentStatusScanner.antigravityConversationState(lastStatus: 4, hasWorkingStep: false),
            .stopped
        )
        XCTAssertEqual(
            AgentStatusScanner.antigravityConversationState(lastStatus: 2, hasWorkingStep: true),
            .working
        )
        // Last step itself is Active even if the EXISTS subquery missed it.
        XCTAssertEqual(
            AgentStatusScanner.antigravityConversationState(lastStatus: 2, hasWorkingStep: false),
            .working
        )
        XCTAssertEqual(
            AgentStatusScanner.antigravityConversationState(lastStatus: 3, hasWorkingStep: false),
            .done
        )
    }

    // MARK: - SQLiteReadOnly

    func testSQLiteReadOnlyReadsRows() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-scanner-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        var db: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open_v2(
                databaseURL.path, &db,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil
            ),
            SQLITE_OK
        )
        defer { sqlite3_close_v2(db) }
        XCTAssertEqual(sqlite3_exec(
            db,
            """
            CREATE TABLE steps (idx INTEGER, status INTEGER);
            INSERT INTO steps VALUES (0, 2), (1, 3);
            """,
            nil, nil, nil
        ), SQLITE_OK)

        let rows = SQLiteReadOnly.query(
            database: databaseURL,
            sql: """
            SELECT (SELECT status FROM steps ORDER BY idx DESC LIMIT 1),
                   EXISTS(SELECT 1 FROM steps WHERE status = 2 LIMIT 1);
            """
        )
        XCTAssertEqual(rows, [["3", "1"]])
    }

    func testSQLiteReadOnlyReturnsEmptyForMissingDatabase() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).sqlite")
        XCTAssertEqual(SQLiteReadOnly.query(database: missing, sql: "SELECT 1;"), [])
    }
}
