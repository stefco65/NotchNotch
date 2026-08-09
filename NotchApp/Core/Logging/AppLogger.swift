import OSLog

enum AppLogger {
    static let subsystem = "com.notchnook.app"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let display = Logger(subsystem: subsystem, category: "display")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let tray = Logger(subsystem: subsystem, category: "tray")
    static let music = Logger(subsystem: subsystem, category: "music")
}
