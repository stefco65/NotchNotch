import Foundation
import OSLog

enum AppLogger {
    static let subsystem = "com.notchnook.app"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let display = Logger(subsystem: subsystem, category: "display")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let tray = Logger(subsystem: subsystem, category: "tray")
    static let music = Logger(subsystem: subsystem, category: "music")

    /// Mirror an error into `AppErrorLog` (Application Support file) and OSLog.
    static func fileError(
        _ message: String,
        category: String,
        logger: Logger,
        details: String? = nil,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        logger.error("\(message, privacy: .public)")
        AppErrorLog.record(
            severity: .error,
            category: category,
            message: message,
            details: details,
            file: file,
            function: function,
            line: line
        )
    }

    static func fileWarning(
        _ message: String,
        category: String,
        logger: Logger,
        details: String? = nil,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        logger.warning("\(message, privacy: .public)")
        AppErrorLog.record(
            severity: .warning,
            category: category,
            message: message,
            details: details,
            file: file,
            function: function,
            line: line
        )
    }
}
