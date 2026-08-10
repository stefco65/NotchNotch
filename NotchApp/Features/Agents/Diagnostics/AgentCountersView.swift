import SwiftUI

struct AgentCountersView: View {
    let snapshot: CounterSnapshot
    var isActive: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            ProviderCounterView(
                value: snapshot.working,
                color: Color(red: 0.20, green: 0.57, blue: 1),
                symbol: "bolt.fill",
                label: "Pracujący",
                isActive: isActive && snapshot.working > 0
            )
            ProviderCounterView(
                value: snapshot.waiting,
                color: Color(red: 1, green: 0.56, blue: 0.18),
                symbol: "pause.fill",
                label: "Oczekujący",
                isActive: isActive && snapshot.waiting > 0
            )
            ProviderCounterView(
                value: snapshot.completed,
                color: Color(red: 0.24, green: 0.82, blue: 0.48),
                symbol: "checkmark",
                label: "Gotowi",
                isActive: isActive && snapshot.completed > 0
            )
        }
    }
}

struct ProviderCounterView: View {
    let value: Int
    let color: Color
    let symbol: String
    let label: String
    let isActive: Bool

    @State private var flashScale: CGFloat = 1

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .bold))
            Text(value.formatted())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.spring(response: 0.28, dampingFraction: 0.75), value: value)
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
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                flashScale = 1.18
            }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55).delay(0.12)) {
                flashScale = 1
            }
        }
    }
}

struct AgentDetailsView: View {
    let snapshot: DebugSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(snapshot.providers, id: \.provider) { info in
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.provider.title)
                        .font(.headline)
                    Text("Running: \(info.isApplicationRunning ? "YES" : "NO")")
                    Text("Agents: \(info.agentCount)")
                    Text("Instance: \(info.instanceID.uuidString)")
                    Text(
                        "Counts: \(info.counters.working)/\(info.counters.waiting)/\(info.counters.completed)"
                    )
                }
                .font(.caption.monospaced())
            }
        }
    }
}
