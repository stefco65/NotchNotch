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

    /// For tools that also run without their desktop app (e.g. a terminal CLI):
    /// reports live sessions so presence does not hinge on the app alone.
    /// Runs off the main actor.
    var detachedSessionProbe: (@Sendable () -> Bool)? { get }

    /// Maps a raw hook / IPC event name into a normalized event kind.
    func mapHookEvent(_ name: String) -> NormalizedAgentEvent.Kind?
}

extension AgentToolInterface {
    var detachedSessionProbe: (@Sendable () -> Bool)? { nil }
}
