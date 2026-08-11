import Foundation

/// Scans Codex lock files + state DB for live agent snapshots.
///
/// When the state DB cannot be opened (typical: missing `state_5.sqlite-wal`
/// while stale `.lock` files remain), we stop retrying every second until the
/// on-disk fingerprint changes — opening is not free and SQLite spam is loud.
final class CodexResyncService: @unchecked Sendable {
    let paths: AgentMonitorPaths

    private let gate = NSLock()
    /// Fingerprint of the last known-unusable DB. Cleared on a successful open.
    private var unavailableFingerprint: String?

    init(paths: AgentMonitorPaths = .currentUser()) {
        self.paths = paths
    }

    func snapshotAgents(now: Date = Date()) -> [AgentSnapshot] {
        let lockURLs = (try? FileManager.default.contentsOfDirectory(
            at: paths.codexThreadLocks,
            includingPropertiesForKeys: nil
        )) ?? []
        let threadIDs = lockURLs.compactMap { url -> String? in
            guard url.pathExtension == "lock", url.lastPathComponent != ".coordination.lock" else {
                return nil
            }
            return url.deletingPathExtension().lastPathComponent
        }
        guard !threadIDs.isEmpty else { return [] }

        let fingerprint = databaseFingerprint()
        gate.lock()
        let skip = unavailableFingerprint == fingerprint
        gate.unlock()
        if skip {
            return []
        }

        // No point querying when Codex has not created its state DB yet.
        guard FileManager.default.fileExists(atPath: paths.codexStateDatabase.path) else {
            rememberUnavailable(fingerprint)
            return []
        }

        let identifiers = threadIDs
            .map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
            .joined(separator: ",")
        switch SQLiteReadOnly.queryResult(
            database: paths.codexStateDatabase,
            sql: "SELECT id, rollout_path FROM threads WHERE id IN (\(identifiers));"
        ) {
        case .unavailable:
            // Stale locks + broken/missing WAL: do not reopen every tick.
            rememberUnavailable(fingerprint)
            return []
        case .rows(let rows):
            clearUnavailable()
            return buildAgents(threadIDs: threadIDs, rows: rows, now: now)
        }
    }

    private func buildAgents(
        threadIDs: [String],
        rows: [[String]],
        now: Date
    ) -> [AgentSnapshot] {
        let rolloutByID = Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (String, String)? in
            guard row.count == 2 else { return nil }
            return (row[0], row[1])
        })

        var agents: [AgentSnapshot] = []
        for threadID in threadIDs {
            guard let path = rolloutByID[threadID] else { continue }
            let rolloutURL = URL(fileURLWithPath: path)
            let lastModified = try? rolloutURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            guard let data = Self.tailData(of: rolloutURL),
                  let status = CodexEventMapper.status(in: data, lastModified: lastModified, now: now)
            else {
                continue
            }
            if status != .working {
                guard let lastModified,
                      now.timeIntervalSince(lastModified) <= CodexEventMapper.recencyWindow else {
                    continue
                }
            }

            let updatedAt = lastModified ?? now
            agents.append(
                AgentSnapshot(
                    id: threadID,
                    provider: .codex,
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

    private func databaseFingerprint() -> String {
        AgentMonitorPaths.sqliteFamilyFingerprint(paths.codexStateDatabase)
    }

    private func rememberUnavailable(_ fingerprint: String) {
        gate.lock()
        unavailableFingerprint = fingerprint
        gate.unlock()
    }

    private func clearUnavailable() {
        gate.lock()
        unavailableFingerprint = nil
        gate.unlock()
    }

    private static func tailData(of url: URL, maximumBytes: UInt64 = 262_144) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > maximumBytes ? size - maximumBytes : 0)
        return try? handle.readToEnd()
    }
}
