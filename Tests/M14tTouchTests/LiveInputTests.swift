import CoreGraphics
import XCTest
@testable import M14tTouch

/// How the live diagnostics read.
///
/// Worth testing rather than eyeballing, because every line is a judgement
/// about absence: "not reported" and "nothing" are different answers, and
/// telling them apart is the entire purpose of a diagnostics pane. A dash where
/// a zero belongs — or a zero where a dash belongs — is exactly the kind of
/// thing that sends someone looking in the wrong place.
final class LiveInputTests: XCTestCase {

    func testAnEmptySnapshotSaysNothingIsArriving() {
        let live = LiveInput()
        XCTAssertEqual(live.activity, "nothing arriving")
        XCTAssertEqual(live.sourceName, "—")
        XCTAssertEqual(live.rawDescription, "—")
        XCTAssertEqual(live.screenDescription, "—")
        XCTAssertEqual(live.pressureDescription, "—")
    }

    func testArrivingValuesAreCounted() {
        var live = LiveInput()
        live.valuesPerSecond = 214
        XCTAssertEqual(live.activity, "214 values/s")
    }

    func testTheSourceDistinguishesAPenInRange() {
        var live = LiveInput()
        live.source = .pen
        XCTAssertEqual(live.sourceName, "Pen")
        live.penInRange = true
        XCTAssertEqual(live.sourceName, "Pen, in range")
    }

    // The open question this view exists to answer: a panel that never fills in
    // ContactCount does not report multi-touch, and the pane has to say so
    // rather than showing a dash that could mean either.
    func testAMissingContactCountIsExplainedRatherThanShownAsADash() {
        var live = LiveInput()
        live.isTouching = true
        XCTAssertEqual(live.contactDescription, "touching")
        XCTAssertFalse(live.contactCountNote.isEmpty)
    }

    func testAReportedContactCountIsShownWithItsMaximum() {
        var live = LiveInput()
        live.isTouching = true
        live.contactCount = 2
        live.contactCountMaximum = 10
        XCTAssertEqual(live.contactDescription, "touching, 2 of 10")
        XCTAssertTrue(live.contactCountNote.isEmpty, "nothing left to explain")
    }

    // A count without a maximum is still worth showing: it is the answer on its
    // own, and inventing a maximum would be worse than omitting one.
    func testAContactCountWithoutAMaximumStillReads() {
        var live = LiveInput()
        live.contactCount = 1
        XCTAssertEqual(live.contactDescription, "not touching, 1")
    }

    func testCoordinatesAreShownBeforeAndAfterMapping() {
        var live = LiveInput()
        live.rawX = 6186
        live.rawY = 3480
        live.screen = CGPoint(x: -960, y: 540)
        XCTAssertEqual(live.rawDescription, "6186, 3480")
        XCTAssertEqual(live.screenDescription, "-960, 540")
    }

    // Raw alongside scaled, because the two disagreeing is how a wrong pressure
    // floor shows itself — a normalised 0 alone could be a light touch or a
    // floor set too high.
    func testPressureShowsRawAndScaledTogether() {
        var live = LiveInput()
        live.rawPressure = 2409
        live.pressure = 0.385
        XCTAssertEqual(live.pressureDescription, "2409 raw, 0.39 scaled")
    }

    func testHeldButtonsAreNamedAndTheirAbsenceIsToo() {
        var live = LiveInput()
        XCTAssertEqual(live.buttonDescription, "none held")
        live.penButtons = [.barrel]
        XCTAssertEqual(live.buttonDescription, "far")
        live.penButtons = [.barrel, .eraserMode]
        XCTAssertEqual(live.buttonDescription, "far, near")
    }
}
