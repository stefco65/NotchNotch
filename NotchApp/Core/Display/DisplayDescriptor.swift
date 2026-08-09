import AppKit
import CoreGraphics

struct DisplayDescriptor: Identifiable, Equatable, Sendable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let visibleFrame: CGRect
    let safeAreaInsets: NSEdgeInsets
    let scaleFactor: CGFloat
    let anchor: DisplayAnchor

    static func == (lhs: DisplayDescriptor, rhs: DisplayDescriptor) -> Bool {
        lhs.id == rhs.id
            && lhs.frame == rhs.frame
            && lhs.visibleFrame == rhs.visibleFrame
            && lhs.safeAreaInsets.top == rhs.safeAreaInsets.top
            && lhs.safeAreaInsets.left == rhs.safeAreaInsets.left
            && lhs.safeAreaInsets.bottom == rhs.safeAreaInsets.bottom
            && lhs.safeAreaInsets.right == rhs.safeAreaInsets.right
            && lhs.scaleFactor == rhs.scaleFactor
            && lhs.anchor == rhs.anchor
    }

    var diagnostics: String {
        """
        display.id=\(id)
        display.frame=\(frame)
        display.visibleFrame=\(visibleFrame)
        display.scaleFactor=\(scaleFactor)
        display.safeAreaInsets=top:\(safeAreaInsets.top),left:\(safeAreaInsets.left),bottom:\(safeAreaInsets.bottom),right:\(safeAreaInsets.right)
        display.anchor=\(anchor.logDescription)
        """
    }
}

enum DisplayAnchor: Equatable, Sendable {
    case physicalNotch(PhysicalNotchGeometry)
    case virtualHandler(VirtualHandlerGeometry)

    var rect: CGRect {
        switch self {
        case .physicalNotch(let geometry): geometry.rect
        case .virtualHandler(let geometry): geometry.rect
        }
    }

    var menuDescription: String {
        switch self {
        case .physicalNotch: "Physical notch detected"
        case .virtualHandler: "Virtual handler"
        }
    }

    var logDescription: String {
        switch self {
        case .physicalNotch(let geometry):
            "physicalNotch(rect: \(geometry.rect), topInset: \(geometry.topInset))"
        case .virtualHandler(let geometry):
            "virtualHandler(rect: \(geometry.rect))"
        }
    }
}

struct PhysicalNotchGeometry: Equatable, Sendable {
    let rect: CGRect
    let topInset: CGFloat
    let leftAuxiliaryArea: CGRect
    let rightAuxiliaryArea: CGRect
}

struct VirtualHandlerGeometry: Equatable, Sendable {
    let rect: CGRect
}
