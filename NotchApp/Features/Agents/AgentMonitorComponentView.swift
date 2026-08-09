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
                // Pulse-in when the app comes online.
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: summary.isApplicationRunning)

            Text(summary.source.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(summary.isApplicationRunning ? 0.9 : 0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .animation(.easeInOut(duration: 0.2), value: summary.isApplicationRunning)

            Spacer(minLength: 2)

            AgentCountField(
                value: summary.counts.working,
                color: Color(red: 0.20, green: 0.57, blue: 1),
                symbol: "bolt.fill",
                label: "Pracujący",
                isActive: summary.isApplicationRunning && summary.counts.working > 0
            )
            AgentCountField(
                value: summary.counts.stopped,
                color: Color(red: 1, green: 0.56, blue: 0.18),
                symbol: "pause.fill",
                label: "Zatrzymani",
                isActive: summary.isApplicationRunning && summary.counts.stopped > 0
            )
            AgentCountField(
                value: summary.counts.done,
                color: Color(red: 0.24, green: 0.82, blue: 0.48),
                symbol: "checkmark",
                label: "Gotowi",
                isActive: summary.isApplicationRunning && summary.counts.done > 0
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
    let isActive: Bool

    // Tracks previous value so we can flash on change.
    @State private var displayValue: Int = 0
    @State private var flashScale: CGFloat = 1

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .bold))
            Text(displayValue.formatted())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: value < displayValue))
                .animation(.spring(response: 0.28, dampingFraction: 0.75), value: displayValue)
        }
        .foregroundStyle(isActive ? color : color.opacity(0.38))
        .frame(width: 27, height: 21)
        .background(
            (isActive ? color.opacity(0.18) : color.opacity(0.07)),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isActive ? color.opacity(0.30) : color.opacity(0.12),
                    lineWidth: 0.8
                )
        }
        .scaleEffect(flashScale)
        .animation(.easeInOut(duration: 0.18), value: isActive)
        .accessibilityLabel(label)
        .accessibilityValue(value.formatted())
        .onChange(of: value) { oldVal, newVal in
            guard oldVal != newVal else { return }
            // Animate the number change with a quick scale flash.
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                flashScale = 1.18
            }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55).delay(0.12)) {
                flashScale = 1
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                displayValue = newVal
            }
        }
        .onAppear {
            displayValue = value
        }
    }
}
