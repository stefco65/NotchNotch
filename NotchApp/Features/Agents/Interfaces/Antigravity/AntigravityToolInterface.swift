import Foundation

@MainActor
final class AntigravityToolInterface: AgentToolInterface {
    let provider: AgentProvider = .antigravity
    let capabilities: ProviderCapabilities = .antigravity
    let adapter: any AgentProviderAdapter
    let signalMonitor: any AgentToolSignalMonitor

    init(paths: AgentMonitorPaths = .currentUser()) {
        self.adapter = AntigravityAdapter(paths: paths)
        self.signalMonitor = FileSystemAgentSignalMonitor(
            provider: .antigravity,
            watchURLs: paths.watchTargets(for: .antigravity),
            debounceMilliseconds: 120
        )
    }

    func mapHookEvent(_ name: String) -> NormalizedAgentEvent.Kind? {
        AntigravityEventMapper.mapHookEvent(name)
    }
}
