import Foundation

/// Builds pluggable AI-tool interfaces. Register new tools here when adding
/// another agent product — `AgentMonitorStore` stays provider-agnostic.
enum AgentToolFactory {
    /// Default production set: Codex, Antigravity, Cursor.
    @MainActor
    static func makeDefaultTools(
        paths: AgentMonitorPaths = .currentUser()
    ) -> [any AgentToolInterface] {
        AgentProvider.allCases.map { make(provider: $0, paths: paths) }
    }

    @MainActor
    static func make(
        provider: AgentProvider,
        paths: AgentMonitorPaths = .currentUser()
    ) -> any AgentToolInterface {
        switch provider {
        case .cursor:
            return CursorToolInterface(paths: paths)
        case .codex:
            return CodexToolInterface(paths: paths)
        case .antigravity:
            return AntigravityToolInterface(paths: paths)
        }
    }
}
