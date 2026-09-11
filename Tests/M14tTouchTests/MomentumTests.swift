import CoreGraphics
import XCTest
@testable import M14tTouch

/// The glide after a flick.
///
/// macOS generates this for its own devices and not for a panel driven from
/// user space, so the deceleration is produced here — which means it is ours
/// to get wrong, and worth pinning.
final class MomentumTests: XCTestCase {

    // MARK: - The decay itself

    func testAGlideSlowsDownAndStops() {
        var momentum = ScrollMomentum(velocity: CGVector(dx: 0, dy: 2000))

        var steps: [CGFloat] = []
        while let step = momentum.next() { steps.append(step.dy) }

        XCTAssertFalse(steps.isEmpty)
        XCTAssertGreaterThan(steps[0], steps[steps.count / 2], "should be slowing")
        XCTAssertGreaterThan(steps[steps.count / 2], steps.last!)
    }

    // An exponential decay never reaches zero, so something else has to end it.
    func testAGlideEndsRatherThanFadingForever() {
        var momentum = ScrollMomentum(velocity: CGVector(dx: 0, dy: 3000))
        var ticks = 0
        while momentum.next() != nil {
            ticks += 1
            if ticks > 10_000 { return XCTFail("the glide never finished") }
        }
        // At sixty a second, a glide of a few seconds at most.
        XCTAssertLessThan(ticks, 300, "\(ticks) ticks is not a glide, it is a journey")
    }

    func testTheGlideGoesTheWayTheFingerWent() {
        var up = ScrollMomentum(velocity: CGVector(dx: 0, dy: 1000))
        var down = ScrollMomentum(velocity: CGVector(dx: 0, dy: -1000))
        XCTAssertGreaterThan(up.next()!.dy, 0)
        XCTAssertLessThan(down.next()!.dy, 0)
    }

    func testBothAxesGlideTogether() {
        var momentum = ScrollMomentum(velocity: CGVector(dx: 600, dy: -800))
        let step = momentum.next()!
        XCTAssertGreaterThan(step.dx, 0)
        XCTAssertLessThan(step.dy, 0)
    }

    // A finger that was placing the content rather than throwing it should stop
    // where it was put.
    func testASlowDragDoesNotGlide() {
        let crawling = ScrollMomentum(velocity: CGVector(dx: 0, dy: 10))
        XCTAssertFalse(crawling.isWorthGliding)

        let flicked = ScrollMomentum(velocity: CGVector(dx: 0, dy: 2000))
        XCTAssertTrue(flicked.isWorthGliding)
    }

    func testTheFirstStepIsAboutOneFrameOfTravel() {
        var momentum = ScrollMomentum(velocity: CGVector(dx: 0, dy: 600))
        // 600 points a second, a sixtieth of a second: ten points.
        XCTAssertEqual(momentum.next()!.dy, 10, accuracy: 0.5)
    }

    // MARK: - Deciding to glide at all

    private func recognizer() -> TouchscreenRecognizer {
        var configuration = GestureConfiguration()
        configuration.scrollMomentum = true
        configuration.restoreCursor = false
        configuration.scrollThreshold = 10
        return TouchscreenRecognizer(configuration: configuration)
    }

    private func frame(y: CGFloat, touching: Bool, at time: TimeInterval) -> TouchFrame {
        TouchFrame(contact: TouchPoint(
            id: 0,
            position: CGPoint(x: 500, y: y),
            rawPosition: CGPoint(x: 500, y: y),
            isTouching: touching,
            pressure: nil,
            timestamp: time
        ))
    }

    private func momentum(in actions: [InputAction]) -> CGVector? {
        for action in actions {
            if case .scrollMomentum(let velocity, _) = action { return velocity }
        }
        return nil
    }

    func testLiftingMidFlickGlides() {
        var recognizer = self.recognizer()
        _ = recognizer.process(frame(y: 900, touching: true, at: 0))
        _ = recognizer.process(frame(y: 800, touching: true, at: 0.02))
        _ = recognizer.process(frame(y: 700, touching: true, at: 0.04))
        _ = recognizer.process(frame(y: 600, touching: true, at: 0.06))

        let actions = recognizer.process(frame(y: 600, touching: false, at: 0.07))
        XCTAssertNotNil(momentum(in: actions), "a flick should glide")
    }

    // The failure this guards: frames in which nothing moved produce no delta
    // and never reach the speed estimate, so a finger that scrolled fast, then
    // rested, then lifted would have thrown the page across the screen at the
    // speed it had a second earlier.
    func testAFingerThatStopsBeforeLiftingDoesNotGlide() {
        var recognizer = self.recognizer()
        _ = recognizer.process(frame(y: 900, touching: true, at: 0))
        _ = recognizer.process(frame(y: 800, touching: true, at: 0.02))
        _ = recognizer.process(frame(y: 700, touching: true, at: 0.04))

        // Held still for half a second — the same position, so no deltas.
        _ = recognizer.process(frame(y: 700, touching: true, at: 0.3))
        _ = recognizer.process(frame(y: 700, touching: true, at: 0.5))

        let actions = recognizer.process(frame(y: 700, touching: false, at: 0.54))
        XCTAssertNil(momentum(in: actions), "a finger at rest was not throwing anything")
    }

