import Foundation

/// Where macOS saves screenshots.
@MainActor
protocol ScreenshotLocationStoring: AnyObject {
    func folder() -> URL
    func setFolder(_ url: URL)
}

/// `com.apple.screencapture` → `location`: the same value the Screenshot app
/// (⇧⌘5) edits under Options → "Save to".
@MainActor
final class SystemScreenshotLocation: ScreenshotLocationStoring {
    private static let domain = "com.apple.screencapture" as CFString
    private static let key = "location" as CFString

    nonisolated init() {}

    func folder() -> URL {
        Self.resolve(storedPath: CFPreferencesCopyAppValue(Self.key, Self.domain) as? String)
    }

    func setFolder(_ url: URL) {
        CFPreferencesSetAppValue(Self.key, url.path as CFString, Self.domain)
        CFPreferencesAppSynchronize(Self.domain)
    }

    /// An unset location means the Desktop; the stored path may start with `~`.
    nonisolated static func resolve(
        storedPath: String?,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        guard let storedPath, !storedPath.trimmingCharacters(in: .whitespaces).isEmpty else {
            return homeDirectory.appendingPathComponent("Desktop", isDirectory: true)
        }
        let path = storedPath.hasPrefix("~")
            ? homeDirectory.path + storedPath.dropFirst()
            : storedPath
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }
}
