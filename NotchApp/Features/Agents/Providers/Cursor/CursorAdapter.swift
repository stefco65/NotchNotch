import Foundation

@MainActor
final class CursorAdapter: AgentProviderAdapter {
    let provider: AgentProvider = .cursor
    var onEvent: ((NormalizedAgentEvent) -> Void)?

    private(set) var health: ProviderHealth = .inactive
    private var instanceID: UUID?
    private let resyncService: CursorResyncService

    init(paths: AgentMonitorPaths = .currentUser()) {
        self.resyncService = CursorResyncService(paths: paths)
    }

    func start(instanceID: UUID) async throws {
        self.instanceID = instanceID
        health = .connected
        AgentEventLogger.notice("CursorAdapter started")
    }

    func stop() {
        instanceID = nil
        health = .inactive
        AgentEventLogger.notice("CursorAdapter stopped")
    }

    func resync() async throws -> [AgentSnapshot] {
        health = .connected
        let service = resyncService
        return await Task.detached(priority: .utility) {
            service.snapshotAgents()
        }.value
    }
}
