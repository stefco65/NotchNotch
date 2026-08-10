import Combine
import Foundation

/// Coordinates presence monitoring, provider adapters, IPC and reconciliation.
/// Publishes UI-facing `summaries` derived exclusively from `AgentStateStore`.
@MainActor
final class AgentMonitorStore: ObservableObject {
    @Published private(set) var summaries: [AgentSourceSummary] = AgentProvider.allCases.map {
        AgentSourceSummary(source: $0, counts: AgentCounts(), isApplicationRunning: false)
    }

    let stateStore: AgentStateStore

    private let paths: AgentMonitorPaths
    private let presenceMonitor = ApplicationPresenceMonitor()
    private let reconciliation = AgentReconciliationService(intervalSeconds: 20)
    private let eventServer = AgentEventServer()

    private var adapters: [AgentProvider: any AgentProviderAdapter] = [:]
    private var activeProviders = Set<AgentProvider>()
    private var storeCancellable: AnyCancellable?
    private var fsWatchers: [String: DispatchSourceFileSystemObject] = [:]
    private var debounceTask: Task<Void, Never>?
    private var hasStarted = false
    private var isResyncing = false
    private var resyncRequested = false

    init(
        stateStore: AgentStateStore? = nil,
        paths: AgentMonitorPaths = .currentUser(),
        adapters: [any AgentProviderAdapter]? = nil
    ) {
        let resolvedStore = stateStore ?? AgentStateStore()
        self.stateStore = resolvedStore
        self.paths = paths

        let builtAdapters = adapters ?? [
            CursorAdapter(paths: paths),
            CodexAdapter(paths: paths),
            AntigravityAdapter(paths: paths)
        ]
        for adapter in builtAdapters {
            self.adapters[adapter.provider] = adapter
            adapter.onEvent = { [weak self] event in
                Task { @MainActor in
                    self?.stateStore.handle(event)
                }
            }
        }

        storeCancellable = resolvedStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.publishSummaries()
                }
            }
        publishSummaries()
    }

    func startMonitoring() {
        guard !hasStarted else { return }
        hasStarted = true

        presenceMonitor.onProviderStarted = { [weak self] provider in
            Task { @MainActor in
                await self?.handleProviderStarted(provider)
            }
        }
        presenceMonitor.onProviderStopped = { [weak self] provider in
            Task { @MainActor in
                await self?.handleProviderStopped(provider)
            }
        }
        // Presence callbacks are async; overlays/UI must not wait on first resync.
        presenceMonitor.start()

        ensureFileSystemWatchers()
        reconciliation.start { [weak self] in
            await self?.resyncActiveProviders()
        }

        Task { [weak self] in
            await self?.startIPCServer()
        }
    }

    func stopMonitoring() {
        debounceTask?.cancel()
        debounceTask = nil
        reconciliation.stop()
        presenceMonitor.stop()
        for provider in activeProviders {
            adapters[provider]?.stop()
        }
        activeProviders.removeAll()
        for watcher in fsWatchers.values {
            watcher.cancel()
        }
        fsWatchers.removeAll()
        Task { await eventServer.stop() }
        hasStarted = false
    }

    func refresh() {
        scheduleResync(debounceMs: 0)
    }

    // MARK: - Presence

    private func handleProviderStarted(_ provider: AgentProvider) async {
        stateStore.providerStarted(provider)
        guard let instanceID = stateStore.instanceID(for: provider),
              let adapter = adapters[provider] else {
            publishSummaries()
            return
        }

        activeProviders.insert(provider)
        publishSummaries()

        do {
            try await adapter.start(instanceID: instanceID)
            let agents = try await adapter.resync()
            // Provider may have been stopped while we were scanning.
            guard activeProviders.contains(provider) else { return }
            stateStore.replaceAgents(agents, for: provider)
        } catch {
            AgentEventLogger.error(
                "adapter start/resync failed for \(provider.rawValue): \(error.localizedDescription)"
            )
        }
        publishSummaries()
    }

    private func handleProviderStopped(_ provider: AgentProvider) async {
        adapters[provider]?.stop()
        activeProviders.remove(provider)
        stateStore.providerStopped(provider)
        publishSummaries()
    }

    // MARK: - Resync / reconciliation

    private func scheduleResync(debounceMs: Int) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            if debounceMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounceMs) * 1_000_000)
            }
            guard !Task.isCancelled else { return }
            await self?.resyncActiveProviders()
        }
    }

    private func resyncActiveProviders() async {
        if isResyncing {
            resyncRequested = true
            return
        }
        isResyncing = true
        defer { isResyncing = false }

        ensureFileSystemWatchers()

        let providers = Array(activeProviders)
        for provider in providers {
            guard activeProviders.contains(provider),
                  let adapter = adapters[provider] else { continue }
            do {
                let agents = try await adapter.resync()
                guard activeProviders.contains(provider) else { continue }
                stateStore.replaceAgents(agents, for: provider)
            } catch {
                AgentEventLogger.debug(
                    "resync failed for \(provider.rawValue): \(error.localizedDescription)"
                )
            }
        }
        publishSummaries()

        if resyncRequested {
            resyncRequested = false
            // Yield so FS bursts / UI events can breathe between scans.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            await resyncActiveProviders()
        }
    }

    // MARK: - IPC

    private func startIPCServer() async {
        do {
            try await eventServer.start { [weak self] payload in
                Task { @MainActor in
                    self?.ingestIPCPayload(payload)
                }
            }
        } catch {
            AgentEventLogger.error("IPC server failed: \(error.localizedDescription)")
        }
    }

    private func ingestIPCPayload(_ payload: AgentEventPayload) {
        guard let provider = AgentProvider(rawValue: payload.provider.lowercased()) else { return }
        let fallbackInstanceID = stateStore.instanceID(for: provider)
        guard let event = AgentEventDecoder.normalize(payload, fallbackInstanceID: fallbackInstanceID) else {
            AgentEventLogger.debug("IPC event rejected / incomplete")
            return
        }
        stateStore.handle(event)
        publishSummaries()
    }

    // MARK: - File watchers (resync triggers)

    private func ensureFileSystemWatchers() {
        for url in paths.watchTargets where fsWatchers[url.path] == nil {
            watchPath(url.path)
        }
    }

    private func watchPath(_ path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib, .link],
            queue: .main
        )

        source.setEventHandler { [weak self, weak source] in
            let flags = source?.data ?? []
            MainActor.assumeIsolated {
                guard let self else { return }
                if flags.contains(.delete) || flags.contains(.rename) {
                    self.fsWatchers[path]?.cancel()
                    self.fsWatchers[path] = nil
                }
                // Cursor/Codex write bursts are frequent — coalesce hard.
                self.scheduleResync(debounceMs: 250)
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fsWatchers[path] = source
    }

    // MARK: - UI publish

    private func publishSummaries() {
        let next = stateStore.summaries
        if next != summaries {
            summaries = next
        }
    }
}
