import CoreGraphics
import XCTest
@testable import M14tTouch

/// Spreading and closing two fingers.
///
/// A real magnification event cannot be built with public APIs, so what this
/// produces is whole zoom steps, which the emitter sends as ⌘ + scroll. The
/// quantising is the part with a decision in it, and therefore the part tested.
final class PinchTests: XCTestCase {

    private var configuration: GestureConfiguration {
        var configuration = GestureConfiguration()
        configuration.pinchToZoom = true
        configuration.zoomStep = 40   // smaller than the default, to keep these readable
        configuration.restoreCursor = false   // one thing at a time
        return configuration
    }

    private func recognizer() -> TouchscreenRecognizer {
        TouchscreenRecognizer(configuration: configuration)
    }

    /// A frame of two fingers a given distance apart, horizontally.
    private func pinch(_ separation: CGFloat, at time: TimeInterval = 0) -> TouchFrame {
        func finger(_ id: Int, x: CGFloat) -> TouchPoint {
            TouchPoint(
                id: id,
                position: CGPoint(x: x, y: 500),
                rawPosition: CGPoint(x: x, y: 500),
                isTouching: true,
                pressure: nil,
                timestamp: time
            )
        }
        return TouchFrame(
            contacts: [finger(0, x: 500 - separation / 2), finger(2, x: 500 + separation / 2)],
            timestamp: time
        )
    }

    private func lift(at time: TimeInterval) -> TouchFrame {
        TouchFrame(contact: TouchPoint(
            id: 0,
            position: CGPoint(x: 500, y: 500),
            rawPosition: CGPoint(x: 500, y: 500),
            isTouching: false,
            pressure: nil,
            timestamp: time
        ))
    }

    // Zoom is sent as ⌘= , which goes to the frontmost window. Without this the
    // gesture happened on the panel and the zoom happened on another screen —
    // reported from use, not imagined.
    func testOpeningTheGestureBringsTheWindowUnderTheFingersForward() {
        var recognizer = self.recognizer()
        XCTAssertEqual(
            recognizer.process(pinch(100)),
            [.focusWindow(position: CGPoint(x: 500, y: 500))]
        )
    }

    func testSpreadingByOneStepZoomsIn() {
        var recognizer = self.recognizer()
        _ = recognizer.process(pinch(100))
        XCTAssertEqual(recognizer.process(pinch(140, at: 0.1)), [.zoom(steps: 1)])
    }

    func testClosingByOneStepZoomsOut() {
        var recognizer = self.recognizer()
        _ = recognizer.process(pinch(200))
        XCTAssertEqual(recognizer.process(pinch(160, at: 0.1)), [.zoom(steps: -1)])
    }

    func testAWideSpreadZoomsBySeveralStepsAtOnce() {
        var recognizer = self.recognizer()
        _ = recognizer.process(pinch(100))
        XCTAssertEqual(recognizer.process(pinch(230, at: 0.1)), [.zoom(steps: 3)])
    }

    // Less than a whole step produces nothing yet, which is correct — and the
    // movement must not be thrown away, or a slow spread would zoom never.
    func testMovementBelowAStepIsKeptRatherThanDiscarded() {
        var recognizer = self.recognizer()
        _ = recognizer.process(pinch(100))

        XCTAssertEqual(recognizer.process(pinch(125, at: 0.1)), [])
        XCTAssertEqual(recognizer.process(pinch(145, at: 0.2)), [.zoom(steps: 1)],
                       "25 + 20 is past one step of 40")
    }

    // The remainder after a step is carried too, not reset.
    func testTheRemainderCarriesIntoTheNextStep() {
        var recognizer = self.recognizer()
        _ = recognizer.process(pinch(100))
        XCTAssertEqual(recognizer.process(pinch(160, at: 0.1)), [.zoom(steps: 1)])
        // 20 left over, so 20 more finishes the second step.
        XCTAssertEqual(recognizer.process(pinch(180, at: 0.2)), [.zoom(steps: 1)])
    }

    func testHoldingStillZoomsNothing() {
        var recognizer = self.recognizer()
        _ = recognizer.process(pinch(100))
        XCTAssertEqual(recognizer.process(pinch(100, at: 0.1)), [])
        XCTAssertEqual(recognizer.process(pinch(100, at: 0.2)), [])
    }

