import CoreGraphics
import XCTest
@testable import M14tTouch

/// Mapping a touch onto a rotated display.
///
/// The panel reports where a finger is on the *glass*, and rotating a display
/// does not move the glass. These tests follow the corners, which is also how
/// the mapping was derived: rotating an image 90° counterclockwise carries its
/// top edge to the left edge, so the top-left of the framebuffer ends up at the
/// bottom-left of the glass.
final class RotationTests: XCTestCase {

    private let landscape = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let portrait = CGRect(x: 0, y: 0, width: 1080, height: 1920)

    private func mapper(bounds: CGRect, rotation: Double) -> CoordinateMapper {
        CoordinateMapper(
            calibration: CalibrationData(xMin: 0, xMax: 1000, yMin: 0, yMax: 1000),
            displayBounds: bounds,
            invertX: false,
            invertY: false,
            rotation: rotation
        )
    }

    // MARK: - The pure part, corner by corner

    func testNoRotationLeavesEverythingWhereItWas() {
        for (x, y) in [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.5, 0.25)] {
            let moved = CoordinateMapper.rotated(x: x, y: y, by: 0)
            XCTAssertEqual(moved.x, x, accuracy: 1e-9)
            XCTAssertEqual(moved.y, y, accuracy: 1e-9)
        }
    }

    func testAQuarterTurnSendsTheGlassTopLeftToTheImageTopRight() {
        let moved = CoordinateMapper.rotated(x: 0, y: 0, by: 90)
        XCTAssertEqual(moved.x, 1, accuracy: 1e-9)
        XCTAssertEqual(moved.y, 0, accuracy: 1e-9)
    }

    func testAQuarterTurnTakesEveryCornerToTheNextOne() {
        let corners: [(glass: (Double, Double), image: (Double, Double))] = [
            ((0, 0), (1, 0)),
            ((1, 0), (1, 1)),
            ((1, 1), (0, 1)),
            ((0, 1), (0, 0))
        ]
        for corner in corners {
            let moved = CoordinateMapper.rotated(x: corner.glass.0, y: corner.glass.1, by: 90)
            XCTAssertEqual(moved.x, corner.image.0, accuracy: 1e-9, "\(corner.glass)")
            XCTAssertEqual(moved.y, corner.image.1, accuracy: 1e-9, "\(corner.glass)")
        }
    }

    func testAHalfTurnIsTheOppositeCorner() {
        let moved = CoordinateMapper.rotated(x: 0.25, y: 0.75, by: 180)
        XCTAssertEqual(moved.x, 0.75, accuracy: 1e-9)
        XCTAssertEqual(moved.y, 0.25, accuracy: 1e-9)
    }

    // The two quarter turns must be opposites, or one of them is backwards —
    // which is the single most likely thing to be wrong here.
    func testTheTwoQuarterTurnsUndoEachOther() {
        for (x, y) in [(0.1, 0.2), (0.9, 0.3), (0.5, 0.5)] {
            let once = CoordinateMapper.rotated(x: x, y: y, by: 90)
            let back = CoordinateMapper.rotated(x: once.x, y: once.y, by: 270)
            XCTAssertEqual(back.x, x, accuracy: 1e-9)
            XCTAssertEqual(back.y, y, accuracy: 1e-9)
        }
    }

    func testFourQuarterTurnsReturnToTheStart() {
        var point = (x: 0.3, y: 0.8)
        for _ in 0..<4 { point = CoordinateMapper.rotated(x: point.x, y: point.y, by: 90) }
        XCTAssertEqual(point.x, 0.3, accuracy: 1e-9)
        XCTAssertEqual(point.y, 0.8, accuracy: 1e-9)
    }

    // A quarter turn the other way can arrive as a negative angle; a negative
    // remainder would match nothing and silently mean "not rotated".
    func testANegativeAngleIsTheSameAsItsPositiveTwin() {
        let negative = CoordinateMapper.rotated(x: 0.2, y: 0.6, by: -90)
        let positive = CoordinateMapper.rotated(x: 0.2, y: 0.6, by: 270)
        XCTAssertEqual(negative.x, positive.x, accuracy: 1e-9)
        XCTAssertEqual(negative.y, positive.y, accuracy: 1e-9)
    }

    // macOS offers four rotations. Inventing an answer for anything else would
    // be worse than declining to.
    func testAnAngleThatIsNotARightAngleIsIgnored() {
        let moved = CoordinateMapper.rotated(x: 0.2, y: 0.6, by: 37)
        XCTAssertEqual(moved.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(moved.y, 0.6, accuracy: 1e-9)
    }

    // MARK: - End to end, onto real bounds

    func testTouchingTheGlassCornerLandsOnTheScreenCornerWhenUpright() {
        let mapper = mapper(bounds: landscape, rotation: 0)
        XCTAssertEqual(mapper.map(rawX: 0, rawY: 0), CGPoint(x: 0, y: 0))
        XCTAssertEqual(mapper.map(rawX: 1000, rawY: 1000), CGPoint(x: 1920, y: 1080))
    }

    // The bounds swap when the display is turned, and the mapping has to land
    // inside the new ones rather than the old.
    func testARotatedDisplayUsesItsSwappedBounds() {
        let mapper = mapper(bounds: portrait, rotation: 90)
        let topLeftOfGlass = mapper.map(rawX: 0, rawY: 0)
        XCTAssertEqual(topLeftOfGlass, CGPoint(x: 1080, y: 0))

        let bottomRightOfGlass = mapper.map(rawX: 1000, rawY: 1000)
        XCTAssertEqual(bottomRightOfGlass, CGPoint(x: 0, y: 1920))
    }

    // The regression this whole thing exists to prevent: without rotation, the
    // long axis of the panel gets mapped across the short axis of the screen
    // and every touch lands somewhere else entirely.
    func testWithoutRotationATurnedDisplayWouldPutTheTouchInTheWrongPlace() {
        let wrong = mapper(bounds: portrait, rotation: 0).map(rawX: 1000, rawY: 0)
        let right = mapper(bounds: portrait, rotation: 90).map(rawX: 1000, rawY: 0)
        XCTAssertEqual(wrong, CGPoint(x: 1080, y: 0))
        XCTAssertEqual(right, CGPoint(x: 1080, y: 1920))
        XCTAssertNotEqual(wrong, right)
    }

    // Inversion describes the panel's own wiring and rotation describes the
    // screen. They have to compose, not replace each other.
    func testInversionStillAppliesOnARotatedDisplay() {
        var mapper = self.mapper(bounds: portrait, rotation: 90)
        mapper.invertX = true
        // Inverted first, so the glass's top-left reads as its top-right.
        XCTAssertEqual(mapper.map(rawX: 0, rawY: 0), CGPoint(x: 1080, y: 1920))
    }
}
