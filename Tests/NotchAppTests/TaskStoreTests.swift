import Foundation
import XCTest
@testable import NotchNook

@MainActor
final class TaskStoreTests: XCTestCase {
    private let suiteName = "com.notchnook.task-tests"

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testAddEditCompleteAndDelayedRemovalPersist() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = TaskStore(defaults: defaults, completionDelay: .milliseconds(10))

        let item = try XCTUnwrap(store.add(title: "  Pierwsze zadanie  "))
        XCTAssertEqual(item.title, "Pierwsze zadanie")

        store.update(id: item.id, title: "Zmienione zadanie")
        let restored = TaskStore(defaults: defaults)
        XCTAssertEqual(restored.items.first?.title, "Zmienione zadanie")

        store.complete(id: item.id)
        XCTAssertTrue(store.items.first?.isCompleted == true)

        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(TaskStore(defaults: defaults).items.isEmpty)
    }

    func testEmptyTaskIsIgnoredAndDeletePersists() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = TaskStore(defaults: defaults)

        XCTAssertNil(store.add(title: "  \n "))
        let item = try XCTUnwrap(store.add(title: "Do usunięcia"))
        store.delete(id: item.id)

        XCTAssertTrue(TaskStore(defaults: defaults).items.isEmpty)
    }
}
