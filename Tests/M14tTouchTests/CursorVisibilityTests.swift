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
        func forgetCounts() { assertions = 0; releases = 0 }
    }

    private func makeController(policy: CursorHiding = .touching, available: Bool = true)
        -> (CursorVisibilityController, SpyVisibility) {
        let spy = SpyVisibility(available: available)
        return (CursorVisibilityController(policy: policy, visibility: spy), spy)
    }

    // One request does not hold — the window server puts the pointer back — so
    // every frame with a contact has to renew it.
    func testEveryTouchingFrameAssertsAHide() {
        let (controller, spy) = makeController()
        for _ in 0..<5 { controller.update(isTouching: true, isScrolling: false) }
        XCTAssertEqual(spy.assertions, 5)
        XCTAssertEqual(spy.releases, 0)
    }

    func testLiftingReleasesOnce() {
        let (controller, spy) = makeController()
        controller.update(isTouching: true, isScrolling: false)
        controller.update(isTouching: false, isScrolling: false)
        XCTAssertEqual(spy.releases, 1)
    }

    // Frames keep arriving with no contact; they must not keep releasing.
    func testFurtherIdleFramesDoNotReleaseAgain() {
        let (controller, spy) = makeController()
        controller.update(isTouching: true, isScrolling: false)
        for _ in 0..<5 { controller.update(isTouching: false, isScrolling: false) }
        XCTAssertEqual(spy.releases, 1)
    }

    func testASecondTouchHidesAgain() {
        let (controller, spy) = makeController()
        controller.update(isTouching: true, isScrolling: false)
        controller.update(isTouching: false, isScrolling: false)
        controller.update(isTouching: true, isScrolling: false)
        XCTAssertEqual(spy.assertions, 2)
        XCTAssertEqual(spy.releases, 1)
    }

    // Device unplugged mid-gesture: no further frame will arrive to give the
    // pointer back, so restore has to do it unprompted.
    func testRestoreReleasesEvenWithoutALift() {
        let (controller, spy) = makeController()
        controller.update(isTouching: true, isScrolling: false)
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
        let (controller, spy) = makeController(policy: .never)
        controller.update(isTouching: true, isScrolling: false)
        controller.update(isTouching: false, isScrolling: false)
        XCTAssertEqual(spy.assertions, 0)
        XCTAssertFalse(controller.isActive)
    }

    // The private symbols may vanish in a future macOS. That must leave the
    // driver working with the feature inert, not failing.
    func testNothingHappensWhenTheImplementationIsUnavailable() {
        let (controller, spy) = makeController(available: false)
        controller.update(isTouching: true, isScrolling: false)
        XCTAssertEqual(spy.assertions, 0)
        XCTAssertFalse(controller.isActive)
    }

    // The bug this guards: the implementation used to be chosen at launch from
    // the setting at launch, so a controller that started with hiding off could
    // never hide afterwards however the policy changed.
    func testTurningHidingOnLaterActuallyHides() {
        let (controller, spy) = makeController(policy: .never)
        XCTAssertFalse(controller.isActive)

        controller.setPolicy(.touching)
        XCTAssertTrue(controller.isActive)

        controller.update(isTouching: true, isScrolling: false)
        XCTAssertEqual(spy.assertions, 1)
    }

    // Switching hiding off has to give the pointer back straight away: the
    // release that would have come at the end of the gesture will now never
    // happen.
    func testTurningHidingOffReleasesImmediately() {
        let (controller, spy) = makeController(policy: .touching)
        controller.update(isTouching: true, isScrolling: false)
        spy.forgetCounts()

        controller.setPolicy(.never)
        XCTAssertEqual(spy.releases, 1)
    }

    func testThePublicImplementationAdmitsItCannotHide() {
        XCTAssertFalse(PublicCursorVisibility().isAvailable)
    }

    // MARK: - The pen's own pointer

    // Same reason as a finger: the window server stops honouring a hide as soon
    // as the pointer moves, and the pen moves it constantly.
    func testEveryPenSampleAssertsAHide() {
        let (controller, spy) = makeController(policy: .never)
        for _ in 0..<5 { controller.updatePenPointer(isDrawn: true) }
        XCTAssertEqual(spy.assertions, 5)
        XCTAssertEqual(spy.releases, 0)
    }

    func testThePenGivesThePointerBackWhenItLeaves() {
        let (controller, spy) = makeController(policy: .never)
        controller.updatePenPointer(isDrawn: true)
        controller.updatePenPointer(isDrawn: false)
        XCTAssertEqual(spy.releases, 1)
    }

    // A drawn pointer is a replacement for the arrow, not a policy about when to
    // hide it, so the finger setting has no say.
    func testThePenHidesEvenWhenTheFingerPolicyIsNever() {
        let (controller, spy) = makeController(policy: .never)
        controller.updatePenPointer(isDrawn: true)
        XCTAssertEqual(spy.assertions, 1)
    }

    // The bug this guards: with one shared flag, a palm lifting off the panel
    // mid-stroke would hand the arrow back on top of the dot.
    func testAFingerLiftingDoesNotUncoverTheDot() {
        let (controller, spy) = makeController(policy: .touching)
        controller.update(isTouching: true, isScrolling: false)
        controller.updatePenPointer(isDrawn: true)
        spy.forgetCounts()

        controller.update(isTouching: false, isScrolling: false)
        XCTAssertEqual(spy.releases, 0)
    }

    // And the other way round, which is the case that actually happens: the pen
    // leaves while a finger is still down.
    func testThePenLeavingDoesNotUncoverAFinger() {
        let (controller, spy) = makeController(policy: .touching)
        controller.updatePenPointer(isDrawn: true)
        controller.update(isTouching: true, isScrolling: false)
        spy.forgetCounts()

        controller.updatePenPointer(isDrawn: false)
        XCTAssertEqual(spy.releases, 0)
    }

    // Both gone, and only then.
    func testThePointerComesBackOnceNeitherWantsItHidden() {
        let (controller, spy) = makeController(policy: .touching)
        controller.update(isTouching: true, isScrolling: false)
        controller.updatePenPointer(isDrawn: true)
        controller.update(isTouching: false, isScrolling: false)
        controller.updatePenPointer(isDrawn: false)
        XCTAssertEqual(spy.releases, 1)
    }

    func testThePenCannotHideWhatTheImplementationCannotHide() {
        let (controller, spy) = makeController(policy: .never, available: false)
        controller.updatePenPointer(isDrawn: true)
        XCTAssertEqual(spy.assertions, 0)
    }

    // Shutdown forgets both wants, or the next idle frame would release again
    // against a pointer nobody is hiding.
    func testRestoreForgetsThePenToo() {
        let (controller, spy) = makeController(policy: .touching)
        controller.updatePenPointer(isDrawn: true)
        controller.restore()
        spy.forgetCounts()

        controller.update(isTouching: false, isScrolling: false)
        XCTAssertEqual(spy.releases, 0)
    }

    // MARK: - The glide after a flick

    // The bug this guards, reported from use: the arrow reappeared the instant
    // the finger lifted and then sat there while the page was still moving —
    // the one moment it is most obviously in the way, since nothing is touching
    // the screen to explain why anything is happening.
    func testTheArrowStaysHiddenWhileTheContentIsStillMoving() {
        let (controller, spy) = makeController(policy: .scrolling)
        controller.update(isTouching: true, isScrolling: true)
        controller.updateGlide(isRunning: true)
        spy.forgetCounts()

        controller.update(isTouching: false, isScrolling: false)
        XCTAssertEqual(spy.releases, 0, "the glide is still going")
    }

    func testTheArrowComesBackWhenTheGlideStops() {
        let (controller, spy) = makeController(policy: .scrolling)
        controller.update(isTouching: true, isScrolling: true)
        controller.updateGlide(isRunning: true)
        controller.update(isTouching: false, isScrolling: false)

        controller.updateGlide(isRunning: false)
        XCTAssertEqual(spy.releases, 1)
    }

    // The blink this guards: the engine releases the hide on the frame the
    // finger lifts, and a glide that only took over on its first timer tick
    // left a sixtieth of a second in which the arrow appeared and vanished
    // again — more distracting than never hiding it at all.
    func testTheGlideTakesOverInTheSameBreathAsTheRelease() {
        let (controller, spy) = makeController(policy: .scrolling)
        controller.update(isTouching: true, isScrolling: true)
        spy.forgetCounts()

        // The order the engine and emitter produce: release, then the glide.
        controller.update(isTouching: false, isScrolling: false)
        controller.updateGlide(isRunning: true)

        XCTAssertEqual(spy.releases, 1)
        XCTAssertEqual(spy.assertions, 1, "and it is hidden again immediately")
    }

    // Renewed every tick, for the same reason a finger's is renewed every
    // frame: the window server drops the request rather than remembering it.
    func testEveryTickOfTheGlideRenewsTheHide() {
        let (controller, spy) = makeController(policy: .scrolling)
        for _ in 0..<5 { controller.updateGlide(isRunning: true) }
        XCTAssertEqual(spy.assertions, 5)
    }

    // A glide is the tail of a scroll, so whoever asked not to have the pointer
    // hidden while scrolling did not ask for this either.
    func testAGlideObeysTheHidingPolicy() {
        let (controller, spy) = makeController(policy: .never)
        controller.updateGlide(isRunning: true)
        XCTAssertEqual(spy.assertions, 0)
    }

    func testAGlideCannotHideWhatTheImplementationCannotHide() {
        let (controller, spy) = makeController(policy: .scrolling, available: false)
        controller.updateGlide(isRunning: true)
        XCTAssertEqual(spy.assertions, 0)
    }

    // A finger landing to stop the page must not uncover the arrow while its
    // own gesture is under way.
    func testAGlideEndingDoesNotUncoverAFingerThatHasLanded() {
        let (controller, spy) = makeController(policy: .touching)
        controller.updateGlide(isRunning: true)
        controller.update(isTouching: true, isScrolling: false)
        spy.forgetCounts()

        controller.updateGlide(isRunning: false)
        XCTAssertEqual(spy.releases, 0)
    }

    func testRestoreForgetsTheGlideToo() {
        let (controller, spy) = makeController(policy: .scrolling)
        controller.updateGlide(isRunning: true)
        controller.restore()
        spy.forgetCounts()

        controller.update(isTouching: false, isScrolling: false)
        XCTAssertEqual(spy.releases, 0)
    }

    // MARK: - Policy

    // The mode that actually works: during a scroll the pointer is placed once
    // and then stays still, which is the only state the window server keeps
    // hidden.
    func testScrollingPolicyHidesOnlyOnceScrollingHasBegun() {
        let (controller, spy) = makeController(policy: .scrolling)
        controller.update(isTouching: true, isScrolling: false)
        XCTAssertEqual(spy.assertions, 0)

        controller.update(isTouching: true, isScrolling: true)
        XCTAssertEqual(spy.assertions, 1)
    }

    // A long press resolving into a drag must give the pointer back, since the
    // drag will be moving it from then on.
    func testScrollingPolicyReleasesIfTheGestureTurnsOutNotToBeAScroll() {
        let (controller, spy) = makeController(policy: .scrolling)
        controller.update(isTouching: true, isScrolling: true)
        controller.update(isTouching: true, isScrolling: false)
        XCTAssertEqual(spy.releases, 1)
    }

    func testTouchingPolicyHidesFromTheFirstContact() {
        let (controller, spy) = makeController(policy: .touching)
        controller.update(isTouching: true, isScrolling: false)
        XCTAssertEqual(spy.assertions, 1)
    }

    func testNeverPolicyIsInactiveEvenWhenSupported() {
        let (controller, spy) = makeController(policy: .never)
        controller.update(isTouching: true, isScrolling: true)
        XCTAssertEqual(spy.assertions, 0)
        XCTAssertFalse(controller.isActive)
    }

    func testThePolicyDefaultsToNeverAndParsesFromTheCommandLine() {
        XCTAssertEqual(GestureConfiguration().cursorHiding, .never)
        guard case .run(let scrolling) = ArgumentParser.parse(["--hide-cursor", "scrolling"]),
              case .run(let touching) = ArgumentParser.parse(["--hide-cursor", "touching"])
        else { return XCTFail("expected run outcomes") }
        XCTAssertEqual(scrolling.gestures.cursorHiding, .scrolling)
        XCTAssertEqual(touching.gestures.cursorHiding, .touching)
    }

    func testAnUnknownModeIsRefusedAndNamesTheValidOnes() {
        guard case .error(let message) = ArgumentParser.parse(["--hide-cursor", "sometimes"]) else {
            return XCTFail("expected an error outcome")
        }
        XCTAssertTrue(message.contains("sometimes"))
        for mode in CursorHiding.allCases { XCTAssertTrue(message.contains(mode.rawValue)) }
    }
}
