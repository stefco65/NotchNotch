import Foundation
import XCTest
@testable import NotchNook

@MainActor
final class AgentToolFactoryTests: XCTestCase {
    func testFactoryBuildsOneToolPerProvider() {
        let tools = AgentToolFactory.makeDefaultTools()
        XCTAssertEqual(Set(tools.map(\.provider)), Set(AgentProvider.allCases))
        XCTAssertEqual(tools.count, AgentProvider.allCases.count)
    }

    func testFactoryMakeMatchesProvider() {
        XCTAssertEqual(AgentToolFactory.make(provider: .cursor).provider, .cursor)
        XCTAssertEqual(AgentToolFactory.make(provider: .codex).provider, .codex)
        XCTAssertEqual(AgentToolFactory.make(provider: .antigravity).provider, .antigravity)
    }

    func testCursorNativeStatusMapsThroughInterfaceEnum() {
        XCTAssertEqual(
            CursorAgentStatus.resolve(from: .init(status: "generating")).canonicalStatus,
            .working
        )
        XCTAssertEqual(
            CursorAgentStatus.resolve(
                from: .init(status: "aborted", hasUnfinishedRun: true)
            ).canonicalStatus,
            .working
        )
        XCTAssertEqual(
            CursorAgentStatus.resolve(
                from: .init(status: "aborted", hasUnfinishedRun: true, hasBlockingPendingActions: true)
            ),
            .awaitingApproval
        )
        XCTAssertEqual(
            CursorAgentStatus.awaitingApproval.activityState,
            .stopped
        )
    }

    func testCodexNativeStatusEnum() {
        XCTAssertEqual(CodexAgentStatus.taskStarted.canonicalStatus, .working)
        XCTAssertEqual(CodexAgentStatus.execApprovalRequest.canonicalStatus, .waitingForUser)
        XCTAssertEqual(CodexAgentStatus.turnComplete.canonicalStatus, .completed)
        XCTAssertEqual(
            CodexAgentStatus.resolve(eventType: "exec_approval_request"),
            .execApprovalRequest
        )
    }

    func testAntigravityNativeStatusEnum() {
        XCTAssertEqual(AntigravityAgentStatus.initializing.canonicalStatus, .working)
        XCTAssertEqual(AntigravityAgentStatus.waitingForUser.canonicalStatus, .waitingForUser)
        XCTAssertEqual(AntigravityAgentStatus.done.canonicalStatus, .completed)
        XCTAssertEqual(
            AntigravityAgentStatus.resolveConversation(lastStatus: 3, hasWorkingStep: true),
            .active
        )
    }

    func testToolHookMappingUsesProviderMapper() {
        let cursor = AgentToolFactory.make(provider: .cursor)
        XCTAssertEqual(cursor.mapHookEvent("awaitingapproval"), .waitingForUser)
        XCTAssertEqual(cursor.mapHookEvent("beforesubmitprompt"), .working)

        let codex = AgentToolFactory.make(provider: .codex)
        XCTAssertEqual(codex.mapHookEvent("permissionrequest"), .waitingForUser)

        let anti = AgentToolFactory.make(provider: .antigravity)
        XCTAssertEqual(anti.mapHookEvent("toolconfirmationpending"), .waitingForUser)
    }

    func testWatchTargetsAreProviderScoped() {
        let paths = AgentMonitorPaths.currentUser()
        XCTAssertFalse(paths.watchTargets(for: .cursor).isEmpty)
        XCTAssertFalse(paths.watchTargets(for: .codex).isEmpty)
        XCTAssertFalse(paths.watchTargets(for: .antigravity).isEmpty)
        XCTAssertEqual(
            Set(paths.watchTargets.map(\.path)),
            Set(AgentProvider.allCases.flatMap { paths.watchTargets(for: $0).map(\.path) })
        )
    }
}
