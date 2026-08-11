import AppKit
import SwiftUI

struct AgentMonitorComponentView: View {
    @ObservedObject var store: AgentMonitorStore

    var body: some View {
        VStack(spacing: 4) {
            ForEach(store.summaries) { summary in
                AgentSourceRow(summary: summary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
        // Epoch forces PassiveHostingView to drop a stale layer tree that otherwise
        // only recomposites on the next hover/layout pass.
        .id(store.renderEpoch)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: store.renderEpoch)
        .onAppear { store.startMonitoring() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Otwarci agenci AI")
    }
}

private struct AgentSourceRow: View {
    let summary: AgentSourceSummary

    private static let iconCache: [AgentSource: NSImage] = Dictionary(
        uniqueKeysWithValues: AgentSource.allCases.map {
            ($0, NSWorkspace.shared.icon(forFile: $0.applicationPath))
        }
    )

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: Self.iconCache[summary.source] ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .opacity(summary.isApplicationRunning ? 1 : 0.42)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: summary.isApplicationRunning)

            Text(summary.source.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(summary.isApplicationRunning ? 0.9 : 0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .animation(.easeInOut(duration: 0.2), value: summary.isApplicationRunning)

            Spacer(minLength: 2)

            AgentCountersView(
                snapshot: CounterSnapshot(
                    working: summary.counts.working,
                    waiting: summary.counts.stopped,
                    completed: summary.counts.done
                ),
                isActive: summary.isApplicationRunning
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: summary.counts)
        }
        .frame(height: 29)
        // Force SwiftUI to diff when counts change even if the row identity is stable
        // (hosting views inside the notch sometimes skip redraws until hover).
        .id(
            "\(summary.source.rawValue)-\(summary.counts.working)-\(summary.counts.stopped)-\(summary.counts.done)-\(summary.isApplicationRunning)"
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(summary.source.title): \(summary.counts.working) pracujących, "
            + "\(summary.counts.stopped) zatrzymanych, \(summary.counts.done) gotowych"
        )
    }
}
