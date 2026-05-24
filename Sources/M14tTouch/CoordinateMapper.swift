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

        return CGPoint(
            x: displayBounds.minX + ratioX * displayBounds.width,
            y: displayBounds.minY + ratioY * displayBounds.height
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
