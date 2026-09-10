import XCTest
import CoreGraphics
@testable import M14tTouch

/// Covers the arithmetic guided calibration exists for. This is where its
/// accuracy lives, and an error here would produce something plausible-looking
/// and wrong, so the fixtures are built from a panel whose true range is known
/// and the answer is checked against it.
final class CalibrationSolverTests: XCTestCase {

    /// The M14t's measured range, so the expected answers mean something.
    private let trueRange = (xMin: 1.0, xMax: 12302.0, yMin: 108.0, yMax: 6959.0)

    /// Targets sit inset from the edges — one in the very corner would be half
    /// off-screen — so the samples are never the extremes.
    private let inset = 0.1

    /// What the panel would report for a target at this fraction, if the user
    /// touched it exactly.
    private func raw(at target: CGPoint, inverted: (x: Bool, y: Bool) = (false, false)) -> CGPoint {
        let fx = inverted.x ? 1 - target.x : target.x
        let fy = inverted.y ? 1 - target.y : target.y
        return CGPoint(
            x: trueRange.xMin + fx * (trueRange.xMax - trueRange.xMin),
            y: trueRange.yMin + fy * (trueRange.yMax - trueRange.yMin)
        )
    }

    private func corners(inverted: (x: Bool, y: Bool) = (false, false)) -> [CalibrationSample] {
        [
            CGPoint(x: inset, y: inset),
            CGPoint(x: 1 - inset, y: inset),
            CGPoint(x: 1 - inset, y: 1 - inset),
            CGPoint(x: inset, y: 1 - inset),
        ].map { CalibrationSample(target: $0, raw: raw(at: $0, inverted: inverted)) }
    }

    // MARK: - The point of the exercise

    // Four inset targets recover the full range, including the parts beyond
    // where anyone actually touched. Watching values go by could not do this: it
    // would have learned the inset range and stopped there.
    func testInsetTargetsRecoverTheEdgesTheyNeverReached() throws {
        let result = try XCTUnwrap(CalibrationSolver.solve(corners()))
        XCTAssertEqual(result.calibration.xMin, trueRange.xMin, accuracy: 0.5)
        XCTAssertEqual(result.calibration.xMax, trueRange.xMax, accuracy: 0.5)
        XCTAssertEqual(result.calibration.yMin, trueRange.yMin, accuracy: 0.5)
        XCTAssertEqual(result.calibration.yMax, trueRange.yMax, accuracy: 0.5)
    }

    func testAPerfectTouchHasNoError() throws {
        let result = try XCTUnwrap(CalibrationSolver.solve(corners()))
        XCTAssertEqual(result.worstError, 0, accuracy: 1e-9)
        XCTAssertFalse(result.invertX)
        XCTAssertFalse(result.invertY)
    }

    // MARK: - Inversion

    // Detected rather than asked about: if raw falls as the target moves right,
    // the axis is mirrored, and the user should not have to find a checkbox.
    func testAMirroredAxisIsDetectedAndTheRangeStillOrdered() throws {
        let result = try XCTUnwrap(CalibrationSolver.solve(corners(inverted: (x: true, y: false))))
        XCTAssertTrue(result.invertX)
        XCTAssertFalse(result.invertY)
        // Whatever the direction, the mapper needs min below max.
        XCTAssertLessThan(result.calibration.xMin, result.calibration.xMax)
        XCTAssertEqual(result.calibration.xMin, trueRange.xMin, accuracy: 0.5)
        XCTAssertEqual(result.calibration.xMax, trueRange.xMax, accuracy: 0.5)
    }

    func testBothAxesCanBeMirroredAtOnce() throws {
        let result = try XCTUnwrap(CalibrationSolver.solve(corners(inverted: (x: true, y: true))))
        XCTAssertTrue(result.invertX)
        XCTAssertTrue(result.invertY)
    }

    // MARK: - Imperfect touches

    // One shaky corner should be diluted by the other three, not decide an edge.
    // Fitting by least squares is what buys this; taking a chosen pair would not.
    func testOneCrookedTouchIsDilutedRatherThanDecisive() throws {
        let mistake = 300.0
        var samples = corners()
        samples[0] = CalibrationSample(
            target: samples[0].target,
            raw: CGPoint(x: samples[0].raw.x + mistake, y: samples[0].raw.y)
        )
        let result = try XCTUnwrap(CalibrationSolver.solve(samples))

        // Costs 169 of the 300 units it was worth — diluted, but only partly,
        // because reading the line off at an edge beyond every sample amplifies
        // whatever error is in them. A chosen pair would have paid the full 300.
        let error = abs(result.calibration.xMin - trueRange.xMin)
        XCTAssertLessThan(error, mistake * 0.6)
        XCTAssertGreaterThan(result.worstError, 0)
    }

    // The interface offers a retry rather than saving something quietly wrong,
    // so a bad set has to be distinguishable from a good one.
    func testACrookedSetReportsALargerErrorThanACleanOne() throws {
        let clean = try XCTUnwrap(CalibrationSolver.solve(corners()))

        var samples = corners()
        samples[2] = CalibrationSample(
            target: samples[2].target,
            raw: CGPoint(x: samples[2].raw.x - 900, y: samples[2].raw.y + 600)
        )
        let crooked = try XCTUnwrap(CalibrationSolver.solve(samples))

        XCTAssertGreaterThan(crooked.worstError, clean.worstError)
        XCTAssertGreaterThan(crooked.worstError, 0.02)   // a few percent of the range
    }

    // MARK: - Refusals

    func testTooFewSamplesGiveNothing() {
        XCTAssertNil(CalibrationSolver.solve([]))
        XCTAssertNil(CalibrationSolver.solve([corners()[0]]))
    }

    // Targets stacked in a column say nothing about the horizontal edges.
    func testTargetsThatNeverMoveAlongAnAxisGiveNothing() {
        let samples = [0.2, 0.5, 0.8].map { y in
            CalibrationSample(
                target: CGPoint(x: 0.5, y: y),
                raw: CGPoint(x: 6000, y: 100 + y * 6000)
            )
        }
        XCTAssertNil(CalibrationSolver.solve(samples))
    }

    // A panel reporting one value throughout has no range to map onto, and
    // mapping would divide by zero.
    func testAPanelReportingNothingGivesNothing() {
        let samples = corners().map {
            CalibrationSample(target: $0.target, raw: CGPoint(x: 5000, y: $0.raw.y))
        }
        XCTAssertNil(CalibrationSolver.solve(samples))
    }

    // MARK: - Round trip

    // The proof that matters: feed the result back through the mapper and the
    // targets land where they were drawn.
    func testTheResultMapsTheTargetsBackToWhereTheyWere() throws {
        let bounds = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let result = try XCTUnwrap(CalibrationSolver.solve(corners()))
        let mapper = CoordinateMapper(
            calibration: result.calibration,
            displayBounds: bounds,
            invertX: result.invertX,
            invertY: result.invertY
        )

        for sample in corners() {
            let mapped = mapper.map(rawX: sample.raw.x, rawY: sample.raw.y)
            let expected = CGPoint(
                x: bounds.minX + sample.target.x * bounds.width,
                y: bounds.minY + sample.target.y * bounds.height
            )
            XCTAssertEqual(mapped.x, expected.x, accuracy: 1)
            XCTAssertEqual(mapped.y, expected.y, accuracy: 1)
        }
    }
}
