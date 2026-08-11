import Foundation

/// Provider-native status value that can be projected into the shared
/// `AgentStatus` / `AgentActivityState` buckets used by the Agents UI and DI.
protocol AgentToolStatus: Equatable, Sendable {
    var canonicalStatus: AgentStatus { get }
}

extension AgentToolStatus {
    var activityState: AgentActivityState {
        AgentActivityState(status: canonicalStatus)
    }
}

/// Watches a single AI tool's on-disk / runtime signals and notifies when a
/// resync (and therefore DI / Agents counters) should refresh.
@MainActor
protocol AgentToolSignalMonitor: AnyObject {
    var provider: AgentProvider { get }
    var onChange: (() -> Void)? { get set }

    func start()
    func stop()
}

/// One pluggable AI-tool surface: Cursor, Codex, Antigravity, or a future tool.
/// The factory builds these; `AgentMonitorStore` only talks to this contract.
@MainActor
protocol AgentToolInterface: AnyObject {
    var provider: AgentProvider { get }
    var capabilities: ProviderCapabilities { get }
    var adapter: any AgentProviderAdapter { get }
    var signalMonitor: any AgentToolSignalMonitor { get }

    /// Maps a raw hook / IPC event name into a normalized event kind.
    func mapHookEvent(_ name: String) -> NormalizedAgentEvent.Kind?
}
