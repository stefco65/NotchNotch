import Foundation

enum AgentProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case antigravity
    case cursor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .cursor: "Cursor"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .codex: "com.openai.codex"
        case .antigravity: "com.google.antigravity"
        case .cursor: "com.todesktop.230313mzl4w4u92"
        }
    }

    var applicationPath: String {
        switch self {
        case .codex: "/Applications/ChatGPT.app"
        case .antigravity: "/Applications/Antigravity.app"
        case .cursor: "/Applications/Cursor.app"
        }
    }
}

/// UI-facing alias kept for existing Live Activity / component call sites.
typealias AgentSource = AgentProvider
