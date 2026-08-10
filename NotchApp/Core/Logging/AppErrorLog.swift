import AppKit
import Darwin
import Foundation
import OSLog

/// Append-only, human-readable error log under Application Support.
///
/// Location:
/// `~/Library/Application Support/com.notchnook.app/Logs/`
///
/// - `errors.log` — every recorded error / warning in chronological order
/// - `latest-fatal.log` — last fatal signal / uncaught ObjC exception (overwrite)
///
/// Also installs process-wide handlers so AppKit traps such as
/// "too many Update Constraints in Window" (SIGTRAP via `_crashOnException`)
/// leave a readable trail before the process dies.
enum AppErrorLog {
    enum Severity: String {
        case debug
        case info
        case warning
        case error
        case fatal
    }

    private static let subsystem = AppLogger.subsystem
    private static let bootstrapLogger = Logger(subsystem: subsystem, category: "error-log")
    private static let ioQueue = DispatchQueue(label: "com.notchnook.app.error-log")
    private static let maxLogBytes: UInt64 = 2 * 1024 * 1024
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS Z"
        return formatter
    }()

    // Protected by `ioQueue` for normal writes; signal path is best-effort.
    nonisolated(unsafe) private static var didBootstrap = false
    nonisolated(unsafe) private static var logFileDescriptor: Int32 = -1

    // MARK: - Public paths

    static var rootDirectoryURL: URL {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return support
            .appendingPathComponent("com.notchnook.app", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
    }

    static var errorsLogURL: URL {
        rootDirectoryURL.appendingPathComponent("errors.log", isDirectory: false)
    }

    static var latestFatalLogURL: URL {
        rootDirectoryURL.appendingPathComponent("latest-fatal.log", isDirectory: false)
    }

    static var readmeURL: URL {
        rootDirectoryURL.appendingPathComponent("README.txt", isDirectory: false)
    }

    // MARK: - Bootstrap

    /// Call once as early as possible (before building windows).
    static func bootstrap() {
        ioQueue.sync {
            guard !didBootstrap else { return }
            didBootstrap = true
            prepareDirectoryLocked()
            openLogFileDescriptorLocked()
            writeReadmeIfNeededLocked()
            installUncaughtExceptionHandler()
            installSignalHandlers()
            appendLocked(
                severity: .info,
                category: "lifecycle",
                message: "Session started",
                details: sessionDetails(),
                markFatal: false
            )
        }
        bootstrapLogger.notice(
            "Error log ready at \(Self.errorsLogURL.path, privacy: .public)"
        )
    }

    static func recordSessionEnd() {
        record(
            severity: .info,
            category: "lifecycle",
            message: "Session ending"
        )
    }

    // MARK: - Recording

    static func record(
        severity: Severity,
        category: String,
        message: String,
        details: String? = nil,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        let callSite = "\(file):\(line) \(function)"
        let payload = details.map { "callSite: \(callSite)\n\($0)" } ?? "callSite: \(callSite)"
        ioQueue.async {
            appendLocked(
                severity: severity,
                category: category,
                message: message,
                details: payload,
                markFatal: severity == .fatal
            )
        }
    }

    static func record(
        _ error: Error,
        category: String,
        message: String? = nil,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        let nsError = error as NSError
        let headline = message ?? error.localizedDescription
        let details = """
        errorType: \(String(describing: type(of: error)))
        localizedDescription: \(error.localizedDescription)
        domain: \(nsError.domain)
        code: \(nsError.code)
        userInfo: \(nsError.userInfo)
        """
        record(
            severity: .error,
            category: category,
            message: headline,
            details: details,
            file: file,
            function: function,
            line: line
        )
    }

    static func revealInFinder() {
        ioQueue.sync { prepareDirectoryLocked() }
        NSWorkspace.shared.activateFileViewerSelecting([errorsLogURL])
    }

    // MARK: - Handlers

    private static func installUncaughtExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.joined(separator: "\n")
            let body = """
            ========== \(AppErrorLog.timestamp()) ==========
            severity: fatal
            category: uncaught-exception
            name: \(exception.name.rawValue)
            reason: \(exception.reason ?? "(nil)")
            userInfo: \(String(describing: exception.userInfo))
            process: \(ProcessInfo.processInfo.processName) pid=\(ProcessInfo.processInfo.processIdentifier)
            host: \(ProcessInfo.processInfo.hostName)
            os: \(ProcessInfo.processInfo.operatingSystemVersionString)

            stack:
            \(stack)

            """
            AppErrorLog.writeFatalBestEffort(body)
        }
    }

    private static func installSignalHandlers() {
        let handler: @convention(c) (Int32) -> Void = { signalCode in
            AppErrorLog.handleFatalSignal(signalCode)
        }
        let signals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGBUS, SIGTRAP, SIGFPE]
        for signalValue in signals {
            signal(signalValue, handler)
        }
    }

    private static func handleFatalSignal(_ signalCode: Int32) {
        let name: String
        switch signalCode {
        case SIGABRT: name = "SIGABRT"
        case SIGILL: name = "SIGILL"
        case SIGSEGV: name = "SIGSEGV"
        case SIGBUS: name = "SIGBUS"
        case SIGTRAP: name = "SIGTRAP"
        case SIGFPE: name = "SIGFPE"
        default: name = "signal(\(signalCode))"
        }

        let maxFrames = 64
        let addresses = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: maxFrames)
        defer { addresses.deallocate() }
        let count = backtrace(addresses, Int32(maxFrames))
        var stackLines: [String] = []
        if let symbols = backtrace_symbols(addresses, count) {
            for index in 0..<Int(count) {
                stackLines.append(String(cString: symbols[index]!))
            }
            free(symbols)
        }

        // Best-effort only: AppKit layout traps often land here as SIGTRAP from
        // +[NSApplication _crashOnException:] on the main thread.
        let pid = getpid()
        let body = """
        ========== \(coarseTimestamp()) ==========
        severity: fatal
        category: fatal-signal
        signal: \(name) (\(signalCode))
        note: AppKit often raises SIGTRAP via +[NSApplication _crashOnException:] for layout faults such as "too many Update Constraints in Window".
        process: NotchNook pid=\(pid)

        stack:
        \(stackLines.joined(separator: "\n"))

        """
        writeFatalBestEffort(body)

        // Restore default and re-raise so the system still generates a crash report.
        signal(signalCode, SIG_DFL)
        raise(signalCode)
    }

    /// Avoid DateFormatter in the signal path.
    private static func coarseTimestamp() -> String {
        var now = time(nil)
        var local = tm()
        localtime_r(&now, &local)
        var buffer = [CChar](repeating: 0, count: 32)
        strftime(&buffer, buffer.count, "%Y-%m-%d %H:%M:%S", &local)
        let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
        return String(decoding: buffer[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    // MARK: - File IO

    private static func prepareDirectoryLocked() {
        try? FileManager.default.createDirectory(
            at: rootDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private static func writeReadmeIfNeededLocked() {
        guard !FileManager.default.fileExists(atPath: readmeURL.path) else { return }
        let text = """
        NotchNook error logs
        ====================

        errors.log
          Chronological log of warnings, errors and fatal events.

        latest-fatal.log
          Overwritten on each fatal signal / uncaught ObjC exception.
          Open this first after a crash.

        Timestamps use the local time zone.
        """
        try? text.write(to: readmeURL, atomically: true, encoding: .utf8)
    }

    private static func openLogFileDescriptorLocked() {
        prepareDirectoryLocked()
        rotateIfNeededLocked()
        let path = errorsLogURL.path
        logFileDescriptor = open(
            path,
            O_WRONLY | O_CREAT | O_APPEND,
            S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
        )
    }

    private static func rotateIfNeededLocked() {
        let path = errorsLogURL.path
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attrs[.size] as? UInt64,
            size >= maxLogBytes
        else { return }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let rotated = rootDirectoryURL.appendingPathComponent(
            "errors-\(stamp).log",
            isDirectory: false
        )
        try? FileManager.default.moveItem(at: errorsLogURL, to: rotated)
    }

    private static func appendLocked(
        severity: Severity,
        category: String,
        message: String,
        details: String?,
        markFatal: Bool
    ) {
        prepareDirectoryLocked()
        if logFileDescriptor < 0 {
            openLogFileDescriptorLocked()
        }

        var block = """
        ========== \(timestamp()) ==========
        severity: \(severity.rawValue)
        category: \(category)
        message: \(message)

        """
        if let details, !details.isEmpty {
            block += details
            if !details.hasSuffix("\n") { block += "\n" }
            block += "\n"
        } else {
            block += "\n"
        }

        writeUTF8BestEffort(block, to: logFileDescriptor)

        if markFatal {
            try? block.write(to: latestFatalLogURL, atomically: true, encoding: .utf8)
        }
    }

    /// Signal / exception paths must avoid locks and allocations where possible.
    private static func writeFatalBestEffort(_ body: String) {
        // Best-effort directory create (may already exist).
        let dir = rootDirectoryURL.path
        _ = dir.withCString { mkdir($0, S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH) }

        if logFileDescriptor < 0 {
            let path = errorsLogURL.path
            logFileDescriptor = open(
                path,
                O_WRONLY | O_CREAT | O_APPEND,
                S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
            )
        }
        writeUTF8BestEffort(body, to: logFileDescriptor)

        let fatalPath = latestFatalLogURL.path
        let fd = open(
            fatalPath,
            O_WRONLY | O_CREAT | O_TRUNC,
            S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
        )
        if fd >= 0 {
            writeUTF8BestEffort(body, to: fd)
            close(fd)
        }
    }

    private static func writeUTF8BestEffort(_ text: String, to fd: Int32) {
        guard fd >= 0, let data = text.data(using: .utf8) else { return }
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var written = 0
            while written < buffer.count {
                let result = Darwin.write(fd, base.advanced(by: written), buffer.count - written)
                if result <= 0 { break }
                written += result
            }
        }
        fsync(fd)
    }

    private static func timestamp() -> String {
        dateFormatter.string(from: Date())
    }

    private static func sessionDetails() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return """
        process: \(ProcessInfo.processInfo.processName) pid=\(ProcessInfo.processInfo.processIdentifier)
        version: \(version) (\(build))
        os: \(ProcessInfo.processInfo.operatingSystemVersionString)
        logDirectory: \(rootDirectoryURL.path)
        """
    }
}
