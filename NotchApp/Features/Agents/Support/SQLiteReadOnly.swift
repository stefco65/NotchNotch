import Foundation
import SQLite3

/// Minimal read-only wrapper around the system SQLite3 C API.
enum SQLiteReadOnly {
    enum Result: Equatable {
        case rows([[String]])
        /// Open/prepare failed (missing WAL, locked, corrupt). Callers should
        /// back off until the on-disk fingerprint changes.
        case unavailable
    }

    /// Executes `sql` against the database and returns all result rows as
    /// arrays of column strings. Returns an empty array on any error.
    static func query(database: URL, sql: String) -> [[String]] {
        switch queryResult(database: database, sql: sql) {
        case .rows(let rows):
            return rows
        case .unavailable:
            return []
        }
    }

    static func queryResult(database: URL, sql: String) -> Result {
        // Skip missing DBs — avoids open/WAL stderr when the store is absent.
        guard FileManager.default.fileExists(atPath: database.path) else {
            return .unavailable
        }

        var handle: OpaquePointer?
        // Plain read-only open so WAL updates from Cursor/Codex stay live.
        // Do not use immutable=1 — that freezes a stale snapshot and delays DI.
        guard sqlite3_open_v2(database.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db = handle else {
            sqlite3_close_v2(handle)
            return .unavailable
        }
        defer { sqlite3_close_v2(db) }
        sqlite3_busy_timeout(db, 200)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let prepared = statement else {
            return .unavailable
        }
        defer { sqlite3_finalize(prepared) }

        var rows: [[String]] = []
        let columnCount = sqlite3_column_count(prepared)
        while sqlite3_step(prepared) == SQLITE_ROW {
            var row: [String] = []
            row.reserveCapacity(Int(columnCount))
            for index in 0..<columnCount {
                if let text = sqlite3_column_text(prepared, index) {
                    row.append(String(cString: text))
                } else {
                    row.append("")
                }
            }
            rows.append(row)
        }
        return .rows(rows)
    }
}

struct AgentMonitorPaths: Sendable {
    let codexStateDatabase: URL
    let codexThreadLocks: URL
    let cursorStateDatabase: URL
    let antigravityAppStorage: URL
    let antigravityConversations: URL

    static func currentUser(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> Self {
        Self(
            codexStateDatabase: homeDirectory.appendingPathComponent(".codex/state_5.sqlite"),
            codexThreadLocks: homeDirectory.appendingPathComponent(".codex/thread-writer-locks"),
            cursorStateDatabase: homeDirectory.appendingPathComponent(
                "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
            ),
            antigravityAppStorage: homeDirectory.appendingPathComponent(
                "Library/Application Support/Antigravity/app_storage.json"
            ),
            antigravityConversations: homeDirectory.appendingPathComponent(
                ".gemini/antigravity/conversations"
            )
        )
    }

    var watchTargets: [URL] {
        AgentProvider.allCases.flatMap { watchTargets(for: $0) }
    }

    /// Filesystem roots observed by each tool's `AgentToolSignalMonitor`.
    func watchTargets(for provider: AgentProvider) -> [URL] {
        switch provider {
        case .codex:
            return [
                codexThreadLocks,
                codexStateDatabase.deletingLastPathComponent()
            ]
        case .cursor:
            return [
                cursorStateDatabase,
                URL(fileURLWithPath: cursorStateDatabase.path + "-wal"),
                URL(fileURLWithPath: cursorStateDatabase.path + "-shm")
            ]
        case .antigravity:
            return [
                antigravityAppStorage,
                antigravityConversations
            ]
        }
    }

    /// Fingerprint of a SQLite main DB + WAL/SHM sidecars. Used to skip
    /// expensive rescans when the on-disk store has not changed.
    static func sqliteFamilyFingerprint(_ database: URL) -> String {
        let candidates = [
            database.path,
            database.path + "-wal",
            database.path + "-shm"
        ]
        return candidates.map { path -> String in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let date = attrs[.modificationDate] as? Date,
                  let size = attrs[.size] as? NSNumber else {
                return "missing"
            }
            return "\(date.timeIntervalSince1970)|\(size.intValue)"
        }.joined(separator: ";")
    }
}
