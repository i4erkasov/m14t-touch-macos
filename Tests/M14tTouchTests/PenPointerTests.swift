import CoreGraphics
import XCTest
@testable import M14tTouch

/// The pieces of the drawn pen pointer that do not need a window.
///
/// The overlay itself is not tested: it is a window, and exercising it would
/// put a dot on the screen of whoever ran the suite. What is pinned here is the
/// part the overlay depends on — that every action carries the place it
/// happened, and that the setting survives being saved and read back.
final class PenPointerTests: XCTestCase {

    private let point = CGPoint(x: 120, y: 340)

    func testEveryActionButLeavingKnowsWhereItHappened() {
        let actions: [PenAction] = [
            .proximityEntered(position: point),
            .hover(position: point),
            .contactBegan(tool: .tip, position: point, pressure: 0.5),
            .contactMoved(tool: .eraser, position: point, pressure: nil),
            .contactEnded(tool: .tip, position: point),
            .buttonsChanged([.barrel], position: point)
        ]
        for action in actions {
            XCTAssertEqual(action.position, point, "\(action) lost its position")
        }
    }

    // The one action with nowhere to be. It is what takes the dot off screen,
    // so it has to be distinguishable rather than defaulting to a stale point.
    func testLeavingHasNoPosition() {
        XCTAssertNil(PenAction.proximityExited.position)
    }

    // The arrow, because the dot depends on hiding the system pointer and that
    // may be unavailable — two pointers on screen is worse than one.
    func testThePointerDefaultsToTheSystemArrow() {
        XCTAssertEqual(PenConfiguration().pointer, .arrow)
    }

    func testTheChoiceSurvivesASaveAndLoad() throws {
        var configuration = PenConfiguration()
        configuration.pointer = .dot
        configuration.pointerSize = 22

        let data = try JSONEncoder().encode(configuration)
        let restored = try JSONDecoder().decode(PenConfiguration.self, from: data)

        XCTAssertEqual(restored.pointer, .dot)
        XCTAssertEqual(restored.pointerSize, 22)
    }

    // Settings saved before this feature existed must still decode, keeping
    // everything they did carry — the same guarantee the other fields have.
    func testSettingsWrittenBeforeThisFeatureStillLoad() throws {
        let json = Data(#"{"palmRejection":false,"farButton":"middleClick"}"#.utf8)
        let restored = try JSONDecoder().decode(PenConfiguration.self, from: json)

        XCTAssertEqual(restored.pointer, .arrow)
        XCTAssertEqual(restored.pointerSize, PenConfiguration().pointerSize)
        XCTAssertFalse(restored.palmRejection)
        XCTAssertEqual(restored.farButton, .middleClick)
    }

    func testBothStylesAreOfferedAndNamed() {
        XCTAssertEqual(PenPointerStyle.allCases.count, 2)
        for style in PenPointerStyle.allCases {
            XCTAssertFalse(style.title.isEmpty)
        }
    }
}
