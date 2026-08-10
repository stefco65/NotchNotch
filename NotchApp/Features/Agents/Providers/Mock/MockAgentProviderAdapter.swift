import Foundation

/// Deterministic adapter used to exercise Core + UI without live providers.
@MainActor
final class MockAgentProviderAdapter: AgentProviderAdapter {
    let provider: AgentProvider
    var onEvent: ((NormalizedAgentEvent) -> Void)?

    private(set) var health: ProviderHealth = .inactive
    private var instanceID: UUID?
    private var agents: [String: AgentStatus] = [:]

    init(provider: AgentProvider = .cursor) {
        self.provider = provider
    }

    func start(instanceID: UUID) async throws {
        self.instanceID = instanceID
        health = .connected
    }

    func stop() {
        instanceID = nil
        agents.removeAll()
        health = .inactive
    }

    func resync() async throws -> [AgentSnapshot] {
        let now = Date()
        return agents.map { id, status in
            AgentSnapshot(
                id: id,
                provider: provider,
                status: status,
                lifecycle: AgentStateReducer.lifecycle(for: status, previous: nil),
                updatedAt: now
            )
        }
    }

    func emit(agentID: String, kind: NormalizedAgentEvent.Kind, at timestamp: Date = Date()) {
        guard let instanceID else { return }
        if let status = AgentStateReducer.reduce(current: agents[agentID], event: kind) {
            agents[agentID] = status
        } else {
            agents.removeValue(forKey: agentID)
        }
        onEvent?(
            NormalizedAgentEvent(
                provider: provider,
                agentID: agentID,
                kind: kind,
                timestamp: timestamp,
                providerInstanceID: instanceID
            )
        )
    }
}
