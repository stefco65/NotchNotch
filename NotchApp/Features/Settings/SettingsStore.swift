import Combine
import Foundation

enum PanelComponentKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case media
    case calendar
    case shortcuts
    case tasks
    case agents
    case mirror
    case systemStatus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Muzyka"
        case .calendar: "Kalendarz"
        case .shortcuts: "Skróty"
        case .tasks: "Zadania"
        case .agents: "Agenci AI"
        case .mirror: "Lustro"
        case .systemStatus: "System"
        }
    }

    var subtitle: String {
        switch self {
        case .media: "Okładka, informacje i sterowanie Spotify"
        case .calendar: "Najbliższe wydarzenia"
        case .shortcuts: "Szybkie akcje"
        case .tasks: "Lista rzeczy do zrobienia"
        case .agents: "Codex, Antigravity i Cursor"
        case .mirror: "Podgląd kamery"
        case .systemStatus: "Stan urządzenia"
        }
    }

    var iconName: String {
        switch self {
        case .media: "music.note"
        case .calendar: "calendar"
        case .shortcuts: "wand.and.stars"
        case .tasks: "checklist"
        case .agents: "cpu"
        case .mirror: "video.fill"
        case .systemStatus: "waveform.path.ecg"
        }
    }
}

struct PanelComponentConfiguration: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: PanelComponentKind
    var widthWeight: Double

    init(
        id: UUID = UUID(),
        kind: PanelComponentKind,
        widthWeight: Double = 1
    ) {
        self.id = id
        self.kind = kind
        self.widthWeight = widthWeight
    }
}

