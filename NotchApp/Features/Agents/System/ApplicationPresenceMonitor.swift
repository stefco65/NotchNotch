import AppKit
import Foundation

@MainActor
final class ApplicationPresenceMonitor {
    var onProviderStarted: ((AgentProvider) -> Void)?
    var onProviderStopped: ((AgentProvider) -> Void)?

    /// Providers whose sessions can outlive their desktop app (a CLI in a terminal).
    /// Such a provider counts as running while its app runs or a probe reports sessions.
    var detachedSessionProbes: [AgentProvider: @Sendable () -> Bool] = [:]

    private let isApplicationRunning: (AgentProvider) -> Bool
    private var observers: [NSObjectProtocol] = []
    private var knownRunning = Set<AgentProvider>()
    private var isRunning = false

    init(isApplicationRunning: @escaping (AgentProvider) -> Bool = ApplicationPresenceMonitor.systemIsApplicationRunning) {
        self.isApplicationRunning = isApplicationRunning
    }

    nonisolated static func systemIsApplicationRunning(_ provider: AgentProvider) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: provider.bundleIdentifier).isEmpty
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        for provider in AgentProvider.allCases where isApplicationRunning(provider) {
            setPresence(true, for: provider)
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
                    await self?.handleTerminate(bundleIdentifier: bundleID)
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

    func isProviderRunning(_ provider: AgentProvider) -> Bool {
        knownRunning.contains(provider)
    }

    /// Re-checks providers with detached-session probes and emits start/stop transitions.
    func refreshDetachedSessions() async {
        guard isRunning, !detachedSessionProbes.isEmpty else { return }
        let probes = detachedSessionProbes
        let withSessions = await Task.detached(priority: .utility) {
            Set(probes.compactMap { provider, probe in probe() ? provider : nil })
        }.value
        guard isRunning else { return }

        for provider in AgentProvider.allCases where probes[provider] != nil {
            setPresence(withSessions.contains(provider) || isApplicationRunning(provider), for: provider)
        }
    }

    private func handleLaunch(bundleIdentifier: String?) {
        guard let provider = ProcessIdentity.provider(forBundleIdentifier: bundleIdentifier) else { return }
        setPresence(true, for: provider)
    }

    private func handleTerminate(bundleIdentifier: String?) async {
        guard let provider = ProcessIdentity.provider(forBundleIdentifier: bundleIdentifier) else { return }
        if detachedSessionProbes[provider] != nil {
            // CLI sessions may keep the provider alive after its app quits.
            await refreshDetachedSessions()
        } else {
            setPresence(isApplicationRunning(provider), for: provider)
        }
    }

    private func setPresence(_ isPresent: Bool, for provider: AgentProvider) {
        guard isPresent != knownRunning.contains(provider) else { return }
        if isPresent {
            knownRunning.insert(provider)
            onProviderStarted?(provider)
        } else {
            knownRunning.remove(provider)
            onProviderStopped?(provider)
        }
    }
}
