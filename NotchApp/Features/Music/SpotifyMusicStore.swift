import AppKit
import Combine
import Foundation
import OSLog
import ScriptingBridge

struct SpotifyTrack: Equatable, Sendable {
    var title: String
    var album: String
    var artist: String
    var artworkURL: URL?
    var artworkData: Data?
    var isPlaying: Bool

    static let unavailable = SpotifyTrack(
        title: "Spotify",
        album: "Brak odtwarzanego utworu",
        artist: "Uruchom Spotify, aby rozpocząć",
        artworkURL: nil,
        artworkData: nil,
        isPlaying: false
    )
}

@MainActor
final class SpotifyMusicStore: ObservableObject {
    typealias ArtworkLoader = @Sendable (URL) async -> Data?

    private struct SnapshotResult: Sendable {
        let track: SpotifyTrack?
        let errorCode: Int?
    }

    enum Command: Sendable {
        case previous
        case playPause
        case next
    }

    @Published private(set) var track = SpotifyTrack.unavailable {
        didSet { updateActiveSourceState() }
    }
    @Published private(set) var isSpotifyRunning = false {
        didSet { updateActiveSourceState() }
    }
    @Published private(set) var hasActiveTrack = false

    private let distributedCenter = DistributedNotificationCenter.default()
    private let logger = AppLogger.music
    private var playbackObserver: NSObjectProtocol?
    private var availabilityMonitorTask: Task<Void, Never>?
    private var isRefreshInProgress = false
    private var consecutiveSnapshotFailures = 0
    private let artworkCache = NSCache<NSURL, NSData>()
    private let artworkLoader: ArtworkLoader
    private var artworkLoadTask: Task<Void, Never>?
    private var loadingArtworkURL: URL?

    init(artworkLoader: ArtworkLoader? = nil) {
        self.artworkLoader = artworkLoader ?? { url in
            await Task.detached(priority: .utility) {
                try? Data(contentsOf: url)
            }.value
        }
        artworkCache.countLimit = 24
    }

    deinit {
        availabilityMonitorTask?.cancel()
        artworkLoadTask?.cancel()
    }

    func startMonitoring() {
        guard availabilityMonitorTask == nil else { return }

        if playbackObserver == nil {
            playbackObserver = distributedCenter.addObserver(
                forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let eventTrack = Self.track(from: notification.userInfo) else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    isSpotifyRunning = true
                    applySnapshot(eventTrack)
                    logger.debug("Spotify playback notification: \(eventTrack.title, privacy: .public)")
                    refresh()
                }
            }
        }

        availabilityMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }

    func stopMonitoring() {
        availabilityMonitorTask?.cancel()
        availabilityMonitorTask = nil

        if let playbackObserver {
            distributedCenter.removeObserver(playbackObserver)
            self.playbackObserver = nil
        }
    }

    func requestAutomationAccessAndRefresh() {
        guard let processIdentifier = Self.spotifyProcessIdentifier() else {
            isSpotifyRunning = false
            return
        }
        isSpotifyRunning = true
        logger.notice(
            "Synchronizing Spotify process \(processIdentifier, privacy: .public)"
        )
        refresh()
    }

    func refresh() {
        let wasSpotifyRunning = isSpotifyRunning
        let processIdentifier = Self.spotifyProcessIdentifier()
        isSpotifyRunning = processIdentifier != nil

        guard let processIdentifier else {
            consecutiveSnapshotFailures = 0
            clearActiveSource()
            return
        }
        if !wasSpotifyRunning {
            logger.notice("Spotify source appeared; requesting access and synchronizing")
            requestAutomationAccessAndRefresh()
            return
        }
        guard !isRefreshInProgress else { return }
        isRefreshInProgress = true

        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Self.readCurrentTrack(processIdentifier: processIdentifier)
            }.value

            guard let self else { return }
            isRefreshInProgress = false

            if let fetchedTrack = result.track {
                consecutiveSnapshotFailures = 0
                applySnapshot(fetchedTrack)
                logger.debug("Spotify track refreshed: \(fetchedTrack.title, privacy: .public)")
                return
            }

            consecutiveSnapshotFailures += 1
            if result.errorCode == -1743 {
                consecutiveSnapshotFailures = 0
                artworkLoadTask?.cancel()
                loadingArtworkURL = nil
                track = SpotifyTrack(
                    title: "Spotify",
                    album: "Brak dostępu do odtwarzania",
                    artist: "Włącz Spotify w Ustawienia > Prywatność > Automatyzacja",
                    artworkURL: nil,
                    artworkData: nil,
                    isPlaying: false
                )
            } else if consecutiveSnapshotFailures >= 2 {
                clearActiveSource()
            }
            logger.error("Spotify Apple Event failed, code=\(result.errorCode ?? 0, privacy: .public)")
            AppErrorLog.record(
                severity: .error,
                category: "music",
                message: "Spotify Apple Event failed",
                details: "errorCode: \(result.errorCode.map(String.init) ?? "nil")"
            )
        }
    }

    func perform(_ command: Command) {
        guard let processIdentifier = Self.spotifyProcessIdentifier() else {
            if let url = URL(string: "spotify:") {
                NSWorkspace.shared.open(url)
            }
            return
        }

        Task { [weak self] in
            await Task.detached(priority: .userInitiated) {
                Self.perform(command, processIdentifier: processIdentifier)
            }.value
            self?.refresh()
        }
    }

    /// Publishes metadata without ever clearing an artwork that is already visible.
    /// A new image replaces the previous one only after the entire payload is available.
    func applySnapshot(_ incomingTrack: SpotifyTrack) {
        var nextTrack = incomingTrack
        var artworkURLToLoad: URL?

        if let artworkData = incomingTrack.artworkData {
            if let artworkURL = incomingTrack.artworkURL {
                artworkCache.setObject(artworkData as NSData, forKey: artworkURL as NSURL)
            }
        } else if let artworkURL = incomingTrack.artworkURL {
            if let cachedArtwork = artworkCache.object(forKey: artworkURL as NSURL) {
                nextTrack.artworkData = cachedArtwork as Data
            } else if artworkURL == track.artworkURL, let currentArtwork = track.artworkData {
                nextTrack.artworkData = currentArtwork
            } else {
                // Keep the old cover while the new track's cover is being fetched.
                nextTrack.artworkData = track.artworkData
                artworkURLToLoad = artworkURL
            }
        } else {
            // Spotify notifications sometimes omit artwork during pause/stop transitions.
            nextTrack.artworkURL = track.artworkURL
            nextTrack.artworkData = track.artworkData
        }

        track = nextTrack

        if let artworkURLToLoad {
            loadArtwork(at: artworkURLToLoad)
        }
    }

    private func loadArtwork(at url: URL) {
        guard loadingArtworkURL != url else { return }
        artworkLoadTask?.cancel()
        loadingArtworkURL = url
        let loader = artworkLoader

        artworkLoadTask = Task { [weak self] in
            let data = await loader(url)
            guard !Task.isCancelled, let self else { return }
            if loadingArtworkURL == url {
                loadingArtworkURL = nil
                artworkLoadTask = nil
            }
            guard let data else { return }

            artworkCache.setObject(data as NSData, forKey: url as NSURL)
            guard track.artworkURL == url else { return }
            var updatedTrack = track
            updatedTrack.artworkData = data
            track = updatedTrack
        }
    }

    private func clearActiveSource() {
        artworkLoadTask?.cancel()
        artworkLoadTask = nil
        loadingArtworkURL = nil
        track = .unavailable
    }

    private func updateActiveSourceState() {
        let isActive = isSpotifyRunning
            && track.title != SpotifyTrack.unavailable.title
        guard isActive != hasActiveTrack else { return }
        hasActiveTrack = isActive
    }

    private static func spotifyProcessIdentifier() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
            .filter { !$0.isTerminated }
            .max {
                ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast)
            }?
            .processIdentifier
    }

    nonisolated private static func readCurrentTrack(
        processIdentifier: pid_t
    ) -> SnapshotResult {
        guard let application = SBApplication(processIdentifier: processIdentifier),
              application.isRunning else {
            return SnapshotResult(track: nil, errorCode: -600)
        }

        guard let state = (application.value(forKey: "playerState") as? NSNumber)?.uint32Value else {
            return SnapshotResult(
                track: nil,
                errorCode: (application.lastError() as NSError?)?.code
            )
        }

        if state == fourCharacterCode("kPSS") {
            return SnapshotResult(track: .unavailable, errorCode: nil)
        }

        guard let activeTrack = application.value(forKey: "currentTrack") as? NSObject else {
            return SnapshotResult(
                track: nil,
                errorCode: (application.lastError() as NSError?)?.code
            )
        }

        let artworkString = activeTrack.value(forKey: "artworkUrl") as? String
            ?? activeTrack.value(forKey: "coverURL") as? String
            ?? ""
        let artworkURL = normalizedArtworkURL(from: artworkString)
        return SnapshotResult(
            track: SpotifyTrack(
                title: activeTrack.value(forKey: "name") as? String ?? "Spotify",
                album: activeTrack.value(forKey: "album") as? String
                    ?? "Brak informacji o albumie",
                artist: activeTrack.value(forKey: "artist") as? String
                    ?? "Brak informacji o artyście",
                artworkURL: artworkURL,
                artworkData: nil,
                isPlaying: state == fourCharacterCode("kPSP")
            ),
            errorCode: nil
        )
    }

    nonisolated private static func perform(
        _ command: Command,
        processIdentifier: pid_t
    ) {
        guard let application = SBApplication(processIdentifier: processIdentifier),
              application.isRunning else { return }

        let selectorName = switch command {
        case .previous: "previousTrack"
        case .playPause: "playpause"
        case .next: "nextTrack"
        }
        _ = application.perform(NSSelectorFromString(selectorName))
    }

    nonisolated private static func fourCharacterCode(_ value: String) -> UInt32 {
        value.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    nonisolated private static func track(from userInfo: [AnyHashable: Any]?) -> SpotifyTrack? {
        guard let userInfo else { return nil }

        func value(_ keys: [String]) -> String? {
            for key in keys {
                if let value = userInfo[key] as? String, !value.isEmpty {
                    return value
                }
            }
            return nil
        }

        guard let title = value(["Name", "Track Name", "Title"]) else { return nil }
        let state = value(["Player State", "State"])?.lowercased()
        let artwork = value(["Album Artwork", "Artwork URL", "Artwork Url"])
        return SpotifyTrack(
            title: title,
            album: value(["Album"]) ?? "Brak informacji o albumie",
            artist: value(["Artist"]) ?? "Brak informacji o artyście",
            artworkURL: artwork.flatMap(normalizedArtworkURL(from:)),
            artworkData: nil,
            isPlaying: state == "playing"
        )
    }

    nonisolated private static func normalizedArtworkURL(from value: String) -> URL? {
        if value.hasPrefix("spotify:image:") {
            let identifier = value.dropFirst("spotify:image:".count)
            return URL(string: "https://i.scdn.co/image/\(identifier)")
        }
        return URL(string: value)
    }
}
