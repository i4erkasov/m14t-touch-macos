import XCTest
import CoreGraphics
@testable import M14tTouch

/// Covers turning a stream of frames into one sample per target.
final class CalibrationCollectorTests: XCTestCase {

    private func frame(_ raw: CGPoint, touching: Bool) -> TouchFrame {
        TouchFrame(contact: TouchPoint(
            id: TouchPoint.primary,
            position: .zero,                 // unused: calibration reads raw
            rawPosition: raw,
            isTouching: touching,
            pressure: nil,
            timestamp: 0
        ))
    }

    /// A steady touch: several frames down, then a lift.
    private func touch(_ collector: inout CalibrationCollector, at raw: CGPoint, wobble: Double = 0) {
        for step in 0..<4 {
            let offset = step.isMultiple(of: 2) ? wobble : -wobble
            collector.process(frame(CGPoint(x: raw.x + offset, y: raw.y), touching: true))
        }
        collector.process(frame(raw, touching: false))
    }

    func testTargetsAreOfferedInOrder() {
        var collector = CalibrationCollector()
        XCTAssertEqual(collector.currentTarget, CalibrationCollector.defaultTargets[0])
        touch(&collector, at: CGPoint(x: 1000, y: 800))
        XCTAssertEqual(collector.currentTarget, CalibrationCollector.defaultTargets[1])
    }

    // The sample is taken on release, not on contact: nothing is recorded while
    // the finger is still down, because it may still be settling.
    func testNothingIsRecordedUntilTheFingerLifts() {
        var collector = CalibrationCollector()
        collector.process(frame(CGPoint(x: 1000, y: 800), touching: true))
        collector.process(frame(CGPoint(x: 1001, y: 801), touching: true))
        XCTAssertTrue(collector.samples.isEmpty)

        collector.process(frame(CGPoint(x: 1001, y: 801), touching: false))
        XCTAssertEqual(collector.samples.count, 1)
    }

    // Averaging the contact costs nothing and takes the sting out of the wobble
    // a lift always has.
    func testTheSampleIsTheMeanOfTheContact() {
        var collector = CalibrationCollector()
        touch(&collector, at: CGPoint(x: 1000, y: 800), wobble: 40)
        XCTAssertEqual(collector.samples.first?.raw.x ?? 0, 1000, accuracy: 0.001)
    }

    // A release with nothing before it is the tail of some other contact, not a
    // touch on this target.
    func testAStrayReleaseIsIgnored() {
        var collector = CalibrationCollector()
        collector.process(frame(CGPoint(x: 1000, y: 800), touching: false))
        XCTAssertTrue(collector.samples.isEmpty)
        XCTAssertEqual(collector.currentTarget, CalibrationCollector.defaultTargets[0])
    }

    func testFramesAfterTheLastTargetAreIgnored() {
        var collector = CalibrationCollector()
        for _ in 0..<4 { touch(&collector, at: CGPoint(x: 1000, y: 800)) }
        XCTAssertTrue(collector.isComplete)
        XCTAssertNil(collector.currentTarget)

        touch(&collector, at: CGPoint(x: 2000, y: 2000))
        XCTAssertEqual(collector.samples.count, 4)
    }

    func testRestartingThrowsEverythingAway() {
        var collector = CalibrationCollector()
        touch(&collector, at: CGPoint(x: 1000, y: 800))
        collector.restart()
        XCTAssertTrue(collector.samples.isEmpty)
        XCTAssertEqual(collector.currentTarget, CalibrationCollector.defaultTargets[0])
    }

    func testNothingIsSolvedBeforeEveryTargetIsDone() {
        var collector = CalibrationCollector()
        touch(&collector, at: CGPoint(x: 1000, y: 800))
        XCTAssertNil(collector.solve())
    }

    // End to end: touching four targets on a panel whose range is known recovers
    // that range, edges included.
    func testACompleteSetSolvesToThePanelsRange() throws {
        let range = (xMin: 1.0, xMax: 12302.0, yMin: 108.0, yMax: 6959.0)
        var collector = CalibrationCollector()

        for target in CalibrationCollector.defaultTargets {
            touch(&collector, at: CGPoint(
                x: range.xMin + target.x * (range.xMax - range.xMin),
                y: range.yMin + target.y * (range.yMax - range.yMin)
            ))
        }

        let result = try XCTUnwrap(collector.solve())
        XCTAssertEqual(result.calibration.xMin, range.xMin, accuracy: 0.5)
        XCTAssertEqual(result.calibration.xMax, range.xMax, accuracy: 0.5)
        XCTAssertEqual(result.calibration.yMin, range.yMin, accuracy: 0.5)
        XCTAssertEqual(result.calibration.yMax, range.yMax, accuracy: 0.5)
    }
}
