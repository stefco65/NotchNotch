import Foundation

actor AgentEventServer {
    private let socket: SocketServer
    private var onEvent: (@Sendable (AgentEventPayload) -> Void)?

    static var defaultSocketURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("NotchNook", isDirectory: true)
            .appendingPathComponent("agent-events.sock")
    }

    init(socketURL: URL = AgentEventServer.defaultSocketURL) {
        self.socket = SocketServer(socketPath: socketURL.path)
    }

    func start(onEvent: @escaping @Sendable (AgentEventPayload) -> Void) async throws {
        self.onEvent = onEvent
        try await socket.start { [weak self] data in
            Task { await self?.handle(data) }
        }
        AgentEventLogger.notice("AgentEventServer listening")
    }

    func stop() async {
        await socket.stop()
        onEvent = nil
        AgentEventLogger.notice("AgentEventServer stopped")
    }

    private func handle(_ data: Data) {
        do {
            let payload = try AgentEventDecoder.decode(data)
            onEvent?(payload)
        } catch {
            AgentEventLogger.debug("IPC decode failed: \(error.localizedDescription)")
        }
    }
}
