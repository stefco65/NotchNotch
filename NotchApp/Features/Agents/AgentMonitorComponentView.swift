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
        .onAppear { store.startMonitoring() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Otwarci agenci AI")
    }
}

private struct AgentSourceRow: View {
    let summary: AgentSourceSummary

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: summary.source.applicationPath))
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .opacity(summary.isApplicationRunning ? 1 : 0.42)

            Text(summary.source.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(summary.isApplicationRunning ? 0.9 : 0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 2)

            AgentCountField(
                value: summary.counts.working,
                color: Color(red: 0.20, green: 0.57, blue: 1),
                symbol: "bolt.fill",
                label: "Pracujący"
            )
            AgentCountField(
                value: summary.counts.stopped,
                color: Color(red: 1, green: 0.56, blue: 0.18),
                symbol: "pause.fill",
                label: "Zatrzymani"
            )
            AgentCountField(
                value: summary.counts.done,
                color: Color(red: 0.24, green: 0.82, blue: 0.48),
                symbol: "checkmark",
                label: "Gotowi"
            )
        }
        .frame(height: 29)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(summary.source.title): \(summary.counts.working) pracujących, "
            + "\(summary.counts.stopped) zatrzymanych, \(summary.counts.done) gotowych"
        )
    }
}

private struct AgentCountField: View {
    let value: Int
    let color: Color
    let symbol: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .bold))
            Text(value.formatted())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .frame(width: 27, height: 21)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(0.22), lineWidth: 0.8)
        }
        .accessibilityLabel(label)
        .accessibilityValue(value.formatted())
    }
}
