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

    /// Map a Codex rollout event `type` (from `event_msg.payload.type` or the
    /// top-level `type`) onto our activity buckets.
    ///
    /// Blue  = actively running a turn
    /// Orange = waiting on the user (approval / input / permissions) or aborted
    /// Green = turn finished successfully
    static func codexEventState(type: String) -> AgentActivityState? {
        switch type {
        case "task_started", "turn_started":
            return .working
        case "task_complete", "turn_complete":
            return .done
        case "turn_aborted",
             "exec_approval_request",
             "apply_patch_approval_request",
             "request_user_input",
             "request_permissions",
             "elicitation_request",
             "collab_waiting_begin",
             "error":
            return .stopped
        default:
            return nil
        }
    }

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
            if let type, let state = codexEventState(type: type) {
                return state
            }
        }
        // Recent write activity with no terminal event in the tail still means
        // the agent is streaming (tool output, reasoning, …).
        if let lastModified, now.timeIntervalSince(lastModified) <= 90 {
            return .working
        }
        return nil
    }

    /// Signals read from a Cursor `composerData:*` row. Cursor itself treats a
    /// composer as generating when `status == "generating"` OR
    /// `generatingBubbleIds` is non-empty (see workbench `isGenerating`);
    /// relying on `status` alone mis-classifies active runs as aborted/stopped.
    struct CursorComposerSignals: Equatable, Sendable {
        var status: String
        var generatingBubbleCount: Int = 0
        var isContinuationInProgress: Bool = false
    }

    /// Map Cursor composer signals to our activity buckets:
    ///  - working (blue): actively generating / streaming
    ///  - stopped (orange): waiting for the user (approval, decision, next
    ///    instruction) or explicitly aborted / blocked
    ///  - done (green): finished its work successfully
    static func cursorState(status: String) -> AgentActivityState {
        cursorState(
            CursorComposerSignals(status: status)
        )
    }

    static func cursorState(_ signals: CursorComposerSignals) -> AgentActivityState {
        let status = signals.status.lowercased()

        // Match Cursor's own isGenerating check. `generatingBubbleIds` wins
        // even over a stale `aborted` status — status alone is what caused
        // working agents to land in the orange bucket.
        let isGenerating =
            status == "generating"
            || status == "running"
            || status == "runningwithqueuedresume"
            || status == "in_progress"
            || status == "in-progress"
            || status == "processing"
            || status == "ongoing"
            || signals.isContinuationInProgress
            || signals.generatingBubbleCount > 0

        if isGenerating {
            return .working
        }

        switch status {
        case "aborted", "blocked", "waiting", "paused", "interrupted",
             "cancelled", "canceled", "error", "failed":
            // Stopped / needs user attention.
            return .stopped
        case "completed", "none":
            return .done
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

    /// Map a raw Antigravity / Jetski `StepStatus` integer.
    ///
    /// Observed + SDK (`StepStatus`) alignment:
    ///   1 / 2 = Active / in-progress          → working (blue)
    ///   3     = Done                          → done (green)
    ///   4     = WaitingForUser                → stopped (orange)
    ///   5 / 6 = Error / Canceled              → stopped (orange)
    ///   7     = TerminalError / permission    → stopped (orange)
    static func antigravityState(status: Int) -> AgentActivityState {
        switch status {
        case 1, 2:
            return .working
        case 3:
            return .done
        case 4, 5, 6, 7:
            return .stopped
        default:
            // Unknown low values lean working; high values lean done.
            return status < 3 ? .working : .done
        }
    }

    /// Derive the overall state of one conversation from its step data.
    ///
    /// Priority matches the Cursor fix: an in-progress step wins so a stale
    /// terminal status cannot paint a live agent orange/green. Otherwise the
    /// last step's status decides (so WaitingForUser / errors stay orange).
    static func antigravityConversationState(
        lastStatus: Int,
        hasWorkingStep: Bool
    ) -> AgentActivityState {
        if hasWorkingStep || lastStatus == 1 || lastStatus == 2 {
            return .working
        }
        return antigravityState(status: lastStatus)
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
        let now = Date()
        for threadID in threadIDs {
            guard let path = rolloutByID[threadID] else {
                // Lock without a rollout row — not enough signal; skip.
                continue
            }
            let rolloutURL = URL(fileURLWithPath: path)
            let lastModified = try? rolloutURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            guard let data = tailData(of: rolloutURL),
                  let state = Self.codexState(in: data, lastModified: lastModified, now: now) else {
                // No recognized lifecycle event and no recent writes — skip
                // instead of dumping into orange (the old default that made
                // idle Codex locks look "stopped").
                continue
            }
            // Same recency rule as Cursor: working always counts; terminal
            // states only while the rollout was touched recently.
            if state != .working {
                guard let lastModified,
                      now.timeIntervalSince(lastModified) <= Self.recencyWindow else {
                    continue
                }
            }
            counts.add(state)
        }
        return counts
    }

    private func scanCursor() -> AgentCounts {
        // Pull the same fields Cursor uses for isGenerating, not just status.
        // json_array_length(NULL) is NULL → COALESCE to 0.
        let sql = """
        SELECT COALESCE(json_extract(k.value, '$.status'), 'none'),
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
        var counts = AgentCounts()
        let now = Date()
        for row in SQLiteReadOnly.query(database: paths.cursorStateDatabase, sql: sql) {
            guard row.count >= 4 else { continue }
            let signals = CursorComposerSignals(
                status: row[0],
                generatingBubbleCount: Int(row[2]) ?? 0,
                isContinuationInProgress: row[3] == "1" || row[3] == "true"
            )
            let state = Self.cursorState(signals)
            // Timestamps are stored as milliseconds since the Unix epoch.
            let lastUpdatedAt = Double(row[1]).flatMap { value -> Date? in
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
            // whether anything is still Active / in-progress (status 1 or 2).
            let row = SQLiteReadOnly.query(
                database: url,
                sql: """
                SELECT (SELECT status FROM steps ORDER BY idx DESC LIMIT 1),
                       EXISTS(SELECT 1 FROM steps WHERE status IN (1, 2) LIMIT 1);
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
