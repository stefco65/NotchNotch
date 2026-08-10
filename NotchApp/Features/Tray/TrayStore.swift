import Combine
import Foundation
import OSLog

@MainActor
final class TrayStore: ObservableObject {
    @Published private(set) var items: [TrayItem]
    @Published private(set) var isIngesting = false
    @Published private(set) var lastError: String?

    private let storage: TrayFileStorage
    private let logger = AppLogger.tray

    init(storage: TrayFileStorage = TrayFileStorage()) {
        self.storage = storage
        items = storage.loadItems()
    }

    func ingest(_ urls: [URL]) {
        // Ignore drops that already live inside Tray storage (e.g. dragging a card
        // back onto the tray) so we don't re-copy managed files.
        let externalURLs = urls.filter { !storage.isManagedURL($0) }
        guard !externalURLs.isEmpty else { return }
        isIngesting = true
        lastError = nil

        Task { [weak self, storage] in
            guard let self else { return }
            for url in externalURLs {
                do {
                    let item = try await storage.ingest(url)
                    items.append(item)
                    try storage.persist(items)
                } catch {
                    lastError = "Nie udało się dodać \(url.lastPathComponent)."
                    AppErrorLog.record(
                        error,
                        category: "tray",
                        message: "Tray ingest failed for \(url.lastPathComponent)"
                    )
                    logger.error("Tray ingest failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            isIngesting = false
        }
    }

    func remove(_ item: TrayItem) {
        do {
            try storage.remove(item)
            items.removeAll { $0.id == item.id }
            try storage.persist(items)
        } catch {
            lastError = "Nie udało się usunąć \(item.displayName)."
            AppErrorLog.record(
                error,
                category: "tray",
                message: "Tray removal failed for \(item.displayName)"
            )
            logger.error("Tray removal failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
