import AppKit
import Combine
import Foundation
import SQLite3

enum AgentActivityState: Equatable, Sendable {
    case working
    case stopped
    case done
}

enum AgentSource: String, CaseIterable, Identifiable, Sendable {
    case codex
    case antigravity
    case cursor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .cursor: "Cursor"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .codex: "com.openai.codex"
        case .antigravity: "com.google.antigravity"
        case .cursor: "com.todesktop.230313mzl4w4u92"
        }
    }

    var applicationPath: String {
        switch self {
        case .codex: "/Applications/ChatGPT.app"
        case .antigravity: "/Applications/Antigravity.app"
        case .cursor: "/Applications/Cursor.app"
        }
    }
}

struct AgentCounts: Equatable, Sendable {
    var working = 0
    var stopped = 0
    var done = 0

    mutating func add(_ state: AgentActivityState) {
        switch state {
        case .working: working += 1
        case .stopped: stopped += 1
        case .done: done += 1
        }
    }
}

struct AgentSourceSummary: Identifiable, Equatable, Sendable {
    let source: AgentSource
    let counts: AgentCounts
    let isApplicationRunning: Bool

    var id: AgentSource { source }
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

    /// All directories / files worth watching with kqueue so that any write
    /// triggers a re-scan immediately.
    var watchTargets: [URL] {
        [
            codexThreadLocks,
            codexStateDatabase.deletingLastPathComponent(),
            cursorStateDatabase,
            antigravityAppStorage,
            antigravityConversations
        ]
    }
}

// MARK: - Read-only SQLite access (in-process)

