import XCTest
import CoreGraphics
@testable import M14tTouch

final class CoordinateMapperTests: XCTestCase {

    // A 1920×1080 display at the origin, calibrated to the M14t's real range
    // discovered during development (X 1–12371, Y 1–6959).
    private func makeMapper(invertX: Bool = false, invertY: Bool = false) -> CoordinateMapper {
        CoordinateMapper(
            calibration: CalibrationData(xMin: 0, xMax: 12000, yMin: 0, yMax: 7000),
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            invertX: invertX,
            invertY: invertY
        )
    }

    func testTopLeftMapsToOrigin() {
        let p = makeMapper().map(rawX: 0, rawY: 0)
        XCTAssertEqual(p.x, 0, accuracy: 0.5)
        XCTAssertEqual(p.y, 0, accuracy: 0.5)
    }

    func testBottomRightMapsToFarCorner() {
        let p = makeMapper().map(rawX: 12000, rawY: 7000)
        XCTAssertEqual(p.x, 1920, accuracy: 0.5)
        XCTAssertEqual(p.y, 1080, accuracy: 0.5)
    }

    func testCenterMapsToCenter() {
        let p = makeMapper().map(rawX: 6000, rawY: 3500)
        XCTAssertEqual(p.x, 960, accuracy: 0.5)
        XCTAssertEqual(p.y, 540, accuracy: 0.5)
    }

    func testOutOfRangeIsClamped() {
        let p = makeMapper().map(rawX: 99999, rawY: -50)
        XCTAssertEqual(p.x, 1920, accuracy: 0.5) // clamped to right edge
        XCTAssertEqual(p.y, 0, accuracy: 0.5)    // clamped to top edge
    }

    func testInvertXMirrorsHorizontally() {
        let p = makeMapper(invertX: true).map(rawX: 0, rawY: 3500)
        XCTAssertEqual(p.x, 1920, accuracy: 0.5)
    }

    func testInvertYMirrorsVertically() {
        let p = makeMapper(invertY: true).map(rawX: 6000, rawY: 0)
        XCTAssertEqual(p.y, 1080, accuracy: 0.5)
    }

    func testDisplayOffsetIsApplied() {
        // Secondary display positioned to the right of a 1440-wide main display.
        var mapper = makeMapper()
        mapper.displayBounds = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let p = mapper.map(rawX: 0, rawY: 0)
        XCTAssertEqual(p.x, 1440, accuracy: 0.5) // origin lands at the display's left edge
    }

    func testDegenerateCalibrationDoesNotCrash() {
        var mapper = makeMapper()
        mapper.calibration = CalibrationData(xMin: 5, xMax: 5, yMin: 0, yMax: 0)
        let p = mapper.map(rawX: 5, rawY: 0)
        XCTAssertEqual(p.x, mapper.displayBounds.minX, accuracy: 0.5)
    }
}

final class ArgumentParserTests: XCTestCase {

    func testDefaultsWhenEmpty() {
        guard case .run(let config) = ArgumentParser.parse([]) else {
            return XCTFail("expected .run")
        }
        // No display named, so nothing is pinned: resolution picks the first
        // external one. The hardcoded index 1 that used to be asserted here is
        // exactly what spec §32 forbids.
        XCTAssertEqual(config.display, .automatic)
        XCTAssertFalse(config.autoCalibrate)
        XCTAssertTrue(config.promptForAccessibility)
    }

    func testDisplayIndexParsed() {
        guard case .run(let config) = ArgumentParser.parse(["--display", "2"]) else {
            return XCTFail("expected .run")
        }
        XCTAssertEqual(config.display.index, 2)
    }

    func testManualCalibrationFlags() {
        let args = ["--x-min", "1", "--x-max", "12371", "--y-min", "1", "--y-max", "6959"]
        guard case .run(let config) = ArgumentParser.parse(args) else {
            return XCTFail("expected .run")
        }
        XCTAssertEqual(config.manualXMax, 12371)
        XCTAssertTrue(config.hasManualCalibration)
    }

    func testNoAccessibilityPromptParsed() {
        guard case .run(let config) = ArgumentParser.parse(["--no-accessibility-prompt"]) else {
            return XCTFail("expected .run")
        }
        XCTAssertFalse(config.promptForAccessibility)
    }

    func testModeDefaultsToMouse() {
        guard case .run(let config) = ArgumentParser.parse([]) else {
            return XCTFail("expected a run outcome")
        }
        XCTAssertEqual(config.mode, .mouse)
    }

    func testModeIsParsed() {
        guard case .run(let config) = ArgumentParser.parse(["--mode", "touchscreen"]) else {
            return XCTFail("expected a run outcome")
        }
        XCTAssertEqual(config.mode, .touchscreen)
    }

    // Parsing accepts an unimplemented mode; availability is decided in one
    // place, TouchMode.makeRecognizer, so the two cannot drift apart.
    func testUnknownModeIsAnErrorNamingTheValidOnes() {
        guard case .error(let message) = ArgumentParser.parse(["--mode", "wiggle"]) else {
            return XCTFail("expected an error outcome")
        }
        XCTAssertTrue(message.contains("wiggle"))
        XCTAssertTrue(message.contains("mouse"))
        XCTAssertTrue(message.contains("touchscreen"))
    }

    func testModeWithoutAValueIsAnError() {
        guard case .error = ArgumentParser.parse(["--mode"]) else {
            return XCTFail("expected an error outcome")
        }
    }

    func testHelpRecognized() {
        guard case .help = ArgumentParser.parse(["--help"]) else {
            return XCTFail("expected .help")
        }
    }

    func testUnknownOptionIsError() {
        guard case .error = ArgumentParser.parse(["--nope"]) else {
            return XCTFail("expected .error")
        }
    }

    func testMissingDisplayValueIsError() {
        guard case .error = ArgumentParser.parse(["--display"]) else {
            return XCTFail("expected .error")
        }
    }
}

final class ObservedRangeTests: XCTestCase {

    func testLearnsZeroValuedEdges() {
        var observed = ObservedRange()

        XCTAssertTrue(observed.update(x: 0, y: 0))
        XCTAssertNil(observed.snapshot())
        XCTAssertTrue(observed.update(x: 12000, y: 7000))

        XCTAssertEqual(
            observed.snapshot(),
            CalibrationData(xMin: 0, xMax: 12000, yMin: 0, yMax: 7000)
        )
    }

    func testFreshRangeCanLearnBoundsInsideDescriptorRange() {
        var observed = ObservedRange()

        XCTAssertTrue(observed.update(x: 1, y: 1))
        XCTAssertTrue(observed.update(x: 12371, y: 6959))

        XCTAssertEqual(
            observed.snapshot(),
            CalibrationData(xMin: 1, xMax: 12371, yMin: 1, yMax: 6959)
        )
    }
}
