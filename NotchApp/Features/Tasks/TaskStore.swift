import Combine
import Foundation

struct NookTask: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.isCompleted = isCompleted
    }
}

@MainActor
final class TaskStore: ObservableObject {
    private static let storageKey = "tasks.items"

    private let defaults: UserDefaults
    private let completionDelay: Duration
    private let encoder = JSONEncoder()

    @Published private(set) var items: [NookTask]

    init(
        defaults: UserDefaults = .standard,
        completionDelay: Duration = .seconds(1)
    ) {
        self.defaults = defaults
        self.completionDelay = completionDelay

        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([NookTask].self, from: data) {
            items = decoded.filter { !$0.isCompleted }
            if items.count != decoded.count {
                persist()
            }
        } else {
            items = []
        }
    }

    @discardableResult
    func add(title: String) -> NookTask? {
        let normalized = normalizedTitle(title)
        guard !normalized.isEmpty else { return nil }

        let item = NookTask(title: normalized)
        items.append(item)
        persist()
        return item
    }

    func update(id: UUID, title: String) {
        let normalized = normalizedTitle(title)
        guard !normalized.isEmpty,
              let index = items.firstIndex(where: { $0.id == id }),
              !items[index].isCompleted else {
            return
        }

        items[index].title = normalized
        persist()
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func complete(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              !items[index].isCompleted else {
            return
        }

        items[index].isCompleted = true
        persist()

        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: completionDelay)
            guard !Task.isCancelled else { return }
            removeCompleted(id: id)
        }
    }

    private func removeCompleted(id: UUID) {
        items.removeAll { $0.id == id && $0.isCompleted }
        persist()
    }

    private func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func persist() {
        if let data = try? encoder.encode(items) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
