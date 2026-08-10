import AppKit

/// Pure AppKit entry — avoids SwiftUI `App` / `Settings` scenes that install
/// additional `NSHostingView` windows and trip macOS 26 constraint traps at launch.
@main
enum NotchNookMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        // NSApplication.delegate is weak; retain for process lifetime.
        app.delegate = delegate
        _ = Unmanaged.passRetained(delegate)
        app.run()
    }
}
