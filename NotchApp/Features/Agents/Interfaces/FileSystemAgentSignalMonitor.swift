import Foundation

/// Shared filesystem watcher used by per-tool signal monitors.
@MainActor
final class FileSystemAgentSignalMonitor: AgentToolSignalMonitor {
    let provider: AgentProvider
    var onChange: (() -> Void)?

    private let watchURLs: [URL]
    private let debounceMilliseconds: Int
    private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    private var debounceTask: Task<Void, Never>?
    private var isRunning = false

    init(
        provider: AgentProvider,
        watchURLs: [URL],
        debounceMilliseconds: Int = 120
    ) {
        self.provider = provider
        self.watchURLs = watchURLs
        self.debounceMilliseconds = debounceMilliseconds
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        ensureWatchers()
    }

    func stop() {
        isRunning = false
        debounceTask?.cancel()
        debounceTask = nil
        for watcher in watchers.values {
            watcher.cancel()
        }
        watchers.removeAll()
    }

    private func ensureWatchers() {
        for url in watchURLs where watchers[url.path] == nil {
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
                guard let self, self.isRunning else { return }
                if flags.contains(.delete) || flags.contains(.rename) {
                    self.watchers[path]?.cancel()
                    self.watchers[path] = nil
                    // Directory / WAL may reappear after atomic replace.
                    self.ensureWatchers()
                } else {
                    // Paths that did not exist at start can appear later.
                    self.ensureWatchers()
                }
                self.scheduleNotify()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watchers[path] = source
    }

    private func scheduleNotify() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            let delay = UInt64(self?.debounceMilliseconds ?? 120) * 1_000_000
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.onChange?()
            }
        }
    }
}
