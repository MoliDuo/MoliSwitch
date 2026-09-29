import AppKit

/// The MoliSwitch mark: a rounded square holding two opposing arrows.
///
/// Scripts/generate-app-icon.swift draws the same shape for the app icon;
/// keep the two in step.
enum BrandMark {
    /// Side of the square grid the coordinates below are laid out on, y down.
    private static let gridSize: CGFloat = 18

    static func menuBarImage() -> NSImage {
        let size = NSSize(width: gridSize, height: gridSize)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }
            context.setStrokeColor(NSColor.black.cgColor)
            draw(in: rect, lineWidth: 1.4, context: context)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppInfo.name
        return image
    }

    /// Strokes the mark into `rect` of a context whose y axis points down.
    /// `lineWidth` is in grid units and scales with `rect`.
    static func draw(in rect: CGRect, lineWidth: CGFloat, context: CGContext) {
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

        // Upper arrow points right.
        context.move(to: CGPoint(x: 5, y: 6.8))
        context.addLine(to: CGPoint(x: 13, y: 6.8))
        context.move(to: CGPoint(x: 11, y: 4.8))
        context.addLine(to: CGPoint(x: 13, y: 6.8))
        context.addLine(to: CGPoint(x: 11, y: 8.8))

        // Lower arrow points left.
        context.move(to: CGPoint(x: 13, y: 11.2))
        context.addLine(to: CGPoint(x: 5, y: 11.2))
        context.move(to: CGPoint(x: 7, y: 9.2))
        context.addLine(to: CGPoint(x: 5, y: 11.2))
        context.addLine(to: CGPoint(x: 7, y: 13.2))

        context.strokePath()
        context.restoreGState()
    }
}
