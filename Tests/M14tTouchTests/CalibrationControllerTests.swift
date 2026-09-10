import XCTest
@testable import M14tTouch

/// Covers the precedence rule — manual flags > saved file > HID descriptor —
/// and auto-calibration. Getting precedence wrong sends every touch to the
/// wrong place, and on this hardware the descriptor is the least trustworthy
/// of the three sources.
final class CalibrationControllerTests: XCTestCase {

    private let descriptor = CalibrationData(xMin: 0, xMax: 12372, yMin: 0, yMax: 6960)
    private let saved      = CalibrationData(xMin: 92, xMax: 12288, yMin: 1, yMax: 6854)

    private func makeController(
        _ configure: (inout TouchConfig) -> Void = { _ in },
        persist: @escaping (CalibrationData, DisplayIdentity?) -> Void = { _, _ in }
    ) -> CalibrationController {
        var config = TouchConfig()
        configure(&config)
        return CalibrationController(config: config, persist: persist)
    }

    // MARK: - Precedence

    func testDescriptorIsUsedWhenNothingElseIsAvailable() {
        let outcome = makeController().resolve(descriptorRange: descriptor, saved: nil)
        XCTAssertEqual(outcome.calibration, descriptor)
        XCTAssertEqual(outcome.source, .descriptor)
    }

    func testSavedCalibrationBeatsTheDescriptor() {
        let outcome = makeController().resolve(descriptorRange: descriptor, saved: saved)
        XCTAssertEqual(outcome.calibration, saved)
        XCTAssertEqual(outcome.source, .saved)
    }

    func testManualBoundsBeatTheSavedCalibration() {
        let controller = makeController { $0.manualXMin = 5; $0.manualXMax = 500 }
        let outcome = controller.resolve(descriptorRange: descriptor, saved: saved)
        XCTAssertEqual(outcome.calibration.xMin, 5)
        XCTAssertEqual(outcome.calibration.xMax, 500)
        XCTAssertEqual(outcome.source, .manual)
    }

    // Worth pinning down because it surprises: a partial manual override does
    // not fall back to the saved file for the axis it leaves alone. Any manual
    // bound discards the saved calibration entirely, so the untouched axis comes
    // from the descriptor.
    func testPartialManualBoundsTakeTheRestFromTheDescriptorNotTheSavedFile() {
        let controller = makeController { $0.manualXMin = 5 }
        let outcome = controller.resolve(descriptorRange: descriptor, saved: saved)
        XCTAssertEqual(outcome.calibration.xMin, 5)
        XCTAssertEqual(outcome.calibration.yMin, descriptor.yMin)
        XCTAssertEqual(outcome.calibration.yMax, descriptor.yMax)
    }

    // --auto-calibrate means "learn fresh bounds", so yesterday's file must not
    // be adopted as the starting point.
    func testAutoCalibrationIgnoresTheSavedCalibration() {
        let controller = makeController { $0.autoCalibrate = true }
        let outcome = controller.resolve(descriptorRange: descriptor, saved: saved)
        XCTAssertEqual(outcome.calibration, descriptor)
        XCTAssertEqual(outcome.source, .descriptor)
    }

    // MARK: - Auto-calibration

    func testRecordingDoesNothingWhenAutoCalibrationIsOff() {
        let controller = makeController()
        XCTAssertNil(controller.record(x: 10))
        XCTAssertNil(controller.record(y: 4000))
    }

    func testRecordingWidensTheRangeAndPersistsIt() {
        var persisted: [CalibrationData] = []
        let controller = makeController({ $0.autoCalibrate = true }, persist: { calibration, _ in
            persisted.append(calibration)
        })

        _ = controller.record(x: 100)
        _ = controller.record(y: 200)
        _ = controller.record(x: 9000)
        let widened = controller.record(y: 5000)

        XCTAssertEqual(widened?.xMin, 100)
        XCTAssertEqual(widened?.xMax, 9000)
        XCTAssertEqual(widened?.yMin, 200)
        XCTAssertEqual(widened?.yMax, 5000)
        XCTAssertEqual(persisted.last, widened)
    }

    // Nothing is produced until *both* axes have spread — a single point, or
    // movement along one axis only, yields no calibration at all. So during
    // `--auto-calibrate` the mapping stays on the descriptor range until the
    // user has moved in both directions, which is why the instructions say to
    // touch all four corners rather than two.
    func testNoCalibrationIsProducedUntilBothAxesHaveSpread() {
        let controller = makeController { $0.autoCalibrate = true }
        XCTAssertNil(controller.record(x: 100))
        XCTAssertNil(controller.record(x: 9000))   // X has a range, Y still does not
        XCTAssertNil(controller.record(y: 200))
        XCTAssertNotNil(controller.record(y: 5000))
    }

    func testRecordingASampleInsideTheKnownRangeChangesNothing() {
        let controller = makeController { $0.autoCalibrate = true }
        _ = controller.record(x: 100)
        _ = controller.record(x: 9000)
        _ = controller.record(y: 10)
        _ = controller.record(y: 5000)
        XCTAssertNil(controller.record(x: 5000))
    }

    // Without auto-calibration the resolved calibration is whatever `resolve`
    // settled on, and stays put.
    func testCalibrationInForceTracksTheResolvedValue() {
        let controller = makeController()
        _ = controller.resolve(descriptorRange: descriptor, saved: saved)
        XCTAssertEqual(controller.calibration, saved)
    }
}
