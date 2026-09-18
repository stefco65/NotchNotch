import AppKit
import QuickLookThumbnailing
import SwiftUI

struct PhotosView: View {
    @ObservedObject var store: ScreenshotStore

    var body: some View {
        HStack(spacing: 8) {
            folderTile

            if store.items.isEmpty {
                emptyState
            } else {
                // A horizontal ScrollView does not bound its content's height,
                // so size the cards from the space the tab actually has.
                GeometryReader { geometry in
                    let thumbnailHeight = max(geometry.size.height - ScreenshotCard.captionHeight, 40)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(store.items) { item in
                                ScreenshotCard(
                                    item: item,
                                    thumbnailSize: CGSize(width: (thumbnailHeight * 1.6).rounded(), height: thumbnailHeight)
                                )
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { store.startMonitoring() }
        .onDisappear { store.stopMonitoring() }
    }

    private var folderTile: some View {
        Button {
            NSWorkspace.shared.open(store.folder)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.purple)
                Text(store.folder.lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Otwórz folder")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 8)
            .frame(width: 96)
            .frame(maxHeight: .infinity)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(store.folder.path)
        .accessibilityLabel("Otwórz folder zrzutów ekranu \(store.folder.lastPathComponent)")
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.purple)
            Text("Brak zrzutów ekranu")
                .font(.system(size: 13, weight: .semibold))
            Text("Zrób zrzut skrótem ⇧⌘3, ⇧⌘4 lub ⇧⌘5 — pojawi się tutaj.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
        }
    }
}

private struct ScreenshotCard: View {
    /// Date line plus its spacing below the thumbnail.
    static let captionHeight: CGFloat = 16

    let item: ScreenshotItem
    let thumbnailSize: CGSize
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.06))
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.1))
            }
            // Same AppKit drag source as Tray: the nonactivating panel cannot
            // start file drags from SwiftUI modifiers.
            .overlay {
                TrayItemDragHandle(url: item.url) {
                    NSWorkspace.shared.open(item.url)
                }
            }

            Text(item.createdAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .frame(height: Self.captionHeight - 4)
        }
        .contextMenu {
            Button("Otwórz") {
                NSWorkspace.shared.open(item.url)
            }
            Button("Kopiuj obraz") {
                guard let image = NSImage(contentsOf: item.url) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            }
            Button("Pokaż w Finderze") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
        .task(id: item) {
            thumbnail = await ScreenshotThumbnails.image(for: item, size: thumbnailSize)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zrzut ekranu \(item.url.deletingPathExtension().lastPathComponent)")
        .accessibilityHint("Kliknij, aby otworzyć. Przeciągnij, aby skopiować do innej aplikacji.")
    }
}

@MainActor
private enum ScreenshotThumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for item: ScreenshotItem, size: CGSize) async -> NSImage? {
        let key = "\(item.url.path)|\(item.createdAt.timeIntervalSince1970)|\(Int(size.width))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        // Fill-cropped into a landscape frame, so request enough pixels for both edges.
        let side = max(size.width, size.height)
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: side, height: side),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        guard let cgImage = await withCheckedContinuation({ (continuation: CheckedContinuation<CGImage?, Never>) in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.cgImage)
            }
        }) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: .zero)
        cache.setObject(image, forKey: key)
        return image
    }
}
