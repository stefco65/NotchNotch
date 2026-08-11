import Foundation

/// Native Antigravity / Jetski `StepStatus` integers.
enum AntigravityAgentStatus: Int, AgentToolStatus, CaseIterable, Sendable {
    case unspecified = 0
    case initializing = 1
    case active = 2
    case done = 3
    case waitingForUser = 4
    case error = 5
    case canceled = 6
    case terminalError = 7

    var canonicalStatus: AgentStatus {
        switch self {
        case .initializing, .active:
            return .working
        case .done, .unspecified:
            return .completed
        case .waitingForUser, .error, .canceled, .terminalError:
            return .waitingForUser
        }
    }

    static func resolve(stepStatus: Int) -> AntigravityAgentStatus {
        AntigravityAgentStatus(rawValue: stepStatus)
            ?? (stepStatus < 3 ? .active : .done)
    }

    static func resolveConversation(lastStatus: Int, hasWorkingStep: Bool) -> AntigravityAgentStatus {
        if hasWorkingStep || lastStatus == 1 || lastStatus == 2 {
            return lastStatus == 1 ? .initializing : .active
        }
        return resolve(stepStatus: lastStatus)
    }
}
