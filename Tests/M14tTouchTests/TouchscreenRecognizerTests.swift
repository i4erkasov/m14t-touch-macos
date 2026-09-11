import XCTest
import CoreGraphics
@testable import M14tTouch

/// Covers tap recognition and the two ways a contact stops being a tap.
///
/// Frames are built by hand at the cadence the driver now publishes — one per
/// report, carrying a matched coordinate pair and a monotonic timestamp.
final class TouchscreenRecognizerTests: XCTestCase {

    private var configuration: GestureConfiguration {
        var c = GestureConfiguration()
        c.scrollThreshold = 10
        c.longPressDelay = 0.4
        // Off here so these assertions describe the gesture itself. The restore
        // is on by default in the product and covered by CursorRestoreTests.
        c.restoreCursor = false
        return c
    }

    private func makeRecognizer() -> TouchscreenRecognizer {
        TouchscreenRecognizer(configuration: configuration)
    }

    private func frame(_ x: CGFloat, _ y: CGFloat, touching: Bool, at time: TimeInterval) -> TouchFrame {
        TouchFrame(contact: TouchPoint(
            id: TouchPoint.primary,
            position: CGPoint(x: x, y: y),
            rawPosition: CGPoint(x: x * 6, y: y * 6),
            isTouching: touching,
            pressure: nil,
            timestamp: time
        ))
    }

    // MARK: - Tap

