import CoreGraphics
import XCTest
@testable import M14tTouch

/// Three fingers travelling together.
///
/// One gesture, not four. The others a trackpad offers run macOS's own
/// shortcuts, and those do not answer a synthesised keystroke — measured both
/// with the modifier flagged on the event and with the key genuinely held.
/// Opening Mission Control as an application is the route that works.
final class SwipeTests: XCTestCase {

    private var configuration: GestureConfiguration {
        var configuration = GestureConfiguration()
        configuration.threeFingerSwipe = true
        configuration.swipeThreshold = 100
        configuration.restoreCursor = false
        return configuration
    }

    /// Three fingers whose middle is at `y`, spread across the panel.
    private func three(y: CGFloat, at time: TimeInterval = 0, count: Int = 3) -> TouchFrame {
        let contacts = (0..<count).map { index in
            TouchPoint(
                id: index * 2,
                position: CGPoint(x: 400 + CGFloat(index) * 100, y: y),
                rawPosition: .zero,
                isTouching: true,
                pressure: nil,
                timestamp: time
            )
        }
        return TouchFrame(contacts: contacts, timestamp: time)
    }

    func testSwipingUpPastTheThresholdShowsEveryWindow() {
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        XCTAssertEqual(recognizer.process(three(y: 800)), [])
        XCTAssertEqual(recognizer.process(three(y: 690, at: 0.1)), [.showAllWindows])
    }

    // Screen coordinates put the origin at the top, so up is *decreasing* y.
    // Getting this backwards is the likeliest mistake here, and it would fire
    // on exactly the wrong gesture.
    func testSwipingDownDoesNothing() {
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(three(y: 400))
        XCTAssertEqual(recognizer.process(three(y: 700, at: 0.1)), [])
    }

    func testASmallMovementIsNotASwipe() {
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(three(y: 800))
        XCTAssertEqual(recognizer.process(three(y: 740, at: 0.1)), [])
    }

    // Once per gesture, not once per frame. Mission Control opening sixty times
    // a second is not what anyone meant.
    func testItFiresOnceHoweverFarTheFingersKeepGoing() {
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(three(y: 900))
        XCTAssertEqual(recognizer.process(three(y: 700, at: 0.1)), [.showAllWindows])
        XCTAssertEqual(recognizer.process(three(y: 500, at: 0.2)), [])
        XCTAssertEqual(recognizer.process(three(y: 300, at: 0.3)), [])
    }

    func testTwoFingersAreNotThree() {
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(three(y: 800, count: 2))
        let actions = recognizer.process(three(y: 600, at: 0.1, count: 2))
        XCTAssertFalse(actions.contains(.showAllWindows))
    }

    // Lifting back to two fingers must not turn the tail of a swipe into a
    // zoom, and lifting to one must not turn it into a scroll.
    func testWhatIsLeftBehindInheritsNothing() {
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(three(y: 900))
        _ = recognizer.process(three(y: 700, at: 0.1))

        XCTAssertEqual(recognizer.process(three(y: 700, at: 0.2, count: 2)), [])
        XCTAssertEqual(recognizer.process(three(y: 300, at: 0.3, count: 2)), [])

        let one = TouchFrame(contact: TouchPoint(
            id: 0, position: CGPoint(x: 400, y: 100), rawPosition: .zero,
            isTouching: true, pressure: nil, timestamp: 0.4
        ))
        XCTAssertEqual(recognizer.process(one), [])
    }

    func testANewGestureWorksAfterASwipe() {
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(three(y: 900))
        _ = recognizer.process(three(y: 700, at: 0.1))

        let lift = TouchFrame(contact: TouchPoint(
            id: 0, position: CGPoint(x: 400, y: 700), rawPosition: .zero,
            isTouching: false, pressure: nil, timestamp: 0.5
        ))
        _ = recognizer.process(lift)

        let down = TouchFrame(contact: TouchPoint(
            id: 0, position: CGPoint(x: 300, y: 300), rawPosition: .zero,
            isTouching: true, pressure: nil, timestamp: 1.0
        ))
        _ = recognizer.process(down)
        let up = TouchFrame(contact: TouchPoint(
            id: 0, position: CGPoint(x: 300, y: 300), rawPosition: .zero,
            isTouching: false, pressure: nil, timestamp: 1.05
        ))
        XCTAssertEqual(recognizer.process(up), [.tap(position: CGPoint(x: 300, y: 300))])
    }

    func testTurningItOffLeavesThreeFingersAlone() {
        var configuration = self.configuration
        configuration.threeFingerSwipe = false
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(three(y: 900))
        XCTAssertFalse(recognizer.process(three(y: 600, at: 0.1)).contains(.showAllWindows))
    }

    func testItIsOnByDefault() {
        XCTAssertTrue(GestureConfiguration().threeFingerSwipe)
        XCTAssertGreaterThan(GestureConfiguration().swipeThreshold, 0)
    }

    func testTheActionGoesToTheWorkspaceAndNowhereElse() {
        let mouse = RecordingEventEmitter()
        let scroll = RecordingEventEmitter()
        let keyboard = RecordingEventEmitter()
        let workspace = RecordingEventEmitter()
        let router = RoutingEventEmitter(
            mouse: mouse, scroll: scroll, keyboard: keyboard, workspace: workspace
        )

        router.emit(.showAllWindows)

        XCTAssertEqual(workspace.actions, [.showAllWindows])
        XCTAssertTrue(mouse.actions.isEmpty)
        XCTAssertTrue(scroll.actions.isEmpty)
        XCTAssertTrue(keyboard.actions.isEmpty)
    }
}
