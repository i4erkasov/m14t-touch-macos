import XCTest
import CoreGraphics
@testable import M14tTouch

/// Locks in the pre-refactor behaviour of `HIDTouchDriver`'s touch state machine.
///
/// These assertions are the contract step 4 has to keep: once the driver stops
/// emitting events itself and feeds this recognizer instead, any behavioural
/// drift should surface here rather than on a user's desk.
///
/// Note what is *not* claimed — no M14t was attached while this was written, so
/// these encode the semantics of the original code, not measurements from the
/// panel. First run on real hardware remains the acceptance gate for v0.1.
final class MouseModeRecognizerTests: XCTestCase {

    private let threshold = 1.5

    private func makeRecognizer() -> MouseModeRecognizer {
        MouseModeRecognizer(dragThreshold: threshold)
    }

    private func frame(_ x: CGFloat, _ y: CGFloat, touching: Bool) -> TouchFrame {
        TouchFrame(contact: TouchPoint(
            id: TouchPoint.primary,
            position: CGPoint(x: x, y: y),
            rawPosition: CGPoint(x: x * 6, y: y * 6),
            isTouching: touching,
            pressure: nil,
            timestamp: 0
        ))
    }

    // MARK: - Contact

    func testContactBeginsADrag() {
        var recognizer = makeRecognizer()
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: true)),
                       [.dragBegin(position: CGPoint(x: 100, y: 100))])
    }

    func testFramesWithoutContactAreIgnoredWhileIdle() {
        var recognizer = makeRecognizer()
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: false)), [])
        XCTAssertEqual(recognizer.process(frame(400, 400, touching: false)), [])
    }

    func testEmptyFrameIsIgnored() {
        var recognizer = makeRecognizer()
        XCTAssertEqual(recognizer.process(TouchFrame(contacts: [], timestamp: 0)), [])
    }

    // MARK: - Movement threshold

    func testMovementBelowThresholdIsIgnored() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true))
        XCTAssertEqual(recognizer.process(frame(101, 101, touching: true)), [])
    }

    func testMovementAboveThresholdDrags() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true))
        XCTAssertEqual(recognizer.process(frame(110, 100, touching: true)),
                       [.dragMove(position: CGPoint(x: 110, y: 100))])
    }

    // The original compared with `>`, so movement of exactly the threshold is
    // not a drag. Preserved so a `>=` slip cannot pass unnoticed.
    func testThresholdIsExclusive() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true))
        XCTAssertEqual(recognizer.process(frame(100 + threshold, 100, touching: true)), [])
    }

    // Judged per axis, not by distance — movement on either axis alone suffices.
    func testMovementIsJudgedPerAxis() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true))
        XCTAssertEqual(recognizer.process(frame(100, 110, touching: true)),
                       [.dragMove(position: CGPoint(x: 100, y: 110))])
    }

    // Consequence of the per-axis rule: a diagonal step can exceed the threshold
    // in distance while staying under it on both axes, and still not drag.
    func testDiagonalMovementUnderThresholdOnBothAxesIsIgnored() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true))
        XCTAssertEqual(recognizer.process(frame(101.4, 101.4, touching: true)), [])
    }

    func testEachDragAdvancesTheReferencePoint() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true))
        _ = recognizer.process(frame(105, 100, touching: true))
        // Measured from 105, not from the original 100.
        XCTAssertEqual(recognizer.process(frame(106, 100, touching: true)), [])
    }

    // MARK: - Release

    // The quirk that matters most: the original released at the last point it
    // had emitted, ignoring the position reported with the release itself.
    func testReleaseFiresAtTheLastEmittedPointNotTheReleasedPoint() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true))
        XCTAssertEqual(recognizer.process(frame(500, 500, touching: false)),
                       [.dragEnd(position: CGPoint(x: 100, y: 100))])
    }

    func testReleaseAfterADragFiresAtTheLastDraggedPoint() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true))
        _ = recognizer.process(frame(200, 200, touching: true))
        XCTAssertEqual(recognizer.process(frame(300, 300, touching: false)),
                       [.dragEnd(position: CGPoint(x: 200, y: 200))])
    }

    func testPressAndReleaseWithoutMovementIsExactlyOneClick() {
        var recognizer = makeRecognizer()
        var actions = recognizer.process(frame(100, 100, touching: true))
        actions += recognizer.process(frame(101, 101, touching: true))
        actions += recognizer.process(frame(100, 100, touching: false))
        XCTAssertEqual(actions, [
            .dragBegin(position: CGPoint(x: 100, y: 100)),
            .dragEnd(position: CGPoint(x: 100, y: 100)),
        ])
    }

    func testReleaseWhileIdleIsIgnored() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true))
        _ = recognizer.process(frame(100, 100, touching: false))
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: false)), [])
    }

    // MARK: - Reset

    // Device unplugged mid-gesture: without this the button stays down with no
    // finger left to release it.
    func testResetWhileDraggingReleasesAtTheLastEmittedPoint() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true))
        _ = recognizer.process(frame(200, 200, touching: true))
        XCTAssertEqual(recognizer.reset(), [.dragEnd(position: CGPoint(x: 200, y: 200))])
    }

    func testResetWhileIdleEmitsNothing() {
        var recognizer = makeRecognizer()
        XCTAssertEqual(recognizer.reset(), [])
    }

    func testResetIsIdempotent() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true))
        _ = recognizer.reset()
        XCTAssertEqual(recognizer.reset(), [])
    }

    func testGestureCanRestartAfterReset() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true))
        _ = recognizer.reset()
        XCTAssertEqual(recognizer.process(frame(300, 300, touching: true)),
                       [.dragBegin(position: CGPoint(x: 300, y: 300))])
    }
}
