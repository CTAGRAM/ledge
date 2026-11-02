// Draws the app icon: a glass trackpad with a lit brightness edge and volume edge.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon.png"

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let canvas = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tile = NSBezierPath(roundedRect: canvas, xRadius: 185, yRadius: 185)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.16, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(calibratedRed: 0.17, green: 0.18, blue: 0.27, alpha: 1),
        NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.12, alpha: 1),
    ])?.draw(in: tile, angle: -90)

    // The trackpad surface.
    let pad = NSRect(x: 215, y: 300, width: 594, height: 424)
    let padPath = NSBezierPath(roundedRect: pad, xRadius: 52, yRadius: 52)
    NSGradient(colors: [
        NSColor(calibratedWhite: 0.96, alpha: 0.22),
        NSColor(calibratedWhite: 0.96, alpha: 0.08),
    ])?.draw(in: padPath, angle: -90)
    NSColor(calibratedWhite: 1, alpha: 0.35).setStroke()
    padPath.lineWidth = 6
    padPath.stroke()

    // Brightness edge (left) and volume edge (right), lit to different levels.
    func bar(x: CGFloat, level: CGFloat, colors: [NSColor]) {
        let track = NSRect(x: x, y: pad.minY + 40, width: 46, height: pad.height - 80)
        NSColor(calibratedWhite: 1, alpha: 0.12).setFill()
        NSBezierPath(roundedRect: track, xRadius: 23, yRadius: 23).fill()
        let fill = NSRect(x: x, y: track.minY, width: 46, height: track.height * level)
        NSGradient(colors: colors)?.draw(in: NSBezierPath(roundedRect: fill, xRadius: 23, yRadius: 23), angle: 90)
    }
    bar(x: pad.minX + 36, level: 0.58, colors: [
        NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.10, alpha: 1),
        NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.30, alpha: 1),
    ])
    bar(x: pad.maxX - 82, level: 0.78, colors: [
        NSColor(calibratedRed: 0.10, green: 0.45, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.35, green: 0.78, blue: 1.0, alpha: 1),
    ])

    // A fingertip on the right edge.
    let finger = NSRect(x: pad.maxX - 105, y: pad.minY + 40 + (pad.height - 80) * 0.78 - 46, width: 92, height: 92)
    NSColor(calibratedWhite: 1, alpha: 0.9).setFill()
    NSBezierPath(ovalIn: finger).fill()
    return true
}

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: output))
