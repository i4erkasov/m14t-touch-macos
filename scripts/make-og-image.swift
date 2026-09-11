import AppKit
import Foundation

// The picture that appears when the site is shared — in a message, a post, a
// chat. Generated for the same reason the app icon is: so it can be redone.
//
//   swift scripts/make-og-image.swift docs/images/share.png

let output = CommandLine.arguments.dropFirst().first ?? "share.png"
let size = NSSize(width: 1200, height: 630)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let whole = NSRect(origin: .zero, size: size)
NSGradient(
    starting: NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1),
    ending: NSColor(srgbRed: 0.05, green: 0.055, blue: 0.065, alpha: 1)
)?.draw(in: whole, angle: -90)

// The same mark as the icon and the site: a panel with a touch on it.
let markSide: CGFloat = 210
let mark = NSRect(x: 96, y: size.height / 2 - markSide / 2, width: markSide, height: markSide * 0.72)
let ink = NSColor(srgbRed: 0.91, green: 0.91, blue: 0.93, alpha: 1)
let screenShape = NSBezierPath(roundedRect: mark, xRadius: 14, yRadius: 14)
screenShape.lineWidth = 9
ink.setStroke()
ink.setFill()
screenShape.stroke()
let footWidth = markSide * 0.32
NSBezierPath(
    roundedRect: NSRect(x: mark.midX - footWidth / 2, y: mark.minY - 22, width: footWidth, height: 9),
    xRadius: 4.5, yRadius: 4.5
).fill()
NSColor(srgbRed: 0.1882, green: 0.8196, blue: 0.3451, alpha: 1).setFill()
let dotSize = mark.height * 0.42
NSBezierPath(ovalIn: NSRect(
    x: mark.midX - dotSize / 2 + mark.width * 0.16,
    y: mark.midY - dotSize / 2 - mark.height * 0.08,
    width: dotSize, height: dotSize
)).fill()

func write(_ text: String, at point: NSPoint, size fontSize: CGFloat, weight: NSFont.Weight, colour: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
        .foregroundColor: colour
    ]
    NSAttributedString(string: text, attributes: attributes).draw(at: point)
}

let textLeft: CGFloat = 380
write("M14t Touch", at: NSPoint(x: textLeft, y: 366), size: 76, weight: .bold,
      colour: NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1))
write("Touch and stylus input for the", at: NSPoint(x: textLeft, y: 300), size: 34, weight: .regular,
      colour: NSColor(srgbRed: 0.68, green: 0.69, blue: 0.72, alpha: 1))
write("Lenovo ThinkVision M14t, on macOS.", at: NSPoint(x: textLeft, y: 252), size: 34, weight: .regular,
      colour: NSColor(srgbRed: 0.68, green: 0.69, blue: 0.72, alpha: 1))
write("No kernel extension · No dependencies · MIT", at: NSPoint(x: textLeft, y: 186), size: 25,
      weight: .medium, colour: NSColor(srgbRed: 0.45, green: 0.47, blue: 0.50, alpha: 1))

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: output))
print("written \(output)")
