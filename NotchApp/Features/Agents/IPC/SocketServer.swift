import Foundation

actor SocketServer {
    private let path: String
    private var listenerFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: DispatchSourceRead] = [:]
    private var onData: (@Sendable (Data) -> Void)?
    private var isRunning = false

    init(socketPath: String) {
        self.path = socketPath
    }

    func start(onData: @escaping @Sendable (Data) -> Void) throws {
        guard !isRunning else { return }
        self.onData = onData

        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw AgentIPCError.socketCreateFailed(errno)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxPath = MemoryLayout.size(ofValue: address.sun_path) - 1
        let pathBytes = path.utf8CString
        guard pathBytes.count - 1 <= maxPath else {
            close(fd)
            throw AgentIPCError.pathTooLong
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: maxPath + 1) { cPath in
                pathBytes.withUnsafeBufferPointer { buffer in
                    cPath.update(from: buffer.baseAddress!, count: buffer.count)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw AgentIPCError.bindFailed(errno)
        }
        guard listen(fd, 16) == 0 else {
            close(fd)
            throw AgentIPCError.listenFailed(errno)
        }

        listenerFD = fd
        isRunning = true

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            Task { await self?.acceptClient() }
        }
        source.setCancelHandler {
            close(fd)
        }
        acceptSource = source
        source.resume()
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        for (_, source) in clients {
            source.cancel()
        }
        clients.removeAll()
        if listenerFD >= 0 {
            close(listenerFD)
            listenerFD = -1
        }
        unlink(path)
        isRunning = false
        onData = nil
    }

    private func acceptClient() {
        guard listenerFD >= 0 else { return }
        let clientFD = accept(listenerFD, nil, nil)
        guard clientFD >= 0 else { return }

        let source = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            Task { await self?.readClient(clientFD) }
        }
        source.setCancelHandler {
            close(clientFD)
        }
        clients[clientFD] = source
        source.resume()
    }

    private func readClient(_ clientFD: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        let bytesRead = read(clientFD, &buffer, buffer.count)
        if bytesRead <= 0 {
            clients[clientFD]?.cancel()
            clients[clientFD] = nil
            return
        }
        let data = Data(buffer.prefix(bytesRead))
        // Support one JSON object per write, or newline-delimited JSON.
        let chunks = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        let payloads = chunks.isEmpty ? [data] : chunks.map { Data($0) }
        for payload in payloads {
            onData?(payload)
        }
    }
}

enum AgentIPCError: Error, LocalizedError {
    case socketCreateFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case pathTooLong
    case connectFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .socketCreateFailed(let code): "socket() failed: \(code)"
        case .bindFailed(let code): "bind() failed: \(code)"
        case .listenFailed(let code): "listen() failed: \(code)"
        case .pathTooLong: "Unix socket path is too long"
        case .connectFailed(let code): "connect() failed: \(code)"
        }
    }
}
