import XCTest
@testable import M14tTouch

/// Covers the gesture-tuning flags. The values themselves are guesses to be
/// tuned on the panel (v0.2 step 8); what is pinned here is that the flags
/// reach the right field, in the right unit, and that nonsense is refused.
final class GestureConfigurationTests: XCTestCase {

    private func parse(_ arguments: [String], file: StaticString = #filePath, line: UInt = #line) -> GestureConfiguration? {
        guard case .run(let config) = ArgumentParser.parse(arguments) else {
            XCTFail("expected a run outcome", file: file, line: line)
            return nil
        }
        return config.gestures
    }

    private func errorMessage(_ arguments: [String], file: StaticString = #filePath, line: UInt = #line) -> String? {
        guard case .error(let message) = ArgumentParser.parse(arguments) else {
            XCTFail("expected an error outcome", file: file, line: line)
            return nil
        }
        return message
    }

    func testDefaultsMatchTheSpecStartingPoints() {
        let gestures = GestureConfiguration()
        XCTAssertEqual(gestures.scrollThreshold, 10)
        XCTAssertEqual(gestures.scrollSensitivity, 1)
        XCTAssertEqual(gestures.longPressDelay, 0.4)   // spec §8
        XCTAssertEqual(gestures.dragThreshold, 1.5)    // unchanged from v0.1
        XCTAssertTrue(gestures.naturalScroll)
    }

    // Durations are given in milliseconds and stored in seconds. Getting this
    // backwards would make a long press fire after 400 seconds, or instantly.
    func testDurationFlagsAreMillisecondsAndStoredAsSeconds() {
        XCTAssertEqual(parse(["--long-press", "250"])?.longPressDelay, 0.25)
    }

    func testPixelAndMultiplierFlagsAreTakenAsGiven() {
        XCTAssertEqual(parse(["--scroll-threshold", "20"])?.scrollThreshold, 20)
        XCTAssertEqual(parse(["--scroll-sensitivity", "2.5"])?.scrollSensitivity, 2.5)
        XCTAssertEqual(parse(["--drag-threshold", "3"])?.dragThreshold, 3)
    }

    func testNaturalScrollCanBeTurnedOffAndBackOn() {
        XCTAssertEqual(parse(["--no-natural-scroll"])?.naturalScroll, false)
        XCTAssertEqual(parse(["--no-natural-scroll", "--natural-scroll"])?.naturalScroll, true)
    }

    // A negative threshold would make every contact instantly exceed it.
    func testNegativeValuesAreRefused() {
        XCTAssertNotNil(errorMessage(["--long-press", "-5"]))
        XCTAssertNotNil(errorMessage(["--drag-threshold", "-2"]))
    }

    // Zero sensitivity would silently disable scrolling rather than fail.
    func testZeroSensitivityIsRefused() {
        XCTAssertNotNil(errorMessage(["--scroll-sensitivity", "0"]))
    }

    func testMissingValueIsRefused() {
        XCTAssertNotNil(errorMessage(["--scroll-threshold"]))
    }
}
