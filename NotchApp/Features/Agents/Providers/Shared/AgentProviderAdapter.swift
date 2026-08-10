import Foundation

@MainActor
protocol AgentProviderAdapter: AnyObject {
    var provider: AgentProvider { get }
    var capabilities: ProviderCapabilities { get }
    var health: ProviderHealth { get }
    var onEvent: ((NormalizedAgentEvent) -> Void)? { get set }

    func start(instanceID: UUID) async throws
    func stop()
    func resync() async throws -> [AgentSnapshot]
}

@MainActor
extension AgentProviderAdapter {
    var capabilities: ProviderCapabilities {
        switch provider {
        case .cursor: .cursor
        case .codex: .codex
        case .antigravity: .antigravity
        }
    }
}
