import XCTest
import CoreGraphics
@testable import M14tTouch

/// Covers which display a selection resolves to. Pure over a list, so the
/// precedence can be tested without plugging monitors in and out — which is
/// exactly the situation the logic exists for.
final class DisplaySelectionTests: XCTestCase {

    private func display(
        _ index: Int,
        builtin: Bool = false,
        vendor: UInt32 = 0,
        model: UInt32 = 0,
        serial: UInt32 = 0,
        origin: CGFloat = 0
    ) -> DisplayInfo {
        DisplayInfo(
            index: index,
            id: CGDirectDisplayID(index + 1),
            bounds: CGRect(x: origin, y: 0, width: 1920, height: 1080),
            isMain: index == 0,
            isBuiltin: builtin,
            identity: DisplayIdentity(vendor: vendor, model: model, serial: serial)
        )
    }

    private lazy var builtin = display(0, builtin: true, vendor: 0x610, model: 0xA050)
    private lazy var panel = display(1, vendor: 0x2D1F, model: 0x524C, origin: -1920)
    private lazy var samsung = display(2, vendor: 0x4C2D, model: 0x0F30, origin: 2000)
    private var all: [DisplayInfo] { [builtin, panel, samsung] }

    // MARK: - Identity

    // The whole point: the panel is found wherever it has ended up in the list.
    func testIdentityFindsTheDisplayWhateverItsIndex() {
        let selection = DisplaySelection(identity: panel.identity, index: 99)
        let resolved = DisplayResolver.resolve(selection, among: all)
        XCTAssertEqual(resolved?.display, panel)
        XCTAssertEqual(resolved?.match, .identity)
    }

    // Unplug the Samsung and the panel becomes index 1 rather than 2; an index
    // would have followed the renumbering, an identity does not.
    func testIdentitySurvivesRenumbering() {
        let selection = DisplaySelection(identity: samsung.identity, index: nil)
        let resolved = DisplayResolver.resolve(selection, among: [builtin, samsung])
        XCTAssertEqual(resolved?.display.identity, samsung.identity)
        XCTAssertEqual(resolved?.match, .identity)
    }

    // Saying so beats silently aiming elsewhere: spec §30 expects a reconnect to
    // restore the old target, and a quiet substitution hides that it did not.
    func testAMissingDisplayIsReportedRatherThanSwappedSilently() {
        let selection = DisplaySelection(identity: panel.identity, index: nil)
        let resolved = DisplayResolver.resolve(selection, among: [builtin, samsung])
        XCTAssertEqual(resolved?.match, .unavailable)
        XCTAssertEqual(resolved?.display, samsung)      // first external
    }

    // A display with no vendor, model or serial cannot be told apart from any
    // other, so the index is all there is.
    func testAnUnusableIdentityFallsThroughToTheIndex() {
        let anonymous = display(1)
        let selection = DisplaySelection(identity: anonymous.identity, index: 2)
        let resolved = DisplayResolver.resolve(selection, among: all)
        XCTAssertEqual(resolved?.display, samsung)
        XCTAssertEqual(resolved?.match, .index)
    }

    // MARK: - Index

    func testAnIndexIsUsedWhenThereIsNoIdentity() {
        let resolved = DisplayResolver.resolve(.index(2), among: all)
        XCTAssertEqual(resolved?.display, samsung)
        XCTAssertEqual(resolved?.match, .index)
    }

    func testAnOutOfRangeIndexFallsBackAndSaysSo() {
        let resolved = DisplayResolver.resolve(.index(9), among: all)
        XCTAssertEqual(resolved?.display, panel)        // first external
        XCTAssertEqual(resolved?.match, .unavailable)
    }

    // MARK: - Automatic

    // Replaces the hardcoded index 1 that spec §32 forbids. External, because a
    // touch panel is by definition not the built-in screen.
    func testAutomaticPicksTheFirstExternalDisplay() {
        let resolved = DisplayResolver.resolve(.automatic, among: all)
        XCTAssertEqual(resolved?.display, panel)
        XCTAssertEqual(resolved?.match, .automatic)
    }

    func testAutomaticFallsBackToTheBuiltInWhenItIsAlone() {
        let resolved = DisplayResolver.resolve(.automatic, among: [builtin])
        XCTAssertEqual(resolved?.display, builtin)
    }

    func testNoDisplaysResolvesToNothing() {
        XCTAssertNil(DisplayResolver.resolve(.automatic, among: []))
    }

    // MARK: - Command line

    // Naming a position explicitly has to beat a stored identity, or the flag
    // would appear to do nothing.
    func testTheDisplayFlagOverridesAStoredIdentity() {
        var stored = AppSettings()
        stored.display = DisplaySelection(identity: panel.identity, index: nil)

        guard case .run(let config) = ArgumentParser.parse(["--display", "2"], defaults: stored.touchConfig)
        else { return XCTFail("expected a run outcome") }

        XCTAssertNil(config.display.identity)
        XCTAssertEqual(config.display.index, 2)
    }
}
