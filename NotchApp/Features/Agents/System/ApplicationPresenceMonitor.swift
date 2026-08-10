import AppKit
import Foundation

@MainActor
final class ApplicationPresenceMonitor {
    var onProviderStarted: ((AgentProvider) -> Void)?
    var onProviderStopped: ((AgentProvider) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var knownRunning = Set<AgentProvider>()
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let running = currentlyRunningProviders()
        knownRunning = running
        for provider in running {
            onProviderStarted?(provider)
        }

        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let bundleID = app?.bundleIdentifier
                Task { @MainActor in
                    self?.handleLaunch(bundleIdentifier: bundleID)
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let bundleID = app?.bundleIdentifier
                Task { @MainActor in
                    self?.handleTerminate(bundleIdentifier: bundleID)
                }
            }
        )
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        knownRunning.removeAll()
        isRunning = false
    }

    func currentlyRunningProviders() -> Set<AgentProvider> {
        var result = Set<AgentProvider>()
        for app in NSWorkspace.shared.runningApplications {
            if let provider = ProcessIdentity.provider(forBundleIdentifier: app.bundleIdentifier) {
                result.insert(provider)
            }
        }
        return result
    }

    private func handleLaunch(bundleIdentifier: String?) {
        guard let provider = ProcessIdentity.provider(forBundleIdentifier: bundleIdentifier) else { return }
        guard !knownRunning.contains(provider) else { return }
        knownRunning.insert(provider)
        onProviderStarted?(provider)
    }

    private func handleTerminate(bundleIdentifier: String?) {
        guard let provider = ProcessIdentity.provider(forBundleIdentifier: bundleIdentifier) else { return }
        let stillRunning = currentlyRunningProviders().contains(provider)
        guard !stillRunning else { return }
        knownRunning.remove(provider)
        onProviderStopped?(provider)
    }
}
