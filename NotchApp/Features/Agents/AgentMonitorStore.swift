import AppKit
import Combine
import Foundation

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

struct AgentStatusScanner: Sendable {
    let paths: AgentMonitorPaths

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

    static func antigravityState(status: Int) -> AgentActivityState {
        switch status {
        case 0, 1, 2, 4: .working
        case 3, 6, 8: .done
        default: .stopped
        }
    }

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
        let rows = sqliteQuery(
            database: paths.codexStateDatabase,
            sql: "SELECT id, rollout_path FROM threads WHERE id IN (\(identifiers));"
        )
        let rolloutByID = Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (String, String)? in
            let fields = row.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { return nil }
            return (String(fields[0]), String(fields[1]))
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
        SELECT COALESCE(json_extract(k.value, '$.status'), 'none')
        FROM cursorDiskKV k
        LEFT JOIN composerHeaders h ON h.composerId = substr(k.key, 14)
        WHERE k.key LIKE 'composerData:%'
          AND COALESCE(json_extract(k.value, '$.isAgentic'), 0) = 1
          AND COALESCE(json_extract(k.value, '$.isDraft'), 0) = 0
          AND COALESCE(h.isArchived, 0) = 0;
        """
        var counts = AgentCounts()
        for status in sqliteQuery(database: paths.cursorStateDatabase, sql: sql) {
            counts.add(Self.cursorState(status: status))
        }
        return counts
    }

    private func scanAntigravity() -> AgentCounts {
        guard let data = try? Data(contentsOf: paths.antigravityAppStorage),
              let storage = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = storage["aux-pane-session"] as? String else {
            return scanAntigravityFromConversations()
        }
        let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return AgentCounts()
        }
        let range = NSRange(text.startIndex..., in: text)
        let identifiers = Set(regex.matches(in: text, range: range).compactMap { match -> String? in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange]).lowercased()
        })

        var counts = AgentCounts()
        for identifier in identifiers {
            let database = paths.antigravityConversations
                .appendingPathComponent(identifier)
                .appendingPathExtension("db")
            guard FileManager.default.fileExists(atPath: database.path) else { continue }
            let value = sqliteQuery(
                database: database,
                sql: "SELECT status FROM steps ORDER BY idx DESC LIMIT 1;"
            ).first
            counts.add(value.flatMap(Int.init).map(Self.antigravityState) ?? .stopped)
        }

        // If the app_storage approach found nothing, also check all conversation DBs directly.
        if counts.working + counts.stopped + counts.done == 0 {
            let fallback = scanAntigravityFromConversations()
            return fallback
        }
        return counts
    }

    /// Fallback: scan all conversation databases directly from the conversations directory.
    private func scanAntigravityFromConversations() -> AgentCounts {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: paths.antigravityConversations,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return AgentCounts() }

        let cutoff = Date().addingTimeInterval(-3600) // only care about last hour
        var counts = AgentCounts()
        for url in urls where url.pathExtension == "db" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            guard modified > cutoff else { continue }
            let value = sqliteQuery(
                database: url,
                sql: "SELECT status FROM steps ORDER BY idx DESC LIMIT 1;"
            ).first
            counts.add(value.flatMap(Int.init).map(Self.antigravityState) ?? .stopped)
        }
        return counts
    }

    private func sqliteQuery(database: URL, sql: String) -> [String] {
        guard FileManager.default.fileExists(atPath: database.path) else { return [] }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        // Use WAL mode and a short busy timeout so we don't block on a live write lock.
        process.arguments = [
            "-readonly",
            "-cmd", "PRAGMA busy_timeout=200;",
            database.path,
            sql
        ]
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        guard process.terminationStatus == 0 else { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .map(String.init) ?? []
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

    /// Fallback polling timer – fires every 1 s to catch anything the file
    /// watchers might miss (e.g. SQLite WAL checkpoints written in-place).
    private var timerCancellable: AnyCancellable?

    /// kqueue / DispatchSource watchers for individual paths.
    private var fsWatchers: [DispatchSourceFileSystemObject] = []

    /// NSWorkspace app-launch / terminate observers.
    private var workspaceCancellables = Set<AnyCancellable>()

    /// Guards against overlapping concurrent scans.
    private var scanTask: Task<Void, Never>?

    init(scanner: AgentStatusScanner = AgentStatusScanner()) {
        self.scanner = scanner
        self.paths = scanner.paths
    }

    func startMonitoring() {
        guard timerCancellable == nil else { return }

        // 1. Immediate first scan.
        scheduleRefresh(debounce: .zero)

        // 2. Fallback polling every 1 s (halved from original 2 s).
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.scheduleRefresh(debounce: .zero) }

        // 3. kqueue file-system watchers for instant reaction.
        startFileSystemWatchers()

        // 4. NSWorkspace notifications for app launch / terminate.
        startWorkspaceObservers()
    }

    // MARK: - Refresh scheduling

    /// Cancels any in-flight scan and starts a new one after `debounce`.
    /// A zero debounce fires immediately; a small debounce coalesces rapid
    /// filesystem events (e.g. many lock files written in quick succession).
    private func scheduleRefresh(debounce: DispatchTimeInterval) {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            if case .milliseconds(let ms) = debounce, ms > 0 {
                try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            }
            guard !Task.isCancelled else { return }
            await self?.performScan()
        }
    }

    private func performScan() async {
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
    }

    // MARK: - File-system watchers (kqueue via DispatchSource)

    private func startFileSystemWatchers() {
        // Cancel existing watchers first.
        fsWatchers.forEach { $0.cancel() }
        fsWatchers.removeAll()

        let targets = paths.watchTargets
        for url in targets {
            guard let source = makeFileWatcher(for: url) else { continue }
            fsWatchers.append(source)
        }
    }

    private func makeFileWatcher(for url: URL) -> DispatchSourceFileSystemObject? {
        // Open with O_EVTONLY so we can watch without preventing deletion.
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib, .link],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            // Coalesce rapid bursts (e.g. lock-file storm when many agents start).
            DispatchQueue.main.async {
                self?.scheduleRefresh(debounce: .milliseconds(150))
            }
        }

        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    // MARK: - NSWorkspace observers

    private func startWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        // App launched → refresh immediately (a new agent app just started).
        NotificationCenter.Publisher(center: nc, name: NSWorkspace.didLaunchApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .filter { app in AgentSource.allCases.contains { $0.bundleIdentifier == app.bundleIdentifier } }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh(debounce: .milliseconds(400)) }
            .store(in: &workspaceCancellables)

        // App terminated → refresh immediately (remove counts for closed app).
        NotificationCenter.Publisher(center: nc, name: NSWorkspace.didTerminateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .filter { app in AgentSource.allCases.contains { $0.bundleIdentifier == app.bundleIdentifier } }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh(debounce: .milliseconds(200)) }
            .store(in: &workspaceCancellables)
    }

    // MARK: - Public imperative refresh (called from outside if needed)

    func refresh() {
        scheduleRefresh(debounce: .zero)
    }
}
