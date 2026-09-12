import XCTest
@testable import M14tTouch

/// How the stylus's charge is presented.
///
/// Worth pinning because of what it is for. This hardware fails by the stylus
/// going silent with no warning, which looks exactly like a broken driver —
/// an afternoon went into that once — and a wrong or invented number here
/// would send the next person the same way.
final class BatteryTests: XCTestCase {

    private func status(_ level: Double?) -> DriverStatus {
        var status = DriverStatus(isConnected: true)
        status.batteryLevel = level
        return status
    }

    // Nothing is invented before the pen has spoken. A pen left on the desk
    // since launch has reported no charge, and saying "100%" would be a guess
    // dressed as a reading.
    func testSilenceIsNotAFullBattery() {
        XCTAssertNil(status(nil).batteryPercentage)
        XCTAssertNil(status(nil).batterySymbol)
    }

    func testTheLevelBecomesAPercentage() {
        XCTAssertEqual(status(1).batteryPercentage, 100)
        XCTAssertEqual(status(0.5).batteryPercentage, 50)
        XCTAssertEqual(status(0).batteryPercentage, 0)
    }

    func testItRoundsRatherThanTruncating() {
        // 0.876 is nearer three quarters than seven eighths of the way to full.
        XCTAssertEqual(status(0.876).batteryPercentage, 88)
        XCTAssertEqual(status(0.874).batteryPercentage, 87)
    }

    // Five symbols is what the set offers, so each stands for a range. Rounding
    // to the nearest keeps a nearly-full battery from being drawn as a
    // three-quarters-empty one.
    func testTheSymbolMatchesTheCharge() {
        XCTAssertEqual(status(1).batterySymbol, "battery.100")
        XCTAssertEqual(status(0.9).batterySymbol, "battery.100")
        XCTAssertEqual(status(0.8).batterySymbol, "battery.75")
        XCTAssertEqual(status(0.5).batterySymbol, "battery.50")
        XCTAssertEqual(status(0.3).batterySymbol, "battery.25")
        XCTAssertEqual(status(0.05).batterySymbol, "battery.0")
    }

    func testALowBatteryIsWorthMentioning() {
        XCTAssertTrue(status(0.2).isBatteryLow)
        XCTAssertTrue(status(0.05).isBatteryLow)
        XCTAssertFalse(status(0.21).isBatteryLow)
        XCTAssertFalse(status(1).isBatteryLow)
    }

    // An unknown charge must not raise an alarm either. "I have not heard from
    // the pen" is not "the pen is nearly flat".
    func testAnUnknownChargeIsNotAWarning() {
        XCTAssertFalse(status(nil).isBatteryLow)
    }

    // A fresh connection knows nothing until the pen reports again, which is
    // the honest state rather than the last value from a different session.
    func testAReconnectionStartsWithoutAReading() {
        XCTAssertNil(DriverStatus(isConnected: true).batteryLevel)
    }
}
