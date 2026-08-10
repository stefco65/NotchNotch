#!/usr/bin/env swift
import AppKit
import Foundation

guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
      let leftAux = screen.auxiliaryTopLeftArea,
      let rightAux = screen.auxiliaryTopRightArea
else {
    fputs("No physical notch\n", stderr)
    exit(1)
}

let physical = CGRect(
    x: leftAux.maxX,
    y: screen.frame.maxY - screen.safeAreaInsets.top,
    width: rightAux.minX - leftAux.maxX,
    height: screen.safeAreaInsets.top
)
let compactExtra: CGFloat = 100
let shoulder: CGFloat = 7
let sideSlot = compactExtra / 2
let musicLeft = physical.midX - (physical.width + compactExtra) / 2
let musicDIWidth = physical.maxX - musicLeft
let artworkCenterX = shoulder + (sideSlot - shoulder) / 2
let collapsedArt: CGFloat = 24
let previewArt: CGFloat = 30

func path(
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
    let p = CGMutablePath()
    p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    if trail > 0.05 {
        p.addCurve(
            to: CGPoint(x: rightEdge, y: rect.maxY - trail),
            control1: CGPoint(x: rect.maxX - trail * 0.25, y: rect.maxY),
            control2: CGPoint(x: rightEdge, y: rect.maxY - trail * 0.5)
        )
    }
    p.addLine(to: CGPoint(x: rightEdge, y: rect.minY + r))
    p.addQuadCurve(to: CGPoint(x: rightEdge - r, y: rect.minY), control: CGPoint(x: rightEdge, y: rect.minY))
    p.addLine(to: CGPoint(x: leftEdge + r, y: rect.minY))
    p.addQuadCurve(to: CGPoint(x: leftEdge, y: rect.minY + r), control: CGPoint(x: leftEdge, y: rect.minY))
    p.addLine(to: CGPoint(x: leftEdge, y: rect.maxY - lead))
    if lead > 0.05 {
        p.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY),
            control1: CGPoint(x: leftEdge, y: rect.maxY - lead * 0.5),
            control2: CGPoint(x: rect.minX + lead * 0.25, y: rect.maxY)
        )
    } else {
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    }
    p.closeSubpath()
    return p
}

func frame(heightExtra: CGFloat) -> CGRect {
    let h = physical.height + heightExtra
    return CGRect(x: musicLeft, y: screen.frame.maxY - h, width: musicDIWidth, height: h)
}

let shots: [(String, CGRect, CGFloat, CGFloat, Bool)] = [
    ("collapsed", frame(heightExtra: 0), 8, collapsedArt, false),
    ("hovered", frame(heightExtra: 20), 13, collapsedArt, false),
    ("musicPreview", frame(heightExtra: 44), 22, previewArt, true)
]

let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("tmp-notch-qa", isDirectory: true)
try? FileManager.default.removeItem(at: outDir)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let crop = CGRect(x: physical.midX - 240, y: screen.frame.maxY - 130, width: 480, height: 130)

for (name, rect, bottom, artSize, showText) in shots {
    let scale: CGFloat = 3
    let image = NSImage(size: CGSize(width: crop.width * scale, height: crop.height * scale))
    image.lockFocus()
    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -crop.minX, y: -crop.minY)
        ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
        ctx.fill(crop)

        // Notch body — music stable leading shoulder, flat trailing
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(path(in: rect, bottom: bottom, leading: shoulder, trailing: 0))
        ctx.fillPath()

        // Physical guide
        ctx.setStrokeColor(NSColor.systemPink.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [3, 2])
        ctx.stroke(physical)

        // Left slot guides: visible wall + physical left + center
        let visibleLeft = rect.minX + shoulder
        ctx.setStrokeColor(NSColor.systemYellow.cgColor)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: visibleLeft, y: crop.minY))
        ctx.addLine(to: CGPoint(x: visibleLeft, y: crop.maxY))
        ctx.strokePath()
        ctx.setStrokeColor(NSColor.systemGreen.cgColor)
        ctx.move(to: CGPoint(x: physical.minX, y: crop.minY))
        ctx.addLine(to: CGPoint(x: physical.minX, y: crop.maxY))
        ctx.strokePath()
        ctx.setStrokeColor(NSColor.cyan.cgColor)
        let artX = rect.minX + artworkCenterX
        ctx.move(to: CGPoint(x: artX, y: crop.minY))
        ctx.addLine(to: CGPoint(x: artX, y: crop.maxY))
        ctx.strokePath()

        // Artwork
        let art = CGRect(
            x: artX - artSize / 2,
            y: rect.maxY - 3 - artSize,
            width: artSize,
            height: artSize
        )
        ctx.setFillColor(NSColor.darkGray.cgColor)
        ctx.addPath(CGPath(roundedRect: art, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.fillPath()

        // DI pill fixed on physical
        let di = CGRect(
            x: physical.maxX + 2,
            y: physical.midY - 14,
            width: 36,
            height: 28
        )
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(CGPath(roundedRect: di, cornerWidth: 14, cornerHeight: 14, transform: nil))
        ctx.fillPath()

        if showText {
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.7).cgColor)
            let textY = art.minY - 20
            ctx.fill(CGRect(x: physical.minX + 8, y: textY, width: 160, height: 12))
        }

        let midSlot = (visibleLeft + physical.minX) / 2
        print("\(name): artCenter=\(artX) slotMid=\(midSlot) delta=\(artX - midSlot) width=\(rect.width) diX=\(di.minX)")
    }
    image.unlockFocus()
    let url = outDir.appendingPathComponent("music-di-\(name).png")
    if let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try png.write(to: url)
        print("wrote \(url.path)")
    }
}
