import SwiftUI

struct MusicComponentView: View {
    @ObservedObject var store: SpotifyMusicStore

    var body: some View {
        HStack(spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 3) {
                Text(store.track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .contentTransition(.opacity)

                Text(store.track.album)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .contentTransition(.opacity)

                Text(store.track.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                    .contentTransition(.opacity)

                HStack(spacing: 4) {
                    controlButton("backward.fill", command: .previous)
                    controlButton(
                        store.track.isPlaying ? "pause.fill" : "play.fill",
                        command: .playPause,
                        prominent: true
                    )
                    controlButton("forward.fill", command: .next)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.22), value: store.track.title)
        .task {
            while !Task.isCancelled {
                store.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let artworkData = store.track.artworkData,
                   let artworkImage = NSImage(data: artworkData) {
                    Image(nsImage: artworkImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholderArtwork
                }
            }
            .artworkStyle()

            SpotifyBadge()
                .frame(width: 22, height: 22)
                .background(.black, in: Circle())
                .overlay {
                    Circle().stroke(.black, lineWidth: 2)
                }
                .offset(x: 3, y: 3)
        }
    }

    private var placeholderArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.77, green: 0.18, blue: 0.48), .purple, .indigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
        }
    }

    private func controlButton(
        _ systemName: String,
        command: SpotifyMusicStore.Command,
        prominent: Bool = false
    ) -> some View {
        Button {
            store.perform(command)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: prominent ? 16 : 13, weight: .semibold))
                .foregroundStyle(.white.opacity(prominent ? 0.94 : 0.72))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(prominent ? .white.opacity(0.12) : .clear, in: Circle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(accessibilityLabel(for: command))
    }

    private func accessibilityLabel(for command: SpotifyMusicStore.Command) -> String {
        switch command {
        case .previous: "Poprzedni utwór"
        case .playPause: store.track.isPlaying ? "Wstrzymaj" : "Odtwórz"
        case .next: "Następny utwór"
        }
    }
}

private extension View {
    func artworkStyle() -> some View {
        frame(width: 82, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
    }
}

private struct SpotifyBadge: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.12, green: 0.84, blue: 0.38))
            Image(systemName: "wave.3.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.black.opacity(0.8))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityLabel("Spotify")
    }
}
