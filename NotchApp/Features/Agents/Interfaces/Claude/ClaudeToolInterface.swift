import Foundation

@MainActor
final class ClaudeToolInterface: AgentToolInterface {
    let provider: AgentProvider = .claude
    let capabilities: ProviderCapabilities = .claude
    let adapter: any AgentProviderAdapter
    let signalMonitor: any AgentToolSignalMonitor
    let detachedSessionProbe: (@Sendable () -> Bool)?

    init(paths: AgentMonitorPaths = .currentUser()) {
        let registry = ClaudeSessionRegistry(sessionsDirectory: paths.claudeSessions)
        self.adapter = ClaudeAdapter(paths: paths, registry: registry)
        self.signalMonitor = FileSystemAgentSignalMonitor(
            provider: .claude,
            watchURLs: paths.watchTargets(for: .claude),
            debounceMilliseconds: 120
        )
        // Claude Code also runs as a terminal CLI without Claude.app.
        self.detachedSessionProbe = { registry.hasLiveSessions() }
    }

    func mapHookEvent(_ name: String) -> NormalizedAgentEvent.Kind? {
        ClaudeEventMapper.mapHookEvent(name)
    }
}
