import CoreGraphics
import XCTest
@testable import M14tTouch

/// What a pen button can be made to do.
///
/// Three kinds of thing, and telling them apart is the whole of it: a mouse
/// button is held and released, a shortcut happens once, and a modifier is in
/// force for as long as the button is down.
final class PenButtonTests: XCTestCase {

    func testAClickIsTheOnlyKindThatIsHeld() {
        XCTAssertTrue(PenButtonMapping.leftClick.isClick)
        XCTAssertTrue(PenButtonMapping.rightClick.isClick)
        XCTAssertTrue(PenButtonMapping.middleClick.isClick)

        for mapping in [PenButtonMapping.undo, .redo, .escape, .holdShift, .none] {
            XCTAssertFalse(mapping.isClick, "\(mapping) is not a mouse button")
        }
    }

    func testAShortcutCarriesItsOwnModifiers() {
        XCTAssertEqual(PenButtonMapping.undo.keystroke?.key, .z)
        XCTAssertEqual(PenButtonMapping.undo.keystroke?.flags, .maskCommand)

        XCTAssertEqual(PenButtonMapping.redo.keystroke?.key, .z)
        XCTAssertEqual(PenButtonMapping.redo.keystroke?.flags, [.maskCommand, .maskShift])
    }

    // Delete and Escape are bare keys. A stray Command on either would be a
    // different command entirely.
    func testBareKeysCarryNoModifiers() {
        XCTAssertEqual(PenButtonMapping.deleteKey.keystroke?.flags, [])
        XCTAssertEqual(PenButtonMapping.escape.keystroke?.flags, [])
    }

    // The three kinds must not overlap: something that is both a click and a
    // keystroke would do two things at once.
    func testEachMappingIsExactlyOneKind() {
        for mapping in PenButtonMapping.allCases {
            let kinds = [mapping.isClick, mapping.keystroke != nil, mapping.heldModifier != nil]
            XCTAssertLessThanOrEqual(kinds.filter { $0 }.count, 1, "\(mapping) is more than one kind")
        }
    }

    func testNothingIsNoneOfThem() {
        XCTAssertFalse(PenButtonMapping.none.isClick)
        XCTAssertNil(PenButtonMapping.none.keystroke)
        XCTAssertNil(PenButtonMapping.none.heldModifier)
    }

    func testEveryModifierIsDistinct() {
        let modifiers = PenButtonMapping.allCases.compactMap(\.heldModifier)
        XCTAssertEqual(modifiers.count, 4)
        XCTAssertEqual(Set(modifiers.map(\.rawValue)).count, 4, "two buttons would do the same thing")
    }

    // A mapping missing from the groups is one the settings cannot offer, which
    // is the quiet way a feature ships switched off for everyone.
    func testTheGroupsOfferEveryMapping() {
        let offered = PenButtonMapping.clicks
            + PenButtonMapping.shortcuts
            + PenButtonMapping.modifiers
        XCTAssertEqual(Set(offered), Set(PenButtonMapping.allCases))
        XCTAssertEqual(offered.count, PenButtonMapping.allCases.count, "something is listed twice")
    }

    func testEveryMappingIsNamed() {
        for mapping in PenButtonMapping.allCases {
            XCTAssertFalse(mapping.title.isEmpty, "\(mapping) has no name to show")
        }
    }

    // Saved settings from before these existed must still load, and a mapping
    // written by a future version must not make the whole file unreadable.
    func testAnUnknownMappingFallsBackRatherThanFailing() throws {
        let json = Data(#"{"farButton":"holdShift","nearButtonHover":"undo"}"#.utf8)
        let restored = try JSONDecoder().decode(PenConfiguration.self, from: json)
        XCTAssertEqual(restored.farButton, .holdShift)
        XCTAssertEqual(restored.nearButtonHover, .undo)

        let future = Data(#"{"farButton":"summonDragons"}"#.utf8)
        let survived = try JSONDecoder().decode(PenConfiguration.self, from: future)
        XCTAssertEqual(survived.farButton, PenConfiguration().farButton,
                       "an unknown mapping falls back to the default")
    }

    // A mouse button mapping still produces the events it always did.
    func testClicksStillMapToTheirEvents() {
        XCTAssertEqual(PenMouseBackend.down(.rightClick), .rightMouseDown)
        XCTAssertEqual(PenMouseBackend.up(.rightClick), .rightMouseUp)
        XCTAssertEqual(PenMouseBackend.dragged(.middleClick), .otherMouseDragged)
    }

    // And the new kinds have no mouse event to produce, which is what stops
    // them pressing a button as well as doing their own job.
    func testShortcutsAndModifiersHaveNoMouseEvent() {
        for mapping in [PenButtonMapping.undo, .escape, .holdShift, .holdCommand] {
            XCTAssertNil(PenMouseBackend.down(mapping))
            XCTAssertNil(PenMouseBackend.up(mapping))
            XCTAssertNil(PenMouseBackend.dragged(mapping))
        }
    }
}
