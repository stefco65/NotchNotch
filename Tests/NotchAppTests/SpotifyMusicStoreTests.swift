import Foundation
import XCTest
@testable import NotchNook

@MainActor
final class SpotifyMusicStoreTests: XCTestCase {
    func testKeepsPreviousArtworkUntilNewArtworkFinishesLoading() async throws {
        let oldArtwork = Data([1, 2, 3])
        let newArtwork = Data([4, 5, 6])
        let oldURL = URL(string: "https://example.com/old.jpg")!
        let newURL = URL(string: "https://example.com/new.jpg")!
        let store = SpotifyMusicStore { url in
            try? await Task.sleep(for: .milliseconds(20))
            return url == newURL ? newArtwork : nil
        }

        store.applySnapshot(SpotifyTrack(
            title: "Old",
            album: "Album",
            artist: "Artist",
            artworkURL: oldURL,
            artworkData: oldArtwork,
            isPlaying: true
        ))
        store.applySnapshot(SpotifyTrack(
            title: "New",
            album: "Album",
            artist: "Artist",
            artworkURL: newURL,
            artworkData: nil,
            isPlaying: true
        ))

        XCTAssertEqual(store.track.artworkData, oldArtwork)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(store.track.artworkData, newArtwork)
    }

    func testMissingArtworkDuringPauseDoesNotClearCurrentCover() {
        let artwork = Data([7, 8, 9])
        let artworkURL = URL(string: "https://example.com/current.jpg")!
        let store = SpotifyMusicStore(artworkLoader: { _ in nil })

        store.applySnapshot(SpotifyTrack(
            title: "Track",
            album: "Album",
            artist: "Artist",
            artworkURL: artworkURL,
            artworkData: artwork,
            isPlaying: true
        ))
        store.applySnapshot(SpotifyTrack(
            title: "Track",
            album: "Album",
            artist: "Artist",
            artworkURL: nil,
            artworkData: nil,
            isPlaying: false
        ))

        XCTAssertEqual(store.track.artworkURL, artworkURL)
        XCTAssertEqual(store.track.artworkData, artwork)
    }

    func testCachedArtworkIsReusedImmediately() {
        let artwork = Data([10, 11, 12])
        let artworkURL = URL(string: "https://example.com/cached.jpg")!
        let store = SpotifyMusicStore(artworkLoader: { _ in nil })

        store.applySnapshot(SpotifyTrack(
            title: "First",
            album: "Album",
            artist: "Artist",
            artworkURL: artworkURL,
            artworkData: artwork,
            isPlaying: true
        ))
        store.applySnapshot(SpotifyTrack(
            title: "Again",
            album: "Album",
            artist: "Artist",
            artworkURL: artworkURL,
            artworkData: nil,
            isPlaying: true
        ))

        XCTAssertEqual(store.track.artworkData, artwork)
    }
}
