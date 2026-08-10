import Foundation

@MainActor
final class AntigravityAdapter: AgentProviderAdapter {
    let provider: AgentProvider = .antigravity
    var onEvent: ((NormalizedAgentEvent) -> Void)?

    private(set) var health: ProviderHealth = .inactive
    private var instanceID: UUID?
    private let resyncService: AntigravityResyncService

    init(paths: AgentMonitorPaths = .currentUser()) {
        self.resyncService = AntigravityResyncService(paths: paths)
    }

    func start(instanceID: UUID) async throws {
        self.instanceID = instanceID
        health = .connected
        AgentEventLogger.notice("AntigravityAdapter started")
    }

    func stop() {
        instanceID = nil
        health = .inactive
        AgentEventLogger.notice("AntigravityAdapter stopped")
    }

    func resync() async throws -> [AgentSnapshot] {
        health = .connected
        let service = resyncService
        return await Task.detached(priority: .utility) {
            service.snapshotAgents()
        }.value
    }
}