struct ShortcutButtonConfiguration: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var shortcutName: String
    var widthWeight: Double

    init(
        id: UUID = UUID(),
        shortcutName: String,
        widthWeight: Double = 1
    ) {
        self.id = id
        self.shortcutName = shortcutName
        self.widthWeight = widthWeight
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let minimumExpandedWidth = 520.0
    static let maximumExpandedWidth = 1_800.0
    private static let componentWidthUnit = 184.0
    private static let componentDividerWidth = 17.0
    private static let expandedHorizontalPadding = 48.0

    private enum Key {
        static let expandedWidth = "panel.expandedWidth"
        static let components = "panel.components"
        static let showOnExternalDisplays = "display.showOnExternalDisplays"
        static let rainbowGlowEnabled = "appearance.rainbowGlowEnabled"
        static let shortcutButtons = "shortcuts.buttons"
        static let didInstallShortcutsComponent = "shortcuts.didInstallComponentV1"
        static let didInstallTasksComponent = "tasks.didInstallComponentV1"
        static let didInstallAgentsComponent = "agents.didInstallComponentV1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()

    @Published private(set) var expandedWidth: Double
    @Published private(set) var components: [PanelComponentConfiguration]
    @Published private(set) var showOnExternalDisplays: Bool
    @Published private(set) var rainbowGlowEnabled: Bool
    @Published private(set) var shortcutButtons: [ShortcutButtonConfiguration]
    @Published private(set) var installedShortcutNames: [String] = []
    @Published private(set) var isLoadingShortcuts = false

    private var shouldSeedShortcutButtons: Bool

    var onGeometryChange: (() -> Void)?
    var onDisplayPolicyChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedWidth = defaults.object(forKey: Key.expandedWidth) as? Double
        expandedWidth = min(
            max(storedWidth ?? 760, Self.minimumExpandedWidth),
            Self.maximumExpandedWidth
        )
        showOnExternalDisplays = defaults.bool(forKey: Key.showOnExternalDisplays)
        rainbowGlowEnabled = defaults.object(forKey: Key.rainbowGlowEnabled) == nil
            ? true
            : defaults.bool(forKey: Key.rainbowGlowEnabled)

        var migratedComponents = false
        let shouldInstallShortcutsComponent = !defaults.bool(
            forKey: Key.didInstallShortcutsComponent
        )
        if let data = defaults.data(forKey: Key.components),
           let decoded = try? JSONDecoder().decode(
               [PanelComponentConfiguration].self,
               from: data
           ),
           !decoded.isEmpty {
            if decoded.contains(where: { $0.kind == .shortcuts })
                || !shouldInstallShortcutsComponent {
                components = decoded
            } else {
                var updated = decoded
                updated.insert(
                    PanelComponentConfiguration(kind: .shortcuts, widthWeight: 1.15),
                    at: min(1, updated.count)
                )
                components = updated
                migratedComponents = true
            }
        } else {
            components = [
                PanelComponentConfiguration(kind: .media, widthWeight: 1.5),
                PanelComponentConfiguration(kind: .shortcuts, widthWeight: 1.15),
                PanelComponentConfiguration(kind: .tasks, widthWeight: 1.25),
                PanelComponentConfiguration(kind: .agents, widthWeight: 2),
                PanelComponentConfiguration(kind: .calendar, widthWeight: 1),
                PanelComponentConfiguration(kind: .systemStatus, widthWeight: 1)
            ]
        }

        defaults.set(true, forKey: Key.didInstallShortcutsComponent)

        if let data = defaults.data(forKey: Key.shortcutButtons),
           let decoded = try? JSONDecoder().decode(
               [ShortcutButtonConfiguration].self,
               from: data
           ) {
            shortcutButtons = decoded
            shouldSeedShortcutButtons = false
        } else {
            shortcutButtons = []
            shouldSeedShortcutButtons = true
        }

        let shouldInstallTasksComponent = !defaults.bool(
            forKey: Key.didInstallTasksComponent
        )
        if shouldInstallTasksComponent,
           !components.contains(where: { $0.kind == .tasks }) {
            let shortcutIndex = components.firstIndex { $0.kind == .shortcuts }
            let insertionIndex = min((shortcutIndex.map { $0 + 1 } ?? 2), components.count)
            components.insert(
                PanelComponentConfiguration(kind: .tasks, widthWeight: 1.25),
                at: insertionIndex
            )
            migratedComponents = true
        }
        defaults.set(true, forKey: Key.didInstallTasksComponent)

        let shouldInstallAgentsComponent = !defaults.bool(
            forKey: Key.didInstallAgentsComponent
        )
        if shouldInstallAgentsComponent,
           !components.contains(where: { $0.kind == .agents }) {
            let tasksIndex = components.firstIndex { $0.kind == .tasks }
            let insertionIndex = min((tasksIndex.map { $0 + 1 } ?? 3), components.count)
            components.insert(
                PanelComponentConfiguration(kind: .agents, widthWeight: 2),
                at: insertionIndex
            )
            migratedComponents = true
        }
        defaults.set(true, forKey: Key.didInstallAgentsComponent)

        if migratedComponents,
           let data = try? encoder.encode(components) {
            defaults.set(data, forKey: Key.components)
        }

        let requiredWidth = Self.requiredExpandedWidth(for: components)
        if expandedWidth < requiredWidth {
            expandedWidth = requiredWidth
            defaults.set(requiredWidth, forKey: Key.expandedWidth)
        }
    }

    var availableComponents: [PanelComponentKind] {
        let selected = Set(components.map(\.kind))
        return PanelComponentKind.allCases.filter { !selected.contains($0) }
    }

    var requiredExpandedWidth: Double {
        Self.requiredExpandedWidth(for: components)
    }

    static func requiredExpandedWidth(
        for components: [PanelComponentConfiguration]
    ) -> Double {
        let totalWeight = max(components.reduce(0) { $0 + $1.widthWeight }, 1)
        let dividerCount = Double(max(components.count - 1, 0))
        let calculated = expandedHorizontalPadding
            + dividerCount * componentDividerWidth
            + totalWeight * componentWidthUnit
        return min(
            max(calculated.rounded(.up), minimumExpandedWidth),
            maximumExpandedWidth
        )
    }

    var availableShortcutNames: [String] {
        let selected = Set(shortcutButtons.map(\.shortcutName))
        return installedShortcutNames.filter { !selected.contains($0) }
    }

    func setExpandedWidth(_ width: Double) {
        let clamped = min(
            max(width, requiredExpandedWidth),
            Self.maximumExpandedWidth
        )
        guard clamped != expandedWidth else { return }
        expandedWidth = clamped
        defaults.set(clamped, forKey: Key.expandedWidth)
        onGeometryChange?()
    }

    func setShowOnExternalDisplays(_ isEnabled: Bool) {
        guard isEnabled != showOnExternalDisplays else { return }
        showOnExternalDisplays = isEnabled
        defaults.set(isEnabled, forKey: Key.showOnExternalDisplays)
        onDisplayPolicyChange?()
    }

    func setRainbowGlowEnabled(_ isEnabled: Bool) {
        guard isEnabled != rainbowGlowEnabled else { return }
        rainbowGlowEnabled = isEnabled
        defaults.set(isEnabled, forKey: Key.rainbowGlowEnabled)
    }

    func refreshInstalledShortcuts() {
        guard !isLoadingShortcuts else { return }
        isLoadingShortcuts = true

        Task { [weak self] in
            let names = await Task.detached(priority: .utility) {
                ShortcutCommandService.listShortcutNames()
            }.value

            guard let self else { return }
            installedShortcutNames = names
            isLoadingShortcuts = false

            if shouldSeedShortcutButtons {
                shortcutButtons = names.prefix(4).map {
                    ShortcutButtonConfiguration(shortcutName: $0)
                }
                shouldSeedShortcutButtons = false
                persistShortcutButtons()
            }
        }
    }

    func addShortcutButton(named shortcutName: String) {
        guard installedShortcutNames.contains(shortcutName),
              !shortcutButtons.contains(where: { $0.shortcutName == shortcutName }) else {
            return
        }
        shortcutButtons.append(ShortcutButtonConfiguration(shortcutName: shortcutName))
        persistShortcutButtons()
    }

    func removeShortcutButton(id: UUID) {
        shortcutButtons.removeAll { $0.id == id }
        persistShortcutButtons()
    }

    func moveShortcutButton(id: UUID, offset: Int) {
        guard let source = shortcutButtons.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard shortcutButtons.indices.contains(destination) else { return }
        shortcutButtons.swapAt(source, destination)
        persistShortcutButtons()
    }

    func setShortcutButtonWidth(id: UUID, value: Double) {
        guard let index = shortcutButtons.firstIndex(where: { $0.id == id }) else { return }
        shortcutButtons[index].widthWeight = min(max(value, 0.6), 3)
        persistShortcutButtons()
    }

    func add(_ kind: PanelComponentKind) {
        guard !components.contains(where: { $0.kind == kind }) else { return }
        components.append(PanelComponentConfiguration(kind: kind))
        persistComponents()
    }

    func remove(id: UUID) {
        guard components.count > 1 else { return }
        components.removeAll { $0.id == id }
        persistComponents()
    }

    func move(id: UUID, offset: Int) {
        guard let source = components.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard components.indices.contains(destination) else { return }
        components.swapAt(source, destination)
        persistComponents()
    }

    func setWidthWeight(id: UUID, value: Double) {
        guard let index = components.firstIndex(where: { $0.id == id }) else { return }
        components[index].widthWeight = min(max(value, 0.5), 3)
        persistComponents()
    }

    /// Live divider drag: keeps `left + right` constant without writing defaults
    /// or resizing the notch window (that would glitch under the cursor).
    func previewDividerWeights(
        leftID: UUID,
        rightID: UUID,
        leftWeight: Double,
        rightWeight: Double
    ) {
        guard let leftIndex = components.firstIndex(where: { $0.id == leftID }),
              let rightIndex = components.firstIndex(where: { $0.id == rightID }) else {
            return
        }

        let pairTotal = components[leftIndex].widthWeight + components[rightIndex].widthWeight
        var left = min(max(leftWeight, 0.5), pairTotal - 0.5)
        var right = pairTotal - left
        right = min(max(right, 0.5), pairTotal - 0.5)
        left = pairTotal - right

        let leftChanged = abs(components[leftIndex].widthWeight - left) > 0.0001
        let rightChanged = abs(components[rightIndex].widthWeight - right) > 0.0001
        guard leftChanged || rightChanged else { return }

        components[leftIndex].widthWeight = left
        components[rightIndex].widthWeight = right
    }

    /// Persists the current component layout after a divider drag ends.
    func commitComponentLayout() {
        persistComponents()
    }

    func adjustDivider(leftID: UUID, rightID: UUID, deltaWeight: Double) {
        guard let leftIndex = components.firstIndex(where: { $0.id == leftID }),
              let rightIndex = components.firstIndex(where: { $0.id == rightID }) else {
            return
        }

        let left = components[leftIndex].widthWeight
        let right = components[rightIndex].widthWeight
        let acceptedDelta = min(max(deltaWeight, 0.5 - left), right - 0.5)
        guard acceptedDelta != 0 else { return }

        components[leftIndex].widthWeight += acceptedDelta
        components[rightIndex].widthWeight -= acceptedDelta
        persistComponents()
    }

    private func persistComponents() {
        if let data = try? encoder.encode(components) {
            defaults.set(data, forKey: Key.components)
        }
        let requiredWidth = Self.requiredExpandedWidth(for: components)
        if expandedWidth < requiredWidth {
            expandedWidth = requiredWidth
            defaults.set(requiredWidth, forKey: Key.expandedWidth)
        }
        onGeometryChange?()
    }

    private func persistShortcutButtons() {
        if let data = try? encoder.encode(shortcutButtons) {
            defaults.set(data, forKey: Key.shortcutButtons)
        }
    }
}
