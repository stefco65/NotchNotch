import Foundation

enum CursorEventMapper {
    struct ComposerSignals: Equatable, Sendable {
        var status: String
        var generatingBubbleCount: Int = 0
        var isContinuationInProgress: Bool = false
        /// Set while a turn is unfinished — Cursor often leaves `status` as
        /// `"aborted"` during active work, so this is the primary "working" signal.
        var hasUnfinishedRun: Bool = false
        /// True when the agent is blocked on user approval / decision.
        var hasBlockingPendingActions: Bool = false
        var hasPendingPlan: Bool = false
    }

    static let recencyWindow: TimeInterval = 3600

    static func status(from signals: ComposerSignals) -> AgentStatus {
        CursorAgentStatus.resolve(from: signals).canonicalStatus
    }

    static func nativeStatus(from signals: ComposerSignals) -> CursorAgentStatus {
        CursorAgentStatus.resolve(from: signals)
    }

    static func shouldInclude(
        status: AgentStatus,
        lastUpdatedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        if status == .working || status == .waitingForUser { return true }
        guard let lastUpdatedAt else { return false }
        return now.timeIntervalSince(lastUpdatedAt) <= recencyWindow
    }

    static func mapHookEvent(_ name: String) -> NormalizedAgentEvent.Kind? {
        switch name.lowercased() {
        case "sessionstart":
            return .started
        case "beforesubmitprompt", "pretooluse", "afteragentthought":
            return .working
        case "permission", "permissionrequest", "awaitingapproval":
            return .waitingForUser
        case "stop", "completed":
            return .completed
        case "aborted", "cancelled":
            return .cancelled
        case "error", "failed":
            return .failed
        default:
            return AgentEventDecoder.mapKind(name)
        }
    }
}
