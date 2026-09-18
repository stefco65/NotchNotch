import Foundation

@MainActor
final class ClaudeAdapter: AgentProviderAdapter {
    let provider: AgentProvider = .claude
    var onEvent: ((NormalizedAgentEvent) -> Void)?

    private(set) var health: ProviderHealth = .inactive
    private var instanceID: UUID?
    private let resyncService: ClaudeResyncService

    init(
        paths: AgentMonitorPaths = .currentUser(),
        registry: ClaudeSessionRegistry? = nil
    ) {
        self.resyncService = ClaudeResyncService(
            paths: paths,
            registry: registry ?? ClaudeSessionRegistry(sessionsDirectory: paths.claudeSessions)
        )
    }

    func start(instanceID: UUID) async throws {
        self.instanceID = instanceID
        health = .connected
        AgentEventLogger.notice("ClaudeAdapter started")
    }

    func stop() {
        instanceID = nil
        health = .inactive
        AgentEventLogger.notice("ClaudeAdapter stopped")
    }

    func resync() async throws -> [AgentSnapshot] {
        health = .connected
        let service = resyncService
        return await Task.detached(priority: .utility) {
            service.snapshotAgents()
        }.value
    }
}
