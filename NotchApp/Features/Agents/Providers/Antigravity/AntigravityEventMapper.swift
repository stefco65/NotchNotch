import Foundation

enum AntigravityEventMapper {
    static let recencyWindow: TimeInterval = 3600

    /// Map a raw Antigravity / Jetski `StepStatus` integer.
    static func status(fromStepStatus status: Int) -> AgentStatus {
        switch status {
        case 1, 2:
            return .working
        case 3:
            return .completed
        case 4, 5, 6, 7:
            // WaitingForUser / Error / Canceled / TerminalError — orange bucket.
            return .waitingForUser
        default:
            return status < 3 ? .working : .completed
        }
    }

    static func conversationStatus(
        lastStatus: Int,
        hasWorkingStep: Bool
    ) -> AgentStatus {
        if hasWorkingStep || lastStatus == 1 || lastStatus == 2 {
            return .working
        }
        return status(fromStepStatus: lastStatus)
    }

    static func mapHookEvent(_ name: String) -> NormalizedAgentEvent.Kind? {
        switch name.lowercased() {
        case "preinvocation", "pretooluse", "posttooluse", "thinking", "working", "tool_use", "initializing":
            return .working
        case "toolconfirmationpending", "tool_confirmation_pending", "permission":
            return .waitingForUser
        case "stop", "completed", "idle_finished":
            return .completed
        case "failed", "error":
            return .failed
        case "cancelled", "canceled":
            return .cancelled
        default:
            return AgentEventDecoder.mapKind(name)
        }
    }
}
