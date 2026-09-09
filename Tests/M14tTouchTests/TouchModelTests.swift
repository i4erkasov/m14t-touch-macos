import XCTest
import CoreGraphics
@testable import M14tTouch

/// Covers the frame accessors the gesture layer depends on. The models are
/// otherwise plain data — what is worth testing is the behaviour a recognizer
/// leans on, chiefly that an empty frame is representable and yields no contact
/// rather than trapping.
final class TouchModelTests: XCTestCase {

    private func makeContact(
        x: CGFloat = 100,
        y: CGFloat = 200,
        touching: Bool = true,
        timestamp: TimeInterval = 1.0
    ) -> TouchPoint {
        TouchPoint(
            id: TouchPoint.primary,
            position: CGPoint(x: x, y: y),
            rawPosition: CGPoint(x: 6000, y: 3500),
            isTouching: touching,
            pressure: nil,
            timestamp: timestamp
        )
    }

    func testPrimaryContactIsTheFirstContact() {
        let first = makeContact(x: 10)
        let second = makeContact(x: 20)
        let frame = TouchFrame(contacts: [first, second], timestamp: 1.0)
        XCTAssertEqual(frame.primaryContact, first)
    }

    // A frame with no contacts must be safe to build and query: step 4 feeds
    // every HID value through this pipeline, and a recognizer guards on
    // `primaryContact` rather than indexing.
    func testPrimaryContactIsNilForAnEmptyFrame() {
        let frame = TouchFrame(contacts: [], timestamp: 1.0)
        XCTAssertNil(frame.primaryContact)
    }

    func testSingleContactInitAdoptsTheContactTimestamp() {
        let contact = makeContact(timestamp: 42.5)
        let frame = TouchFrame(contact: contact)
        XCTAssertEqual(frame.contacts, [contact])
        XCTAssertEqual(frame.timestamp, 42.5)
    }

    // Recognizer tests in step 3 assert on `[InputAction]` equality, so distinct
    // cases carrying the same point must not compare equal.
    func testInputActionsWithSamePointButDifferentCasesDiffer() {
        let point = CGPoint(x: 5, y: 5)
        XCTAssertNotEqual(InputAction.dragBegin(position: point),
                          InputAction.dragMove(position: point))
        XCTAssertEqual(InputAction.dragEnd(position: point),
                       InputAction.dragEnd(position: point))
    }
}
