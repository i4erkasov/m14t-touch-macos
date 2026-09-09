import XCTest
import CoreGraphics
@testable import M14tTouch

/// Covers the action → mouse event mapping. Posting itself is untested by
/// design: exercising it would move the real cursor, so `MouseEventEmitter`
/// keeps the decision in a pure function and delegates the CoreGraphics call.
final class MouseEventEmitterTests: XCTestCase {

    private let point = CGPoint(x: 640, y: 480)

    private func types(for action: InputAction) -> [CGEventType] {
        MouseEventEmitter.mouseEvents(for: action).map(\.type)
    }

    // The drag triad reproduces the original driver's touch model, so these
    // three assertions are the behaviour contract mouse mode has to keep.
    func testDragBeginIsAPress() {
        let events = MouseEventEmitter.mouseEvents(for: .dragBegin(position: point))
        XCTAssertEqual(events.map(\.type), [.leftMouseDown])
        XCTAssertEqual(events.first?.point, point)
    }

    func testDragMoveIsADrag() {
        XCTAssertEqual(types(for: .dragMove(position: point)), [.leftMouseDragged])
    }

    func testDragEndIsARelease() {
        XCTAssertEqual(types(for: .dragEnd(position: point)), [.leftMouseUp])
    }

    // A tap is press and release at one point, emitted back to back: in
    // touchscreen mode a tap is only known to be one once the finger has left,
    // so there is no moment at which a button could be held.
    func testTapIsAPressAndReleaseAtOnePoint() {
        let events = MouseEventEmitter.mouseEvents(for: .tap(position: point))
        XCTAssertEqual(events.map(\.type), [.leftMouseDown, .leftMouseUp])
        XCTAssertEqual(events.map(\.point), [point, point])
    }

    // Placing the cursor before a scroll, which has no destination of its own.
    // A move event rather than a warp, so applications update hover state.
    func testPointerMoveIsAMouseMove() {
        XCTAssertEqual(types(for: .pointerMove(position: point)), [.mouseMoved])
    }

    // Unhandled on purpose: scroll belongs to ScrollEventEmitter and is routed
    // there, and rightClick waits for two-finger gestures (spec §11).
    func testScrollAndRightClickAreNotThisEmittersBusiness() {
        XCTAssertTrue(MouseEventEmitter.mouseEvents(for: .scroll(deltaX: 1, deltaY: 2)).isEmpty)
        XCTAssertTrue(MouseEventEmitter.mouseEvents(for: .rightClick(position: point)).isEmpty)
    }

    func testRecordingEmitterKeepsActionsInOrder() {
        let emitter = RecordingEventEmitter()
        emitter.emit(.dragBegin(position: point))
        emitter.emit(.dragMove(position: point))
        emitter.emit(.dragEnd(position: point))
        XCTAssertEqual(emitter.actions, [
            .dragBegin(position: point),
            .dragMove(position: point),
            .dragEnd(position: point),
        ])
    }
}
