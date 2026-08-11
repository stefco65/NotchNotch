import Foundation

/// Native Cursor composer / agent status values used by the Cursor tool interface.
enum CursorAgentStatus: String, AgentToolStatus, CaseIterable, Sendable {
    case generating
    case running
    case runningWithQueuedResume = "runningwithqueuedresume"
    case inProgress = "in_progress"
    case processing
    case ongoing
    case blocked
    case waiting
    case paused
    case interrupted
    case aborted
    case cancelled
    case completed
    case none
    case error
    case failed
    /// Synthetic: `unfinishedRunAt` set while raw status is non-terminal.
    case unfinishedRun
    /// Synthetic: `hasBlockingPendingActions` / pending plan / approval.
    case awaitingApproval

    var canonicalStatus: AgentStatus {
        switch self {
        case .generating, .running, .runningWithQueuedResume, .inProgress,
             .processing, .ongoing, .unfinishedRun:
            return .working
        case .blocked, .waiting, .paused, .interrupted, .awaitingApproval:
            return .waitingForUser
        case .aborted, .cancelled, .completed, .none, .error, .failed:
            return .completed
        }
    }

    /// Resolves Cursor's on-disk composer signals into a single native status.
    static func resolve(from signals: CursorEventMapper.ComposerSignals) -> CursorAgentStatus {
        if signals.hasBlockingPendingActions || signals.hasPendingPlan {
            return .awaitingApproval
        }

        let raw = signals.status.lowercased()
        let parsed = CursorAgentStatus(rawValue: raw)
            ?? (raw == "in-progress" ? .inProgress : nil)

        let isTerminal =
            parsed == CursorAgentStatus.completed
            || parsed == CursorAgentStatus.none
            || parsed == CursorAgentStatus.cancelled
            || parsed == CursorAgentStatus.error
            || parsed == CursorAgentStatus.failed
            || raw == "canceled"

        let isExplicitlyGenerating =
            parsed == .generating
            || parsed == .running
            || parsed == .runningWithQueuedResume
            || parsed == .inProgress
            || parsed == .processing
            || parsed == .ongoing
            || raw == "in-progress"

        if isExplicitlyGenerating
            || signals.isContinuationInProgress
            || signals.generatingBubbleCount > 0
            || (signals.hasUnfinishedRun && !isTerminal) {
            return isExplicitlyGenerating ? (parsed ?? .generating) : .unfinishedRun
        }

        if let parsed {
            return parsed
        }
        if raw == "canceled" { return .cancelled }
        return .completed
    }
}
