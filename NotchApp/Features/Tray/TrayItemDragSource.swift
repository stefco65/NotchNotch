import AppKit
import SwiftUI

/// AppKit drag source — SwiftUI `.draggable` / `.onDrag` do not reliably start
/// file drags from a `nonactivatingPanel` notch overlay.
struct TrayItemDragHandle: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> TrayDragSourceView {
        let view = TrayDragSourceView()
        view.url = url
        view.wantsLayer = true
        // Tiny alpha so AppKit hit-testing treats the view as opaque enough
        // while remaining invisible in the UI.
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.001).cgColor
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: TrayDragSourceView, context: Context) {
        nsView.url = url
    }
}

final class TrayDragSourceView: NSView, NSDraggingSource {
    var url: URL?

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard url != nil, !isHidden, alphaValue > 0.01 else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }

        // Run a nested tracking loop so SwiftUI's horizontal ScrollView cannot
        // steal mouseDragged before we begin the file-drag session.
        let start = event.locationInWindow
        var didStartDragging = false

        window?.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking,
            handler: { [weak self] trackedEvent, stop in
                guard let self, let trackedEvent else {
                    stop.pointee = true
                    return
                }

                if trackedEvent.type == .leftMouseUp {
                    stop.pointee = true
                    return
                }

                let location = trackedEvent.locationInWindow
                let distance = hypot(location.x - start.x, location.y - start.y)
                guard distance >= 5, !didStartDragging else { return }

                didStartDragging = true
                self.startDragging(url: url, mouseDownEvent: event, currentEvent: trackedEvent)
                stop.pointee = true
            }
        )
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Always advertise copy so Finder / other apps duplicate the tray file
        // instead of trying to move it out of Application Support.
        .copy
    }

    private func startDragging(url: URL, mouseDownEvent: NSEvent, currentEvent: NSEvent) {
        let writer = TrayFilePasteboardWriter(url: url)
        let draggingItem = NSDraggingItem(pasteboardWriter: writer)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 40, height: 40)

        let localPoint = convert(currentEvent.locationInWindow, from: nil)
        draggingItem.setDraggingFrame(
            CGRect(x: localPoint.x - 20, y: localPoint.y - 20, width: 40, height: 40),
            contents: icon
        )

        let session = beginDraggingSession(
            with: [draggingItem],
            event: mouseDownEvent,
            source: self
        )
        session.animatesToStartingPositionsOnCancelOrFail = true
    }
}

/// Explicit file-URL + legacy filenames pasteboard payload for Finder compatibility.
private final class TrayFilePasteboardWriter: NSObject, NSPasteboardWriting {
    private let url: URL
    private let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    init(url: URL) {
        self.url = url
        super.init()
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.fileURL, filenamesType]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL:
            return url.absoluteURL.absoluteString
        case filenamesType:
            return [url.path]
        default:
            return nil
        }
    }
}
