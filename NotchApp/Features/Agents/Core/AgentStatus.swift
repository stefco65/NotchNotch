import Foundation

enum AgentStatus: String, Codable, Sendable {
    case working
    case waitingForUser
    case completed
    case unknown
    case failed
    case cancelled
}

/// Compact activity bucket used by the notch UI and Dynamic Island.
enum AgentActivityState: Equatable, Sendable {
    case working
    case stopped
    case done

    init(status: AgentStatus) {
        switch status {
        case .working:
            self = .working
        case .waitingForUser, .failed, .cancelled, .unknown:
            self = .stopped
        case .completed:
            self = .done
        }
    }

    var status: AgentStatus {
        switch self {
        case .working: .working
        case .stopped: .waitingForUser
        case .done: .completed
        }
    }
}
