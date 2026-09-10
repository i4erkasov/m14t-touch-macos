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

    /// A backend whose pointer calls and timer are all under the test's control.
    ///
    /// `pointerFollowsHover` is off so that no action posts an event: the tests
    /// below drive real code paths, and a posted event would move the pointer of
    /// whoever is running them.
    private func makeBackend(restores: Bool = true) -> (
        backend: PenMouseBackend,
        warps: () -> [CGPoint],
        fireTimer: () -> Void,
        delays: () -> [TimeInterval]
    ) {
        var configuration = PenConfiguration()
        configuration.restoresPointerOnExit = restores
        configuration.pointerFollowsHover = false

        var warps: [CGPoint] = []
        var pending: [(TimeInterval, () -> Void)] = []

        let backend = PenMouseBackend(configuration: configuration)
        backend.parking.readLocation = { self.origin }
        backend.parking.warp = { warps.append($0) }
        backend.schedule = { delay, work in pending.append((delay, work)) }

        return (
            backend,
            { warps },
            { pending.forEach { $0.1() }; pending = [] },
            { pending.map(\.0) }
        )
    }

    // The regression this exists for: a pen loses proximity every time it is
    // lifted between strokes, so returning the pointer at once warped it across
    // the desk after every stroke, and the drawing lagged behind the warps.
    func testLeavingSchedulesTheRestoreRatherThanDoingItNow() {
        let (backend, warps, fireTimer, delays) = makeBackend()
        backend.parking.rememberIfNeeded()

        backend.handle(.proximityExited)
        XCTAssertTrue(warps().isEmpty, "the pointer moved before the pen was gone")
        XCTAssertEqual(delays(), [PenMouseBackend.restoreDelay])

        fireTimer()
        XCTAssertEqual(warps(), [origin])
    }

    // Lifting between strokes: the pen comes back before the wait is over, and
    // the pointer never leaves the panel.
    func testAPenThatComesBackAbandonsTheRestore() {
        let (backend, warps, fireTimer, _) = makeBackend()
        backend.parking.rememberIfNeeded()

        backend.handle(.proximityExited)
        backend.handle(.proximityEntered(position: panel))
        fireTimer()

        XCTAssertTrue(warps().isEmpty)
        // And the original position is still held, so putting the pen down at
        // the end of the session still returns the pointer.
        XCTAssertTrue(backend.parking.isParked)
    }

    // Several lifts in a row must not leave several restores armed.
    func testOnlyTheLastDepartureCounts() {
        let (backend, warps, fireTimer, _) = makeBackend()
        backend.parking.rememberIfNeeded()

        for _ in 0..<3 {
            backend.handle(.proximityExited)
            backend.handle(.proximityEntered(position: panel))
        }
        backend.handle(.proximityExited)
        fireTimer()

        XCTAssertEqual(warps(), [origin])
    }

    func testThePenKeepsThePointerWhenTheSettingIsOff() {
        let (backend, warps, fireTimer, delays) = makeBackend(restores: false)
        backend.parking.rememberIfNeeded()

        backend.handle(.proximityExited)
        fireTimer()

        XCTAssertTrue(warps().isEmpty)
        XCTAssertTrue(delays().isEmpty, "nothing should have been scheduled at all")
        // Forgotten rather than kept: the next visit must start from where the
        // pointer is then, not from where it was hours ago.
        XCTAssertFalse(backend.parking.isParked)
    }

    func testSwitchingTheReturnOffDisarmsARestoreAlreadyWaiting() {
        let (backend, warps, fireTimer, _) = makeBackend()
        backend.parking.rememberIfNeeded()
        backend.handle(.proximityExited)

        var off = PenConfiguration()
        off.restoresPointerOnExit = false
        off.pointerFollowsHover = false
        backend.apply(off)

        fireTimer()
        XCTAssertTrue(warps().isEmpty)
    }

    // Documents the intent rather than the number: the wait has to outlast a
    // lift between strokes, or it is not doing its job.
    func testTheWaitOutlastsALiftBetweenStrokes() {
        XCTAssertGreaterThanOrEqual(PenMouseBackend.restoreDelay, 0.5)
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
