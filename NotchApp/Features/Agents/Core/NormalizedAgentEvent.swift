import Foundation

struct NormalizedAgentEvent: Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case started
        case working
        case waitingForUser
        case resumed
        case completed
        case failed
        case cancelled
        case removed
    }

    let provider: AgentProvider
    let agentID: String
    let kind: Kind
    let timestamp: Date
    let providerInstanceID: UUID

    var eventID: String?
    var title: String?
    var workspace: String?
    var isSubagent: Bool
    var parentAgentID: String?

    init(
        provider: AgentProvider,
        agentID: String,
        kind: Kind,
        timestamp: Date,
        providerInstanceID: UUID,
        eventID: String? = nil,
        title: String? = nil,
        workspace: String? = nil,
        isSubagent: Bool = false,
        parentAgentID: String? = nil
    ) {
        self.provider = provider
        self.agentID = agentID
        self.kind = kind
        self.timestamp = timestamp
        self.providerInstanceID = providerInstanceID
        self.eventID = eventID
        self.title = title
        self.workspace = workspace
        self.isSubagent = isSubagent
        self.parentAgentID = parentAgentID
    }
}
