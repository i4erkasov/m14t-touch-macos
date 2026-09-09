import XCTest
@testable import M14tTouch

/// Covers which of a descriptor's several declared ranges is believed.
///
/// The fixtures are the M14t's real descriptor, in the order `ioreg` reports
/// it — the touch collection first, then the pen collection, then a
/// vendor-specific page repeating the same usages with different bounds.
final class DescriptorRangeTests: XCTestCase {

    private func element(page: UInt32, usage: UInt32, _ min: Int, _ max: Int) -> DescriptorRange.Element {
        DescriptorRange.Element(usagePage: page, usage: usage, logicalMin: min, logicalMax: max)
    }

    private func x(_ min: Int, _ max: Int) -> DescriptorRange.Element { element(page: 0x01, usage: 0x30, min, max) }
    private func y(_ min: Int, _ max: Int) -> DescriptorRange.Element { element(page: 0x01, usage: 0x31, min, max) }

    // The regression this rule exists for. Keeping the last declaration gave
    // 0…30931, while the panel never reports above 12288.
    func testFirstDeclarationWinsOverLaterOnes() {
        let range = DescriptorRange.range(from: [
            x(0, 12372), y(0, 6960),      // touch collection — the one that fits
            x(0, 30931), y(0, 17399),     // pen collection
            x(0, 32767), y(0, 32767),     // vendor-specific repeat
        ])
        XCTAssertEqual(range, CalibrationData(xMin: 0, xMax: 12372, yMin: 0, yMax: 6960))
    }

    func testAxesAreChosenIndependently() {
        let range = DescriptorRange.range(from: [
            x(0, 12372),
            y(0, 6960),
            x(0, 32767),
        ])
        XCTAssertEqual(range.xMax, 12372)
        XCTAssertEqual(range.yMax, 6960)
    }

    // Digitizer and vendor-specific pages declare their own X/Y-numbered usages;
    // only Generic Desktop (0x01) carries the coordinates.
    func testOtherUsagePagesAreIgnored() {
        let range = DescriptorRange.range(from: [
            element(page: 0x0D, usage: 0x30, 0, 4095),      // digitizer TipPressure
            element(page: 0xFF00, usage: 0x30, 0, 255),     // vendor-specific
            x(0, 12372), y(0, 6960),
        ])
        XCTAssertEqual(range, CalibrationData(xMin: 0, xMax: 12372, yMin: 0, yMax: 6960))
    }

    // A descriptor missing an axis falls back to the neutral full range for it,
    // which auto-calibration or a saved file then narrows.
    func testMissingAxisKeepsTheIdentityRange() {
        let range = DescriptorRange.range(from: [x(0, 12372)])
        XCTAssertEqual(range.xMax, 12372)
        XCTAssertEqual(range.yMin, CalibrationData.identity.yMin)
        XCTAssertEqual(range.yMax, CalibrationData.identity.yMax)
    }

    func testNoElementsGivesTheIdentityRange() {
        XCTAssertEqual(DescriptorRange.range(from: []), .identity)
    }
}
