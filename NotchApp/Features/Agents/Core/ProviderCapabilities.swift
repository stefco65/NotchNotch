import Foundation

struct ProviderCapabilities: Equatable, Sendable {
    var supportsLiveEvents: Bool
    var supportsResync: Bool
    var supportsPermissionState: Bool
    var supportsSubagents: Bool
    var supportsCompletionState: Bool

    static let cursor = ProviderCapabilities(
        supportsLiveEvents: true,
        supportsResync: true,
        supportsPermissionState: false,
        supportsSubagents: false,
        supportsCompletionState: true
    )

    static let codex = ProviderCapabilities(
        supportsLiveEvents: true,
        supportsResync: true,
        supportsPermissionState: true,
        supportsSubagents: false,
        supportsCompletionState: true
    )

    static let antigravity = ProviderCapabilities(
        supportsLiveEvents: true,
        supportsResync: true,
        supportsPermissionState: true,
        supportsSubagents: false,
        supportsCompletionState: true
    )
}

enum AgentCountingMode: String, Sendable {
    case topLevelOnly
    case includeSubagents
}
