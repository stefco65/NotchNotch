import Foundation

struct CodexResyncService: Sendable {
    let paths: AgentMonitorPaths

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

        let identifiers = threadIDs
            .map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
            .joined(separator: ",")
        let rows = SQLiteReadOnly.query(
            database: paths.codexStateDatabase,
            sql: "SELECT id, rollout_path FROM threads WHERE id IN (\(identifiers));"
        )
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

    private static func tailData(of url: URL, maximumBytes: UInt64 = 262_144) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > maximumBytes ? size - maximumBytes : 0)
        return try? handle.readToEnd()
    }
}
