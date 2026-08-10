import Foundation

@MainActor
final class CodexAdapter: AgentProviderAdapter {
    let provider: AgentProvider = .codex
    var onEvent: ((NormalizedAgentEvent) -> Void)?

    private(set) var health: ProviderHealth = .inactive
    private var instanceID: UUID?
    private let resyncService: CodexResyncService

    init(paths: AgentMonitorPaths = .currentUser()) {
        self.resyncService = CodexResyncService(paths: paths)
    }

    func start(instanceID: UUID) async throws {
        self.instanceID = instanceID
        health = .connected
        AgentEventLogger.notice("CodexAdapter started")
    }

    func stop() {
        instanceID = nil
        health = .inactive
        AgentEventLogger.notice("CodexAdapter stopped")
    }

    func resync() async throws -> [AgentSnapshot] {
        health = .connected
        let service = resyncService
        return await Task.detached(priority: .utility) {
            service.snapshotAgents()
        }.value
    }
}
