import Combine
import Foundation

/// Coordinates presence monitoring, provider tool interfaces, IPC and reconciliation.
/// Publishes UI-facing `summaries` derived exclusively from `AgentStateStore`.
@MainActor
final class AgentMonitorStore: ObservableObject {
    @Published private(set) var summaries: [AgentSourceSummary] = AgentProvider.allCases.map {
        AgentSourceSummary(source: $0, counts: AgentCounts(), isApplicationRunning: false)
    }

    let stateStore: AgentStateStore

    private let paths: AgentMonitorPaths
    private let presenceMonitor = ApplicationPresenceMonitor()
    // Cursor status chips change several times per turn; keep this tight so
    // the Agents component / DI update without waiting for a hover redraw.
    private let reconciliation = AgentReconciliationService(intervalSeconds: 1)
    private let eventServer = AgentEventServer()

    private var tools: [AgentProvider: any AgentToolInterface] = [:]
    private var activeProviders = Set<AgentProvider>()
    private var storeCancellable: AnyCancellable?
    private var debounceTask: Task<Void, Never>?
    private var hasStarted = false
    private var isResyncing = false
    private var resyncRequested = false

    /// Bumped on every summaries publish so AppKit-hosted SwiftUI cannot keep
    /// a stale render until the next pointer/layout pass.
    @Published private(set) var renderEpoch: UInt64 = 0

    init(
        stateStore: AgentStateStore? = nil,
        paths: AgentMonitorPaths = .currentUser(),
        tools: [any AgentToolInterface]? = nil,
        adapters: [any AgentProviderAdapter]? = nil
    ) {
        let resolvedStore = stateStore ?? AgentStateStore()
        self.stateStore = resolvedStore
        self.paths = paths

        let resolvedTools: [any AgentToolInterface]
        if let tools {
            resolvedTools = tools
        } else if let adapters {
            // Test / legacy injection: wrap bare adapters in lightweight shells
            // without filesystem signal monitors.
            resolvedTools = adapters.map { AdapterOnlyToolInterface(adapter: $0) }
        } else {
            resolvedTools = AgentToolFactory.makeDefaultTools(paths: paths)
        }

        for tool in resolvedTools {
            self.tools[tool.provider] = tool
            tool.adapter.onEvent = { [weak self] event in
                Task { @MainActor in
                    self?.stateStore.handle(event)
                }
            }
            tool.signalMonitor.onChange = { [weak self] in
                self?.scheduleResync(debounceMs: 120)
            }
        }

        storeCancellable = resolvedStore.$providers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.publishSummaries()
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
            tools[provider]?.signalMonitor.stop()
            tools[provider]?.adapter.stop()
        }
        activeProviders.removeAll()
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
              let tool = tools[provider] else {
            publishSummaries()
            return
        }

        activeProviders.insert(provider)
        tool.signalMonitor.start()
        publishSummaries()

        do {
            try await tool.adapter.start(instanceID: instanceID)
            let agents = try await tool.adapter.resync()
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
        tools[provider]?.signalMonitor.stop()
        tools[provider]?.adapter.stop()
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

        let providers = Array(activeProviders)
        for provider in providers {
            guard activeProviders.contains(provider),
                  let tool = tools[provider] else { continue }
            do {
                let agents = try await tool.adapter.resync()
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
        let kindOverride = tools[provider]?.mapHookEvent(payload.event)
        guard let event = AgentEventDecoder.normalize(
            payload,
            fallbackInstanceID: fallbackInstanceID,
            kindOverride: kindOverride
        ) else {
            AgentEventLogger.debug("IPC event rejected / incomplete")
            return
        }
        stateStore.handle(event)
        publishSummaries()
    }

    // MARK: - UI publish

    private func publishSummaries() {
        let next = stateStore.summaries
        guard next != summaries else { return }
        summaries = next
        renderEpoch &+= 1
    }
}

/// Thin shell so tests can still inject bare `AgentProviderAdapter` instances.
@MainActor
private final class AdapterOnlyToolInterface: AgentToolInterface {
    let provider: AgentProvider
    let capabilities: ProviderCapabilities
    let adapter: any AgentProviderAdapter
    let signalMonitor: any AgentToolSignalMonitor

    init(adapter: any AgentProviderAdapter) {
        self.provider = adapter.provider
        self.capabilities = adapter.capabilities
        self.adapter = adapter
        self.signalMonitor = NoopAgentSignalMonitor(provider: adapter.provider)
    }

    func mapHookEvent(_ name: String) -> NormalizedAgentEvent.Kind? {
        AgentEventDecoder.mapKind(name)
    }
}

@MainActor
private final class NoopAgentSignalMonitor: AgentToolSignalMonitor {
    let provider: AgentProvider
    var onChange: (() -> Void)?

    init(provider: AgentProvider) {
        self.provider = provider
    }

    func start() {}
    func stop() {}
}
