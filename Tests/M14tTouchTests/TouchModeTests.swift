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
        config.dragThreshold = 9
        let recognizer = TouchMode.mouse.makeRecognizer(config: config) as? MouseModeRecognizer
        XCTAssertEqual(recognizer?.dragThreshold, 9)
    }

    // Should fail the moment v0.2 implements it — at which point this test is
    // replaced rather than deleted, and main.swift's guard becomes dead code.
    func testTouchscreenModeIsNotAvailableYet() {
        XCTAssertNil(TouchMode.touchscreen.makeRecognizer(config: TouchConfig()))
    }
}
