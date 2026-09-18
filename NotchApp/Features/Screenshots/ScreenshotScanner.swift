import Darwin
import Foundation

struct ScreenshotItem: Identifiable, Equatable, Sendable {
    let url: URL
    let createdAt: Date

    var id: URL { url }
}

enum ScreenshotScanner {
    /// macOS tags every capture with this attribute, which keeps other images
    /// (e.g. on the Desktop) out of the Photos tab.
    static let screenCaptureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"
    static let defaultLimit = 60

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "bmp", "pdf"
    ]

    /// Screenshots directly inside `folder`, newest first.
    static func screenshots(in folder: URL, limit: Int = defaultLimit) -> [ScreenshotItem] {
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let items = urls.compactMap { url -> ScreenshotItem? in
            guard imageExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  isScreenCapture(url) else {
                return nil
            }
            return ScreenshotItem(url: url, createdAt: values.creationDate ?? .distantPast)
        }
        return Array(items.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    static func isScreenCapture(_ url: URL) -> Bool {
        getxattr(url.path, screenCaptureAttribute, nil, 0, 0, 0) >= 0
    }
}
