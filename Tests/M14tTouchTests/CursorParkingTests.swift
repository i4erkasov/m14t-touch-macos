import CoreGraphics
import XCTest
@testable import M14tTouch

/// The pointer's round trip, tested without moving the pointer.
///
/// Both calls that touch it are injected, which is the whole reason this was
/// pulled out of `MouseEventEmitter`: the logic — remember once, give back once,
/// give back nothing that was not taken — used to be unreachable from a test
/// because exercising it moved the cursor of whoever ran the suite.
final class CursorParkingTests: XCTestCase {

    private let origin = CGPoint(x: 100, y: 200)
    private let panel = CGPoint(x: -900, y: 500)

    private func makeParking(at location: CGPoint? = nil)
        -> (CursorParking, () -> [CGPoint]) {
        var warps: [CGPoint] = []
        var parking = CursorParking()
        parking.readLocation = { location }
        parking.warp = { warps.append($0) }
        return (parking, { warps })
    }

    func testTheFirstMoveRemembersWhereThePointerWas() {
        var (parking, warps) = makeParking(at: origin)
        parking.rememberIfNeeded()
        parking.restore()
        XCTAssertEqual(warps(), [origin])
    }

    // The second move is already on the panel. Remembering it would send the
    // pointer back to where the driver had just put it.
    func testLaterMovesDoNotOverwriteTheMemory() {
        var warps: [CGPoint] = []
        var parking = CursorParking()
        var current = origin
        parking.readLocation = { current }
        parking.warp = { warps.append($0) }

        parking.rememberIfNeeded()
        current = panel
        parking.rememberIfNeeded()
        parking.restore()

        XCTAssertEqual(warps, [origin])
    }

    func testRestoringTwiceMovesThePointerOnce() {
        var (parking, warps) = makeParking(at: origin)
        parking.rememberIfNeeded()
        parking.restore()
        parking.restore()
        XCTAssertEqual(warps().count, 1)
    }

    // Nothing was taken, so there is nothing to give back — a gesture that only
    // scrolled, or a pen that hovered with hover-following switched off.
    func testRestoringWithoutAMoveDoesNothing() {
        var (parking, warps) = makeParking(at: origin)
        parking.restore()
        XCTAssertTrue(warps().isEmpty)
        XCTAssertFalse(parking.isParked)
    }

    func testForgettingDropsTheMemoryWithoutMovingAnything() {
        var (parking, warps) = makeParking(at: origin)
        parking.rememberIfNeeded()
        parking.forget()
        parking.restore()
        XCTAssertTrue(warps().isEmpty)
    }

    // A later visit starts fresh, or turning the setting back on would send the
    // pointer somewhere it has not been for hours.
    func testANewVisitRemembersAgain() {
        var warps: [CGPoint] = []
        var parking = CursorParking()
        var current = origin
        parking.readLocation = { current }
        parking.warp = { warps.append($0) }

        parking.rememberIfNeeded()
        parking.restore()
        current = CGPoint(x: 7, y: 8)
        parking.rememberIfNeeded()
        parking.restore()

        XCTAssertEqual(warps, [origin, CGPoint(x: 7, y: 8)])
    }

    // A pointer whose position cannot be read must not be "restored" to zero.
    func testAnUnreadablePointerIsNotRememberedAsTheOrigin() {
        var (parking, warps) = makeParking(at: nil)
        parking.rememberIfNeeded()
        parking.restore()
        XCTAssertTrue(warps().isEmpty)
    }

    // MARK: - The pen

    // `proximityExited` posts no events, so this exercises the real wiring
    // without anything reaching the window server.
    func testThePenGivesThePointerBackWhenItLeaves() {
        var warps: [CGPoint] = []
        let backend = PenMouseBackend(configuration: PenConfiguration())
        backend.parking.readLocation = { self.origin }
        backend.parking.warp = { warps.append($0) }
        backend.parking.rememberIfNeeded()

        backend.handle(.proximityExited)

        XCTAssertEqual(warps, [origin])
    }

    func testThePenKeepsThePointerWhenTheSettingIsOff() {
        var configuration = PenConfiguration()
        configuration.restoresPointerOnExit = false

        var warps: [CGPoint] = []
        let backend = PenMouseBackend(configuration: configuration)
        backend.parking.readLocation = { self.origin }
        backend.parking.warp = { warps.append($0) }
        backend.parking.rememberIfNeeded()

        backend.handle(.proximityExited)

        XCTAssertTrue(warps.isEmpty)
        // Forgotten rather than kept: the next visit must start from where the
        // pointer is then, not from where it was hours ago.
        XCTAssertFalse(backend.parking.isParked)
    }

    func testReturningThePointerIsOnByDefault() {
        XCTAssertTrue(PenConfiguration().restoresPointerOnExit)
    }

    func testTheChoiceSurvivesASaveAndLoad() throws {
        var configuration = PenConfiguration()
        configuration.restoresPointerOnExit = false
        let data = try JSONEncoder().encode(configuration)
        let restored = try JSONDecoder().decode(PenConfiguration.self, from: data)
        XCTAssertFalse(restored.restoresPointerOnExit)
    }
}
