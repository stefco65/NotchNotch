import Foundation

/// Builds agent snapshots from live Claude Code sessions (desktop app and CLI).
struct ClaudeResyncService: Sendable {
    let paths: AgentMonitorPaths
    let registry: ClaudeSessionRegistry

    init(
        paths: AgentMonitorPaths = .currentUser(),
        registry: ClaudeSessionRegistry? = nil
    ) {
        self.paths = paths
        self.registry = registry ?? ClaudeSessionRegistry(sessionsDirectory: paths.claudeSessions)
    }

    func snapshotAgents(now: Date = Date()) -> [AgentSnapshot] {
        registry.liveSessions().compactMap { session -> AgentSnapshot? in
            let transcriptModifiedAt = ClaudeEventMapper.publishesTypedStatus(session)
                ? nil
                : transcriptModificationDate(for: session)
            guard let native = ClaudeEventMapper.nativeStatus(
                for: session,
                transcriptModifiedAt: transcriptModifiedAt,
                now: now
            ) else {
                return nil
            }

            let status = native.canonicalStatus
            let updatedAt = session.statusUpdatedAt ?? transcriptModifiedAt ?? session.startedAt ?? now
            return AgentSnapshot(
                id: session.sessionID,
                provider: .claude,
                status: status,
                lifecycle: AgentStateReducer.lifecycle(for: status, previous: nil),
                updatedAt: updatedAt,
                workspace: session.cwd,
                title: session.name,
                description: session.waitingFor,
                startedAt: session.startedAt ?? updatedAt,
                completedAt: status == .completed ? updatedAt : nil
            )
        }
    }

    private func transcriptModificationDate(for session: ClaudeSessionRecord) -> Date? {
        guard let cwd = session.cwd,
              let directory = ClaudeEventMapper.projectDirectoryName(forWorkingDirectory: cwd) else {
            return nil
        }
        let transcript = paths.claudeProjects
            .appendingPathComponent(directory, isDirectory: true)
            .appendingPathComponent("\(session.sessionID).jsonl")
        return try? transcript.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
