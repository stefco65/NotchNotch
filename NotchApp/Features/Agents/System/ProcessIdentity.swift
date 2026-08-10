import Foundation

struct ProcessIdentity: Equatable, Sendable {
    let provider: AgentProvider
    let bundleIdentifier: String
    let applicationPath: String

    static let known: [ProcessIdentity] = AgentProvider.allCases.map {
        ProcessIdentity(
            provider: $0,
            bundleIdentifier: $0.bundleIdentifier,
            applicationPath: $0.applicationPath
        )
    }

    static func provider(forBundleIdentifier bundleIdentifier: String?) -> AgentProvider? {
        guard let bundleIdentifier else { return nil }
        return known.first { $0.bundleIdentifier == bundleIdentifier }?.provider
    }
}
