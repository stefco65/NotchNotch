import Foundation

/// Compatibility façade for older tests / geometry checks.
/// Prefer provider-specific mappers (`CursorEventMapper`, `CodexEventMapper`, …) in new code.
enum AgentStatusScanner {
    static let recencyWindow: TimeInterval = 3600

    static func codexEventState(type: String) -> AgentActivityState? {
        CodexEventMapper.status(fromEventType: type).map(AgentActivityState.init(status:))
    }

    static func codexState(
        in rolloutData: Data,
        lastModified: Date? = nil,
        now: Date = Date()
    ) -> AgentActivityState? {
        CodexEventMapper.status(in: rolloutData, lastModified: lastModified, now: now)
            .map(AgentActivityState.init(status:))
    }

    typealias CursorComposerSignals = CursorEventMapper.ComposerSignals

    static func cursorState(status: String) -> AgentActivityState {
        cursorState(CursorComposerSignals(status: status))
    }

    static func cursorState(_ signals: CursorComposerSignals) -> AgentActivityState {
        AgentActivityState(status: CursorEventMapper.status(from: signals))
    }

    static func cursorShouldInclude(
        state: AgentActivityState,
        lastUpdatedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        CursorEventMapper.shouldInclude(
            status: state.status,
            lastUpdatedAt: lastUpdatedAt,
            now: now
        )
    }

    static func antigravityState(status: Int) -> AgentActivityState {
        AgentActivityState(status: AntigravityEventMapper.status(fromStepStatus: status))
    }

    static func antigravityConversationState(
        lastStatus: Int,
        hasWorkingStep: Bool
    ) -> AgentActivityState {
        AgentActivityState(
            status: AntigravityEventMapper.conversationStatus(
                lastStatus: lastStatus,
                hasWorkingStep: hasWorkingStep
            )
        )
    }
}
