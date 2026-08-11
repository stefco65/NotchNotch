import Foundation

@MainActor
final class CodexToolInterface: AgentToolInterface {
    let provider: AgentProvider = .codex
    let capabilities: ProviderCapabilities = .codex
    let adapter: any AgentProviderAdapter
    let signalMonitor: any AgentToolSignalMonitor

    init(paths: AgentMonitorPaths = .currentUser()) {
        self.adapter = CodexAdapter(paths: paths)
        self.signalMonitor = FileSystemAgentSignalMonitor(
            provider: .codex,
            watchURLs: paths.watchTargets(for: .codex),
            debounceMilliseconds: 120
        )
    }

    func mapHookEvent(_ name: String) -> NormalizedAgentEvent.Kind? {
        CodexEventMapper.mapHookEvent(name)
    }
}
