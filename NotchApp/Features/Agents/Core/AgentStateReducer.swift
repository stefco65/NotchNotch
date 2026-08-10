import Foundation

enum AgentStateReducer {
    static func reduce(
        current: AgentStatus?,
        event: NormalizedAgentEvent.Kind
    ) -> AgentStatus? {
        switch event {
        case .started, .working, .resumed:
            return .working
        case .waitingForUser:
            return .waitingForUser
        case .completed:
            return .completed
        case .failed:
            return .failed
        case .cancelled:
            return .cancelled
        case .removed:
            return nil
        }
    }

    static func lifecycle(
        for status: AgentStatus?,
        previous: AgentLifecycle?
    ) -> AgentLifecycle {
        guard let status else {
            return previous ?? .created
        }
        switch status {
        case .working, .waitingForUser, .unknown:
            return .executing
        case .completed, .failed, .cancelled:
            return .finished
        }
    }
}
