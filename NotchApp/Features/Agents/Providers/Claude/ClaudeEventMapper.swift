import Foundation

enum ClaudeEventMapper {
    static let recencyWindow: TimeInterval = 3600
    /// Matches Codex: without a typed status, a transcript this fresh means a turn is running.
    static let transcriptActivityWindow: TimeInterval = 90
    /// An idle status written right after launch means no turn has finished yet.
    static let startupGrace: TimeInterval = 3
    private static let maximumProjectDirectoryLength = 200

    static func nativeStatus(
        for session: ClaudeSessionRecord,
        transcriptModifiedAt: Date?,
        now: Date = Date()
    ) -> ClaudeAgentStatus? {
        switch session.status {
        case ClaudeAgentStatus.busy.rawValue:
            return .busy
        case ClaudeAgentStatus.waiting.rawValue:
            return .waiting
        case ClaudeAgentStatus.idle.rawValue:
            guard let finishedAt = session.statusUpdatedAt,
                  now.timeIntervalSince(finishedAt) <= recencyWindow else {
                return nil
            }
            if let startedAt = session.startedAt,
               finishedAt.timeIntervalSince(startedAt) <= startupGrace {
                return nil
            }
            return .idle
        default:
            guard let transcriptModifiedAt else { return nil }
            let age = now.timeIntervalSince(transcriptModifiedAt)
            if age <= transcriptActivityWindow { return .recentTranscriptActivity }
            return age <= recencyWindow ? .idle : nil
        }
    }

    /// Sessions without a status we understand fall back to transcript recency.
    static func publishesTypedStatus(_ session: ClaudeSessionRecord) -> Bool {
        [ClaudeAgentStatus.busy, .waiting, .idle].contains { $0.rawValue == session.status }
    }

    /// Claude Code stores transcripts under `~/.claude/projects/<cwd with non-alphanumerics as "-">`.
    /// Longer paths get a hash suffix we do not reproduce.
    static func projectDirectoryName(forWorkingDirectory cwd: String) -> String? {
        // Mirrors JS `replace(/[^a-zA-Z0-9]/g, "-")`, which works on UTF-16 code units.
        let units = cwd.utf16.map { unit -> UInt8 in
            switch unit {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: UInt8(unit)
            default: UInt8(ascii: "-")
            }
        }
        guard units.count <= maximumProjectDirectoryLength else { return nil }
        return String(decoding: units, as: UTF8.self)
    }

    static func mapHookEvent(_ name: String) -> NormalizedAgentEvent.Kind? {
        switch name.lowercased() {
        case "userpromptsubmit", "pretooluse", "posttooluse":
            return .working
        case "notification", "permissionrequest":
            return .waitingForUser
        case "stop", "subagentstop":
            return .completed
        case "sessionend":
            return .removed
        default:
            return AgentEventDecoder.mapKind(name)
        }
    }
}
