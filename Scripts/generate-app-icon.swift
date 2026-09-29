import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let temporaryDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("MoliSwitchIcon-\(UUID().uuidString)", isDirectory: true)
let iconsetURL = temporaryDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)

let iconFiles: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

try FileManager.default.createDirectory(
    at: iconsetURL,
    withIntermediateDirectories: true
)
defer {
    try? FileManager.default.removeItem(at: temporaryDirectory)
}

for file in iconFiles {
    try drawIcon(
        size: file.size,
        to: iconsetURL.appendingPathComponent(file.name)
    )
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c",
    "icns",
    iconsetURL.path,
    "-o",
    outputURL.path
]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw NSError(domain: "MoliSwitchIcon", code: Int(process.terminationStatus))
}

private func drawIcon(size: CGFloat, to url: URL) throws {
    let pixelSize = Int(size)
    guard let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "MoliSwitchIcon", code: 1)
    }

    context.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let scale = size / 1024
    let backgroundRect = CGRect(
        x: 96 * scale,
        y: 96 * scale,
        width: 832 * scale,
        height: 832 * scale
    )
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.addPath(
        CGPath(
            roundedRect: backgroundRect,
            cornerWidth: 220 * scale,
            cornerHeight: 220 * scale,
            transform: nil
        )
    )
    context.fillPath()

    // The mark's coordinates put y down; flip so they read the same here.
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    drawMark(
        in: CGRect(x: 232 * scale, y: 232 * scale, width: 560 * scale, height: 560 * scale),
        lineWidth: 1.6,
        context: context
    )

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
          ) else {
        throw NSError(domain: "MoliSwitchIcon", code: 2)
    }

    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) {
        throw NSError(domain: "MoliSwitchIcon", code: 3)
    }
}

/// Same shape as BrandMark.draw in Sources/MoliSwitchApp/BrandMark.swift;
/// keep the two in step.
private func drawMark(in rect: CGRect, lineWidth: CGFloat, context: CGContext) {
    let gridSize: CGFloat = 18
    let scale = rect.width / gridSize
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.minY)
    context.scaleBy(x: scale, y: scale)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    context.addPath(
        CGPath(
            roundedRect: CGRect(x: 1.5, y: 1.5, width: 15, height: 15),
            cornerWidth: 3.6,
            cornerHeight: 3.6,
            transform: nil
        )
    )

    context.move(to: CGPoint(x: 5, y: 6.8))
    context.addLine(to: CGPoint(x: 13, y: 6.8))
    context.move(to: CGPoint(x: 11, y: 4.8))
    context.addLine(to: CGPoint(x: 13, y: 6.8))
    context.addLine(to: CGPoint(x: 11, y: 8.8))

    context.move(to: CGPoint(x: 13, y: 11.2))
    context.addLine(to: CGPoint(x: 5, y: 11.2))
    context.move(to: CGPoint(x: 7, y: 9.2))
    context.addLine(to: CGPoint(x: 5, y: 11.2))
    context.addLine(to: CGPoint(x: 7, y: 13.2))

    context.strokePath()
    context.restoreGState()
}
