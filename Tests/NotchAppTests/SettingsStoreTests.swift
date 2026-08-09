import Foundation
import XCTest
@testable import NotchNook

@MainActor
final class SettingsStoreTests: XCTestCase {
    private let suiteName = "com.notchnook.settings-tests"

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testWidthAndComponentsPersist() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = SettingsStore(defaults: defaults)

        store.setExpandedWidth(1_700)
        store.add(.mirror)
        store.setShowOnExternalDisplays(true)

        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.expandedWidth, 1_700)
        XCTAssertTrue(restored.components.contains { $0.kind == .mirror })
        XCTAssertTrue(restored.showOnExternalDisplays)
    }

    func testExternalDisplayPolicyNotifiesOnlyWhenItChanges() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = SettingsStore(defaults: defaults)
        var notificationCount = 0
        store.onDisplayPolicyChange = { notificationCount += 1 }

        store.setShowOnExternalDisplays(true)
        store.setShowOnExternalDisplays(true)

        XCTAssertEqual(notificationCount, 1)
    }

    func testRainbowGlowIsEnabledByDefaultAndPersists() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = SettingsStore(defaults: defaults)

        XCTAssertTrue(store.rainbowGlowEnabled)
        store.setRainbowGlowEnabled(false)

        let restored = SettingsStore(defaults: defaults)
        XCTAssertFalse(restored.rainbowGlowEnabled)
    }

    func testDividerKeepsCombinedWeight() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = SettingsStore(defaults: defaults)
        let left = try XCTUnwrap(store.components.first)
        let right = try XCTUnwrap(store.components.dropFirst().first)
        let combined = left.widthWeight + right.widthWeight

        store.adjustDivider(leftID: left.id, rightID: right.id, deltaWeight: 0.25)

        XCTAssertEqual(
            store.components[0].widthWeight + store.components[1].widthWeight,
            combined,
            accuracy: 0.0001
        )
    }

    func testShortcutButtonSizeOrderAndRemovalPersist() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let first = ShortcutButtonConfiguration(shortcutName: "Pierwszy")
        let second = ShortcutButtonConfiguration(shortcutName: "Drugi")
        defaults.set(
            try JSONEncoder().encode([first, second]),
            forKey: "shortcuts.buttons"
        )

        let store = SettingsStore(defaults: defaults)
        store.setShortcutButtonWidth(id: first.id, value: 2.4)
        store.moveShortcutButton(id: first.id, offset: 1)

        var restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.shortcutButtons.map(\.shortcutName), ["Drugi", "Pierwszy"])
        XCTAssertEqual(restored.shortcutButtons[1].widthWeight, 2.4, accuracy: 0.0001)

        restored.removeShortcutButton(id: second.id)
        restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.shortcutButtons.map(\.shortcutName), ["Pierwszy"])
    }

    func testRemovingShortcutsComponentDoesNotUndoMigration() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = SettingsStore(defaults: defaults)
        let shortcuts = try XCTUnwrap(store.components.first { $0.kind == .shortcuts })

        store.remove(id: shortcuts.id)

        let restored = SettingsStore(defaults: defaults)
        XCTAssertFalse(restored.components.contains { $0.kind == .shortcuts })
    }

    func testAddingComponentAutomaticallyExpandsPanelWhenNeeded() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let initialComponents = [
            PanelComponentConfiguration(kind: .media, widthWeight: 1),
            PanelComponentConfiguration(kind: .calendar, widthWeight: 1),
            PanelComponentConfiguration(kind: .mirror, widthWeight: 1),
            PanelComponentConfiguration(kind: .systemStatus, widthWeight: 1)
        ]
        defaults.set(try JSONEncoder().encode(initialComponents), forKey: "panel.components")
        defaults.set(true, forKey: "shortcuts.didInstallComponentV1")
        defaults.set(true, forKey: "tasks.didInstallComponentV1")
        defaults.set(true, forKey: "agents.didInstallComponentV1")

        let store = SettingsStore(defaults: defaults)
        let initialWidth = store.expandedWidth
        store.add(.shortcuts)

        XCTAssertGreaterThan(store.expandedWidth, initialWidth)
        XCTAssertEqual(store.expandedWidth, store.requiredExpandedWidth)
    }
}
