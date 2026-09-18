import Darwin
import Foundation

/// One entry of Claude Code's live session registry (`~/.claude/sessions/<pid>.json`).
struct ClaudeSessionRecord: Equatable, Sendable {
    let pid: Int32
    let sessionID: String
    var cwd: String?
    var name: String?
    var status: String?
    var waitingFor: String?
    var startedAt: Date?
    var statusUpdatedAt: Date?
    /// Pre-warmed desktop process that has not been claimed by a conversation yet.
    var isSpare = false
    /// Interactive session parked behind a background job that is listed on its own.
    var isParked = false
}

/// Reads the session registry and keeps only sessions whose process is still alive.
struct ClaudeSessionRegistry: Sendable {
    let sessionsDirectory: URL
    var processStartTime: @Sendable (Int32) -> Date? = ProcessStartTime.lookup

    /// A reused PID starts after the stale session it inherited was registered.
    static let startTimeTolerance: TimeInterval = 5

    func liveSessions() -> [ClaudeSessionRecord] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return urls.compactMap { url -> ClaudeSessionRecord? in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let record = Self.decode(data),
                  !record.isSpare, !record.isParked,
                  isAlive(record) else {
                return nil
            }
            return record
        }
    }

    func hasLiveSessions() -> Bool {
        !liveSessions().isEmpty
    }

    private func isAlive(_ record: ClaudeSessionRecord) -> Bool {
        guard let processStartedAt = processStartTime(record.pid) else { return false }
        guard let startedAt = record.startedAt else { return true }
        return processStartedAt <= startedAt.addingTimeInterval(Self.startTimeTolerance)
    }

    static func decode(_ data: Data) -> ClaudeSessionRecord? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = (object["pid"] as? NSNumber)?.int32Value, pid > 0,
              let sessionID = object["sessionId"] as? String, !sessionID.isEmpty else {
            return nil
        }
        return ClaudeSessionRecord(
            pid: pid,
            sessionID: sessionID,
            cwd: object["cwd"] as? String,
            name: object["name"] as? String,
            status: object["status"] as? String,
            waitingFor: object["waitingFor"] as? String,
            startedAt: millisecondsDate(object["startedAt"]),
            statusUpdatedAt: millisecondsDate(object["statusUpdatedAt"]),
            isSpare: object["spare"] as? Bool ?? false,
            isParked: object["parkedJobId"] is String
        )
    }

    private static func millisecondsDate(_ value: Any?) -> Date? {
        guard let milliseconds = (value as? NSNumber)?.doubleValue, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}

enum ProcessStartTime {
    /// Start time of a running process, or `nil` when no such process exists.
    @Sendable static func lookup(pid: Int32) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(
            timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000
        )
    }
}
