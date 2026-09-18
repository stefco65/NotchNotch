import AppKit
import SwiftUI

struct AgentMonitorComponentView: View {
    @ObservedObject var store: AgentMonitorStore

    var body: some View {
        // Titles are shown for all rows or none, so narrow cards stay aligned
        // instead of truncating some names to "…".
        ViewThatFits(in: .horizontal) {
            rows(showsTitles: true)
            rows(showsTitles: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: store.summaries)
        .onAppear { store.startMonitoring() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Otwarci agenci AI")
    }

    private func rows(showsTitles: Bool) -> some View {
        // Rows share the fixed panel height, so any number of enabled agents fits.
        VStack(spacing: 3) {
            ForEach(store.summaries) { summary in
                AgentSourceRow(summary: summary, showsTitle: showsTitles)
                    .frame(maxHeight: AgentSourceRow.maximumHeight)
                    .transition(.opacity)
            }
        }
    }
}

@MainActor
enum AgentProviderIcon {
    private static let cache: [AgentProvider: NSImage] = Dictionary(
        uniqueKeysWithValues: AgentProvider.allCases.map {
            ($0, NSWorkspace.shared.icon(forFile: $0.applicationPath))
        }
    )

    static func image(for provider: AgentProvider) -> NSImage {
        cache[provider] ?? NSImage()
    }
}

private struct AgentSourceRow: View {
    static let maximumHeight: CGFloat = 29
    private static let iconSize: CGFloat = 20

    let summary: AgentSourceSummary
    let showsTitle: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: AgentProviderIcon.image(for: summary.source))
                .resizable()
                .interpolation(.high)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .opacity(summary.isApplicationRunning ? 1 : 0.42)

            if showsTitle {
                Text(summary.source.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(summary.isApplicationRunning ? 0.9 : 0.42))
                    .lineLimit(1)
                    .fixedSize()
            }

            Spacer(minLength: 0)

            AgentCountersView(
                snapshot: CounterSnapshot(
                    working: summary.counts.working,
                    waiting: summary.counts.stopped,
                    completed: summary.counts.done
                ),
                isActive: summary.isApplicationRunning
            )
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        guard summary.isApplicationRunning else {
            return "\(summary.source.title): nie działa"
        }
        return "\(summary.source.title): \(summary.counts.working) pracujących, "
            + "\(summary.counts.stopped) oczekujących, \(summary.counts.done) gotowych"
    }
}
