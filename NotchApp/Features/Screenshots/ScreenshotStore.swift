import Combine
import Foundation

/// Screenshots saved by macOS into its configured screenshot folder.
/// The folder is watched only while the Photos tab is on screen.
@MainActor
final class ScreenshotStore: ObservableObject {
    @Published private(set) var folder: URL
    @Published private(set) var items: [ScreenshotItem] = []

    private let location: any ScreenshotLocationStoring
    private let watcher = DirectoryChangeWatcher()
    private var rescanTask: Task<Void, Never>?
    /// One per visible Photos tab (each display has its own notch).
    private var viewerCount = 0
    private var isMonitoring: Bool { viewerCount > 0 }

    init(location: any ScreenshotLocationStoring = SystemScreenshotLocation()) {
        self.location = location
        folder = location.folder()
        watcher.onChange = { [weak self] in
            // Screenshots land as a hidden temp file that is renamed shortly after.
            self?.scheduleRescan(delayMilliseconds: 250)
        }
    }

    func startMonitoring() {
        viewerCount += 1
        syncFolderWithSystem()
        // Re-attach every time: the folder may have been recreated meanwhile.
        watcher.watch(folder)
        scheduleRescan(delayMilliseconds: 0)
    }

    func stopMonitoring() {
        viewerCount = max(viewerCount - 1, 0)
        guard !isMonitoring else { return }
        watcher.stop()
        rescanTask?.cancel()
    }

    /// Picks up a destination changed elsewhere, e.g. in the Screenshot app's Options.
    func syncFolderWithSystem() {
        apply(folder: location.folder())
    }

    func setFolder(_ url: URL) {
        location.setFolder(url)
        apply(folder: url.standardizedFileURL)
    }

    func reload() async {
        let folder = folder
        let found = await Task.detached(priority: .utility) {
            ScreenshotScanner.screenshots(in: folder)
        }.value
        guard folder == self.folder, found != items else { return }
        items = found
    }

    private func apply(folder newFolder: URL) {
        guard newFolder != folder else { return }
        folder = newFolder
        items = []
        if isMonitoring {
            watcher.watch(newFolder)
        }
        scheduleRescan(delayMilliseconds: 0)
    }

    private func scheduleRescan(delayMilliseconds: Int) {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            if delayMilliseconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delayMilliseconds) * 1_000_000)
            }
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }
}

@MainActor
private final class DirectoryChangeWatcher {
    var onChange: (() -> Void)?
    private var source: DispatchSourceFileSystemObject?

    func watch(_ directory: URL) {
        stop()
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .link],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
