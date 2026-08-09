import Foundation

struct TrayItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let storedURL: URL
    let displayName: String
    let fileSize: Int64?
    let addedAt: Date
    let isDirectory: Bool
}
