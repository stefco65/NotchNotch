import Foundation

enum AntigravityEventMapper {
    static let recencyWindow: TimeInterval = 3600

    /// Map a raw Antigravity / Jetski `StepStatus` integer.
    static func status(fromStepStatus status: Int) -> AgentStatus {
        AntigravityAgentStatus.resolve(stepStatus: status).canonicalStatus
    }

    static func nativeStatus(fromStepStatus status: Int) -> AntigravityAgentStatus {
        AntigravityAgentStatus.resolve(stepStatus: status)
    }

    static func conversationStatus(
        lastStatus: Int,
        hasWorkingStep: Bool
    ) -> AgentStatus {
        AntigravityAgentStatus.resolveConversation(
            lastStatus: lastStatus,
            hasWorkingStep: hasWorkingStep
        ).canonicalStatus
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
