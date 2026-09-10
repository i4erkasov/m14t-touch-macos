import XCTest
import CoreGraphics
@testable import M14tTouch

/// Covers the whole guided flow without opening a window — including which
/// button a finger landed on, which is the part that would otherwise only be
/// testable by touching a screen.
final class GuidedCalibrationTests: XCTestCase {

    private let range = (xMin: 1.0, xMax: 12302.0, yMin: 108.0, yMax: 6959.0)

    private func raw(at fraction: CGPoint) -> CGPoint {
        CGPoint(
            x: range.xMin + fraction.x * (range.xMax - range.xMin),
            y: range.yMin + fraction.y * (range.yMax - range.yMin)
        )
    }

    private func frame(_ raw: CGPoint, touching: Bool) -> TouchFrame {
        TouchFrame(contact: TouchPoint(
            id: TouchPoint.primary,
            position: .zero,
            rawPosition: raw,
            isTouching: touching,
            pressure: nil,
            timestamp: 0
        ))
    }

    @discardableResult
    private func touch(_ session: inout GuidedCalibration, at fraction: CGPoint)
        -> GuidedCalibration.Button? {
        let point = raw(at: fraction)
        session.handle(frame(point, touching: true))
        session.handle(frame(point, touching: true))
        return session.handle(frame(point, touching: false))
    }

    /// Touch all four targets accurately.
    private func completeAiming(_ session: inout GuidedCalibration) {
        for target in CalibrationCollector.defaultTargets {
            touch(&session, at: target)
        }
    }

    // MARK: - Aiming

    func testItStartsAimingAtTheFirstTarget() {
        let session = GuidedCalibration()
        XCTAssertEqual(session.phase, .aiming)
        XCTAssertEqual(session.currentTarget, CalibrationCollector.defaultTargets[0])
    }

    func testFinishingTheTargetsMovesToVerification() {
        var session = GuidedCalibration()
        completeAiming(&session)
        guard case .verifying(let result) = session.phase else {
            return XCTFail("expected verification")
        }
        XCTAssertEqual(result.calibration.xMax, range.xMax, accuracy: 1)
    }

    // Every target in a line says nothing about the other axis, and a panel that
    // reported one value throughout says nothing at all.
    func testSamplesThatSayNothingAreReportedRatherThanSaved() {
        var session = GuidedCalibration()
        for _ in CalibrationCollector.defaultTargets {
            touch(&session, at: CGPoint(x: 0.5, y: 0.5))
        }
        XCTAssertEqual(session.phase, .unusable)
    }

    // MARK: - Verification

    // The marker is the visible proof: it follows the finger through the
    // calibration that was just worked out.
    func testTheMarkerFollowsTheFingerThroughTheNewCalibration() {
        var session = GuidedCalibration()
        completeAiming(&session)

        session.handle(frame(raw(at: CGPoint(x: 0.25, y: 0.75)), touching: true))
        let marker = try? XCTUnwrap(session.marker)
        XCTAssertEqual(marker?.x ?? 0, 0.25, accuracy: 0.01)
        XCTAssertEqual(marker?.y ?? 0, 0.75, accuracy: 0.01)
    }

    func testTheMarkerDisappearsWhenTheFingerLifts() {
        var session = GuidedCalibration()
        completeAiming(&session)
        session.handle(frame(raw(at: CGPoint(x: 0.5, y: 0.5)), touching: true))
        session.handle(frame(raw(at: CGPoint(x: 0.5, y: 0.5)), touching: false))
        XCTAssertNil(session.marker)
    }

    // Tapping Save with a finger is the honest end-to-end test: if the
    // calibration is right you can hit the button, and if it is not, you cannot.
    func testTappingWhereSaveIsDrawnPressesIt() {
        var session = GuidedCalibration()
        completeAiming(&session)

        let save = GuidedCalibration.Button.save.rect
        let pressed = touch(&session, at: CGPoint(x: save.midX, y: save.midY))
        XCTAssertEqual(pressed, .save)
    }

    func testTappingWhereRetryIsDrawnPressesIt() {
        var session = GuidedCalibration()
        completeAiming(&session)

        let retry = GuidedCalibration.Button.retry.rect
        XCTAssertEqual(touch(&session, at: CGPoint(x: retry.midX, y: retry.midY)), .retry)
    }

    func testTappingElsewherePressesNothing() {
        var session = GuidedCalibration()
        completeAiming(&session)
        XCTAssertNil(touch(&session, at: CGPoint(x: 0.05, y: 0.05)))
    }

    // Pressed on release, so a finger that lands on a button and slides off does
    // not press it.
    func testAFingerThatSlidesOffTheButtonDoesNotPressIt() {
        var session = GuidedCalibration()
        completeAiming(&session)

        let save = GuidedCalibration.Button.save.rect
        session.handle(frame(raw(at: CGPoint(x: save.midX, y: save.midY)), touching: true))
        let pressed = session.handle(frame(raw(at: CGPoint(x: 0.05, y: 0.05)), touching: false))
        XCTAssertNil(pressed)
    }

    // MARK: - Outcomes

    func testSavingFinishesWithTheResult() {
        var session = GuidedCalibration()
        completeAiming(&session)
        session.press(.save)

        guard case .finished(let result) = session.phase else { return XCTFail("expected finished") }
        XCTAssertEqual(result?.calibration.xMax ?? 0, range.xMax, accuracy: 1)
    }

    func testRetryingStartsTheTargetsAgain() {
        var session = GuidedCalibration()
        completeAiming(&session)
        session.press(.retry)

        XCTAssertEqual(session.phase, .aiming)
        XCTAssertEqual(session.currentTarget, CalibrationCollector.defaultTargets[0])
        XCTAssertNil(session.marker)
    }

    // Nothing is kept, so an interrupted calibration leaves what was there.
    func testCancellingFinishesWithNothing() {
        var session = GuidedCalibration()
        completeAiming(&session)
        session.cancel()
        XCTAssertEqual(session.phase, .finished(nil))
    }
}
