import Foundation

enum CursorEventMapper {
    struct ComposerSignals: Equatable, Sendable {
        var status: String
        var generatingBubbleCount: Int = 0
        var isContinuationInProgress: Bool = false
    }

    static let recencyWindow: TimeInterval = 3600

    static func status(from signals: ComposerSignals) -> AgentStatus {
        let status = signals.status.lowercased()
        let isGenerating =
            status == "generating"
            || status == "running"
            || status == "runningwithqueuedresume"
            || status == "in_progress"
            || status == "in-progress"
            || status == "processing"
            || status == "ongoing"
            || signals.isContinuationInProgress
            || signals.generatingBubbleCount > 0

        if isGenerating {
            return .working
        }

        switch status {
        case "aborted", "blocked", "waiting", "paused", "interrupted",
             "cancelled", "canceled", "error", "failed":
            return .waitingForUser
        case "completed", "none":
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
        if status == .working { return true }
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
