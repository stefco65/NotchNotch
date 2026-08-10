import Foundation
import OSLog

enum AgentEventLogger {
    private static let logger = Logger(subsystem: "com.notchnook", category: "AgentMonitor")

    static func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        AppErrorLog.record(
            severity: .error,
            category: "agents",
            message: message
        )
    }
}

enum ProviderHealth: Equatable, Sendable {
    case inactive
    case starting
    case connected
    case degraded
    case unavailable
    case error(String)
}

struct ProviderDebugInfo: Equatable, Sendable {
    let provider: AgentProvider
    let isApplicationRunning: Bool
    let instanceID: UUID
    let agentCount: Int
    let counters: CounterSnapshot
    let agents: [AgentSnapshot]
}

struct DebugSnapshot: Equatable, Sendable {
    let providers: [ProviderDebugInfo]
}
