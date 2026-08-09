import SwiftUI

@main
struct NotchNookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView(store: appDelegate.settingsStore)
        }
    }
}
