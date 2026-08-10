import Foundation

struct CursorResyncService: Sendable {
    let paths: AgentMonitorPaths

    init(paths: AgentMonitorPaths = .currentUser()) {
        self.paths = paths
    }

    func snapshotAgents(now: Date = Date()) -> [AgentSnapshot] {
        let sql = """
        SELECT substr(k.key, 14),
               COALESCE(json_extract(k.value, '$.status'), 'none'),
               COALESCE(json_extract(k.value, '$.lastUpdatedAt'), json_extract(k.value, '$.createdAt'), 0),
               COALESCE(json_array_length(json_extract(k.value, '$.generatingBubbleIds')), 0),
               COALESCE(json_extract(k.value, '$.isContinuationInProgress'), 0)
        FROM cursorDiskKV k
        LEFT JOIN composerHeaders h ON h.composerId = substr(k.key, 14)
        WHERE k.key LIKE 'composerData:%'
          AND COALESCE(json_extract(k.value, '$.isAgentic'), 0) = 1
          AND COALESCE(json_extract(k.value, '$.isDraft'), 0) = 0
          AND COALESCE(h.isArchived, 0) = 0;
        """

        var agents: [AgentSnapshot] = []
        for row in SQLiteReadOnly.query(database: paths.cursorStateDatabase, sql: sql) {
            guard row.count >= 5 else { continue }
            let agentID = row[0]
            guard !agentID.isEmpty else { continue }

            let signals = CursorEventMapper.ComposerSignals(
                status: row[1],
                generatingBubbleCount: Int(row[3]) ?? 0,
                isContinuationInProgress: row[4] == "1" || row[4] == "true"
            )
            let status = CursorEventMapper.status(from: signals)
            let lastUpdatedAt = Double(row[2]).flatMap { value -> Date? in
                value > 0 ? Date(timeIntervalSince1970: value / 1000) : nil
            }
            guard CursorEventMapper.shouldInclude(status: status, lastUpdatedAt: lastUpdatedAt, now: now) else {
                continue
            }

            let updatedAt = lastUpdatedAt ?? now
            agents.append(
                AgentSnapshot(
                    id: agentID,
                    provider: .cursor,
                    status: status,
                    lifecycle: AgentStateReducer.lifecycle(for: status, previous: nil),
                    updatedAt: updatedAt,
                    startedAt: updatedAt,
                    completedAt: status == .completed ? updatedAt : nil
                )
            )
        }
        return agents
    }
}
