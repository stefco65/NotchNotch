import Foundation

/// Native Codex rollout / thread event statuses.
enum CodexAgentStatus: String, AgentToolStatus, CaseIterable, Sendable {
    case taskStarted = "task_started"
    case turnStarted = "turn_started"
    case taskComplete = "task_complete"
    case turnComplete = "turn_complete"
    case execApprovalRequest = "exec_approval_request"
    case applyPatchApprovalRequest = "apply_patch_approval_request"
    case requestUserInput = "request_user_input"
    case requestPermissions = "request_permissions"
    case elicitationRequest = "elicitation_request"
    case collabWaitingBegin = "collab_waiting_begin"
    case turnAborted = "turn_aborted"
    case error
    /// Synthetic: recent rollout log activity without a typed terminal event.
    case recentLogActivity

    var canonicalStatus: AgentStatus {
        switch self {
        case .taskStarted, .turnStarted, .recentLogActivity:
            return .working
        case .taskComplete, .turnComplete:
            return .completed
        case .execApprovalRequest, .applyPatchApprovalRequest, .requestUserInput,
             .requestPermissions, .elicitationRequest, .collabWaitingBegin,
             .turnAborted, .error:
            return .waitingForUser
        }
    }

    static func resolve(eventType: String) -> CodexAgentStatus? {
        CodexAgentStatus(rawValue: eventType)
    }
}
