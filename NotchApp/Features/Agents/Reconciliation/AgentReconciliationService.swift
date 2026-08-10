import Foundation

@MainActor
final class AgentReconciliationService {
    private let intervalNanoseconds: UInt64
    private var task: Task<Void, Never>?

    init(intervalSeconds: TimeInterval = 20) {
        self.intervalNanoseconds = UInt64(intervalSeconds * 1_000_000_000)
    }

    func start(tick: @escaping @MainActor () async -> Void) {
        stop()
        task = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
                guard !Task.isCancelled else { return }
                await tick()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
