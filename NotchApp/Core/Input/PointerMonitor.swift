import AppKit

@MainActor
protocol InputMonitoring: AnyObject {
    func start()
    func stop()
}

@MainActor
final class PointerMonitor: InputMonitoring {
    typealias HitTest = @MainActor (CGPoint) -> Bool
    typealias HoverHandler = @MainActor (Bool, CGPoint) -> Void
    typealias PointerDownHandler = @MainActor (CGPoint) -> Void

    private let hitTest: HitTest
    private let onHoverChanged: HoverHandler
    private let onPointerDown: PointerDownHandler
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isInside = false

    init(
        hitTest: @escaping HitTest,
        onHoverChanged: @escaping HoverHandler,
        onPointerDown: @escaping PointerDownHandler
    ) {
        self.hitTest = hitTest
        self.onHoverChanged = onHoverChanged
        self.onPointerDown = onPointerDown
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }

        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged
        ]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let eventType = event.type
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.handle(eventType: eventType, location: location)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(eventType: event.type, location: NSEvent.mouseLocation)
            }
            return event
        }

        evaluate(location: NSEvent.mouseLocation)
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isInside = false
    }

    private func evaluate(location: CGPoint) {
        let nowInside = hitTest(location)
        let didChange = nowInside != isInside
        isInside = nowInside
        if didChange || nowInside {
            onHoverChanged(nowInside, location)
        }
    }

    private func handle(eventType: NSEvent.EventType, location: CGPoint) {
        switch eventType {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            onPointerDown(location)
        default:
            break
        }
        evaluate(location: location)
    }
}
