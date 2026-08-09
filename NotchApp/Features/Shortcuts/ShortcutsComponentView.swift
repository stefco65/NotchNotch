import SwiftUI

struct ShortcutsComponentView: View {
    let buttons: [ShortcutButtonConfiguration]
    @StateObject private var runner = ShortcutRunner()

    var body: some View {
        Group {
            if buttons.isEmpty {
                emptyState
            } else {
                GeometryReader { geometry in
                    let totalWeight = max(buttons.reduce(0) { $0 + $1.widthWeight }, 0.6)
                    let spacing: CGFloat = 6
                    let availableHeight = max(
                        geometry.size.height - spacing * CGFloat(max(buttons.count - 1, 0)),
                        1
                    )

                    VStack(spacing: spacing) {
                        ForEach(buttons) { button in
                            shortcutButton(button)
                                .frame(
                                    height: availableHeight * CGFloat(button.widthWeight / totalWeight)
                                )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let lastError = runner.lastError {
                Text(lastError)
                    .font(.system(size: 8))
                    .foregroundStyle(.red.opacity(0.85))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            Text("Dodaj przyciski Skrótów w ustawieniach")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .multilineTextAlignment(.center)
        }
    }

    private func shortcutButton(_ button: ShortcutButtonConfiguration) -> some View {
        let appearance = ShortcutAppearance.style(for: button.shortcutName)

        return Button {
            runner.run(button)
        } label: {
            HStack(spacing: 9) {
                ShortcutGlyph(kind: appearance.glyph)
                    .frame(width: 23, height: 23)

                Text(button.shortcutName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 2)

                if runner.runningButtonID == button.id {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.88))
                        .frame(width: 18, height: 18)
                        .background(.black.opacity(0.14), in: Circle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: appearance.colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.16), lineWidth: 0.8)
            }
            .shadow(color: appearance.colors.last?.opacity(0.18) ?? .clear, radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(runner.runningButtonID != nil)
        .accessibilityLabel("Uruchom skrót \(button.shortcutName)")
    }
}

private struct ShortcutAppearance {
    enum Glyph {
        case terminal
        case apps
        case calendar
        case generic
    }

    let glyph: Glyph
    let colors: [Color]

    static func style(for shortcutName: String) -> ShortcutAppearance {
        switch shortcutName.lowercased() {
        case "haos":
            ShortcutAppearance(
                glyph: .terminal,
                colors: [
                    Color(red: 0.13, green: 0.85, blue: 0.36),
                    Color(red: 0.34, green: 0.87, blue: 0.48)
                ]
            )
        case "apps":
            ShortcutAppearance(
                glyph: .apps,
                colors: [
                    Color(red: 0.91, green: 0.34, blue: 0.74),
                    Color(red: 0.96, green: 0.52, blue: 0.81)
                ]
            )
        case "odliczanie dni":
            ShortcutAppearance(
                glyph: .calendar,
                colors: [
                    Color(red: 1, green: 0.57, blue: 0.16),
                    Color(red: 1, green: 0.72, blue: 0.34)
                ]
            )
        default:
            ShortcutAppearance(
                glyph: .generic,
                colors: [
                    Color(red: 0.43, green: 0.31, blue: 0.88),
                    Color(red: 0.68, green: 0.38, blue: 0.92)
                ]
            )
        }
    }
}

private struct ShortcutGlyph: View {
    let kind: ShortcutAppearance.Glyph

    var body: some View {
        Group {
            switch kind {
            case .terminal:
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.black.opacity(0.78))
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.right")
                        Rectangle()
                            .frame(width: 5, height: 1)
                    }
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                }
            case .apps:
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.white.opacity(0.96))
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(3), spacing: 2), count: 3),
                        spacing: 2
                    ) {
                        ForEach(0..<9, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 0.8)
                                .fill(appTileColor(at: index))
                                .frame(width: 3, height: 3)
                        }
                    }
                }
            case .calendar:
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.white.opacity(0.96))
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(red: 1, green: 0.58, blue: 0.18))
                }
            case .generic:
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.white.opacity(0.18))
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func appTileColor(at index: Int) -> Color {
        let colors: [Color] = [
            .red, .orange, .yellow,
            .green, .cyan, .blue,
            .purple, .pink, .mint
        ]
        return colors[index]
    }
}
