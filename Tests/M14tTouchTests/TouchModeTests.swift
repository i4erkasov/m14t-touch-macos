import XCTest
@testable import M14tTouch

/// The seam v0.1 exists to build. These assertions are what "the architecture
/// allows adding a touchscreen mode" means concretely (spec §28).
final class TouchModeTests: XCTestCase {

    func testMouseModeProducesTheMouseRecognizer() {
        let recognizer = TouchMode.mouse.makeRecognizer(config: TouchConfig())
        XCTAssertTrue(recognizer is MouseModeRecognizer)
    }

    func testTheRecognizerTakesItsThresholdFromTheConfig() {
        var config = TouchConfig()
        config.gestures.dragThreshold = 9
        let recognizer = TouchMode.mouse.makeRecognizer(config: config) as? MouseModeRecognizer
        XCTAssertEqual(recognizer?.dragThreshold, 9)
    }

    func testTouchscreenModeProducesTheTouchscreenRecognizer() {
        let recognizer = TouchMode.touchscreen.makeRecognizer(config: TouchConfig())
        XCTAssertTrue(recognizer is TouchscreenRecognizer)
    }

    func testTheTouchscreenRecognizerTakesTheGestureConfiguration() {
        var config = TouchConfig()
        config.gestures.longPressDelay = 0.9
        let recognizer = TouchMode.touchscreen.makeRecognizer(config: config) as? TouchscreenRecognizer
        XCTAssertEqual(recognizer?.configuration.longPressDelay, 0.9)
    }
}
