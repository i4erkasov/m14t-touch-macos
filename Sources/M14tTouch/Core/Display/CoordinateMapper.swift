import CoreGraphics

/// Translates a raw touch coordinate into a point on a specific display.
///
/// This is the mathematical heart of the driver, intentionally isolated as a
/// pure value type with no IOKit or global state. That makes the trickiest part
/// of the system — the part that decides *where* the cursor goes — fully unit
/// testable without any hardware (see `CoordinateMapperTests`).
struct CoordinateMapper {

    /// The raw coordinate range the panel actually reports.
    var calibration: CalibrationData

    /// The target display's bounds in the global screen coordinate space.
    var displayBounds: CGRect

    var invertX: Bool
    var invertY: Bool

    /// How the display is rotated, in degrees counterclockwise — what
    /// `CGDisplayRotation` reports, and what the user chose in System Settings.
    ///
    /// The panel reports where a finger is on the *glass*, and rotating a
    /// display does not move the glass. Without this the two disagree the
    /// moment anyone rotates anything: the long axis of the panel would be
    /// mapped across the short axis of the screen.
    var rotation: Double = 0

    /// Map a raw `(x, y)` touch sample to an absolute screen point.
    ///
    /// The result is clamped to the display so a slightly-out-of-range sample
    /// (common near the bezel) never throws the cursor off-screen.
    func map(rawX: Double, rawY: Double) -> CGPoint {
        let rangeX = calibration.xMax - calibration.xMin
        let rangeY = calibration.yMax - calibration.yMin

        // Degenerate calibration — avoid divide-by-zero, fall back to origin.
        guard rangeX > 0, rangeY > 0 else { return displayBounds.origin }

        var ratioX = (rawX - calibration.xMin) / rangeX
        var ratioY = (rawY - calibration.yMin) / rangeY

        if invertX { ratioX = 1 - ratioX }
        if invertY { ratioY = 1 - ratioY }

        ratioX = ratioX.clamped(to: 0...1)
        ratioY = ratioY.clamped(to: 0...1)

        let (screenX, screenY) = Self.rotated(x: ratioX, y: ratioY, by: rotation)

        return CGPoint(
            x: displayBounds.minX + screenX * displayBounds.width,
            y: displayBounds.minY + screenY * displayBounds.height
        )
    }

    /// Turn a position on the glass into a position in the rotated image.
    ///
    /// Derived rather than guessed, by following the corners. Rotating an image
    /// 90° counterclockwise carries its top edge to the left edge, so the
    /// framebuffer's top-left corner ends up at the bottom-left of the glass.
    /// Reading that backwards — from a point on the glass to the point of the
    /// image now under it — gives the cases below.
    ///
    /// Anything that is not a right angle is treated as no rotation. macOS only
    /// offers the four, and inventing an answer for 37° would be worse than
    /// declining to.
    static func rotated(x: Double, y: Double, by degrees: Double) -> (x: Double, y: Double) {
        // Normalised into 0..<360 first: a quarter turn the other way can
        // arrive as -90, and a negative remainder would match nothing and
        // silently become "no rotation".
        let turn = ((Int(degrees.rounded()) % 360) + 360) % 360
        switch turn {
        case 90:  return (1 - y, x)
        case 180: return (1 - x, 1 - y)
        case 270: return (y, 1 - x)
        default:  return (x, y)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
