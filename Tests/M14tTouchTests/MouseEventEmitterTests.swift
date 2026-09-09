import XCTest
import CoreGraphics
@testable import M14tTouch

/// Covers the action → mouse event mapping. Posting itself is untested by
/// design: exercising it would move the real cursor, so `MouseEventEmitter`
/// keeps the decision in a pure function and delegates the CoreGraphics call.
final class MouseEventEmitterTests: XCTestCase {

    private let point = CGPoint(x: 640, y: 480)

    // The drag triad is the whole of v0.1 — it reproduces the original driver's
    // touch model, so these three assertions are the behaviour contract.
    func testDragBeginIsAPress() {
        let event = MouseEventEmitter.mouseEvent(for: .dragBegin(position: point))
        XCTAssertEqual(event?.type, .leftMouseDown)
        XCTAssertEqual(event?.point, point)
    }

    func testDragMoveIsADrag() {
        let event = MouseEventEmitter.mouseEvent(for: .dragMove(position: point))
        XCTAssertEqual(event?.type, .leftMouseDragged)
        XCTAssertEqual(event?.point, point)
    }

    func testDragEndIsARelease() {
        let event = MouseEventEmitter.mouseEvent(for: .dragEnd(position: point))
        XCTAssertEqual(event?.type, .leftMouseUp)
        XCTAssertEqual(event?.point, point)
    }

    // Unhandled on purpose, not by omission: scroll belongs to a future
    // ScrollEventEmitter (spec §23), and the rest wait on the v0.2 cursor
    // policy decision (spec §10). If v0.2 implements one of these, the
    // corresponding assertion here should fail and be replaced.
    func testActionsNotYetImplementedAreNotMapped() {
        XCTAssertNil(MouseEventEmitter.mouseEvent(for: .tap(position: point)))
        XCTAssertNil(MouseEventEmitter.mouseEvent(for: .pointerMove(position: point)))
        XCTAssertNil(MouseEventEmitter.mouseEvent(for: .rightClick(position: point)))
        XCTAssertNil(MouseEventEmitter.mouseEvent(for: .scroll(deltaX: 1, deltaY: 2)))
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
