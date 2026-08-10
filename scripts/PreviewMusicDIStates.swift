#!/usr/bin/env swift
import AppKit
import Foundation

guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
      let leftAux = screen.auxiliaryTopLeftArea,
      let rightAux = screen.auxiliaryTopRightArea
else {
    fputs("No physical notch screen\n", stderr)
    exit(1)
}

let physical = CGRect(
    x: leftAux.maxX,
    y: screen.frame.maxY - screen.safeAreaInsets.top,
    width: rightAux.minX - leftAux.maxX,
    height: screen.safeAreaInsets.top
)
let musicExtra: CGFloat = 100
let musicLeft = physical.midX - (physical.width + musicExtra) / 2

func musicDI(heightExtra: CGFloat) -> CGRect {
    let height = physical.height + heightExtra
    return CGRect(
        x: musicLeft,
        y: screen.frame.maxY - height,
        width: physical.maxX - musicLeft,
        height: height
    )
}

func notchPath(
    in rect: CGRect,
    bottom: CGFloat,
    leading: CGFloat,
    trailing: CGFloat
) -> CGPath {
    let lead = min(leading, rect.width / 4, rect.height / 2)
    let trail = min(trailing, rect.width / 4, rect.height / 2)
    let leftEdge = rect.minX + lead
    let rightEdge = rect.maxX - trail
    let r = min(bottom, (rightEdge - leftEdge) / 2, max(rect.height - max(lead, trail), 0))
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    if trail > 0.05 {
        path.addCurve(
            to: CGPoint(x: rightEdge, y: rect.maxY - trail),
            control1: CGPoint(x: rect.maxX - trail * 0.25, y: rect.maxY),
            control2: CGPoint(x: rightEdge, y: rect.maxY - trail * 0.5)
        )
    }
    path.addLine(to: CGPoint(x: rightEdge, y: rect.minY + r))
    path.addQuadCurve(
        to: CGPoint(x: rightEdge - r, y: rect.minY),
        control: CGPoint(x: rightEdge, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: leftEdge + r, y: rect.minY))
    path.addQuadCurve(
        to: CGPoint(x: leftEdge, y: rect.minY + r),
        control: CGPoint(x: leftEdge, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: leftEdge, y: rect.maxY - lead))
    if lead > 0.05 {
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY),
            control1: CGPoint(x: leftEdge, y: rect.maxY - lead * 0.5),
            control2: CGPoint(x: rect.minX + lead * 0.25, y: rect.maxY)
        )
    } else {
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    }
    path.closeSubpath()
    return path
}

let shots: [(String, CGRect, CGFloat, CGFloat)] = [
    ("collapsed", musicDI(heightExtra: 0), 8, 7),
    ("hovered", musicDI(heightExtra: 20), 13, 11),
    ("musicPreview", musicDI(heightExtra: 64), 22, 16)
]

let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("tmp-notch-qa", isDirectory: true)
try? FileManager.default.removeItem(at: outDir)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let crop = CGRect(
    x: physical.midX - 220,
    y: screen.frame.maxY - 120,
    width: 440,
    height: 120
)

for (name, frame, bottom, leading) in shots {
    let scale: CGFloat = 3
    let size = CGSize(width: crop.width * scale, height: crop.height * scale)
    let image = NSImage(size: size)
    image.lockFocus()
    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -crop.minX, y: -crop.minY)
        ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
        ctx.fill(crop)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.08).cgColor)
        ctx.fill(CGRect(x: crop.minX, y: screen.frame.maxY - 38, width: crop.width, height: 38))
        ctx.setFillColor(NSColor.black.cgColor)
        // Music+DI: trailing shoulder flattened to 0.
        ctx.addPath(notchPath(in: frame, bottom: bottom, leading: leading, trailing: 0))
        ctx.fillPath()
        ctx.setStrokeColor(NSColor.systemPink.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [3, 2])
        ctx.stroke(physical)
        ctx.setStrokeColor(NSColor.systemGreen.cgColor)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setLineWidth(1.5)
        ctx.move(to: CGPoint(x: physical.maxX, y: crop.minY))
        ctx.addLine(to: CGPoint(x: physical.maxX, y: crop.maxY))
        ctx.strokePath()
        let pill = CGRect(
            x: physical.maxX + 2,
            y: frame.maxY - (frame.height + 28) / 2,
            width: 36,
            height: 28
        )
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 14, cornerHeight: 14, transform: nil))
        ctx.fillPath()
    }
    image.unlockFocus()
    let url = outDir.appendingPathComponent("music-di-\(name).png")
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: url)
    print("wrote \(url.path) maxX=\(frame.maxX) physical.maxX=\(physical.maxX) delta=\(frame.maxX - physical.maxX)")
}
print("physical=\(physical)")
