import XCTest
@testable import M14tTouch

/// Round-trips calibration through a real file, in a temporary directory.
///
/// The store's location is injectable precisely so this can run: pointed at the
/// default it would overwrite the calibration of whoever ran the suite.
final class CalibrationStoreTests: XCTestCase {

    private var directory: URL!
    private var store: CalibrationStore!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("m14t-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = CalibrationStore(url: directory.appendingPathComponent("calibration.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private let sample = CalibrationData(xMin: 92, xMax: 12288, yMin: 1, yMax: 6854)
    private let panel = DisplayIdentity(vendor: 0x2D1F, model: 0x524C, serial: 0)
    private let other = DisplayIdentity(vendor: 0x4C2D, model: 0x0F30, serial: 7)

    func testLoadReturnsNilWhenNothingIsSaved() {
        XCTAssertNil(store.load(for: panel))
    }

    func testSavedCalibrationRoundTrips() {
        store.save(sample, for: panel)
        XCTAssertEqual(store.load(for: panel), sample)
    }

    func testSavingAgainReplacesThePreviousValue() {
        store.save(sample, for: panel)
        let updated = CalibrationData(xMin: 0, xMax: 1, yMin: 0, yMax: 1)
        store.save(updated, for: panel)
        XCTAssertEqual(store.load(for: panel), updated)
    }

    func testResetDeletesTheFile() {
        store.save(sample, for: panel)
        XCTAssertTrue(store.reset(for: panel))
        XCTAssertNil(store.load(for: panel))
    }

    // main.swift branches on this to choose between "reset" and "nothing to
    // reset", so the false case has to be reachable rather than thrown.
    func testResetReportsFailureWhenThereIsNothingToDelete() {
        XCTAssertFalse(store.reset(for: panel))
    }

    // MARK: - One entry per display

    func testTwoDisplaysKeepSeparateCalibrations() {
        let otherCalibration = CalibrationData(xMin: 0, xMax: 30000, yMin: 0, yMax: 17000)
        store.save(sample, for: panel)
        store.save(otherCalibration, for: other)

        XCTAssertEqual(store.load(for: panel), sample)
        XCTAssertEqual(store.load(for: other), otherCalibration)
    }

    func testCalibratingOneDisplayLeavesTheOtherAlone() {
        store.save(sample, for: panel)
        XCTAssertNil(store.load(for: other))
    }

    // Displays that report no vendor, model or serial are indistinguishable, so
    // they share a bucket rather than pretending to be told apart.
    func testUnidentifiedDisplaysShareOneEntry() {
        let anonymous = DisplayIdentity(vendor: 0, model: 0, serial: 0)
        store.save(sample, for: anonymous)
        XCTAssertEqual(store.load(for: nil), sample)
    }

    // MARK: - Upgrading from a single stored value

    // People have calibrated already. A file written before calibration was per
    // display has to keep working, or the upgrade silently costs them the
    // calibration they did.
    func testAFileFromBeforePerDisplayStorageStillApplies() throws {
        let json = """
        { "xMin": 1, "xMax": 12302, "yMin": 108, "yMax": 6959 }
        """
        try Data(json.utf8).write(to: store.url)

        let loaded = try XCTUnwrap(store.load(for: panel))
        XCTAssertEqual(loaded, CalibrationData(xMin: 1, xMax: 12302, yMin: 108, yMax: 6959))
    }

    func testTheOldValueServesAnyDisplayUntilOneIsCalibrated() throws {
        let json = """
        { "xMin": 1, "xMax": 12302, "yMin": 108, "yMax": 6959 }
        """
        try Data(json.utf8).write(to: store.url)

        store.save(sample, for: panel)
        XCTAssertEqual(store.load(for: panel), sample)          // its own now
        XCTAssertEqual(store.load(for: other)?.xMax, 12302)     // still the fallback
    }

    // Resetting clears the fallback too. Leaving it behind would make the reset
    // look like it had done nothing — the display would simply fall back to it.
    func testResettingAlsoClearsTheOldSharedValue() throws {
        let json = """
        { "xMin": 1, "xMax": 12302, "yMin": 108, "yMax": 6959 }
        """
        try Data(json.utf8).write(to: store.url)

        XCTAssertTrue(store.reset(for: panel))
        XCTAssertNil(store.load(for: panel))
    }

    func testResetAllForgetsEveryDisplay() {
        store.save(sample, for: panel)
        store.save(sample, for: other)
        XCTAssertTrue(store.resetAll())
        XCTAssertNil(store.load(for: panel))
        XCTAssertNil(store.load(for: other))
    }

    // A hand-edited file is a documented workflow, so a broken one must degrade
    // to "no calibration" rather than crashing on launch.
    func testCorruptFileLoadsAsNil() throws {
        try Data("not json".utf8).write(to: store.url)
        XCTAssertNil(store.load(for: panel))
    }
}