    func testTheEndOfTheGestureComesBeforeTheGlide() {
        var recognizer = self.recognizer()
        _ = recognizer.process(frame(y: 900, touching: true, at: 0))
        _ = recognizer.process(frame(y: 700, touching: true, at: 0.02))

        let actions = recognizer.process(frame(y: 700, touching: false, at: 0.03))
        XCTAssertEqual(actions.first, .scrollEnd, "that is the order a trackpad sends them")
    }

    func testTurningMomentumOffStopsTheGlide() {
        var configuration = GestureConfiguration()
        configuration.scrollMomentum = false
        configuration.restoreCursor = false
        configuration.scrollThreshold = 10
        var recognizer = TouchscreenRecognizer(configuration: configuration)

        // Several moving frames: the first commits to scrolling and consumes
        // its own movement, so the speed is measured from the ones after it.
        _ = recognizer.process(frame(y: 900, touching: true, at: 0))
        _ = recognizer.process(frame(y: 800, touching: true, at: 0.02))
        _ = recognizer.process(frame(y: 700, touching: true, at: 0.04))
        _ = recognizer.process(frame(y: 600, touching: true, at: 0.06))
        let actions = recognizer.process(frame(y: 600, touching: false, at: 0.07))

        XCTAssertNil(momentum(in: actions))
        XCTAssertEqual(actions, [.scrollEnd])
    }

    // The bug this guards, reported from use: the pointer went home the moment
    // the finger lifted, while the glide carried on for another second — so the
    // flick happened on the panel and the scrolling happened on whatever window
    // the pointer had returned to.
    func testThePointerIsNotTakenHomeWhileTheGlideIsStillRunning() {
        var configuration = GestureConfiguration()
        configuration.scrollMomentum = true
        configuration.restoreCursor = true
        configuration.scrollThreshold = 10
        var recognizer = TouchscreenRecognizer(configuration: configuration)

        // Several moving frames: the first commits to scrolling and consumes
        // its own movement, so the speed is measured from the ones after it.
        _ = recognizer.process(frame(y: 900, touching: true, at: 0))
        _ = recognizer.process(frame(y: 800, touching: true, at: 0.02))
        _ = recognizer.process(frame(y: 700, touching: true, at: 0.04))
        _ = recognizer.process(frame(y: 600, touching: true, at: 0.06))
        let actions = recognizer.process(frame(y: 600, touching: false, at: 0.07))

        XCTAssertFalse(actions.contains(.cursorRestore), "the glide still needs the pointer")
        guard case .scrollMomentum(_, let restores)? = actions.last else {
            return XCTFail("expected a glide: \(actions)")
        }
        XCTAssertTrue(restores, "and it carries the instruction to put it back afterwards")
    }

    // Without a glide there is nothing to wait for, so it goes home at once.
    func testThePointerGoesHomeAtOnceWhenThereIsNoGlide() {
        var configuration = GestureConfiguration()
        configuration.scrollMomentum = false
        configuration.restoreCursor = true
        configuration.scrollThreshold = 10
        var recognizer = TouchscreenRecognizer(configuration: configuration)

        // Several moving frames: the first commits to scrolling and consumes
        // its own movement, so the speed is measured from the ones after it.
        _ = recognizer.process(frame(y: 900, touching: true, at: 0))
        _ = recognizer.process(frame(y: 800, touching: true, at: 0.02))
        _ = recognizer.process(frame(y: 700, touching: true, at: 0.04))
        _ = recognizer.process(frame(y: 600, touching: true, at: 0.06))
        let actions = recognizer.process(frame(y: 600, touching: false, at: 0.07))

        XCTAssertEqual(actions, [.scrollEnd, .cursorRestore])
    }

    // And a gesture that is not going to put the pointer back says so, rather
    // than leaving the emitter to guess.
    func testAGlideDoesNotRestoreWhenRestoringIsSwitchedOff() {
        var configuration = GestureConfiguration()
        configuration.scrollMomentum = true
        configuration.restoreCursor = false
        configuration.scrollThreshold = 10
        var recognizer = TouchscreenRecognizer(configuration: configuration)

        // Several moving frames: the first commits to scrolling and consumes
        // its own movement, so the speed is measured from the ones after it.
        _ = recognizer.process(frame(y: 900, touching: true, at: 0))
        _ = recognizer.process(frame(y: 800, touching: true, at: 0.02))
        _ = recognizer.process(frame(y: 700, touching: true, at: 0.04))
        _ = recognizer.process(frame(y: 600, touching: true, at: 0.06))
        let actions = recognizer.process(frame(y: 600, touching: false, at: 0.07))

        guard case .scrollMomentum(_, let restores)? = actions.last else {
            return XCTFail("expected a glide: \(actions)")
        }
        XCTAssertFalse(restores)
    }

    func testItIsOnByDefault() {
        XCTAssertTrue(GestureConfiguration().scrollMomentum)
    }
}
