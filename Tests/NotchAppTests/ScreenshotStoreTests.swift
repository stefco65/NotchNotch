import Darwin
import Foundation
import XCTest
@testable import NotchNook

@MainActor
final class ScreenshotStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenshot-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testUnsetLocationDefaultsToDesktop() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        XCTAssertEqual(SystemScreenshotLocation.resolve(storedPath: nil, homeDirectory: home).path, "/Users/tester/Desktop")
        XCTAssertEqual(SystemScreenshotLocation.resolve(storedPath: "  ", homeDirectory: home).path, "/Users/tester/Desktop")
    }

    func testStoredLocationExpandsTilde() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        XCTAssertEqual(
            SystemScreenshotLocation.resolve(storedPath: "~/Pictures/Shots", homeDirectory: home).path,
            "/Users/tester/Pictures/Shots"
        )
        XCTAssertEqual(SystemScreenshotLocation.resolve(storedPath: "/Volumes/Data/Shots", homeDirectory: home).path, "/Volumes/Data/Shots")
    }

    func testScannerKeepsOnlyTaggedImagesNewestFirst() throws {
        let now = Date()
        try makeFile("older.png", screenshot: true, createdAt: now.addingTimeInterval(-600))
        try makeFile("newer.jpg", screenshot: true, createdAt: now.addingTimeInterval(-60))
        try makeFile("photo.png", screenshot: false, createdAt: now)
        try makeFile("notes.txt", screenshot: true, createdAt: now)
        try makeFile(".hidden.png", screenshot: true, createdAt: now)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("folder.png"), withIntermediateDirectories: true)

        let names = ScreenshotScanner.screenshots(in: root).map(\.url.lastPathComponent)

        XCTAssertEqual(names, ["newer.jpg", "older.png"])
    }

    func testScannerRespectsLimitAndMissingFolder() throws {
        let now = Date()
        for index in 0..<5 {
            try makeFile("shot-\(index).png", screenshot: true, createdAt: now.addingTimeInterval(TimeInterval(index)))
        }

        XCTAssertEqual(ScreenshotScanner.screenshots(in: root, limit: 2).map(\.url.lastPathComponent), ["shot-4.png", "shot-3.png"])
        XCTAssertTrue(ScreenshotScanner.screenshots(in: root.appendingPathComponent("missing")).isEmpty)
    }

    func testSetFolderUpdatesSystemLocationAndReloads() async throws {
        let first = root.appendingPathComponent("first", isDirectory: true)
        let second = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try makeFile("second/shot.png", screenshot: true, createdAt: Date())
        let location = FakeScreenshotLocation(folder: first)
        let store = ScreenshotStore(location: location)

        store.setFolder(second)
        await store.reload()

        XCTAssertEqual(location.storedFolder, second.standardizedFileURL)
        XCTAssertEqual(store.folder, second.standardizedFileURL)
        XCTAssertEqual(store.items.map(\.url.lastPathComponent), ["shot.png"])
    }

    func testNewScreenshotAppearsWhileMonitoring() async throws {
        let store = ScreenshotStore(location: FakeScreenshotLocation(folder: root))
        store.startMonitoring()
        defer { store.stopMonitoring() }
        await store.reload()
        XCTAssertTrue(store.items.isEmpty)

        // macOS writes a hidden temp file first, then renames it into place.
        try makeFile(".Zrzut ekranu.png", screenshot: true, createdAt: Date())
        try FileManager.default.moveItem(
            at: root.appendingPathComponent(".Zrzut ekranu.png"),
            to: root.appendingPathComponent("Zrzut ekranu.png")
        )

        for _ in 0..<30 where store.items.isEmpty {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(store.items.map(\.url.lastPathComponent), ["Zrzut ekranu.png"])
    }

    func testSyncPicksUpFolderChangedOutsideTheApp() throws {
        let first = root.appendingPathComponent("first", isDirectory: true)
        let other = root.appendingPathComponent("other", isDirectory: true)
        let location = FakeScreenshotLocation(folder: first)
        let store = ScreenshotStore(location: location)

        location.storedFolder = other
        store.syncFolderWithSystem()

        XCTAssertEqual(store.folder, other)
    }

    private func makeFile(_ name: String, screenshot: Bool, createdAt: Date) throws {
        let url = root.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        try FileManager.default.setAttributes([.creationDate: createdAt], ofItemAtPath: url.path)
        if screenshot {
            let value: [UInt8] = [1]
            let result = setxattr(url.path, ScreenshotScanner.screenCaptureAttribute, value, value.count, 0, 0)
            XCTAssertEqual(result, 0)
        }
    }
}

@MainActor
private final class FakeScreenshotLocation: ScreenshotLocationStoring {
    var storedFolder: URL

    init(folder: URL) {
        storedFolder = folder
    }

    func folder() -> URL {
        storedFolder
    }

    func setFolder(_ url: URL) {
        storedFolder = url.standardizedFileURL
    }
}
