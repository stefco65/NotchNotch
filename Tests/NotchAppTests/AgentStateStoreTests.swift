import Foundation
import XCTest
@testable import NotchNook

@MainActor
final class AgentStateStoreTests: XCTestCase {
    func testInactiveProviderIgnoresWorkingEvent() {
        let store = AgentStateStore()
        let event = NormalizedAgentEvent(
            provider: .cursor,
            agentID: "a1",
            kind: .working,
            timestamp: Date(),
            providerInstanceID: UUID()
        )
        store.handle(event)
        XCTAssertEqual(store.summaries.first { $0.source == .cursor }?.counts.working, 0)
    }

    func testStartedAgentCountsAsWorking() {
        let store = AgentStateStore()
        store.providerStarted(.cursor)
        let instance = store.instanceID(for: .cursor)!
        store.handle(
            NormalizedAgentEvent(
                provider: .cursor,
                agentID: "a1",
                kind: .started,
                timestamp: Date(),
                providerInstanceID: instance
            )
        )
        XCTAssertEqual(store.summaries.first { $0.source == .cursor }?.counts.working, 1)
    }

    func testWorkingToWaitingTransition() {
        let store = AgentStateStore()
        store.providerStarted(.codex)
        let instance = store.instanceID(for: .codex)!
        let t0 = Date(timeIntervalSince1970: 100)
        store.handle(.init(provider: .codex, agentID: "a", kind: .working, timestamp: t0, providerInstanceID: instance))
        store.handle(.init(provider: .codex, agentID: "a", kind: .waitingForUser, timestamp: t0.addingTimeInterval(1), providerInstanceID: instance))

        let summary = store.summaries.first { $0.source == .codex }
        XCTAssertEqual(summary?.counts.working, 0)
        XCTAssertEqual(summary?.counts.stopped, 1)
    }

    func testWaitingToResumedTransition() {
        let store = AgentStateStore()
        store.providerStarted(.codex)
        let instance = store.instanceID(for: .codex)!
        let t0 = Date(timeIntervalSince1970: 100)
        store.handle(.init(provider: .codex, agentID: "a", kind: .waitingForUser, timestamp: t0, providerInstanceID: instance))
        store.handle(.init(provider: .codex, agentID: "a", kind: .resumed, timestamp: t0.addingTimeInterval(1), providerInstanceID: instance))

        let summary = store.summaries.first { $0.source == .codex }
        XCTAssertEqual(summary?.counts.working, 1)
        XCTAssertEqual(summary?.counts.stopped, 0)
    }

    func testWorkingToCompletedTransition() {
        let store = AgentStateStore()
        store.providerStarted(.antigravity)
        let instance = store.instanceID(for: .antigravity)!
        let t0 = Date(timeIntervalSince1970: 100)
        store.handle(.init(provider: .antigravity, agentID: "a", kind: .working, timestamp: t0, providerInstanceID: instance))
        store.handle(.init(provider: .antigravity, agentID: "a", kind: .completed, timestamp: t0.addingTimeInterval(1), providerInstanceID: instance))

        let summary = store.summaries.first { $0.source == .antigravity }
        XCTAssertEqual(summary?.counts.working, 0)
        XCTAssertEqual(summary?.counts.done, 1)
    }

    func testProviderTerminatedClearsAgents() {
        let store = AgentStateStore()
        store.providerStarted(.cursor)
        let instance = store.instanceID(for: .cursor)!
        for index in 0..<5 {
            store.handle(
                .init(
                    provider: .cursor,
                    agentID: "a\(index)",
                    kind: .working,
                    timestamp: Date(),
                    providerInstanceID: instance
                )
            )
        }
        store.providerStopped(.cursor)
        let summary = store.summaries.first { $0.source == .cursor }
        XCTAssertEqual(summary?.counts.working, 0)
        XCTAssertEqual(summary?.counts.stopped, 0)
        XCTAssertEqual(summary?.counts.done, 0)
        XCTAssertEqual(store.providers[.cursor]?.agents.isEmpty, true)
    }

    func testStaleInstanceEventsAreIgnored() {
        let store = AgentStateStore()
        store.providerStarted(.cursor)
        let oldInstance = store.instanceID(for: .cursor)!
        store.providerStopped(.cursor)
        store.providerStarted(.cursor)

        store.handle(
            .init(
                provider: .cursor,
                agentID: "ghost",
                kind: .working,
                timestamp: Date(),
                providerInstanceID: oldInstance
            )
        )
        XCTAssertEqual(store.summaries.first { $0.source == .cursor }?.counts.working, 0)
    }

    func testOutOfOrderEventsDoNotRewindState() {
        let store = AgentStateStore()
        store.providerStarted(.cursor)
        let instance = store.instanceID(for: .cursor)!
        let completedAt = Date(timeIntervalSince1970: 1_000)
        let olderWorking = Date(timeIntervalSince1970: 900)

        store.handle(.init(provider: .cursor, agentID: "a", kind: .completed, timestamp: completedAt, providerInstanceID: instance))
        store.handle(.init(provider: .cursor, agentID: "a", kind: .working, timestamp: olderWorking, providerInstanceID: instance))

        let agent = store.providers[.cursor]?.agents["a"]
        XCTAssertEqual(agent?.status, .completed)
    }

    func testEventDeduplication() {
        let store = AgentStateStore()
        store.providerStarted(.cursor)
        let instance = store.instanceID(for: .cursor)!
        let event = NormalizedAgentEvent(
            provider: .cursor,
            agentID: "a",
            kind: .working,
            timestamp: Date(),
            providerInstanceID: instance,
            eventID: "evt-1"
        )
        store.handle(event)
        store.handle(
            NormalizedAgentEvent(
                provider: .cursor,
                agentID: "a",
                kind: .completed,
                timestamp: Date().addingTimeInterval(1),
                providerInstanceID: instance,
                eventID: "evt-1"
            )
        )
        XCTAssertEqual(store.providers[.cursor]?.agents["a"]?.status, .working)
    }

    func testReplaceAgentsResync() {
        let store = AgentStateStore()
        store.providerStarted(.cursor)
        store.replaceAgents(
            [
                AgentSnapshot(
                    id: "one",
                    provider: .cursor,
                    status: .working,
                    lifecycle: .executing,
                    updatedAt: Date()
                ),
                AgentSnapshot(
                    id: "two",
                    provider: .cursor,
                    status: .waitingForUser,
                    lifecycle: .executing,
                    updatedAt: Date()
                )
            ],
            for: .cursor
        )
        let summary = store.summaries.first { $0.source == .cursor }
        XCTAssertEqual(summary?.counts.working, 1)
        XCTAssertEqual(summary?.counts.stopped, 1)
    }
}
