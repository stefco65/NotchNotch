import Foundation

/// Native Claude Code session statuses published in `~/.claude/sessions/<pid>.json`.
enum ClaudeAgentStatus: String, AgentToolStatus, CaseIterable, Sendable {
    case busy
    /// Blocked on a permission prompt, dialog or elicitation (`waitingFor` says which).
    case waiting
    case idle
    /// Synthetic: older Claude Code builds omit `status`; a fresh transcript write means a turn is running.
    case recentTranscriptActivity

    var canonicalStatus: AgentStatus {
        switch self {
        case .busy, .recentTranscriptActivity:
            return .working
        case .waiting:
            return .waitingForUser
        case .idle:
            return .completed
        }
    }
}
