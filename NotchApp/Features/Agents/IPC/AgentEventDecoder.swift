import Foundation

/// Wire format for events received from `agentbridge` / provider hooks.
struct AgentEventPayload: Codable, Equatable, Sendable {
    var version: Int
    var provider: String
    var agentId: String
    var event: String
    var timestamp: String?
    var unixTimestamp: TimeInterval?
    var providerInstanceId: String?
    var eventId: String?
    var title: String?
    var workspace: String?
    var isSubagent: Bool?
    var parentAgentId: String?

    enum CodingKeys: String, CodingKey {
        case version
        case provider
        case agentId
        case event
        case timestamp
        case unixTimestamp
        case providerInstanceId
        case eventId
        case title
        case workspace
        case isSubagent
        case parentAgentId
    }
}

enum AgentEventDecoder {
    static func decode(_ data: Data) throws -> AgentEventPayload {
        try JSONDecoder().decode(AgentEventPayload.self, from: data)
    }

    static func normalize(
        _ payload: AgentEventPayload,
        fallbackInstanceID: UUID?,
        kindOverride: NormalizedAgentEvent.Kind? = nil
    ) -> NormalizedAgentEvent? {
        guard let provider = AgentProvider(rawValue: payload.provider.lowercased()) else {
            return nil
        }
        guard let kind = kindOverride ?? mapKind(payload.event) else {
            return nil
        }

        let timestamp: Date
        if let unix = payload.unixTimestamp {
            timestamp = Date(timeIntervalSince1970: unix)
        } else if let raw = payload.timestamp, let parsed = parseTimestamp(raw) {
            timestamp = parsed
        } else {
            timestamp = Date()
        }

        let instanceID: UUID
        if let raw = payload.providerInstanceId, let parsed = UUID(uuidString: raw) {
            instanceID = parsed
        } else if let fallbackInstanceID {
            instanceID = fallbackInstanceID
        } else {
            return nil
        }

        return NormalizedAgentEvent(
            provider: provider,
            agentID: payload.agentId,
            kind: kind,
            timestamp: timestamp,
            providerInstanceID: instanceID,
            eventID: payload.eventId,
            title: payload.title,
            workspace: payload.workspace,
            isSubagent: payload.isSubagent ?? false,
            parentAgentID: payload.parentAgentId
        )
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    static func mapKind(_ raw: String) -> NormalizedAgentEvent.Kind? {
        switch raw.lowercased() {
        case "started", "start", "sessionstart":
            return .started
        case "working", "resume", "resumed", "tool", "thinking":
            return .working
        case "waiting", "waitingforuser", "permission", "approval":
            return .waitingForUser
        case "completed", "complete", "stop", "done":
            return .completed
        case "failed", "error":
            return .failed
        case "cancelled", "canceled", "aborted":
            return .cancelled
        case "removed", "remove":
            return .removed
        default:
            return NormalizedAgentEvent.Kind(rawValue: raw)
        }
    }
}

enum AgentEventEncoder {
    static func encode(_ payload: AgentEventPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }
}
