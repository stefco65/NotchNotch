import AppKit
import CoreGraphics

struct NotchGeometryResolver {
    private let virtualWidth: CGFloat
    private let virtualHeight: CGFloat

    init(virtualWidth: CGFloat = 180, virtualHeight: CGFloat = 12) {
        self.virtualWidth = virtualWidth
        self.virtualHeight = virtualHeight
    }

    @MainActor
    func resolve(screen: NSScreen) -> DisplayDescriptor {
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let displayID = screenNumber?.uint32Value ?? 0
        let anchor: DisplayAnchor

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            let rect = CGRect(
                x: left.maxX,
                y: screen.frame.maxY - screen.safeAreaInsets.top,
                width: right.minX - left.maxX,
                height: screen.safeAreaInsets.top
            )
            anchor = .physicalNotch(
                PhysicalNotchGeometry(
                    rect: rect,
                    topInset: screen.safeAreaInsets.top,
                    leftAuxiliaryArea: left,
                    rightAuxiliaryArea: right
                )
            )
        } else {
            let rect = CGRect(
                x: screen.frame.midX - virtualWidth / 2,
                y: screen.frame.maxY - virtualHeight,
                width: virtualWidth,
                height: virtualHeight
            )
            anchor = .virtualHandler(VirtualHandlerGeometry(rect: rect))
        }

        return DisplayDescriptor(
            id: displayID,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: screen.safeAreaInsets,
            scaleFactor: screen.backingScaleFactor,
            anchor: anchor
        )
    }
}
