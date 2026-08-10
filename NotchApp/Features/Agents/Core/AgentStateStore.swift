import Combine
import Foundation
import OSLog

@MainActor
final class AgentStateStore: ObservableObject {
    @Published private(set) var providers: [AgentProvider: ProviderState] = Dictionary(
        uniqueKeysWithValues: AgentProvider.allCases.map { ($0, ProviderState()) }
    )

    var countingMode: AgentCountingMode = .topLevelOnly

    private var recentEventIDs = Set<String>()
    private let recentEventIDLimit = 512
    private let logger = Logger(subsystem: "com.notchnook", category: "AgentStateStore")

    var summaries: [AgentSourceSummary] {
        AgentProvider.allCases.map { provider in
            let state = providers[provider] ?? ProviderState()
            let snapshot = CounterSnapshot(
                working: state.count(matching: .working, mode: countingMode),
                waiting: state.count(matching: .waitingForUser, mode: countingMode),
                completed: state.count(matching: .completed, mode: countingMode)
            )
            return AgentSourceSummary(
                source: provider,
                counts: snapshot.asAgentCounts,
                isApplicationRunning: state.isApplicationRunning
            )
        }
    }

    var globalCounters: CounterSnapshot {
        summaries.reduce(into: CounterSnapshot.zero) { partial, summary in
            guard summary.isApplicationRunning else { return }
            partial = CounterSnapshot(
                working: partial.working + summary.counts.working,
                waiting: partial.waiting + summary.counts.stopped,
                completed: partial.completed + summary.counts.done
            )
        }
    }

    func providerStarted(_ provider: AgentProvider) {
        var state = providers[provider] ?? ProviderState()
        state.isApplicationRunning = true
        state.instanceID = UUID()
        state.agents.removeAll()
        providers[provider] = state
        logger.notice("provider launched: \(provider.rawValue, privacy: .public) instance=\(state.instanceID.uuidString, privacy: .public)")
        objectWillChange.send()
    }

    func providerStopped(_ provider: AgentProvider) {
        var state = providers[provider] ?? ProviderState()
        state.isApplicationRunning = false
        state.agents.removeAll()
        providers[provider] = state
        logger.notice("provider terminated: \(provider.rawValue, privacy: .public)")
        objectWillChange.send()
    }

    func instanceID(for provider: AgentProvider) -> UUID? {
        guard let state = providers[provider], state.isApplicationRunning else { return nil }
        return state.instanceID
    }

    func handle(_ event: NormalizedAgentEvent) {
        guard var state = providers[event.provider] else { return }

        guard state.isApplicationRunning else {
            logger.debug("event rejected (provider inactive): \(event.provider.rawValue, privacy: .public)")
            return
        }

        guard event.providerInstanceID == state.instanceID else {
            logger.debug("event rejected (stale instance): \(event.provider.rawValue, privacy: .public)")
            return
        }

        if let eventID = event.eventID {
            if recentEventIDs.contains(eventID) {
                logger.debug("event rejected (duplicate): \(eventID, privacy: .public)")
                return
            }
            recentEventIDs.insert(eventID)
            if recentEventIDs.count > recentEventIDLimit {
                recentEventIDs.removeAll(keepingCapacity: true)
            }
        }

        let existing = state.agents[event.agentID]
        if let existing, event.timestamp < existing.updatedAt {
            logger.debug("event rejected (out-of-order): \(event.agentID, privacy: .public)")
            return
        }

        let nextStatus = AgentStateReducer.reduce(current: existing?.status, event: event.kind)
        guard let nextStatus else {
            if state.agents.removeValue(forKey: event.agentID) != nil {
                providers[event.provider] = state
                logger.notice("agent removed: \(event.provider.rawValue, privacy: .public)/\(event.agentID, privacy: .public)")
                objectWillChange.send()
            }
            return
        }

        var snapshot = existing ?? AgentSnapshot(
            id: event.agentID,
            provider: event.provider,
            status: nextStatus,
            lifecycle: .created,
            updatedAt: event.timestamp,
            workspace: event.workspace,
            title: event.title,
            startedAt: event.timestamp,
            parentAgentID: event.parentAgentID,
            isSubagent: event.isSubagent
        )

        let previousStatus = snapshot.status
        snapshot.status = nextStatus
        snapshot.lifecycle = AgentStateReducer.lifecycle(for: nextStatus, previous: snapshot.lifecycle)
        snapshot.updatedAt = event.timestamp
        if let title = event.title { snapshot.title = title }
        if let workspace = event.workspace { snapshot.workspace = workspace }
        snapshot.isSubagent = event.isSubagent || snapshot.isSubagent
        if let parent = event.parentAgentID { snapshot.parentAgentID = parent }
        if snapshot.startedAt == nil {
            snapshot.startedAt = event.timestamp
        }
        if snapshot.lifecycle == .finished {
            snapshot.completedAt = event.timestamp
        }

        state.agents[event.agentID] = snapshot
        providers[event.provider] = state

        if previousStatus != nextStatus || existing == nil {
            logger.notice(
                "agent state changed: \(event.provider.rawValue, privacy: .public)/\(event.agentID, privacy: .public) -> \(nextStatus.rawValue, privacy: .public)"
            )
        }
        objectWillChange.send()
    }

    /// Replaces runtime agents for a provider with a fresh snapshot (resync).
    func replaceAgents(_ agents: [AgentSnapshot], for provider: AgentProvider) {
        guard var state = providers[provider], state.isApplicationRunning else { return }
        var mapped: [String: AgentSnapshot] = [:]
        for agent in agents {
            mapped[agent.id] = agent
        }
        state.agents = mapped
        providers[provider] = state
        logger.notice(
            "resync completed: \(provider.rawValue, privacy: .public) agents=\(agents.count, privacy: .public)"
        )
        objectWillChange.send()
    }

    func debugSnapshot() -> DebugSnapshot {
        DebugSnapshot(
            providers: AgentProvider.allCases.map { provider in
                let state = providers[provider] ?? ProviderState()
                return ProviderDebugInfo(
                    provider: provider,
                    isApplicationRunning: state.isApplicationRunning,
                    instanceID: state.instanceID,
                    agentCount: state.agents.count,
                    counters: state.counterSnapshot,
                    agents: Array(state.agents.values).sorted { $0.updatedAt > $1.updatedAt }
                )
            }
        )
    }
}
