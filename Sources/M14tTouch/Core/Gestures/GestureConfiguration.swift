import Foundation

/// Everything a recognizer needs to tune how it reads a gesture (spec §4).
///
/// One home for these values rather than scattering them across recognizers,
/// because they are what the Settings window will edit in v0.3 — and because
/// step 8 of v0.2 exists to tune them against the panel. The defaults below are
/// **starting guesses**, not measurements.
struct GestureConfiguration: Equatable {

    // MARK: Tap
    //
    // Spec §7.1 lists a tap movement threshold and a maximum tap duration.
    // Neither is here, on purpose. A contact is a tap when it is released
    // before anything else has claimed it, so the only boundaries that matter
    // are the ones that claim it: `scrollThreshold` and `longPressDelay`.
    //
    // Separate tap limits would not add control, they would add dead zones. A
    // tap budget of 8 px against a scroll threshold of 10 px means a touch that
    // moves 9 px and lifts is neither a tap nor a scroll, and silently does
    // nothing; a 300 ms tap limit against a 400 ms long press does the same to a
    // touch held for 350 ms. Making them agree removes the gap and proves they
    // were the same two numbers under different names. Spec §8 allows a better
    // UX than the one it sketches.

    // MARK: Scroll

    /// Movement, in screen pixels, that commits the gesture to scrolling
    /// (spec §7.2). Larger than `tapMovementThreshold` on purpose: the tap
    /// budget is jitter tolerance, this is a decision.
    var scrollThreshold: Double = 10

    /// Multiplier applied to scroll deltas before they are emitted.
    var scrollSensitivity: Double = 1.0

    /// Content follows the finger, as on a touch device (spec §7.2).
    ///
    /// Default on because this is a touchscreen, not a mouse wheel. The sign of
    /// the emitted delta is derived from this and never hardcoded (spec §23).
    var naturalScroll: Bool = true

    // MARK: Cursor

    /// Put the pointer back where it was once a gesture finishes (spec §10).
    ///
    /// Touchscreen mode has to move the cursor onto the target — a scroll event
    /// goes wherever the pointer is, and a click carries its position as a warp.
    /// Hiding the cursor instead is not achievable with public APIs, and spec
    /// §10 and §32 forbid the private one that would. Restoring it afterwards is
    /// the closest thing: the arrow visits the panel for the length of a gesture
    /// and then goes back where the user left it.
    var restoreCursor: Bool = false

    // MARK: Drag

    /// How long a contact must be held, without committing to a scroll, before
    /// it becomes a drag (spec §8).
    var longPressDelay: TimeInterval = 0.4

    /// Mouse mode only: minimum movement, in screen pixels, before a held
    /// contact counts as a drag. Filters panel jitter so a stationary press
    /// stays a clean click.
    ///
    /// Unrelated to the touchscreen thresholds above and deliberately much
    /// smaller — mouse mode has no gesture to decide, only noise to reject.
    var dragThreshold: Double = 1.5
}
