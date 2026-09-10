import CoreGraphics
import Foundation

/// One target the user was asked to touch, and what the panel reported.
struct CalibrationSample: Equatable {

    /// Where the target sat, as a fraction of the display: `(0, 0)` is the
    /// top-left corner, `(1, 1)` the bottom-right.
    let target: CGPoint

    /// The raw coordinate the panel reported for that touch.
    let raw: CGPoint
}

/// What a set of samples says about the panel.
struct CalibrationResult: Equatable {
    let calibration: CalibrationData

    /// Whether the panel counts in the opposite direction to the screen.
    ///
    /// Detected rather than asked about: if raw values fall as the target moves
    /// right, the axis is mirrored, and the user should not have to find a
    /// checkbox to say so.
    let invertX: Bool
    let invertY: Bool

    /// How far the worst sample sat from the fitted line, as a fraction of the
    /// range. A crooked or mistimed touch shows up here; the interface can offer
    /// a retry rather than saving something quietly wrong.
    let worstError: Double
}

extension CalibrationResult {

    /// Where a raw coordinate lands, as a fraction of the display.
    ///
    /// The same arithmetic `CoordinateMapper` does, stopping one step earlier:
    /// verification draws in the overlay's own coordinates, and going out to
    /// screen pixels and back would only add a chance to disagree.
    func fraction(of raw: CGPoint) -> CGPoint {
        func ratio(_ value: Double, _ low: Double, _ high: Double, inverted: Bool) -> Double {
            guard high > low else { return 0 }
            let r = min(max((value - low) / (high - low), 0), 1)
            return inverted ? 1 - r : r
        }
        return CGPoint(
            x: ratio(raw.x, calibration.xMin, calibration.xMax, inverted: invertX),
            y: ratio(raw.y, calibration.yMin, calibration.yMax, inverted: invertY)
        )
    }
}

/// Turns touched targets into a coordinate range (spec §16).
///
/// The improvement over watching values go by is that these targets are at
/// *known* screen positions. Learning by observation cannot tell the panel's
/// edge from the furthest the user happened to reach; this can, because it knows
/// where each sample was supposed to be.
enum CalibrationSolver {

    /// Fit each axis independently and extrapolate to the display's edges.
    ///
    /// Targets sit inset from the edges — one in the very corner would be half
    /// off-screen and impossible to touch accurately — so the samples are never
    /// the extremes and the line has to be extended past them. Fitted by least
    /// squares rather than from a chosen pair, so all four corners contribute and
    /// one shaky touch is diluted instead of deciding an edge.
    ///
    /// - Returns: `nil` when the samples cannot determine a range: fewer than two
    ///   of them, targets that never move along an axis, or a panel that reported
    ///   the same value throughout.
    static func solve(_ samples: [CalibrationSample]) -> CalibrationResult? {
        guard samples.count >= 2 else { return nil }

        guard let x = fit(samples.map { ($0.target.x, $0.raw.x) }),
              let y = fit(samples.map { ($0.target.y, $0.raw.y) })
        else { return nil }

        return CalibrationResult(
            calibration: CalibrationData(
                xMin: x.low, xMax: x.high,
                yMin: y.low, yMax: y.high
            ),
            invertX: x.inverted,
            invertY: y.inverted,
            worstError: max(x.worstError, y.worstError)
        )
    }

    /// A least-squares line through `(fraction, raw)`, read off at both edges.
    private static func fit(_ points: [(fraction: Double, raw: Double)])
        -> (low: Double, high: Double, inverted: Bool, worstError: Double)? {

        let meanFraction = points.map(\.fraction).reduce(0, +) / Double(points.count)
        let meanRaw = points.map(\.raw).reduce(0, +) / Double(points.count)

        var covariance = 0.0
        var spread = 0.0
        for point in points {
            let df = point.fraction - meanFraction
            covariance += df * (point.raw - meanRaw)
            spread += df * df
        }

        // Every target at the same place along this axis: the line is vertical
        // and says nothing about where the edges are.
        guard spread > 0 else { return nil }

        let slope = covariance / spread
        let intercept = meanRaw - slope * meanFraction

        // The panel reported one value throughout, so there is no range to map
        // onto. Mapping would divide by zero; better to refuse.
        guard slope != 0 else { return nil }

        let atStart = intercept                 // fraction 0 — the left or top edge
        let atEnd = intercept + slope           // fraction 1 — the right or bottom edge

        let worst = points
            .map { abs($0.raw - (intercept + slope * $0.fraction)) }
            .max() ?? 0

        return (
            low: min(atStart, atEnd),
            high: max(atStart, atEnd),
            inverted: slope < 0,
            worstError: worst / abs(slope)      // as a fraction of the full range
        )
    }
}
