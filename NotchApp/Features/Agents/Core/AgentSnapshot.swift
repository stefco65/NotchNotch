import Foundation

struct AgentSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let provider: AgentProvider

    var status: AgentStatus
    var lifecycle: AgentLifecycle
    var updatedAt: Date

    var workspace: String?
    var title: String?
    var description: String?

    var startedAt: Date?
    var completedAt: Date?
    var parentAgentID: String?
    var isSubagent: Bool

    init(
        id: String,
        provider: AgentProvider,
        status: AgentStatus,
        lifecycle: AgentLifecycle,
        updatedAt: Date,
        workspace: String? = nil,
        title: String? = nil,
        description: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        parentAgentID: String? = nil,
        isSubagent: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.status = status
        self.lifecycle = lifecycle
        self.updatedAt = updatedAt
        self.workspace = workspace
        self.title = title
        self.description = description
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.parentAgentID = parentAgentID
        self.isSubagent = isSubagent
    }
}
