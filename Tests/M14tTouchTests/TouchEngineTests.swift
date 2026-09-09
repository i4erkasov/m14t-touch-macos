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

    /// One drag per frame that moves — the recognizer's rule, independent of how
    /// often the driver publishes.
    ///
    /// Since v0.2 the driver batches a report into a single frame, so a diagonal
    /// movement now arrives as one frame carrying both axes and produces one
    /// drag. Before batching the same movement arrived as two frames, the first
    /// carrying a new X against the previous Y, and produced two drags through
    /// an intermediate point that the finger never visited.
    func testAMatchedCoordinatePairProducesOneDrag() {
        let (engine, emitter) = makeMousePipeline()
        engine.process(frame(100, 100, touching: true))   // contact
        engine.process(frame(200, 300, touching: true))   // one report, both axes

        XCTAssertEqual(emitter.actions, [
            .dragBegin(position: CGPoint(x: 100, y: 100)),
            .dragMove(position: CGPoint(x: 200, y: 300)),
        ])
    }

    /// The unbatched cadence still has to work: a panel that does not mark
    /// report boundaries falls back to a frame per value, and the recognizer
    /// must behave sensibly there too — each frame that moves far enough drags.
    func testUnbatchedFramesEachDragSeparately() {
        let (engine, emitter) = makeMousePipeline()
        engine.process(frame(100, 100, touching: true))
        engine.process(frame(200, 100, touching: true))   // X only
        engine.process(frame(200, 300, touching: true))   // then Y

        XCTAssertEqual(emitter.actions, [
            .dragBegin(position: CGPoint(x: 100, y: 100)),
            .dragMove(position: CGPoint(x: 200, y: 100)),
            .dragMove(position: CGPoint(x: 200, y: 300)),
        ])
    }

    /// A held finger sends only ScanTime, so the driver publishes frames that
    /// repeat the last position. They must stay silent in mouse mode — the tick
    /// exists for the v0.2 long-press deadline, not to generate events.
    func testRepeatedFramesAtTheSamePositionEmitNothing() {
        let (engine, emitter) = makeMousePipeline()
        engine.process(frame(100, 100, touching: true))
        emitter.reset()

        for _ in 0..<10 {
            engine.process(frame(100, 100, touching: true))
        }
        XCTAssertEqual(emitter.actions, [])
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