    // Nothing is emitted while the finger is down. This is the whole difference
    // from mouse mode, and what stops the panel feeling like a giant touchpad.
    func testContactEmitsNothingUntilItIsUnderstood() {
        var recognizer = makeRecognizer()
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: true, at: 0)), [])
        XCTAssertEqual(recognizer.process(frame(101, 101, touching: true, at: 0.05)), [])
    }

    func testQuickReleaseIsATap() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: false, at: 0.1)),
                       [.tap(position: CGPoint(x: 100, y: 100))])
    }

    // The landing point is what the user aimed at; the release may have drifted.
    func testTapIsReportedWhereTheFingerLandedNotWhereItLeft() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(104, 103, touching: true, at: 0.05))
        XCTAssertEqual(recognizer.process(frame(104, 103, touching: false, at: 0.1)),
                       [.tap(position: CGPoint(x: 100, y: 100))])
    }

    // A small wobble must not cost the user their click.
    func testDriftWithinTheThresholdIsStillATap() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(106, 108, touching: true, at: 0.05))   // 10.0 px
        XCTAssertEqual(recognizer.process(frame(106, 108, touching: false, at: 0.1)).count, 1)
    }

    // MARK: - Movement claims the contact

    func testMovingPastTheScrollThresholdIsNoLongerATap() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(140, 100, touching: true, at: 0.05))
        // The release ends the scroll; no click is produced.
        XCTAssertEqual(recognizer.process(frame(140, 100, touching: false, at: 0.1)), [.scrollEnd])
    }

    // Exactly at the threshold is not past it. v0.1 showed how easily a strict
    // comparison becomes an inclusive one.
    func testMovementExactlyAtTheThresholdIsStillATap() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(110, 100, touching: true, at: 0.05))   // exactly 10
        XCTAssertEqual(recognizer.process(frame(110, 100, touching: false, at: 0.1)).count, 1)
    }

    // Distance, not per-axis: 8 px on each axis is 11.3 px of travel, which is
    // past the threshold even though neither axis alone is.
    func testDiagonalMovementIsJudgedByDistance() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        // Neither axis alone exceeds 10, but the travel is 11.3.
        XCTAssertEqual(recognizer.process(frame(108, 108, touching: true, at: 0.05)),
                       [.pointerMove(position: CGPoint(x: 100, y: 100))])
    }

    // Measured from where the finger landed, so wandering out and back does not
    // restore the tap.
    func testReturningToTheOriginDoesNotRestoreTheTap() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(200, 100, touching: true, at: 0.05))
        _ = recognizer.process(frame(100, 100, touching: true, at: 0.1))
        // It lifts while still travelling, so the content glides after it.
        let actions = recognizer.process(frame(100, 100, touching: false, at: 0.15))
        XCTAssertEqual(actions.first, .scrollEnd)
        XCTAssertEqual(actions.count, 2, "expected a glide to follow: \(actions)")
    }

    // MARK: - Time claims the contact

    func testHoldingPastTheLongPressDelayIsNoLongerATap() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 100, touching: true, at: 0.5))   // becomes a drag
        // The release ends the drag rather than producing a tap.
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: false, at: 0.6)),
                       [.dragEnd(position: CGPoint(x: 100, y: 100))])
    }

    func testHoldingExactlyToTheDelayIsStillATap() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 100, touching: true, at: 0.4))   // exactly the delay
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: false, at: 0.45)).count, 1)
    }

    // The deadline is noticed on a frame that carries no movement at all — the
    // ScanTime tick. A held finger sends nothing else, which is why step 2
    // publishes those frames.
    func testTheDeadlineIsNoticedOnAMotionlessFrame() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        // No movement in this frame at all — only the clock advanced.
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: true, at: 0.41)).count, 1)
    }

    // MARK: - Long press to drag

    // The press fires on a frame carrying no movement — the ScanTime tick. This
    // is the branch that could not exist before step 2 published those frames.
    func testHoldingPastTheDelayBeginsADrag() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: true, at: 0.41)),
                       [.dragBegin(position: CGPoint(x: 100, y: 100))])
    }

    func testTheDragBeginsOnlyOnce() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 100, touching: true, at: 0.41))
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: true, at: 0.42)), [])
    }

    // Grabbed at the landing point, for the same reason a tap is reported there.
    func testTheDragGrabsAtTheLandingPoint() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(105, 104, touching: true, at: 0.2))   // drift
        XCTAssertEqual(recognizer.process(frame(105, 104, touching: true, at: 0.41)),
                       [.dragBegin(position: CGPoint(x: 100, y: 100))])
    }

    func testMovementAfterTheGrabDrags() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 100, touching: true, at: 0.41))
        XCTAssertEqual(recognizer.process(frame(300, 400, touching: true, at: 0.5)),
                       [.dragMove(position: CGPoint(x: 300, y: 400))])
    }

    // A resting finger must not walk the grabbed object around.
    func testJitterDuringADragIsFiltered() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 100, touching: true, at: 0.41))
        XCTAssertEqual(recognizer.process(frame(101, 100, touching: true, at: 0.5)), [])
    }

    func testReleasingADragEndsIt() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 100, touching: true, at: 0.41))
        _ = recognizer.process(frame(300, 400, touching: true, at: 0.5))
        XCTAssertEqual(recognizer.process(frame(305, 405, touching: false, at: 0.6)),
                       [.dragEnd(position: CGPoint(x: 300, y: 400))])
    }

    // Moving away before the deadline is a scroll in the making, never a drag,
    // however long the finger stays down afterwards.
    // The gesture lock. A slow scroll must not become a drag partway through,
    // however long the finger stays down.
    func testAScrollNeverBecomesADragHoweverLongItLasts() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(400, 400, touching: true, at: 0.05))   // commits to scroll

        // Well past longPressDelay, and motionless — the deadline is not consulted.
        XCTAssertEqual(recognizer.process(frame(400, 400, touching: true, at: 2.0)), [])
        // Further movement keeps scrolling rather than dragging.
        let actions = recognizer.process(frame(400, 500, touching: true, at: 2.1))
        XCTAssertEqual(actions, [.scroll(deltaX: 0, deltaY: 100)])
        // And the release ends the scroll rather than producing a dragEnd.
        XCTAssertEqual(recognizer.process(frame(400, 500, touching: false, at: 2.2)), [.scrollEnd])
    }

    // Unplugging mid-drag has to release the button; nothing else will.
    func testResetDuringADragReleasesTheButton() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 100, touching: true, at: 0.41))
        _ = recognizer.process(frame(300, 400, touching: true, at: 0.5))
        XCTAssertEqual(recognizer.reset(), [.dragEnd(position: CGPoint(x: 300, y: 400))])
    }

    func testATapWorksAfterADrag() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 100, touching: true, at: 0.41))
        _ = recognizer.process(frame(100, 100, touching: false, at: 0.5))
        _ = recognizer.process(frame(700, 700, touching: true, at: 1.0))
        XCTAssertEqual(recognizer.process(frame(700, 700, touching: false, at: 1.1)),
                       [.tap(position: CGPoint(x: 700, y: 700))])
    }

    // MARK: - Scrolling

    // The cursor is placed once, at the start. A scroll event has no
    // destination of its own — it goes wherever the cursor is.
    func testCommittingToAScrollPlacesTheCursorAndScrollsNothingYet() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        XCTAssertEqual(recognizer.process(frame(100, 140, touching: true, at: 0.05)),
                       [.pointerMove(position: CGPoint(x: 100, y: 100))])
    }

    // Deltas are measured from where the commitment happened, so the threshold
    // distance is consumed by committing rather than scrolling the page by it.
    func testScrollDeltasAreMeasuredFromTheCommitmentPoint() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 140, touching: true, at: 0.05))
        XCTAssertEqual(recognizer.process(frame(100, 190, touching: true, at: 0.1)),
                       [.scroll(deltaX: 0, deltaY: 50)])
    }

    func testEachFrameScrollsByItsOwnDelta() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 140, touching: true, at: 0.05))
        _ = recognizer.process(frame(100, 190, touching: true, at: 0.1))
        XCTAssertEqual(recognizer.process(frame(120, 200, touching: true, at: 0.15)),
                       [.scroll(deltaX: 20, deltaY: 10)])
    }

    func testAMotionlessFrameDuringAScrollEmitsNothing() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 140, touching: true, at: 0.05))
        XCTAssertEqual(recognizer.process(frame(100, 140, touching: true, at: 0.1)), [])
    }

    func testSensitivityScalesTheDelta() {
        var configuration = self.configuration
        configuration.scrollSensitivity = 2.5
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 140, touching: true, at: 0.05))
        XCTAssertEqual(recognizer.process(frame(100, 160, touching: true, at: 0.1)),
                       [.scroll(deltaX: 0, deltaY: 50)])
    }

    // Natural scrolling is the default — content follows the finger. Turning it
    // off inverts the gesture, and must invert both axes.
    func testTurningOffNaturalScrollingInvertsBothAxes() {
        var configuration = self.configuration
        configuration.naturalScroll = false
        var recognizer = TouchscreenRecognizer(configuration: configuration)
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 140, touching: true, at: 0.05))
        XCTAssertEqual(recognizer.process(frame(130, 160, touching: true, at: 0.1)),
                       [.scroll(deltaX: -30, deltaY: -20)])
    }

    // Nothing is held *down* during a scroll, but the gesture itself is open:
    // leaving it open would make the next scroll a continuation of one that
    // ended when the panel was unplugged.
    func testResetDuringAScrollClosesTheGestureWithoutReleasingAButton() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 140, touching: true, at: 0.05))
        XCTAssertEqual(recognizer.reset(), [.scrollEnd])
    }

    // Nothing was under way, so there is nothing to close.
    func testResetWhileIdleEmitsNothing() {
        var recognizer = makeRecognizer()
        XCTAssertEqual(recognizer.reset(), [])
    }

    // MARK: - Sequencing

    func testASecondTapIsRecognisedAfterTheFirst() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 100, touching: false, at: 0.1))
        _ = recognizer.process(frame(500, 500, touching: true, at: 1.0))
        XCTAssertEqual(recognizer.process(frame(500, 500, touching: false, at: 1.1)),
                       [.tap(position: CGPoint(x: 500, y: 500))])
    }

    // An abandoned gesture must release its claim, or the next touch inherits it.
    func testATapWorksAfterAScroll() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(400, 400, touching: true, at: 0.05))
        _ = recognizer.process(frame(400, 400, touching: false, at: 0.1))
        _ = recognizer.process(frame(700, 700, touching: true, at: 1.0))
        XCTAssertEqual(recognizer.process(frame(700, 700, touching: false, at: 1.1)),
                       [.tap(position: CGPoint(x: 700, y: 700))])
    }

    // Nothing is held down, so there is nothing to release on unplug.
    func testResetEmitsNothing() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        XCTAssertEqual(recognizer.reset(), [])
    }

    func testResetAbandonsTheGestureInProgress() {
        var recognizer = makeRecognizer()
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.reset()
        // The release belongs to a gesture that no longer exists.
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: false, at: 0.1)), [])
    }
}

