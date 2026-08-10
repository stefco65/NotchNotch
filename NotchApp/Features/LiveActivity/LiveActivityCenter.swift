import Combine
import Foundation

/// One piece of "live" information the dynamic-island bubble can display.
enum LiveActivity: Equatable, Sendable {
    /// Aggregated agent state across all sources. Bucket priority inside the
    /// agents component: working (blue) > stopped (orange) > done (green).
    case agents(state: AgentActivityState, count: Int)
    /// Number of open tasks on the task list.
    case tasks(count: Int)
}

/// Who currently owns the Dynamic Island turn. Only a real component state
/// update (or music starting) may change the owner — there is no timeout.
enum LiveActivityDisplayOwner: Equatable, Sendable {
    case agents
    case tasks
    /// Music claimed the notch; the DI bubble stays hidden.
    case music
    case none
}

/// Decides what the dynamic-island bubble next to the notch should show.
///
/// Rules (last update wins):
///  - An agents status change claims the island and keeps it until something
///    else updates (agents have priority on cold start).
///  - A tasks count change claims the island with the open-task count.
///  - Music starting claims the turn and **hides** the DI so the compact
///    music surface can take over; a later agents/tasks update can reclaim.
///  - No timers — content stays until the next claiming update.
@MainActor
final class LiveActivityCenter: ObservableObject {
    @Published private(set) var activity: LiveActivity?

    private var owner: LiveActivityDisplayOwner = .none
    private var latestAgentHighlight: LiveActivity?
    private var openTaskCount = 0
    private var cancellables = Set<AnyCancellable>()

    init(
        agentMonitorStore: AgentMonitorStore,
        taskStore: TaskStore,
        spotifyMusicStore: SpotifyMusicStore
    ) {
        latestAgentHighlight = Self.agentHighlight(from: agentMonitorStore.summaries)
        openTaskCount = taskStore.items.count { !$0.isCompleted }
        owner = Self.initialOwner(
            agentHighlight: latestAgentHighlight,
            openTaskCount: openTaskCount,
            isMusicPlaying: spotifyMusicStore.hasActiveTrack
        )
        publish()

        agentMonitorStore.$summaries
            .map(Self.agentHighlight(from:))
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] highlight in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.latestAgentHighlight = highlight
                    // Any agents status change claims the island (including
                    // clearing it when the highlight becomes nil).
                    self.owner = .agents
                    self.publish()
                }
            }
            .store(in: &cancellables)

        taskStore.$items
            .map { items in items.count { !$0.isCompleted } }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] count in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.openTaskCount = count
                    self.owner = .tasks
                    self.publish()
                }
            }
            .store(in: &cancellables)

        spotifyMusicStore.$hasActiveTrack
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isPlaying in
                MainActor.assumeIsolated {
                    guard let self, isPlaying else { return }
                    // Music starting takes the turn and hides the DI. Stopping
                    // does not auto-restore — the next agents/tasks update will.
                    self.owner = .music
                    self.publish()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Pure decision logic (unit-tested)

    /// Collapses all per-source agent counts into the single most important
    /// bucket for the Agents component / DI: working > stopped > done.
    nonisolated static func agentHighlight(from summaries: [AgentSourceSummary]) -> LiveActivity? {
        var totals = AgentCounts()
        for summary in summaries where summary.isApplicationRunning {
            totals.working += summary.counts.working
            totals.stopped += summary.counts.stopped
            totals.done += summary.counts.done
        }
        if totals.working > 0 { return .agents(state: .working, count: totals.working) }
        if totals.stopped > 0 { return .agents(state: .stopped, count: totals.stopped) }
        if totals.done > 0 { return .agents(state: .done, count: totals.done) }
        return nil
    }

    /// Cold-start owner. Agents win over tasks; music only claims when neither
    /// agents nor tasks have anything to show.
    nonisolated static func initialOwner(
        agentHighlight: LiveActivity?,
        openTaskCount: Int,
        isMusicPlaying: Bool
    ) -> LiveActivityDisplayOwner {
        if agentHighlight != nil { return .agents }
        if openTaskCount > 0 { return .tasks }
        if isMusicPlaying { return .music }
        return .none
    }

    /// Maps the current owner + latest component snapshots onto DI content.
    nonisolated static func resolve(
        owner: LiveActivityDisplayOwner,
        agentHighlight: LiveActivity?,
        openTaskCount: Int
    ) -> LiveActivity? {
        switch owner {
        case .agents:
            return agentHighlight
        case .tasks:
            return openTaskCount > 0 ? .tasks(count: openTaskCount) : nil
        case .music, .none:
            return nil
        }
    }

    // MARK: - Private

    private func publish() {
        let resolved = Self.resolve(
            owner: owner,
            agentHighlight: latestAgentHighlight,
            openTaskCount: openTaskCount
        )
        if resolved != activity {
            activity = resolved
        }
    }
}
