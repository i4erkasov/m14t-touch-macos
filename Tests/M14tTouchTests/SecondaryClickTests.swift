import CoreGraphics
import XCTest
@testable import M14tTouch

/// Hold one finger on something, tap with a second: a secondary click.
///
/// The point of the gesture, and the thing most worth pinning, is *where* the
/// click lands — at the first finger, which is what the user is pointing at.
/// The second finger is the instruction, not the address.
final class SecondaryClickTests: XCTestCase {

    private var configuration: GestureConfiguration {
        var configuration = GestureConfiguration()
        configuration.twoFingerSecondaryClick = true
        configuration.restoreCursor = false
        configuration.longPressDelay = 0.4
        configuration.scrollThreshold = 10
        return configuration
    }

    private let anchor = CGPoint(x: 400, y: 300)

    private func finger(_ id: Int, _ point: CGPoint, at time: TimeInterval, touching: Bool = true) -> TouchPoint {
        TouchPoint(id: id, position: point, rawPosition: point,
                   isTouching: touching, pressure: nil, timestamp: time)
    }

    private func one(_ point: CGPoint, at time: TimeInterval, touching: Bool = true) -> TouchFrame {
        TouchFrame(contacts: [finger(0, point, at: time, touching: touching)], timestamp: time)
    }

    private func two(_ second: CGPoint, at time: TimeInterval) -> TouchFrame {
        TouchFrame(
            contacts: [finger(0, anchor, at: time), finger(2, second, at: time)],
            timestamp: time
        )
    }

    private let secondFinger = CGPoint(x: 500, y: 300)

    // MARK: -

    func testTappingWithASecondFingerIsASecondaryClick() {
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(one(anchor, at: 0))
        _ = recognizer.process(two(secondFinger, at: 0.1))

        let actions = recognizer.process(one(anchor, at: 0.2))
        XCTAssertEqual(actions, [.rightClick(position: anchor)])
    }

    // The whole reason for preferring this to a trackpad's two-finger tap.
    func testTheClickLandsUnderTheFirstFingerNotTheSecond() {
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(one(anchor, at: 0))
        _ = recognizer.process(two(CGPoint(x: 900, y: 700), at: 0.1))

        let actions = recognizer.process(one(anchor, at: 0.2))
        XCTAssertEqual(actions, [.rightClick(position: anchor)],
                       "the second finger says when, the first says where")
    }

    // Nothing is emitted while it is still ambiguous. A click on the way down
    // would fire before the gesture had been made.
    func testNothingHappensUntilTheSecondFingerLeaves() {
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(one(anchor, at: 0))

        XCTAssertEqual(recognizer.process(two(secondFinger, at: 0.1)), [])
        XCTAssertEqual(recognizer.process(two(secondFinger, at: 0.15)), [])
    }

    // A second finger that settles in is not tapping.
    func testASecondFingerThatRestsTooLongIsNotATap() {
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(one(anchor, at: 0))
        _ = recognizer.process(two(secondFinger, at: 0.1))

        let actions = recognizer.process(one(anchor, at: 0.8))
        XCTAssertFalse(actions.contains(.rightClick(position: anchor)))
    }

    // Fingers that move apart were pinching all along.
    func testFingersThatSeparateZoomRatherThanClick() {
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(one(anchor, at: 0))
        _ = recognizer.process(two(secondFinger, at: 0.1))

        // Moved well apart: this is a pinch.
        let opening = recognizer.process(two(CGPoint(x: 600, y: 300), at: 0.2))
        XCTAssertTrue(opening.contains { if case .focusWindow = $0 { return true } else { return false } },
                      "a pinch begins by bringing the window forward: \\(opening)")

        // And lifting now must not also produce a click.
        let lift = recognizer.process(one(anchor, at: 0.3))
        XCTAssertFalse(lift.contains(.rightClick(position: anchor)))
    }

    // Resting a finger for longer than the long-press delay turns it into a
    // drag, which holds a button down. That button has to be let go before a
    // secondary click, or the two press at once.
    func testAFirstFingerThatHadBecomeADragLetsGoFirst() {
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(one(anchor, at: 0))
        // Past the long-press delay: now dragging.
        let began = recognizer.process(one(anchor, at: 0.5))
        XCTAssertEqual(began, [.dragBegin(position: anchor)])

        _ = recognizer.process(two(secondFinger, at: 0.6))
        let actions = recognizer.process(one(anchor, at: 0.7))

        XCTAssertEqual(actions, [.dragEnd(position: anchor), .rightClick(position: anchor)])
    }

    // The finger still on the glass must not carry on into a scroll or a drag.
    func testTheRemainingFingerDoesNothingAfterTheClick() {
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(one(anchor, at: 0))
        _ = recognizer.process(two(secondFinger, at: 0.1))
        _ = recognizer.process(one(anchor, at: 0.2))

        XCTAssertEqual(recognizer.process(one(CGPoint(x: 400, y: 900), at: 0.3)), [])
        XCTAssertEqual(recognizer.process(one(CGPoint(x: 400, y: 200), at: 0.4)), [])
    }

    func testANewGestureWorksAfterwards() {
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(one(anchor, at: 0))
        _ = recognizer.process(two(secondFinger, at: 0.1))
        _ = recognizer.process(one(anchor, at: 0.2))
        _ = recognizer.process(one(anchor, at: 0.3, touching: false))

        let target = CGPoint(x: 700, y: 500)
        _ = recognizer.process(one(target, at: 1.0))
        XCTAssertEqual(recognizer.process(one(target, at: 1.05, touching: false)),
                       [.tap(position: target)])
    }

    func testTurningItOffLeavesTwoFingersToThePinch() {
        var configuration = self.configuration
        configuration.twoFingerSecondaryClick = false
        var recognizer = TouchscreenRecognizer(configuration: configuration)

        _ = recognizer.process(one(anchor, at: 0))
        _ = recognizer.process(two(secondFinger, at: 0.1))
        let actions = recognizer.process(one(anchor, at: 0.2))
        XCTAssertFalse(actions.contains(.rightClick(position: anchor)))
    }

    func testItIsOnByDefault() {
        XCTAssertTrue(GestureConfiguration().twoFingerSecondaryClick)
    }

    // Unplugging with a second finger down must not stand the drag's button.
    func testResetLetsGoOfADragCaughtMidGesture() {
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(one(anchor, at: 0))
        _ = recognizer.process(one(anchor, at: 0.5))      // becomes a drag
        _ = recognizer.process(two(secondFinger, at: 0.6))

        XCTAssertEqual(recognizer.reset(), [.dragEnd(position: anchor)])
    }
}