/// Covers the cursor restore (spec §10). Touchscreen mode has to move the
/// pointer onto the target; this puts it back afterwards, which is the closest
/// public-API answer to "don't leave an arrow sitting on the panel".
final class CursorRestoreTests: XCTestCase {

    private func makeRecognizer(restoring: Bool) -> TouchscreenRecognizer {
        var c = GestureConfiguration()
        c.scrollThreshold = 10
        c.longPressDelay = 0.4
        c.restoreCursor = restoring
        return TouchscreenRecognizer(configuration: c)
    }

    private func frame(_ x: CGFloat, _ y: CGFloat, touching: Bool, at time: TimeInterval) -> TouchFrame {
        TouchFrame(contact: TouchPoint(
            id: TouchPoint.primary,
            position: CGPoint(x: x, y: y),
            rawPosition: .zero,
            isTouching: touching,
            pressure: nil,
            timestamp: time
        ))
    }

    // Last, always: the pointer goes home only after the click it was moved for.
    func testTheRestoreFollowsTheTap() {
        var recognizer = makeRecognizer(restoring: true)
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: false, at: 0.1)),
                       [.tap(position: CGPoint(x: 100, y: 100)), .cursorRestore])
    }

    func testTheRestoreFollowsTheDragEnd() {
        var recognizer = makeRecognizer(restoring: true)
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 100, touching: true, at: 0.41))
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: false, at: 0.5)),
                       [.dragEnd(position: CGPoint(x: 100, y: 100)), .cursorRestore])
    }

    // The restore comes last, after the gesture has been closed: the pointer
    // goes home only once the scroll it was moved for is over.
    func testAScrollRestoresOnRelease() {
        var recognizer = makeRecognizer(restoring: true)
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 140, touching: true, at: 0.05))
        XCTAssertEqual(
            recognizer.process(frame(100, 140, touching: false, at: 0.2)),
            [.scrollEnd, .cursorRestore]
        )
    }

    // Unplugging mid-drag must not strand the pointer on the panel either.
    func testResetRestoresToo() {
        var recognizer = makeRecognizer(restoring: true)
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 100, touching: true, at: 0.41))
        XCTAssertEqual(recognizer.reset(),
                       [.dragEnd(position: CGPoint(x: 100, y: 100)), .cursorRestore])
    }

    func testNothingIsRestoredWhenTheSettingIsOff() {
        var recognizer = makeRecognizer(restoring: false)
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: false, at: 0.1)),
                       [.tap(position: CGPoint(x: 100, y: 100))])
    }

    // On by default, having been judged acceptable on the panel.
    func testRestoringIsOnByDefaultAndTogglesFromTheCommandLine() {
        XCTAssertTrue(GestureConfiguration().restoreCursor)
        guard case .run(let off) = ArgumentParser.parse(["--no-restore-cursor"]),
              case .run(let on) = ArgumentParser.parse(["--no-restore-cursor", "--restore-cursor"])
        else { return XCTFail("expected run outcomes") }
        XCTAssertFalse(off.gestures.restoreCursor)
        XCTAssertTrue(on.gestures.restoreCursor)
    }
}

