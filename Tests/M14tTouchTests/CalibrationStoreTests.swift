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

    func testLoadReturnsNilWhenNothingIsSaved() {
        XCTAssertNil(store.load())
    }

    func testSavedCalibrationRoundTrips() {
        store.save(sample)
        XCTAssertEqual(store.load(), sample)
    }

    func testSavingAgainReplacesThePreviousValue() {
        store.save(sample)
        let updated = CalibrationData(xMin: 0, xMax: 1, yMin: 0, yMax: 1)
        store.save(updated)
        XCTAssertEqual(store.load(), updated)
    }

    func testResetDeletesTheFile() {
        store.save(sample)
        XCTAssertTrue(store.reset())
        XCTAssertNil(store.load())
    }

    // main.swift branches on this to choose between "reset" and "nothing to
    // reset", so the false case has to be reachable rather than thrown.
    func testResetReportsFailureWhenThereIsNothingToDelete() {
        XCTAssertFalse(store.reset())
    }

    // A hand-edited file is a documented workflow, so a broken one must degrade
    // to "no calibration" rather than crashing on launch.
    func testCorruptFileLoadsAsNil() throws {
        try Data("not json".utf8).write(to: store.url)
        XCTAssertNil(store.load())
    }
}
