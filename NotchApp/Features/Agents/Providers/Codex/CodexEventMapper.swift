import Foundation

enum CodexEventMapper {
    static let recencyWindow: TimeInterval = 3600

    static func status(fromEventType type: String) -> AgentStatus? {
        CodexAgentStatus.resolve(eventType: type)?.canonicalStatus
    }

    static func nativeStatus(fromEventType type: String) -> CodexAgentStatus? {
        CodexAgentStatus.resolve(eventType: type)
    }

    static func status(
        in rolloutData: Data,
        lastModified: Date? = nil,
        now: Date = Date()
    ) -> AgentStatus? {
        guard let text = String(data: rolloutData, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let type = ((object["payload"] as? [String: Any])?["type"] as? String)
                ?? (object["type"] as? String)
            if let type, let status = status(fromEventType: type) {
                return status
            }
        }
        if let lastModified, now.timeIntervalSince(lastModified) <= 90 {
            return CodexAgentStatus.recentLogActivity.canonicalStatus
        }
        return nil
    }

    static func mapHookEvent(_ name: String) -> NormalizedAgentEvent.Kind? {
        switch name.lowercased() {
        case "sessionstart":
            return .started
        case "userpromptsubmit", "pretooluse", "posttooluse":
            return .working
        case "permissionrequest", "permission":
            return .waitingForUser
        case "stop", "completed":
            return .completed
        case "failed", "error":
            return .failed
        case "cancelled", "aborted":
            return .cancelled
        default:
            return AgentEventDecoder.mapKind(name)
        }
    }
}
