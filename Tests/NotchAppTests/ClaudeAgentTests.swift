import Foundation
import os
import XCTest
@testable import NotchNook

@MainActor
final class ClaudeAgentTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-agent-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: paths.claudeSessions, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: home)
    }

    private var paths: AgentMonitorPaths {
        .currentUser(homeDirectory: home)
    }

    // MARK: - Registry

    func testRegistryKeepsOnlyLiveClaimedSessions() throws {
        try writeSession(pid: 100, id: "live", status: "busy", startedAt: now.addingTimeInterval(-30))
        try writeSession(pid: 200, id: "dead", status: "busy", startedAt: now.addingTimeInterval(-30))
        try writeSession(pid: 300, id: "reused-pid", status: "busy", startedAt: now.addingTimeInterval(-600))
        try writeSession(pid: 400, id: "spare", status: "idle", startedAt: now, extra: ["spare": true])
        try writeSession(pid: 500, id: "parked", status: "idle", startedAt: now, extra: ["parkedJobId": "job"])
        try Data("not json".utf8).write(to: paths.claudeSessions.appendingPathComponent("600.json"))
        try Data("{}".utf8).write(to: paths.claudeSessions.appendingPathComponent("notes.txt"))

        let ids = registry().liveSessions().map(\.sessionID)

        XCTAssertEqual(ids, ["live"])
    }

    func testRegistryDecodesSessionFields() throws {
        let data = Data("""
        {"pid":42,"sessionId":"abc","cwd":"/tmp/x","name":"Refactor","status":"waiting",
         "waitingFor":"input needed","startedAt":1800000000000,"statusUpdatedAt":1800000005000}
        """.utf8)

        let record = try XCTUnwrap(ClaudeSessionRegistry.decode(data))

        XCTAssertEqual(record.pid, 42)
        XCTAssertEqual(record.cwd, "/tmp/x")
        XCTAssertEqual(record.name, "Refactor")
        XCTAssertEqual(record.waitingFor, "input needed")
        XCTAssertEqual(record.startedAt, now)
        XCTAssertEqual(record.statusUpdatedAt, now.addingTimeInterval(5))
    }

    func testProcessStartTimeOfCurrentProcess() {
        let started = ProcessStartTime.lookup(pid: getpid())
        XCTAssertNotNil(started)
        XCTAssertLessThanOrEqual(started ?? .distantFuture, Date())
    }

    // MARK: - Status mapping

    func testTypedStatusesMapToBuckets() {
        XCTAssertEqual(status(of: session(status: "busy")), .busy)
        XCTAssertEqual(status(of: session(status: "waiting")), .waiting)
        XCTAssertEqual(ClaudeAgentStatus.busy.activityState, .working)
        XCTAssertEqual(ClaudeAgentStatus.waiting.activityState, .stopped)
        XCTAssertEqual(ClaudeAgentStatus.idle.activityState, .done)
    }

    func testIdleCountsAsDoneOnlyAfterAFinishedTurn() {
        let finishedTurn = session(status: "idle", startedAt: now.addingTimeInterval(-600), statusUpdatedAt: now.addingTimeInterval(-60))
        let neverRan = session(status: "idle", startedAt: now.addingTimeInterval(-600), statusUpdatedAt: now.addingTimeInterval(-599))
        let stale = session(status: "idle", startedAt: now.addingTimeInterval(-9_000), statusUpdatedAt: now.addingTimeInterval(-7_200))

        XCTAssertEqual(status(of: finishedTurn), .idle)
        XCTAssertNil(status(of: neverRan))
        XCTAssertNil(status(of: stale))
    }

    func testSessionsWithoutStatusFallBackToTranscriptRecency() {
        let legacy = session(status: nil)

        XCTAssertEqual(status(of: legacy, transcript: now.addingTimeInterval(-10)), .recentTranscriptActivity)
        XCTAssertEqual(status(of: legacy, transcript: now.addingTimeInterval(-600)), .idle)
        XCTAssertNil(status(of: legacy, transcript: now.addingTimeInterval(-7_200)))
        XCTAssertNil(status(of: legacy, transcript: nil))
    }

    func testProjectDirectoryNameMatchesClaudeCode() {
        XCTAssertEqual(
            ClaudeEventMapper.projectDirectoryName(forWorkingDirectory: "/Users/stefan/Desktop/Notch"),
            "-Users-stefan-Desktop-Notch"
        )
        XCTAssertEqual(ClaudeEventMapper.projectDirectoryName(forWorkingDirectory: "/a b/ż.c"), "-a-b---c")
        XCTAssertNil(ClaudeEventMapper.projectDirectoryName(forWorkingDirectory: String(repeating: "a", count: 201)))
    }

    // MARK: - Resync

    func testResyncBuildsSnapshotsFromLiveSessions() throws {
        try writeSession(pid: 100, id: "busy", status: "busy", startedAt: now.addingTimeInterval(-30), extra: ["name": "Fix bug", "cwd": "/work/app"])
        try writeSession(pid: 101, id: "waiting", status: "waiting", startedAt: now.addingTimeInterval(-30), extra: ["waitingFor": "input needed"])
        try writeSession(pid: 102, id: "done", status: "idle", startedAt: now.addingTimeInterval(-600), statusUpdatedAt: now.addingTimeInterval(-60))
        try writeSession(pid: 103, id: "fresh", status: "idle", startedAt: now.addingTimeInterval(-5), statusUpdatedAt: now.addingTimeInterval(-4))
        try writeSession(pid: 104, id: "legacy", status: nil, startedAt: now.addingTimeInterval(-300), extra: ["cwd": "/work/legacy"])
        let transcript = paths.claudeProjects
            .appendingPathComponent("-work-legacy", isDirectory: true)
            .appendingPathComponent("legacy.jsonl")
        try FileManager.default.createDirectory(at: transcript.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: transcript)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-5)], ofItemAtPath: transcript.path)

        let snapshots = ClaudeResyncService(paths: paths, registry: registry())
            .snapshotAgents(now: now)
        let byID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })

        XCTAssertEqual(Set(byID.keys), ["busy", "waiting", "done", "legacy"])
        XCTAssertEqual(byID["busy"]?.status, .working)
        XCTAssertEqual(byID["busy"]?.title, "Fix bug")
        XCTAssertEqual(byID["busy"]?.workspace, "/work/app")
        XCTAssertEqual(byID["waiting"]?.status, .waitingForUser)
        XCTAssertEqual(byID["waiting"]?.description, "input needed")
        XCTAssertEqual(byID["done"]?.status, .completed)
        XCTAssertEqual(byID["legacy"]?.status, .working)
        XCTAssertTrue(snapshots.allSatisfy { $0.provider == .claude })
    }

    // MARK: - Presence and visibility

    func testDetachedSessionsDrivePresenceWithoutApplication() async {
        let hasSessions = OSAllocatedUnfairLock(initialState: true)
        let monitor = ApplicationPresenceMonitor(isApplicationRunning: { _ in false })
        monitor.detachedSessionProbes = [.claude: { hasSessions.withLock { $0 } }]
        var events: [String] = []
        monitor.onProviderStarted = { events.append("start:\($0.rawValue)") }
        monitor.onProviderStopped = { events.append("stop:\($0.rawValue)") }

        monitor.start()
        await monitor.refreshDetachedSessions()
        await monitor.refreshDetachedSessions()
        XCTAssertTrue(monitor.isProviderRunning(.claude))

        hasSessions.withLock { $0 = false }
        await monitor.refreshDetachedSessions()
        monitor.stop()

        XCTAssertEqual(events, ["start:claude", "stop:claude"])
    }

    func testRunningApplicationKeepsProviderPresentWithoutSessions() async {
        let monitor = ApplicationPresenceMonitor(isApplicationRunning: { $0 == .claude })
        monitor.detachedSessionProbes = [.claude: { false }]
        var stopCount = 0
        monitor.onProviderStopped = { _ in stopCount += 1 }

        monitor.start()
        await monitor.refreshDetachedSessions()

        XCTAssertTrue(monitor.isProviderRunning(.claude))
        XCTAssertEqual(stopCount, 0)
        monitor.stop()
    }

    func testDisabledProvidersAreNotPublished() {
        let store = AgentMonitorStore(tools: [])
        XCTAssertEqual(store.summaries.map(\.source), AgentProvider.allCases)

        store.setEnabledProviders([.claude, .cursor])

        XCTAssertEqual(store.summaries.map(\.source), [.cursor, .claude])
    }

    // MARK: - Helpers

    private func registry() -> ClaudeSessionRegistry {
        let now = now
        var registry = ClaudeSessionRegistry(sessionsDirectory: paths.claudeSessions)
        registry.processStartTime = { pid in
            switch pid {
            case 200: nil
            case 300: now
            default: now.addingTimeInterval(-3_600)
            }
        }
        return registry
    }

    private func session(
        status: String?,
        startedAt: Date? = nil,
        statusUpdatedAt: Date? = nil
    ) -> ClaudeSessionRecord {
        ClaudeSessionRecord(
            pid: 1,
            sessionID: "s",
            status: status,
            startedAt: startedAt ?? now.addingTimeInterval(-60),
            statusUpdatedAt: statusUpdatedAt ?? now.addingTimeInterval(-30)
        )
    }

    private func status(of session: ClaudeSessionRecord, transcript: Date? = nil) -> ClaudeAgentStatus? {
        ClaudeEventMapper.nativeStatus(for: session, transcriptModifiedAt: transcript, now: now)
    }

    private func writeSession(
        pid: Int32,
        id: String,
        status: String?,
        startedAt: Date,
        statusUpdatedAt: Date? = nil,
        extra: [String: Any] = [:]
    ) throws {
        var object: [String: Any] = [
            "pid": pid,
            "sessionId": id,
            "startedAt": startedAt.timeIntervalSince1970 * 1000,
            "kind": "interactive"
        ]
        if let status {
            object["status"] = status
            object["statusUpdatedAt"] = (statusUpdatedAt ?? startedAt.addingTimeInterval(1)).timeIntervalSince1970 * 1000
        }
        object.merge(extra) { _, new in new }
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: paths.claudeSessions.appendingPathComponent("\(pid).json"))
    }
}
