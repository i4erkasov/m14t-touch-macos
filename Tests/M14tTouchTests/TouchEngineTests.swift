import XCTest
import CoreGraphics
@testable import M14tTouch

/// Covers the wiring itself, and then the pipeline end to end.
///
/// The sequence test is the closest thing to a regression test for step 4 that
/// is possible without an M14t: it replays the order in which the device reports
/// values and asserts the actions the original driver would have posted.
final class TouchEngineTests: XCTestCase {

    /// Returns canned actions so the engine's forwarding can be observed
    /// independently of any real gesture logic.
    private struct StubRecognizer: GestureRecognizer {
        let processResult: [InputAction]
        let resetResult: [InputAction]
        func process(_ frame: TouchFrame) -> [InputAction] { processResult }
        func reset() -> [InputAction] { resetResult }
    }

    private let point = CGPoint(x: 10, y: 20)

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

    // MARK: - Forwarding

    func testProcessForwardsEveryActionToTheEmitter() {
        let emitter = RecordingEventEmitter()
        let engine = TouchEngine(
            recognizer: StubRecognizer(
                processResult: [.dragBegin(position: point), .dragMove(position: point)],
                resetResult: []
            ),
            emitter: emitter
        )
        engine.process(frame(0, 0, touching: true))
        XCTAssertEqual(emitter.actions, [.dragBegin(position: point), .dragMove(position: point)])
    }

    func testResetForwardsToTheEmitter() {
        let emitter = RecordingEventEmitter()
        let engine = TouchEngine(
            recognizer: StubRecognizer(processResult: [], resetResult: [.dragEnd(position: point)]),
            emitter: emitter
        )
        engine.reset()
        XCTAssertEqual(emitter.actions, [.dragEnd(position: point)])
    }

    // The driver logs what was emitted, so the return value has to carry it.
    func testProcessReturnsTheEmittedActionsForLogging() {
        let engine = TouchEngine(
            recognizer: StubRecognizer(processResult: [.dragBegin(position: point)], resetResult: []),
            emitter: RecordingEventEmitter()
        )
        XCTAssertEqual(engine.process(frame(0, 0, touching: true)), [.dragBegin(position: point)])
    }

    // MARK: - Pipeline

    private func makeMousePipeline() -> (TouchEngine, RecordingEventEmitter) {
        let emitter = RecordingEventEmitter()
        let engine = TouchEngine(
            recognizer: MouseModeRecognizer(dragThreshold: 1.5),
            emitter: emitter
        )
        return (engine, emitter)
    }

    /// A stationary press and release, in the order the device reports values:
    /// TipSwitch first, then the coordinates that accompany it.
    func testTapProducesExactlyAPressAndRelease() {
        let (engine, emitter) = makeMousePipeline()
        engine.process(frame(100, 100, touching: true))   // TipSwitch 1
        engine.process(frame(100, 100, touching: true))   // X
        engine.process(frame(100, 100, touching: true))   // Y
        engine.process(frame(100, 100, touching: false))  // TipSwitch 0

        XCTAssertEqual(emitter.actions, [
            .dragBegin(position: CGPoint(x: 100, y: 100)),
            .dragEnd(position: CGPoint(x: 100, y: 100)),
        ])
    }

    /// Each axis arrives as its own value, so a frame carries a new X against
    /// the previous Y. Both frames cross the threshold here, so both drag —
    /// which is what the pre-refactor driver did, one `emitDragIfMoved` per axis.
    func testEachAxisValueDragsIndependently() {
        let (engine, emitter) = makeMousePipeline()
        engine.process(frame(100, 100, touching: true))   // TipSwitch 1
        engine.process(frame(200, 100, touching: true))   // X moves
        engine.process(frame(200, 300, touching: true))   // Y moves

        XCTAssertEqual(emitter.actions, [
            .dragBegin(position: CGPoint(x: 100, y: 100)),
            .dragMove(position: CGPoint(x: 200, y: 100)),
            .dragMove(position: CGPoint(x: 200, y: 300)),
        ])
    }

    /// A TipSwitch repeated at an unchanged position must stay silent.
    ///
    /// The pre-refactor driver ignored a redundant TipSwitch outright, whereas
    /// every value now produces a frame — so this is where an extra event would
    /// appear if the two ever diverged.
    func testRedundantContactValueEmitsNothing() {
        let (engine, emitter) = makeMousePipeline()
        engine.process(frame(100, 100, touching: true))
        engine.process(frame(200, 100, touching: true))
        emitter.reset()

        engine.process(frame(200, 100, touching: true))   // TipSwitch 1 again
        XCTAssertEqual(emitter.actions, [])
    }

    /// Unplugged mid-drag: the release has to be synthesised or the button stays
    /// down with no finger left to lift it.
    func testUnplugMidDragReleasesAtTheLastEmittedPoint() {
        let (engine, emitter) = makeMousePipeline()
        engine.process(frame(100, 100, touching: true))
        engine.process(frame(200, 200, touching: true))
        emitter.reset()

        engine.reset()
        XCTAssertEqual(emitter.actions, [.dragEnd(position: CGPoint(x: 200, y: 200))])
    }
}