/// Covers what switching a gesture off actually does (spec §14, §21). The three
/// toggles do not all mean the same thing, and the difference is deliberate.
final class GestureToggleTests: XCTestCase {

    private func makeRecognizer(_ configure: (inout GestureConfiguration) -> Void)
        -> TouchscreenRecognizer {
        var c = GestureConfiguration()
        c.scrollThreshold = 10
        c.longPressDelay = 0.4
        c.restoreCursor = false
        configure(&c)
        return TouchscreenRecognizer(configuration: c)
    }

    private func frame(_ x: CGFloat, _ y: CGFloat, touching: Bool, at time: TimeInterval) -> TouchFrame {
        TouchFrame(contact: TouchPoint(
            id: TouchPoint.primary,
            position: CGPoint(x: x, y: y),
            rawPosition: .zero,
            isTouching: touching,
            pressure: nil,
            timestamp: time
        ))
    }

    // MARK: - Tap

    func testWithTapOffAReleaseClicksNothing() {
        var recognizer = makeRecognizer { $0.tapEnabled = false }
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: false, at: 0.1)), [])
    }

    // Switching taps off must not switch scrolling off with them.
    func testScrollingStillWorksWithTapOff() {
        var recognizer = makeRecognizer { $0.tapEnabled = false }
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        XCTAssertEqual(recognizer.process(frame(100, 140, touching: true, at: 0.05)),
                       [.pointerMove(position: CGPoint(x: 100, y: 100))])
    }

    // MARK: - Scroll

    // A swipe does nothing at all — it does not fall back to being a click.
    // Switching scrolling off is a wish for swipes to have no effect.
    func testWithScrollOffASwipeDoesNothingAndDoesNotBecomeATap() {
        var recognizer = makeRecognizer { $0.oneFingerScrollEnabled = false }
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        XCTAssertEqual(recognizer.process(frame(300, 300, touching: true, at: 0.05)), [])
        XCTAssertEqual(recognizer.process(frame(400, 400, touching: true, at: 0.1)), [])
        XCTAssertEqual(recognizer.process(frame(400, 400, touching: false, at: 0.15)), [])
    }

    func testAbandoningOneSwipeDoesNotSpoilTheNextTap() {
        var recognizer = makeRecognizer { $0.oneFingerScrollEnabled = false }
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(400, 400, touching: true, at: 0.05))
        _ = recognizer.process(frame(400, 400, touching: false, at: 0.1))

        _ = recognizer.process(frame(700, 700, touching: true, at: 1.0))
        XCTAssertEqual(recognizer.process(frame(700, 700, touching: false, at: 1.1)),
                       [.tap(position: CGPoint(x: 700, y: 700))])
    }

    // A short touch is unaffected — only travelling far enough is.
    func testTappingStillWorksWithScrollOff() {
        var recognizer = makeRecognizer { $0.oneFingerScrollEnabled = false }
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: false, at: 0.1)),
                       [.tap(position: CGPoint(x: 100, y: 100))])
    }

    // MARK: - Long press

    // Deliberately unlike scrolling: moving away is a different gesture, whereas
    // holding still is the same gesture done slowly, so a slow tap stays a tap
    // rather than being thrown away.
    func testWithLongPressOffHoldingStillRemainsATap() {
        var recognizer = makeRecognizer { $0.longPressDragEnabled = false }
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: true, at: 3.0)), [])
        XCTAssertEqual(recognizer.process(frame(100, 100, touching: false, at: 3.1)),
                       [.tap(position: CGPoint(x: 100, y: 100))])
    }

    func testScrollingStillWorksWithLongPressOff() {
        var recognizer = makeRecognizer { $0.longPressDragEnabled = false }
        _ = recognizer.process(frame(100, 100, touching: true, at: 0))
        _ = recognizer.process(frame(100, 140, touching: true, at: 0.5))
        XCTAssertEqual(recognizer.process(frame(100, 190, touching: true, at: 0.6)),
                       [.scroll(deltaX: 0, deltaY: 50)])
    }

    // MARK: - Defaults and flags

    func testEverythingIsOnByDefault() {
        let c = GestureConfiguration()
        XCTAssertTrue(c.tapEnabled)
        XCTAssertTrue(c.oneFingerScrollEnabled)
        XCTAssertTrue(c.longPressDragEnabled)
    }

    func testTheFlagsTurnThemOff() {
        guard case .run(let config) = ArgumentParser.parse(
            ["--no-tap", "--no-one-finger-scroll", "--no-long-press-drag"]
        ) else { return XCTFail("expected a run outcome") }
        XCTAssertFalse(config.gestures.tapEnabled)
        XCTAssertFalse(config.gestures.oneFingerScrollEnabled)
        XCTAssertFalse(config.gestures.longPressDragEnabled)
    }
}
