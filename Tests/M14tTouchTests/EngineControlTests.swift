import XCTest
import CoreGraphics
@testable import M14tTouch

/// Covers what the menu's controls do to a running pipeline. The menu itself is
/// AppKit and untested; what matters is that switching touch off or changing
/// mode mid-gesture leaves nothing held.
final class EngineControlTests: XCTestCase {

    private func makePipeline() -> (TouchEngine, RecordingEventEmitter) {
        let emitter = RecordingEventEmitter()
        let engine = TouchEngine(
            recognizer: MouseModeRecognizer(dragThreshold: 1.5),
            emitter: emitter
        )
        return (engine, emitter)
    }

    private func frame(_ x: CGFloat, _ y: CGFloat, touching: Bool) -> TouchFrame {
        TouchFrame(contact: TouchPoint(
            id: TouchPoint.primary,
            position: CGPoint(x: x, y: y),
            rawPosition: .zero,
            isTouching: touching,
            pressure: nil,
            timestamp: 0
        ))
    }

    // MARK: - Enable

    func testDisablingStopsTranslation() {
        let (engine, emitter) = makePipeline()
        engine.setEnabled(false)
        engine.process(frame(100, 100, touching: true))
        engine.process(frame(200, 200, touching: true))
        XCTAssertEqual(emitter.actions, [])
    }

    // Switching off mid-drag must give the button back. Freezing the gesture
    // would leave it held with no finger and no way to release it.
    func testDisablingMidGestureReleasesWhatIsHeld() {
        let (engine, emitter) = makePipeline()
        engine.process(frame(100, 100, touching: true))
        emitter.reset()

        engine.setEnabled(false)
        XCTAssertEqual(emitter.actions, [.dragEnd(position: CGPoint(x: 100, y: 100))])
    }

    func testEnablingAgainResumesTranslation() {
        let (engine, emitter) = makePipeline()
        engine.setEnabled(false)
        engine.setEnabled(true)
        emitter.reset()

        engine.process(frame(100, 100, touching: true))
        XCTAssertEqual(emitter.actions, [.dragBegin(position: CGPoint(x: 100, y: 100))])
    }

    // The finger that was down when translation stopped is long gone by the time
    // it resumes, so the next contact has to start a fresh gesture.
    func testResumingStartsAFreshGesture() {
        let (engine, emitter) = makePipeline()
        engine.process(frame(100, 100, touching: true))
        engine.setEnabled(false)
        engine.setEnabled(true)
        emitter.reset()

        engine.process(frame(500, 500, touching: true))
        XCTAssertEqual(emitter.actions, [.dragBegin(position: CGPoint(x: 500, y: 500))])
    }

    func testTogglingToTheSameValueChangesNothing() {
        let (engine, emitter) = makePipeline()
        engine.process(frame(100, 100, touching: true))
        emitter.reset()

        engine.setEnabled(true)     // already on
        XCTAssertEqual(emitter.actions, [])
    }

    // MARK: - Mode

    func testSwitchingModeReleasesWhatTheOldOneHeld() {
        let (engine, emitter) = makePipeline()
        engine.process(frame(100, 100, touching: true))
        emitter.reset()

        engine.setRecognizer(TouchscreenRecognizer(configuration: GestureConfiguration()))
        XCTAssertEqual(emitter.actions, [.dragEnd(position: CGPoint(x: 100, y: 100))])
    }

    func testTheNewRecognizerTakesOver() {
        let (engine, emitter) = makePipeline()
        var configuration = GestureConfiguration()
        configuration.restoreCursor = false
        engine.setRecognizer(TouchscreenRecognizer(configuration: configuration))
        emitter.reset()

        // Touchscreen mode commits to nothing on contact, unlike mouse mode.
        engine.process(frame(100, 100, touching: true))
        XCTAssertEqual(emitter.actions, [])
    }
}
