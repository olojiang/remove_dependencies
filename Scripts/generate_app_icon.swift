#!/usr/bin/env swift

import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/DevCleaner.icns")
let fileManager = FileManager.default
let workRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("DevCleanerIcon-\(UUID().uuidString)", isDirectory: true)
let iconsetURL = workRoot.appendingPathComponent("DevCleaner.iconset", isDirectory: true)

try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func c(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ scale: CGFloat) -> NSRect {
    NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
}

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat, _ scale: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect(x, y, width, height, scale), xRadius: radius * scale, yRadius: radius * scale)
}

func drawLine(from start: CGPoint, to end: CGPoint, width: CGFloat, color: NSColor, scale: CGFloat) {
    let path = NSBezierPath()
    path.move(to: CGPoint(x: start.x * scale, y: start.y * scale))
    path.line(to: CGPoint(x: end.x * scale, y: end.y * scale))
    path.lineWidth = width * scale
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()
}

func drawIcon(size: Int, to url: URL) throws {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    guard let context = NSGraphicsContext.current?.cgContext else {
        throw NSError(domain: "DevCleanerIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create drawing context"])
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let scale = CGFloat(size) / 1024
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let background = roundedRect(64, 64, 896, 896, 210, scale)
    let gradient = NSGradient(colors: [c(21, 95, 139), c(22, 155, 143), c(76, 188, 154)])!
    gradient.draw(in: background, angle: 315)

    c(255, 255, 255, 0.16).setStroke()
    background.lineWidth = 18 * scale
    background.stroke()

    c(4, 38, 62, 0.28).setFill()
    roundedRect(160, 636, 558, 110, 38, scale).fill()
    roundedRect(160, 286, 704, 404, 62, scale).fill()

    let tab = roundedRect(154, 662, 278, 132, 44, scale)
    c(248, 211, 102).setFill()
    tab.fill()

    let folder = roundedRect(132, 304, 760, 426, 70, scale)
    let folderGradient = NSGradient(colors: [c(255, 222, 114), c(249, 183, 72)])!
    folderGradient.draw(in: folder, angle: 270)

    c(150, 93, 22, 0.22).setStroke()
    folder.lineWidth = 12 * scale
    folder.stroke()

    c(255, 248, 216, 0.55).setFill()
    roundedRect(184, 620, 574, 38, 19, scale).fill()

    let blockColors = [c(19, 111, 153), c(34, 145, 136), c(244, 248, 247)]
    let blocks: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (248, 438, 126, 126),
        (430, 438, 126, 126),
        (612, 438, 126, 126),
        (340, 340, 126, 126),
        (522, 340, 126, 126),
    ]

    for (index, block) in blocks.enumerated() {
        c(104, 77, 18, 0.18).setFill()
        roundedRect(block.0 + 8, block.1 - 10, block.2, block.3, 30, scale).fill()

        blockColors[index % blockColors.count].setFill()
        roundedRect(block.0, block.1, block.2, block.3, 30, scale).fill()

        c(255, 255, 255, index % blockColors.count == 2 ? 0.7 : 0.28).setStroke()
        let box = roundedRect(block.0, block.1, block.2, block.3, 30, scale)
        box.lineWidth = 8 * scale
        box.stroke()
    }

    drawLine(from: CGPoint(x: 628, y: 244), to: CGPoint(x: 812, y: 642), width: 34, color: c(121, 73, 25), scale: scale)
    drawLine(from: CGPoint(x: 642, y: 252), to: CGPoint(x: 824, y: 646), width: 14, color: c(245, 196, 89), scale: scale)

    let bristleBase = NSBezierPath()
    bristleBase.move(to: CGPoint(x: 542 * scale, y: 216 * scale))
    bristleBase.line(to: CGPoint(x: 704 * scale, y: 160 * scale))
    bristleBase.line(to: CGPoint(x: 758 * scale, y: 292 * scale))
    bristleBase.line(to: CGPoint(x: 600 * scale, y: 348 * scale))
    bristleBase.close()
    c(43, 72, 87).setFill()
    bristleBase.fill()

    c(219, 240, 235).setStroke()
    for offset in stride(from: 0, through: 120, by: 30) {
        drawLine(
            from: CGPoint(x: 574 + CGFloat(offset), y: 232 - CGFloat(offset) * 0.34),
            to: CGPoint(x: 612 + CGFloat(offset), y: 320 - CGFloat(offset) * 0.34),
            width: 9,
            color: c(219, 240, 235, 0.72),
            scale: scale
        )
    }

    c(235, 247, 245, 0.9).setFill()
    roundedRect(232, 244, 54, 54, 16, scale).fill()
    roundedRect(306, 206, 38, 38, 12, scale).fill()
    roundedRect(398, 230, 30, 30, 10, scale).fill()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DevCleanerIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG"])
    }

    try png.write(to: url)
}

for variant in variants {
    try drawIcon(size: variant.pixels, to: iconsetURL.appendingPathComponent(variant.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw NSError(domain: "DevCleanerIcon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}

try? fileManager.removeItem(at: workRoot)
print("Generated \(outputURL.path)")
