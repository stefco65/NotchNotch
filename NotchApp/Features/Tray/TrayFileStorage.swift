import Foundation

struct TrayFileStorage: Sendable {
    let rootURL: URL

    private var metadataURL: URL {
        rootURL.appendingPathComponent("tray-items.json", isDirectory: false)
    }

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)

            self.rootURL = applicationSupport
                .appendingPathComponent("com.notchnook.app", isDirectory: true)
                .appendingPathComponent("Tray", isDirectory: true)
        }

        try? FileManager.default.createDirectory(
            at: self.rootURL,
            withIntermediateDirectories: true
        )
    }

    func loadItems() -> [TrayItem] {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([TrayItem].self, from: data) else {
            return []
        }

        return decoded.filter {
            FileManager.default.fileExists(atPath: $0.storedURL.path)
        }
    }

    /// Returns true when `url` points inside this Tray storage root (including managed copies).
    func isManagedURL(_ url: URL) -> Bool {
        let rootPath = rootURL.resolvingSymlinksInPath().path
        let path = url.resolvingSymlinksInPath().path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    func persist(_ items: [TrayItem]) throws {
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(items)
        try data.write(to: metadataURL, options: .atomic)
    }

    func ingest(_ sourceURL: URL) async throws -> TrayItem {
        let destinationRoot = rootURL

        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let scopedAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if scopedAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: sourceURL.path,
                isDirectory: &isDirectory
            ) else {
                throw CocoaError(.fileNoSuchFile)
            }

            let id = UUID()
            let itemDirectory = destinationRoot
                .appendingPathComponent(id.uuidString, isDirectory: true)
            let destination = itemDirectory
                .appendingPathComponent(sourceURL.lastPathComponent, isDirectory: isDirectory.boolValue)

            do {
                try fileManager.createDirectory(
                    at: itemDirectory,
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: sourceURL, to: destination)

                let attributes = try? fileManager.attributesOfItem(atPath: destination.path)
                let fileSize = (attributes?[.size] as? NSNumber)?.int64Value

                return TrayItem(
                    id: id,
                    storedURL: destination,
                    displayName: sourceURL.lastPathComponent,
                    fileSize: fileSize,
                    addedAt: Date(),
                    isDirectory: isDirectory.boolValue
                )
            } catch {
                try? fileManager.removeItem(at: itemDirectory)
                throw error
            }
        }.value
    }

    func remove(_ item: TrayItem) throws {
        let itemDirectory = item.storedURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: itemDirectory.path) {
            try FileManager.default.removeItem(at: itemDirectory)
        }
    }
}