/// Minimal read-only wrapper around the system SQLite3 C API.
///
/// The previous implementation spawned `/usr/bin/sqlite3` processes and waited
/// for them with `waitUntilExit()` before draining stdout, which deadlocks as
/// soon as the output exceeds the pipe buffer and permanently blocks a thread
/// of the Swift Concurrency pool. Querying in-process avoids the whole class
/// of problems and is an order of magnitude cheaper per scan.
enum SQLiteReadOnly {
    /// Executes `sql` against the database and returns all result rows as
    /// arrays of column strings. Returns an empty array on any error
    /// (missing file, locked database, unknown table, ...).
    static func query(database: URL, sql: String) -> [[String]] {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(database.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db = handle else {
            sqlite3_close_v2(handle)
            return []
        }
        defer { sqlite3_close_v2(db) }
        // Never wait longer than 200 ms on a live writer's lock.
        sqlite3_busy_timeout(db, 200)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let prepared = statement else {
            return []
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
        return rows
    }
}

// MARK: - AgentStatusScanner

struct AgentStatusScanner: Sendable {
    let paths: AgentMonitorPaths

    /// Conversations not updated within this window are ignored so that the
    /// component shows the current session, not all-time history.
    static let recencyWindow: TimeInterval = 3600

    init(paths: AgentMonitorPaths = .currentUser()) {
        self.paths = paths
    }

    func scan(runningBundleIdentifiers: Set<String>) -> [AgentSourceSummary] {
        AgentSource.allCases.map { source in
            let isRunning = runningBundleIdentifiers.contains(source.bundleIdentifier)
            guard isRunning else {
                return AgentSourceSummary(
                    source: source,
                    counts: AgentCounts(),
                    isApplicationRunning: false
                )
            }

            let counts: AgentCounts
            switch source {
            case .codex: counts = scanCodex()
            case .antigravity: counts = scanAntigravity()
            case .cursor: counts = scanCursor()
            }
            return AgentSourceSummary(
                source: source,
                counts: counts,
                isApplicationRunning: true
            )
        }
    }

    // MARK: State mapping (pure, unit-tested)

    static func codexState(
        in rolloutData: Data,
        lastModified: Date? = nil,
        now: Date = Date()
    ) -> AgentActivityState? {
        guard let text = String(data: rolloutData, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let type = ((object["payload"] as? [String: Any])?["type"] as? String)
                ?? (object["type"] as? String)
            switch type {
            case "task_started": return .working
            case "turn_aborted": return .stopped
            case "task_complete": return .done
            default: continue
            }
        }
        if let lastModified, now.timeIntervalSince(lastModified) <= 90 {
            return .working
        }
        return nil
    }

    static func cursorState(status: String) -> AgentActivityState {
        switch status.lowercased() {
        case "generating", "running", "in_progress", "in-progress", "processing",
             "ongoing", "runningwithqueuedresume":
            return .working
        case "blocked", "waiting", "paused", "interrupted", "aborted", "cancelled",
             "canceled", "error", "failed":
            return .stopped
        default:
            return .done
        }
    }

    /// Whether a Cursor conversation should be counted at all.
    /// Working agents are always shown; finished / stopped ones only while
    /// they were updated recently, so old history doesn't inflate the counts.
    static func cursorShouldInclude(
        state: AgentActivityState,
        lastUpdatedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        if state == .working { return true }
        guard let lastUpdatedAt else { return false }
        return now.timeIntervalSince(lastUpdatedAt) <= recencyWindow
    }

    /// Map a raw Antigravity step status integer to an agent activity state.
    /// Values observed in real databases:
    ///   2 = in-progress / generating
    ///   3 = done / completed
    ///   7 = stopped / aborted
    static func antigravityState(status: Int) -> AgentActivityState {
        switch status {
        case 2:         return .working
        case 3:         return .done
        case 7:         return .stopped
        default:
            return status < 3 ? .working : .done
        }
    }

    /// Derive the overall state of one conversation from its step data.
    /// Rules:
    ///  1. The LAST step's status wins for working/done/stopped.
    ///     (A single intermediate aborted step should not make a finished
    ///      conversation appear as stopped.)
    ///  2. If the last step is in-progress but there is also a more-recent
    ///     finished step, we trust the finished one.
    static func antigravityConversationState(
        lastStatus: Int,
        hasWorkingStep: Bool
    ) -> AgentActivityState {
        // If last step is definitively done or stopped, trust it.
        if lastStatus == 3 { return .done }
        if lastStatus == 7 { return .stopped }
        // Last step is in-progress (2) or unknown.
        if hasWorkingStep { return .working }
        return .done
    }

    // MARK: Per-source scans

    private func scanCodex() -> AgentCounts {
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
        guard !threadIDs.isEmpty else { return AgentCounts() }

        let identifiers = threadIDs
            .map { "'\($0.replacingOccurrences(of: "'", with: "''"))'"}
            .joined(separator: ",")
        let rows = SQLiteReadOnly.query(
            database: paths.codexStateDatabase,
            sql: "SELECT id, rollout_path FROM threads WHERE id IN (\(identifiers));"
        )
        let rolloutByID = Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (String, String)? in
            guard row.count == 2 else { return nil }
            return (row[0], row[1])
        })

        var counts = AgentCounts()
        for threadID in threadIDs {
            guard let path = rolloutByID[threadID] else {
                counts.add(.stopped)
                continue
            }
            let rolloutURL = URL(fileURLWithPath: path)
            let lastModified = try? rolloutURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            guard let data = tailData(of: rolloutURL),
                  let state = Self.codexState(in: data, lastModified: lastModified) else {
                counts.add(.stopped)
                continue
            }
            counts.add(state)
        }
        return counts
    }

    private func scanCursor() -> AgentCounts {
        let sql = """
        SELECT COALESCE(json_extract(k.value, '$.status'), 'none'),
               COALESCE(json_extract(k.value, '$.lastUpdatedAt'), json_extract(k.value, '$.createdAt'), 0)
        FROM cursorDiskKV k
        LEFT JOIN composerHeaders h ON h.composerId = substr(k.key, 14)
        WHERE k.key LIKE 'composerData:%'
          AND COALESCE(json_extract(k.value, '$.isAgentic'), 0) = 1
          AND COALESCE(json_extract(k.value, '$.isDraft'), 0) = 0
          AND COALESCE(h.isArchived, 0) = 0;
        """
        var counts = AgentCounts()
        let now = Date()
        for row in SQLiteReadOnly.query(database: paths.cursorStateDatabase, sql: sql) {
            guard let status = row.first else { continue }
            let state = Self.cursorState(status: status)
            // Timestamps are stored as milliseconds since the Unix epoch.
            let milliseconds = row.count > 1 ? Double(row[1]) : nil
            let lastUpdatedAt = milliseconds.flatMap { value -> Date? in
                value > 0 ? Date(timeIntervalSince1970: value / 1000) : nil
            }
            guard Self.cursorShouldInclude(state: state, lastUpdatedAt: lastUpdatedAt, now: now) else {
                continue
            }
            counts.add(state)
        }
        return counts
    }

    private func scanAntigravity() -> AgentCounts {
        // Always scan all recent conversation DBs directly.
        // The aux-pane-session field in app_storage.json is often empty
        // (it only contains IDs of currently open side-panel sessions),
        // so we cannot rely on it as the primary source.
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: paths.antigravityConversations,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return AgentCounts() }

        let cutoff = Date().addingTimeInterval(-Self.recencyWindow)
        var counts = AgentCounts()

        for url in urls where url.pathExtension == "db" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            guard modified > cutoff else { continue }

            // Last step determines the final state; a subquery tells us
            // whether anything is still in progress. One connection per DB.
            let row = SQLiteReadOnly.query(
                database: url,
                sql: """
                SELECT (SELECT status FROM steps ORDER BY idx DESC LIMIT 1),
                       EXISTS(SELECT 1 FROM steps WHERE status = 2 LIMIT 1);
                """
            ).first
            guard let row, row.count == 2, let lastStatus = Int(row[0]) else { continue }

            counts.add(Self.antigravityConversationState(
                lastStatus: lastStatus,
                hasWorkingStep: row[1] == "1"
            ))
        }
        return counts
    }

    private func tailData(of url: URL, maximumBytes: UInt64 = 262_144) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > maximumBytes ? size - maximumBytes : 0)
        return try? handle.readToEnd()
    }
}

// MARK: - AgentMonitorStore

