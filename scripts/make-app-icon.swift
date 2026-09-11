import AppKit
import Foundation

// Draws the application icon and writes an .icns.
//
// Generated rather than drawn by hand so it can be regenerated: the mark is the
// same one the website uses — a panel with a touch point on it — and the green
// is the pen dot's own default, read from NSColor.systemGreen.
//
//   swift scripts/make-app-icon.swift resources/AppIcon.icns

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.icns"

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("no bitmap") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // macOS icons leave a margin; the rounded square is the classic proportion.
    let margin = size * 0.085
    let side = size - margin * 2
    let plate = NSRect(x: margin, y: margin, width: side, height: side)
    let plateShape = NSBezierPath(roundedRect: plate,
                                  xRadius: side * 0.2237, yRadius: side * 0.2237)

    NSGradient(
        starting: NSColor(srgbRed: 0.23, green: 0.25, blue: 0.28, alpha: 1),
        ending: NSColor(srgbRed: 0.08, green: 0.09, blue: 0.10, alpha: 1)
    )?.draw(in: plateShape, angle: -90)

    // A panel, seen face on: the thing this drives.
    let screenWidth = side * 0.62
    let screenHeight = screenWidth * 9 / 16
    let screen = NSRect(
        x: plate.midX - screenWidth / 2,
        y: plate.midY - screenHeight / 2 + side * 0.05,
        width: screenWidth,
        height: screenHeight
    )
    let stroke = max(1, side * 0.038)
    let screenShape = NSBezierPath(roundedRect: screen,
                                   xRadius: side * 0.045, yRadius: side * 0.045)
    screenShape.lineWidth = stroke
    let ink = NSColor(srgbRed: 0.91, green: 0.91, blue: 0.93, alpha: 1)
    ink.setStroke()
    ink.setFill()
    screenShape.stroke()

    // Its stand, so the shape reads as a monitor rather than a window.
    let footWidth = screenWidth * 0.34
    let foot = NSRect(
        x: plate.midX - footWidth / 2,
        y: screen.minY - side * 0.075,
        width: footWidth,
        height: stroke
    )
    // Same ink as the outline — without setting it, this filled with the
    // default black and read as a hole rather than a stand.
    NSBezierPath(roundedRect: foot, xRadius: stroke / 2, yRadius: stroke / 2).fill()

    // And the touch: the pen's dot, in the colour it uses by default.
    let dotSize = screenHeight * 0.42
    let dot = NSRect(
        x: screen.midX - dotSize / 2 + screenWidth * 0.16,
        y: screen.midY - dotSize / 2 - screenHeight * 0.08,
        width: dotSize, height: dotSize
    )
    NSColor(srgbRed: 0.1882, green: 0.8196, blue: 0.3451, alpha: 1).setFill()
    NSBezierPath(ovalIn: dot).fill()

    return rep
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("M14tTouch.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let rep = drawIcon(size: CGFloat(pixels))
        guard let data = rep.representation(using: .png, properties: [:]) else { continue }
        let suffix = scale == 1 ? "" : "@2x"
        let name = "icon_\(base)x\(base)\(suffix).png"
        try data.write(to: iconset.appendingPathComponent(name))
    }
}

let convert = Process()
convert.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
convert.arguments = ["-c", "icns", iconset.path, "-o", output]
try convert.run()
convert.waitUntilExit()
print(convert.terminationStatus == 0 ? "written \(output)" : "iconutil failed")
