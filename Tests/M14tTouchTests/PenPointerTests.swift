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

    // MARK: - Colour

    func testTheRingIsSystemGreenUntilChanged() {
        XCTAssertEqual(PenConfiguration().pointerColor, .systemGreen)
    }

    func testAColourSurvivesASaveAndLoad() throws {
        var configuration = PenConfiguration()
        configuration.pointerColor = RGBAColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5)

        let data = try JSONEncoder().encode(configuration)
        let restored = try JSONDecoder().decode(PenConfiguration.self, from: data)

        XCTAssertEqual(restored.pointerColor, configuration.pointerColor)
    }

    // Settings written before the colour existed keep everything they had, and
    // gain the default rather than black — the failure a plain `Double` default
    // of zero would have produced.
    func testAColourMissingFromTheFileBecomesTheDefault() throws {
        let json = Data(#"{"pointer":"dot","pointerSize":20}"#.utf8)
        let restored = try JSONDecoder().decode(PenConfiguration.self, from: json)

        XCTAssertEqual(restored.pointerColor, .systemGreen)
        XCTAssertEqual(restored.pointer, .dot)
        XCTAssertEqual(restored.pointerSize, 20)
    }

    // A half-written colour must not turn the missing channels into black
    // either, which is what decoding straight into `Double` would do.
    func testAPartialColourFillsTheRestFromTheDefault() throws {
        let json = Data(#"{"pointerColor":{"red":1.0}}"#.utf8)
        let restored = try JSONDecoder().decode(PenConfiguration.self, from: json)

        XCTAssertEqual(restored.pointerColor.red, 1.0)
        XCTAssertEqual(restored.pointerColor.green, RGBAColor.systemGreen.green)
        XCTAssertEqual(restored.pointerColor.blue, RGBAColor.systemGreen.blue)
        XCTAssertEqual(restored.pointerColor.alpha, 1.0)
    }

    // The default is macOS's own green, read from the system rather than
    // invented, so it is worth pinning that it still looks green.
    func testTheDefaultIsRecognisablyGreen() {
        let green = RGBAColor.systemGreen
        XCTAssertGreaterThan(green.green, green.red)
        XCTAssertGreaterThan(green.green, green.blue)
        XCTAssertEqual(green.alpha, 1)
    }

    func testBothStylesAreOfferedAndNamed() {
        XCTAssertEqual(PenPointerStyle.allCases.count, 2)
        for style in PenPointerStyle.allCases {
            XCTAssertFalse(style.title.isEmpty)
        }
    }
}

/// Pressure, which measurement showed applications actually receive.
///
/// See `M14t_PEN_CAPABILITIES.md`: a stroke marked as a tablet point arrives
/// with its pressure intact, while an ordinary click carries only 1 or 0.
final class PenPressureTests: XCTestCase {

    private let point = CGPoint(x: 10, y: 20)

    private func events(_ action: PenAction, sending: Bool = true)
        -> [(type: CGEventType, point: CGPoint, pressure: Double?)] {
        PenMouseBackend.mouseEvents(for: action, sendsPressure: sending)
    }

    // Off by default because turning it on broke a real application — a
    // browser-based paint program, where the pen stopped working mid-stroke.
    // Marking events as tablet points changes what every application receives,
    // so it is asked for rather than assumed.
    func testSendingPressureIsOffByDefault() {
        XCTAssertFalse(PenConfiguration().sendsPressure)
    }

    // Nothing is marked as a tablet event unless asked, so switching the setting
    // off restores exactly the events sent before the feature existed.
    func testNothingCarriesPressureWhenTheSettingIsOff() {
        let actions: [PenAction] = [
            .contactBegan(tool: .tip, position: point, pressure: 0.5),
            .contactMoved(tool: .tip, position: point, pressure: 0.5),
            .contactEnded(tool: .tip, position: point)
        ]
        for action in actions {
            XCTAssertNil(events(action, sending: false).first?.pressure, "\(action)")
        }
    }

    func testAStrokeCarriesThePressureItWasGiven() {
        let began = events(.contactBegan(tool: .tip, position: point, pressure: 1.0))
        XCTAssertEqual(began.first?.pressure, 1.0)
    }

    // Zero in a tablet event means "not touching", and the panel's lightest
    // registering press normalises to about 0.006 — so a real touch would
    // otherwise arrive claiming not to be one.
    func testTheLightestTouchStillCountsAsTouching() {
        let began = events(.contactBegan(tool: .tip, position: point, pressure: 0))
        XCTAssertEqual(began.first?.pressure, PressureScale.minimumContactPressure)
        XCTAssertGreaterThan(began.first?.pressure ?? 0, 0)
    }

    // Lifted is the one contact event whose honest pressure is nothing.
    func testLiftingReportsNoPressure() {
        XCTAssertEqual(events(.contactEnded(tool: .tip, position: point)).first?.pressure, 0)
    }

    // Light strokes must stay distinguishable rather than flattening onto one
    // minimum, which is why the scale is lifted off zero and not clamped at it.
    func testLightStrokesRemainDistinguishable() {
        let soft = PressureScale.eventPressure(0.01)
        let softer = PressureScale.eventPressure(0.005)
        XCTAssertGreaterThan(soft, softer)
        XCTAssertGreaterThan(softer, 0)
    }

    func testTheScaleStillReachesTheTop() {
        XCTAssertEqual(PressureScale.eventPressure(1), 1, accuracy: 0.0001)
    }

    // A hover has no contact, so it has no pressure to report.
    func testHoveringCarriesNoPressure() {
        XCTAssertNil(events(.hover(position: point)).first?.pressure)
    }

    func testTheSettingSurvivesASaveAndLoad() throws {
        var configuration = PenConfiguration()
        configuration.sendsPressure = false
        let data = try JSONEncoder().encode(configuration)
        XCTAssertFalse(try JSONDecoder().decode(PenConfiguration.self, from: data).sendsPressure)
    }
}
