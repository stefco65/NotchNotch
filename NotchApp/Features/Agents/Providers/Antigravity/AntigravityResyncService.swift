import Foundation

struct AntigravityResyncService: Sendable {
    let paths: AgentMonitorPaths

    init(paths: AgentMonitorPaths = .currentUser()) {
        self.paths = paths
    }

    func snapshotAgents(now: Date = Date()) -> [AgentSnapshot] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: paths.antigravityConversations,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        let cutoff = now.addingTimeInterval(-AntigravityEventMapper.recencyWindow)
        var agents: [AgentSnapshot] = []

        for url in urls where url.pathExtension == "db" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            guard modified > cutoff else { continue }

            let row = SQLiteReadOnly.query(
                database: url,
                sql: """
                SELECT (SELECT status FROM steps ORDER BY idx DESC LIMIT 1),
                       EXISTS(SELECT 1 FROM steps WHERE status IN (1, 2) LIMIT 1);
                """
            ).first
            guard let row, row.count == 2, let lastStatus = Int(row[0]) else { continue }

            let status = AntigravityEventMapper.conversationStatus(
                lastStatus: lastStatus,
                hasWorkingStep: row[1] == "1"
            )
            let agentID = url.deletingPathExtension().lastPathComponent
            agents.append(
                AgentSnapshot(
                    id: agentID,
                    provider: .antigravity,
                    status: status,
                    lifecycle: AgentStateReducer.lifecycle(for: status, previous: nil),
                    updatedAt: modified,
                    startedAt: modified,
                    completedAt: status == .completed ? modified : nil
                )
            )
        }
        return agents
    }
}
