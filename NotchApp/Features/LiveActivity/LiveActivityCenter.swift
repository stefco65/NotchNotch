import Combine
import Foundation

/// One piece of "live" information the dynamic-island bubble can display.
enum LiveActivity: Equatable, Sendable {
    /// Aggregated agent state across all sources. The state carries the
    /// display priority: stopped (orange) > done (green) > working (blue).
    case agents(state: AgentActivityState, count: Int)
    /// Number of open tasks on the task list.
    case tasks(count: Int)
}

/// Decides what the dynamic-island bubble next to the notch should show.
///
/// Rules:
///  - When agent counts change, the agent summary takes the bubble over for
///    `agentTakeoverDuration` seconds (like an iOS Live Activity update).
///  - Otherwise the bubble shows the open-task count, if any tasks exist.
///  - With nothing to show the bubble hides (`activity == nil`).
@MainActor
final class LiveActivityCenter: ObservableObject {
    @Published private(set) var activity: LiveActivity?

    /// How long an agent status update owns the bubble before it falls back
    /// to the default content.
    static let agentTakeoverDuration: TimeInterval = 8

    private var latestAgentHighlight: LiveActivity?
    private var openTaskCount = 0
    private var agentTakeoverActive = false
    private var takeoverExpiryTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(agentMonitorStore: AgentMonitorStore, taskStore: TaskStore) {
        latestAgentHighlight = Self.agentHighlight(from: agentMonitorStore.summaries)

        agentMonitorStore.$summaries
            .map(Self.agentHighlight(from:))
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] highlight in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.latestAgentHighlight = highlight
                    if highlight != nil {
                        self.beginAgentTakeover()
                    } else {
                        self.resolveActivity()
                    }
                }
            }
            .store(in: &cancellables)

        taskStore.$items
            .map { items in items.count { !$0.isCompleted } }
            .removeDuplicates()
            .sink { [weak self] count in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.openTaskCount = count
                    self.resolveActivity()
                }
            }
            .store(in: &cancellables)

        resolveActivity()
    }

    // MARK: - Pure decision logic (unit-tested)

    /// Collapses all per-source agent counts into the single most important
    /// piece of information. Priority: stopped (orange) > done (green) >
    /// working (blue). Sources whose application is not running are ignored.
    nonisolated static func agentHighlight(from summaries: [AgentSourceSummary]) -> LiveActivity? {
        var totals = AgentCounts()
        for summary in summaries where summary.isApplicationRunning {
            totals.working += summary.counts.working
            totals.stopped += summary.counts.stopped
            totals.done += summary.counts.done
        }
        if totals.stopped > 0 { return .agents(state: .stopped, count: totals.stopped) }
        if totals.done > 0 { return .agents(state: .done, count: totals.done) }
        if totals.working > 0 { return .agents(state: .working, count: totals.working) }
        return nil
    }

    /// Picks the activity to display given the current inputs.
    nonisolated static func resolve(
        agentHighlight: LiveActivity?,
        agentTakeoverActive: Bool,
        openTaskCount: Int
    ) -> LiveActivity? {
        if agentTakeoverActive, let agentHighlight {
            return agentHighlight
        }
        if openTaskCount > 0 {
            return .tasks(count: openTaskCount)
        }
        return nil
    }

    // MARK: - Private

    private func beginAgentTakeover() {
        agentTakeoverActive = true
        takeoverExpiryTask?.cancel()
        takeoverExpiryTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Self.agentTakeoverDuration * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            self?.agentTakeoverActive = false
            self?.resolveActivity()
        }
        resolveActivity()
    }

    private func resolveActivity() {
        let resolved = Self.resolve(
            agentHighlight: latestAgentHighlight,
            agentTakeoverActive: agentTakeoverActive,
            openTaskCount: openTaskCount
        )
        if resolved != activity {
            activity = resolved
        }
    }
}
