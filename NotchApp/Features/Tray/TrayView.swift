import AppKit
import SwiftUI

struct TrayView: View {
    @ObservedObject var store: TrayStore
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if store.items.isEmpty {
                emptyDropArea
            } else {
                populatedTray
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            store.ingest(urls)
            return !urls.isEmpty
        } isTargeted: { isTargeted in
            withAnimation(.easeOut(duration: 0.14)) {
                isDropTargeted = isTargeted
            }
        }
    }

    private var emptyDropArea: some View {
        VStack(spacing: 7) {
            Image(systemName: store.isIngesting ? "arrow.triangle.2.circlepath" : "arrow.down.doc.fill")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(isDropTargeted ? .white : .purple)
                .symbolEffect(.pulse, isActive: store.isIngesting)

            Text(store.isIngesting ? "Dodawanie plików…" : "Upuść pliki w Tray")
                .font(.system(size: 13, weight: .semibold))

            Text("Zostaną skopiowane i będą dostępne po ponownym uruchomieniu.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDropTargeted ? Color.purple.opacity(0.22) : .white.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDropTargeted ? Color.purple.opacity(0.9) : .white.opacity(0.16),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                )
        }
    }

    private var populatedTray: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(store.items.count) w Tray", systemImage: "tray.full.fill")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(isDropTargeted ? "Upuść, aby dodać" : "Możesz upuścić kolejne pliki")
                    .font(.system(size: 10))
                    .foregroundStyle(isDropTargeted ? .purple : .white.opacity(0.45))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.items) { item in
                        trayItemCard(item)
                    }
                }
            }

            if let error = store.lastError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.9))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDropTargeted ? Color.purple.opacity(0.16) : .white.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isDropTargeted ? Color.purple.opacity(0.8) : .white.opacity(0.08))
        }
    }

    private func trayItemCard(_ item: TrayItem) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.storedURL.path))
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(item.isDirectory ? "Folder" : formattedSize(item.fileSize))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.42))
            }

            Button {
                store.remove(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.42))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Usuń \(item.displayName) z Tray")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 170)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func formattedSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "Plik" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
