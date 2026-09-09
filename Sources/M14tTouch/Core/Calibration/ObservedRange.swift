import Foundation

/// Tracks the tightest min/max coordinates seen during auto-calibration.
struct ObservedRange {
    private var minX = Double.infinity
    private var maxX = -Double.infinity
    private var minY = Double.infinity
    private var maxY = -Double.infinity

    /// Seed from a previously-saved calibration so auto-cal refines rather than
    /// starting from nothing.
    mutating func seed(with c: CalibrationData) {
        minX = c.xMin; maxX = c.xMax
        minY = c.yMin; maxY = c.yMax
    }

    /// Feed a new sample. Returns `true` if the range expanded.
    mutating func update(x: Double?, y: Double?) -> Bool {
        var changed = false
        if let x, x >= 0 {
            if x < minX { minX = x; changed = true }
            if x > maxX { maxX = x; changed = true }
        }
        if let y, y >= 0 {
            if y < minY { minY = y; changed = true }
            if y > maxY { maxY = y; changed = true }
        }
        return changed
    }

    /// A valid calibration, or `nil` if the range hasn't formed yet.
    func snapshot() -> CalibrationData? {
        guard minX < maxX, minY < maxY else { return nil }
        return CalibrationData(xMin: minX, xMax: maxX, yMin: minY, yMax: maxY)
    }
}