    // Lifting one finger ends the zoom. The survivor must not inherit it as a
    // scroll: the user is lifting off, not starting something new.
    func testLiftingOneFingerDoesNotTurnTheOtherIntoAScroll() {
        var recognizer = self.recognizer()
        _ = recognizer.process(pinch(100))
        _ = recognizer.process(pinch(200, at: 0.1))

        let oneFinger = TouchFrame(contact: TouchPoint(
            id: 0, position: CGPoint(x: 450, y: 500), rawPosition: .zero,
            isTouching: true, pressure: nil, timestamp: 0.2
        ))
        XCTAssertEqual(recognizer.process(oneFinger), [])

        // And moving it produces nothing either, until everything lifts.
        let moved = TouchFrame(contact: TouchPoint(
            id: 0, position: CGPoint(x: 450, y: 900), rawPosition: .zero,
            isTouching: true, pressure: nil, timestamp: 0.3
        ))
        XCTAssertEqual(recognizer.process(moved), [])
    }

    // ...and after everything lifts, a new gesture starts cleanly.
    func testANewGestureWorksAfterAZoom() {
        var recognizer = self.recognizer()
        _ = recognizer.process(pinch(100))
        _ = recognizer.process(pinch(200, at: 0.1))
        _ = recognizer.process(lift(at: 0.2))

        let tapDown = TouchFrame(contact: TouchPoint(
            id: 0, position: CGPoint(x: 300, y: 300), rawPosition: .zero,
            isTouching: true, pressure: nil, timestamp: 1.0
        ))
        _ = recognizer.process(tapDown)
        let tapUp = TouchFrame(contact: TouchPoint(
            id: 0, position: CGPoint(x: 300, y: 300), rawPosition: .zero,
            isTouching: false, pressure: nil, timestamp: 1.05
        ))
        XCTAssertEqual(recognizer.process(tapUp), [.tap(position: CGPoint(x: 300, y: 300))])
    }

    func testTurningPinchOffLeavesTwoFingersToTheOneFingerLogic() {
        var configuration = self.configuration
        configuration.pinchToZoom = false
        var recognizer = TouchscreenRecognizer(configuration: configuration)

        let actions = recognizer.process(pinch(100))
        XCTAssertFalse(actions.contains { if case .zoom = $0 { return true } else { return false } })
    }

    func testPinchIsOnByDefaultAndTheStepIsSane() {
        let defaults = GestureConfiguration()
        XCTAssertTrue(defaults.pinchToZoom)
        XCTAssertGreaterThan(defaults.zoomStep, 0)
    }

    // Unplugging mid-zoom must not leave the recognizer believing two fingers
    // are still on the glass.
    func testResetDuringAZoomEndsIt() {
        var recognizer = self.recognizer()
        _ = recognizer.process(pinch(100))
        XCTAssertEqual(recognizer.reset(), [])

        // A fresh gesture is recognised afterwards, so the state really cleared.
        XCTAssertEqual(recognizer.process(pinch(100, at: 1.0)),
                       [.focusWindow(position: CGPoint(x: 500, y: 500))])
        XCTAssertEqual(recognizer.process(pinch(140, at: 1.1)), [.zoom(steps: 1)])
    }
}

/// Where a zoom is sent.
final class ZoomRoutingTests: XCTestCase {

    // It is not a scroll, however much it looks like one. Sending it as ⌘ with
    // a scroll was tried first and measured: the browser read it as a plain
    // scroll and ran to the top of the page, both with the flag set on the
    // event and with Command genuinely held down.
    func testZoomGoesToTheKeyboardAndNothingElseDoes() {
        let mouse = RecordingEventEmitter()
        let scroll = RecordingEventEmitter()
        let keyboard = RecordingEventEmitter()
        let router = RoutingEventEmitter(mouse: mouse, scroll: scroll, keyboard: keyboard)

        router.emit(.zoom(steps: 2))
        router.emit(.scroll(deltaX: 0, deltaY: 5))
        router.emit(.tap(position: .zero))

        XCTAssertEqual(keyboard.actions, [.zoom(steps: 2)])
        XCTAssertEqual(scroll.actions, [.scroll(deltaX: 0, deltaY: 5)])
        XCTAssertEqual(mouse.actions, [.tap(position: .zero)])
    }
}
