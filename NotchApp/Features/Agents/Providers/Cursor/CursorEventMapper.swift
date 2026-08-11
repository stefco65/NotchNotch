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
        // Match Cursor's own header classification priority:
        // needs_attention (blocking / pending plan) > in_progress > done.
        if signals.hasBlockingPendingActions || signals.hasPendingPlan {
            return .waitingForUser
        }

        let status = signals.status.lowercased()

        // Explicit terminal statuses win over a stale unfinishedRunAt —
        // Cursor sometimes leaves unfinishedRunAt set after status flips
        // to completed/none.
        let isTerminal =
            status == "completed"
            || status == "none"
            || status == "cancelled"
            || status == "canceled"
            || status == "error"
            || status == "failed"

        let isExplicitlyGenerating =
            status == "generating"
            || status == "running"
            || status == "runningwithqueuedresume"
            || status == "in_progress"
            || status == "in-progress"
            || status == "processing"
            || status == "ongoing"

        // unfinishedRunAt is the live "still running" signal for aborted /
        // unknown races, but must not override a completed turn.
        let isGenerating =
            isExplicitlyGenerating
            || signals.isContinuationInProgress
            || signals.generatingBubbleCount > 0
            || (signals.hasUnfinishedRun && !isTerminal)

        if isGenerating {
            return .working
        }

        switch status {
        case "blocked", "waiting", "paused", "interrupted":
            // Stopped and waiting for a user decision / permission.
            return .waitingForUser
        case "aborted", "cancelled", "canceled", "error", "failed",
             "completed", "none":
            // Finished / cancelled turns are not "waiting for user".
            return .completed
        default:
            return .completed
        }
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