@MainActor
final class AgentMonitorStore: ObservableObject {
    @Published private(set) var summaries: [AgentSourceSummary] = AgentSource.allCases.map {
        AgentSourceSummary(source: $0, counts: AgentCounts(), isApplicationRunning: false)
    }

    private let scanner: AgentStatusScanner
    private let paths: AgentMonitorPaths

    /// Fallback polling timer – catches anything the file watchers miss
    /// (e.g. SQLite WAL checkpoints written in-place).
    private var timerCancellable: AnyCancellable?

    /// kqueue / DispatchSource watchers, keyed by the watched path so a
    /// watcher can be re-created after the file is deleted or replaced.
    private var fsWatchers: [String: DispatchSourceFileSystemObject] = [:]

    /// NSWorkspace app-launch / terminate observers.
    private var workspaceCancellables = Set<AnyCancellable>()

    /// Debounce for rapid bursts of filesystem events.
    private var debounceTask: Task<Void, Never>?

    /// Single-flight guard: at most one scan runs at any time. Additional
    /// requests arriving mid-scan set `rescanRequested` and are coalesced
    /// into exactly one follow-up scan, so work can never pile up.
    private var isScanning = false
    private var rescanRequested = false

    // MARK: - Init

    init(scanner: AgentStatusScanner = AgentStatusScanner()) {
        self.scanner = scanner
        self.paths = scanner.paths
    }

    func startMonitoring() {
        guard timerCancellable == nil else { return }

        // 1. Immediate first scan.
        scheduleRefresh(debounceMs: 0)

        // 2. Fallback polling every 2 s; file watchers provide the instant
        //    reaction, so the timer is only a safety net.
        timerCancellable = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.ensureFileSystemWatchers()
                    self?.scheduleRefresh(debounceMs: 0)
                }
            }

        // 3. kqueue file-system watchers for instant reaction.
        ensureFileSystemWatchers()

        // 4. NSWorkspace notifications for app launch / terminate.
        startWorkspaceObservers()
    }

    // MARK: - Refresh scheduling

    /// Starts a scan after `debounceMs` milliseconds, replacing any scan that
    /// is still waiting in its debounce window. Pass 0 to fire immediately.
    private func scheduleRefresh(debounceMs: Int) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            if debounceMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounceMs) * 1_000_000)
            }
            guard !Task.isCancelled else { return }
            await self?.performScan()
        }
    }

    private func performScan() async {
        if isScanning {
            rescanRequested = true
            return
        }
        isScanning = true
        defer { isScanning = false }

        let runningBundleIdentifiers = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
        let scanner = scanner
        let newSummaries = await Task.detached(priority: .utility) {
            scanner.scan(runningBundleIdentifiers: runningBundleIdentifiers)
        }.value

        // Only publish if something actually changed to avoid unnecessary SwiftUI redraws.
        if newSummaries != summaries {
            summaries = newSummaries
        }

        if rescanRequested {
            rescanRequested = false
            scheduleRefresh(debounceMs: 100)
        }
    }

    // MARK: - File-system watchers (kqueue via DispatchSource)

    /// Creates watchers for any target that isn't being watched yet. Called
    /// on start and from the polling timer, so watchers lost to file deletion
    /// or paths that didn't exist at launch are picked up automatically.
    private func ensureFileSystemWatchers() {
        for url in paths.watchTargets where fsWatchers[url.path] == nil {
            watchPath(url.path)
        }
    }

    private func watchPath(_ path: String) {
        // Open with O_EVTONLY so we can watch without preventing deletion.
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib, .link],
            queue: .main
        )

        source.setEventHandler { [weak self, weak source] in
            let flags = source?.data ?? []
            MainActor.assumeIsolated {
                guard let self else { return }
                if flags.contains(.delete) || flags.contains(.rename) {
                    // The watched inode is gone (file replaced atomically or
                    // removed). Drop the watcher; the polling timer re-creates
                    // it once the path exists again.
                    self.fsWatchers[path]?.cancel()
                    self.fsWatchers[path] = nil
                }
                self.scheduleRefresh(debounceMs: 150)
            }
        }

        source.setCancelHandler { close(fd) }
        source.resume()
        fsWatchers[path] = source
    }

    // MARK: - NSWorkspace observers

    private func startWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        // App launched → refresh immediately (a new agent app just started).
        NotificationCenter.Publisher(center: nc, name: NSWorkspace.didLaunchApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .filter { app in AgentSource.allCases.contains { $0.bundleIdentifier == app.bundleIdentifier } }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh(debounceMs: 400) }
            }
            .store(in: &workspaceCancellables)

        // App terminated → refresh immediately (remove counts for closed app).
        NotificationCenter.Publisher(center: nc, name: NSWorkspace.didTerminateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .filter { app in AgentSource.allCases.contains { $0.bundleIdentifier == app.bundleIdentifier } }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh(debounceMs: 200) }
            }
            .store(in: &workspaceCancellables)
    }

    // MARK: - Public imperative refresh (called from outside if needed)

    func refresh() {
        scheduleRefresh(debounceMs: 0)
    }
}
