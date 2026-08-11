import Foundation

/// Scans Cursor's `state.vscdb` for agentic composers.
///
/// Full SQL scans are expensive. We cache the last snapshot against the
/// sqlite file-family fingerprint (db/wal/shm). Reconciliation can tick every
/// second cheaply; a real rescan runs only when Cursor writes the store (or
/// the FS watcher asks for one after a change).
final class CursorResyncService: @unchecked Sendable {
    let paths: AgentMonitorPaths

    private let gate = NSLock()
    private var cachedFingerprint: String?
    private var cachedAgents: [AgentSnapshot] = []

    init(paths: AgentMonitorPaths = .currentUser()) {
        self.paths = paths
    }

    func snapshotAgents(now: Date = Date()) -> [AgentSnapshot] {
        let fingerprint = AgentMonitorPaths.sqliteFamilyFingerprint(paths.cursorStateDatabase)
        gate.lock()
        if cachedFingerprint == fingerprint {
            let cached = cachedAgents
            gate.unlock()
            return cached.filter {
                CursorEventMapper.shouldInclude(
                    status: $0.status,
                    lastUpdatedAt: $0.updatedAt,
                    now: now
                )
            }
        }
        gate.unlock()

        let agents = scanAgents(now: now)
        gate.lock()
        cachedFingerprint = fingerprint
        cachedAgents = agents
        gate.unlock()
        return agents
    }

    private func scanAgents(now: Date) -> [AgentSnapshot] {
        // Prefer composerHeaders.value for unfinishedRunAt / blocking flags —
        // that head document is what Cursor uses for its own status chips.
        // Fall back to composerData fields when the header omits them.
        let sql = """
        SELECT substr(k.key, 14),
               COALESCE(json_extract(k.value, '$.status'), 'none'),
               COALESCE(
                   json_extract(k.value, '$.lastUpdatedAt'),
                   json_extract(h.value, '$.lastUpdatedAt'),
                   json_extract(k.value, '$.createdAt'),
                   h.lastUpdatedAt,
                   0
               ),
               COALESCE(json_array_length(json_extract(k.value, '$.generatingBubbleIds')), 0),
               COALESCE(json_extract(k.value, '$.isContinuationInProgress'), 0),
               CASE
                   WHEN json_extract(h.value, '$.unfinishedRunAt') IS NOT NULL THEN 1
                   WHEN json_extract(k.value, '$.unfinishedRunAt') IS NOT NULL THEN 1
                   ELSE 0
               END,
               CASE
                   WHEN COALESCE(json_extract(h.value, '$.hasBlockingPendingActions'), 0) IN (1, 'true') THEN 1
                   WHEN COALESCE(json_extract(k.value, '$.hasBlockingPendingActions'), 0) IN (1, 'true') THEN 1
                   ELSE 0
               END,
               CASE
                   WHEN COALESCE(json_extract(h.value, '$.hasPendingPlan'), 0) IN (1, 'true') THEN 1
                   WHEN COALESCE(json_extract(k.value, '$.hasPendingPlan'), 0) IN (1, 'true') THEN 1
                   ELSE 0
               END
        FROM cursorDiskKV k
        LEFT JOIN composerHeaders h ON h.composerId = substr(k.key, 14)
        WHERE k.key LIKE 'composerData:%'
          AND COALESCE(json_extract(k.value, '$.isAgentic'), 0) = 1
          AND COALESCE(json_extract(k.value, '$.isDraft'), 0) = 0
          AND COALESCE(json_extract(h.value, '$.isDraft'), 0) = 0
          AND COALESCE(h.isArchived, 0) = 0;
        """

        var agents: [AgentSnapshot] = []
        for row in SQLiteReadOnly.query(database: paths.cursorStateDatabase, sql: sql) {
            guard row.count >= 8 else { continue }
            let agentID = row[0]
            guard !agentID.isEmpty else { continue }

            let signals = CursorEventMapper.ComposerSignals(
                status: row[1],
                generatingBubbleCount: Int(row[3]) ?? 0,
                isContinuationInProgress: row[4] == "1" || row[4] == "true",
                hasUnfinishedRun: row[5] == "1" || row[5] == "true",
                hasBlockingPendingActions: row[6] == "1" || row[6] == "true",
                hasPendingPlan: row[7] == "1" || row[7] == "true"
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
