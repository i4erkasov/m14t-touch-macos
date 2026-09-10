import XCTest
@testable import M14tTouch

/// Covers the controller's balancing. The private implementation itself is not
/// tested — exercising it would hide the pointer of whoever ran the suite — so
/// what is pinned here is that hides are asserted while a finger is down,
/// released exactly once when it lifts, and never asserted at all when the
/// feature is off or unsupported.
final class CursorVisibilityTests: XCTestCase {

    private final class SpyVisibility: CursorVisibility {
        var isAvailable: Bool
        private(set) var assertions = 0
        private(set) var releases = 0

        init(available: Bool = true) { isAvailable = available }
        func assertHidden() { assertions += 1 }
        func release() { releases += 1 }
    }

    private func makeController(enabled: Bool = true, available: Bool = true)
        -> (CursorVisibilityController, SpyVisibility) {
        let spy = SpyVisibility(available: available)
        return (CursorVisibilityController(enabled: enabled, visibility: spy), spy)
    }

    // One request does not hold — the window server puts the pointer back — so
    // every frame with a contact has to renew it.
    func testEveryTouchingFrameAssertsAHide() {
        let (controller, spy) = makeController()
        for _ in 0..<5 { controller.update(isTouching: true) }
        XCTAssertEqual(spy.assertions, 5)
        XCTAssertEqual(spy.releases, 0)
    }

    func testLiftingReleasesOnce() {
        let (controller, spy) = makeController()
        controller.update(isTouching: true)
        controller.update(isTouching: false)
        XCTAssertEqual(spy.releases, 1)
    }

    // Frames keep arriving with no contact; they must not keep releasing.
    func testFurtherIdleFramesDoNotReleaseAgain() {
        let (controller, spy) = makeController()
        controller.update(isTouching: true)
        for _ in 0..<5 { controller.update(isTouching: false) }
        XCTAssertEqual(spy.releases, 1)
    }

    func testASecondTouchHidesAgain() {
        let (controller, spy) = makeController()
        controller.update(isTouching: true)
        controller.update(isTouching: false)
        controller.update(isTouching: true)
        XCTAssertEqual(spy.assertions, 2)
        XCTAssertEqual(spy.releases, 1)
    }

    // Device unplugged mid-gesture: no further frame will arrive to give the
    // pointer back, so restore has to do it unprompted.
    func testRestoreReleasesEvenWithoutALift() {
        let (controller, spy) = makeController()
        controller.update(isTouching: true)
        controller.restore()
        XCTAssertEqual(spy.releases, 1)
    }

    // Cheap and idempotent, because shutdown calls it whatever state we are in.
    func testRestoreIsSafeWhenNothingIsHidden() {
        let (controller, spy) = makeController()
        controller.restore()
        controller.restore()
        XCTAssertEqual(spy.releases, 2)
        XCTAssertEqual(spy.assertions, 0)
    }

    func testNothingHappensWhenTheSettingIsOff() {
        let (controller, spy) = makeController(enabled: false)
        controller.update(isTouching: true)
        controller.update(isTouching: false)
        XCTAssertEqual(spy.assertions, 0)
        XCTAssertFalse(controller.isActive)
    }

    // The private symbols may vanish in a future macOS. That must leave the
    // driver working with the feature inert, not failing.
    func testNothingHappensWhenTheImplementationIsUnavailable() {
        let (controller, spy) = makeController(available: false)
        controller.update(isTouching: true)
        XCTAssertEqual(spy.assertions, 0)
        XCTAssertFalse(controller.isActive)
    }

    func testThePublicImplementationAdmitsItCannotHide() {
        XCTAssertFalse(PublicCursorVisibility().isAvailable)
    }

    func testTheSettingIsOffByDefaultAndTogglesFromTheCommandLine() {
        XCTAssertFalse(GestureConfiguration().hideCursorWhileTouching)
        guard case .run(let on) = ArgumentParser.parse(["--hide-cursor"]),
              case .run(let off) = ArgumentParser.parse(["--hide-cursor", "--no-hide-cursor"])
        else { return XCTFail("expected run outcomes") }
        XCTAssertTrue(on.gestures.hideCursorWhileTouching)
        XCTAssertFalse(off.gestures.hideCursorWhileTouching)
    }
}
