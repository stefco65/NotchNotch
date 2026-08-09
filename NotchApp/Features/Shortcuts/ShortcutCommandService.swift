import Combine
import Foundation

enum ShortcutCommandService {
    struct ExecutionResult: Sendable {
        let succeeded: Bool
        let message: String?
    }

    nonisolated static func listShortcutNames() -> [String] {
        let result = execute(arguments: ["list"])
        guard result.succeeded, let output = result.message else { return [] }

        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated static func run(shortcutName: String) -> ExecutionResult {
        execute(arguments: ["run", shortcutName])
    }

    nonisolated private static func execute(arguments: [String]) -> ExecutionResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ExecutionResult(succeeded: false, message: error.localizedDescription)
        }

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let errorOutput = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        return ExecutionResult(
            succeeded: process.terminationStatus == 0,
            message: process.terminationStatus == 0 ? output : errorOutput
        )
    }
}

@MainActor
final class ShortcutRunner: ObservableObject {
    @Published private(set) var runningButtonID: UUID?
    @Published private(set) var lastError: String?

    func run(_ button: ShortcutButtonConfiguration) {
        guard runningButtonID == nil else { return }
        runningButtonID = button.id
        lastError = nil

        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                ShortcutCommandService.run(shortcutName: button.shortcutName)
            }.value

            guard let self else { return }
            runningButtonID = nil
            if !result.succeeded {
                lastError = result.message ?? "Nie udało się uruchomić skrótu."
            }
        }
    }
}
