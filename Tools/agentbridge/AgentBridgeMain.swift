import Foundation

@main
struct AgentBridgeMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        do {
            if args.isEmpty || args.contains("-h") || args.contains("--help") {
                printHelp()
                return
            }

            if args.first == "emit" {
                try emit(fromCLI: Array(args.dropFirst()))
                return
            }

            if args.contains("--stdin") || args.first == "-" {
                try emit(fromStdin: FileHandle.standardInput.readDataToEndOfFile())
                return
            }

            // Bare JSON string argument.
            if let first = args.first, first.hasPrefix("{") {
                try emit(fromStdin: Data(first.utf8))
                return
            }

            fputs("Unknown arguments. Use `agentbridge emit ...` or pipe JSON to stdin.\n", stderr)
            exit(2)
        } catch {
            fputs("agentbridge error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func printHelp() {
        print(
            """
            agentbridge — emit normalized agent events to NotchNook via Unix socket.

            Usage:
              agentbridge emit --provider <cursor|codex|antigravity> --agent <id> --state <event> [options]
              echo '<json>' | agentbridge --stdin

            Options:
              --provider <name>          Provider id
              --agent <id>               Agent / session / conversation id
              --state <event>            started|working|waiting|waitingForUser|completed|failed|cancelled|removed
              --instance <uuid>          Provider instance id (optional)
              --event-id <id>            Deduplication id (optional)
              --title <text>             Optional title
              --workspace <path>         Optional workspace
              --socket <path>            Override socket path
              --stdin                    Read one JSON payload from stdin

            Socket default:
              ~/Library/Application Support/NotchNook/agent-events.sock
            """
        )
    }

    private static func emit(fromCLI args: [String]) throws {
        var provider: String?
        var agent: String?
        var state: String?
        var instance: String?
        var eventID: String?
        var title: String?
        var workspace: String?
        var socketPath: String?

        var index = 0
        while index < args.count {
            let key = args[index]
            let value = index + 1 < args.count ? args[index + 1] : nil
            switch key {
            case "--provider":
                provider = value; index += 2
            case "--agent":
                agent = value; index += 2
            case "--state", "--event":
                state = value; index += 2
            case "--instance":
                instance = value; index += 2
            case "--event-id":
                eventID = value; index += 2
            case "--title":
                title = value; index += 2
            case "--workspace":
                workspace = value; index += 2
            case "--socket":
                socketPath = value; index += 2
            default:
                throw BridgeError.unknownArgument(key)
            }
        }

        guard let provider, let agent, let state else {
            throw BridgeError.missingRequiredArguments
        }

        let payload = AgentBridgePayload(
            version: 1,
            provider: provider,
            agentId: agent,
            event: state,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            unixTimestamp: Date().timeIntervalSince1970,
            providerInstanceId: instance,
            eventId: eventID,
            title: title,
            workspace: workspace,
            isSubagent: nil,
            parentAgentId: nil
        )
        try send(payload: payload, socketPath: socketPath)
    }

    private static func emit(fromStdin data: Data) throws {
        guard !data.isEmpty else { throw BridgeError.emptyStdin }
        let payload = try JSONDecoder().decode(AgentBridgePayload.self, from: data)
        try send(payload: payload, socketPath: nil)
    }

    private static func send(payload: AgentBridgePayload, socketPath: String?) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(payload)
        data.append(UInt8(ascii: "\n"))

        let path = socketPath ?? defaultSocketPath()
        try UnixSocketClient.send(data: data, path: path)
        fputs("ok\n", stdout)
    }

    private static func defaultSocketPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/NotchNook/agent-events.sock"
    }
}

struct AgentBridgePayload: Codable {
    var version: Int
    var provider: String
    var agentId: String
    var event: String
    var timestamp: String?
    var unixTimestamp: TimeInterval?
    var providerInstanceId: String?
    var eventId: String?
    var title: String?
    var workspace: String?
    var isSubagent: Bool?
    var parentAgentId: String?
}

enum BridgeError: Error, LocalizedError {
    case unknownArgument(String)
    case missingRequiredArguments
    case emptyStdin
    case connectFailed(Int32)
    case writeFailed(Int32)
    case pathTooLong

    var errorDescription: String? {
        switch self {
        case .unknownArgument(let arg): "Unknown argument: \(arg)"
        case .missingRequiredArguments: "Required: --provider, --agent, --state"
        case .emptyStdin: "stdin was empty"
        case .connectFailed(let code): "connect() failed (\(code)). Is NotchNook running?"
        case .writeFailed(let code): "write() failed (\(code))"
        case .pathTooLong: "Socket path too long"
        }
    }
}

enum UnixSocketClient {
    static func send(data: Data, path: String) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BridgeError.connectFailed(errno) }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxPath = MemoryLayout.size(ofValue: address.sun_path) - 1
        let pathBytes = path.utf8CString
        guard pathBytes.count - 1 <= maxPath else { throw BridgeError.pathTooLong }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: maxPath + 1) { cPath in
                pathBytes.withUnsafeBufferPointer { buffer in
                    cPath.update(from: buffer.baseAddress!, count: buffer.count)
                }
            }
        }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw BridgeError.connectFailed(errno) }

        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let wrote = write(fd, base.advanced(by: sent), data.count - sent)
                if wrote <= 0 { throw BridgeError.writeFailed(errno) }
                sent += wrote
            }
        }
    }
}
