import XCTest
@testable import M14tTouch

/// Covers the arithmetic between a finger delta and a whole wheel step, and the
/// routing that keeps scroll and mouse events apart. Posting is untested by
/// design — exercising it would scroll whatever the user is looking at.
final class ScrollEmissionTests: XCTestCase {

    // MARK: - Accumulation

    func testWholePixelsPassStraightThrough() {
        var accumulator = ScrollAccumulator()
        let wheel = accumulator.take(x: 3, y: -7)
        XCTAssertEqual(wheel?.horizontal, 3)
        XCTAssertEqual(wheel?.vertical, -7)
    }

    // The reason the accumulator exists. Rounding each delta on its own would
    // throw all of these away and a slow scroll would not move the page at all.
    func testSubPixelDeltasAccumulateInsteadOfBeingLost() {
        var accumulator = ScrollAccumulator()
        XCTAssertNil(accumulator.take(x: 0, y: 0.4))
        XCTAssertNil(accumulator.take(x: 0, y: 0.4))
        XCTAssertEqual(accumulator.take(x: 0, y: 0.4)?.vertical, 1)
    }

    func testTheRemainderIsCarriedRatherThanDiscarded() {
        var accumulator = ScrollAccumulator()
        XCTAssertEqual(accumulator.take(x: 0, y: 1.6)?.vertical, 1)   // 0.6 carried
        XCTAssertEqual(accumulator.take(x: 0, y: 1.6)?.vertical, 2)   // 0.2 carried
    }

    func testAccumulationWorksInBothDirections() {
        var accumulator = ScrollAccumulator()
        XCTAssertNil(accumulator.take(x: -0.5, y: 0))
        XCTAssertEqual(accumulator.take(x: -0.6, y: 0)?.horizontal, -1)
    }

    // One axis reaching a whole pixel must not be held up by the other.
    func testEitherAxisAloneIsEnoughToEmit() {
        var accumulator = ScrollAccumulator()
        let wheel = accumulator.take(x: 0.2, y: 5)
        XCTAssertEqual(wheel?.vertical, 5)
        XCTAssertEqual(wheel?.horizontal, 0)
    }

    // A wild sensitivity must not overflow the event's Int32 fields.
    func testAbsurdDeltasAreClamped() {
        var accumulator = ScrollAccumulator()
        let wheel = accumulator.take(x: 1e12, y: -1e12)
        XCTAssertEqual(wheel?.horizontal, 10_000)
        XCTAssertEqual(wheel?.vertical, -10_000)
    }

    // MARK: - Routing

    func testScrollGoesToTheScrollEmitterAndNothingElseDoes() {
        let mouse = RecordingEventEmitter()
        let scroll = RecordingEventEmitter()
        let router = RoutingEventEmitter(mouse: mouse, scroll: scroll)

        router.emit(.scroll(deltaX: 1, deltaY: 2))
        router.emit(.tap(position: .zero))
        router.emit(.dragBegin(position: .zero))
        router.emit(.pointerMove(position: .zero))

        XCTAssertEqual(scroll.actions, [.scroll(deltaX: 1, deltaY: 2)])
        XCTAssertEqual(mouse.actions, [
            .tap(position: .zero),
            .dragBegin(position: .zero),
            .pointerMove(position: .zero),
        ])
    }
}
