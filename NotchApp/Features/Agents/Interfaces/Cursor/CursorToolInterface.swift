import Foundation

@MainActor
final class CursorToolInterface: AgentToolInterface {
    let provider: AgentProvider = .cursor
    let capabilities: ProviderCapabilities = .cursor
    let adapter: any AgentProviderAdapter
    let signalMonitor: any AgentToolSignalMonitor

    init(paths: AgentMonitorPaths = .currentUser()) {
        self.adapter = CursorAdapter(paths: paths)
        self.signalMonitor = FileSystemAgentSignalMonitor(
            provider: .cursor,
            watchURLs: paths.watchTargets(for: .cursor),
            debounceMilliseconds: 120
        )
    }

    func mapHookEvent(_ name: String) -> NormalizedAgentEvent.Kind? {
        CursorEventMapper.mapHookEvent(name)
    }
}
