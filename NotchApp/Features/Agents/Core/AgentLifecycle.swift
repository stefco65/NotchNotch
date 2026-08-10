import Foundation

enum AgentLifecycle: String, Codable, Sendable {
    case created
    case executing
    case finished
}
