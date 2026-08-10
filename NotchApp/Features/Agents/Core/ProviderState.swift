import Foundation

struct ProviderState: Equatable, Sendable {
    var isApplicationRunning: Bool = false
    var instanceID: UUID = UUID()
    var agents: [String: AgentSnapshot] = [:]

    var workingCount: Int {
        count(matching: .working)
    }

    var waitingCount: Int {
        count(matching: .waitingForUser)
    }

    var completedCount: Int {
        count(matching: .completed)
    }

    func count(matching status: AgentStatus, mode: AgentCountingMode = .topLevelOnly) -> Int {
        guard isApplicationRunning else { return 0 }
        return agents.values.filter { agent in
            guard agent.status == status else { return false }
            if mode == .topLevelOnly, agent.isSubagent {
                return false
            }
            return true
        }.count
    }

    var counterSnapshot: CounterSnapshot {
        CounterSnapshot(
            working: workingCount,
            waiting: waitingCount,
            completed: completedCount
        )
    }
}

struct CounterSnapshot: Equatable, Sendable {
    let working: Int
    let waiting: Int
    let completed: Int

    static let zero = CounterSnapshot(working: 0, waiting: 0, completed: 0)

    var asAgentCounts: AgentCounts {
        AgentCounts(working: working, stopped: waiting, done: completed)
    }
}

struct AgentCounts: Equatable, Sendable {
    var working = 0
    var stopped = 0
    var done = 0

    mutating func add(_ state: AgentActivityState) {
        switch state {
        case .working: working += 1
        case .stopped: stopped += 1
        case .done: done += 1
        }
    }
}

struct AgentSourceSummary: Identifiable, Equatable, Sendable {
    let source: AgentSource
    let counts: AgentCounts
    let isApplicationRunning: Bool

    var id: AgentSource { source }
}
