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

    let keyboardRect = CGRect(
        x: 236 * scale,
        y: 330 * scale,
        width: 552 * scale,
        height: 364 * scale
    )
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    context.setLineWidth(max(2, 52 * scale))
    context.addPath(
        CGPath(
            roundedRect: keyboardRect,
            cornerWidth: 72 * scale,
            cornerHeight: 72 * scale,
            transform: nil
        )
    )
    context.strokePath()

    let keySize = 44 * scale
    let keySpacing = 66 * scale
    let firstX = 324 * scale
    let firstY = 464 * scale
    context.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor)

    for row in 0..<2 {
        for column in 0..<5 {
            let rect = CGRect(
                x: firstX + CGFloat(column) * keySpacing,
                y: firstY + CGFloat(row) * keySpacing,
                width: keySize,
                height: keySize
            )
            context.addPath(
                CGPath(
                    roundedRect: rect,
                    cornerWidth: 10 * scale,
                    cornerHeight: 10 * scale,
                    transform: nil
                )
            )
            context.fillPath()
        }
    }

    let spaceRect = CGRect(
        x: 360 * scale,
        y: 378 * scale,
        width: 304 * scale,
        height: 44 * scale
    )
    context.addPath(
        CGPath(
            roundedRect: spaceRect,
            cornerWidth: 18 * scale,
            cornerHeight: 18 * scale,
            transform: nil
        )
    )
    context.fillPath()

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
