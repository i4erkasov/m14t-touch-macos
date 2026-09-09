import Foundation

/// Everything a recognizer needs to tune how it reads a gesture (spec §4).
///
/// One home for these values rather than scattering them across recognizers,
/// because they are what the Settings window will edit in v0.3 — and because
/// step 8 of v0.2 exists to tune them against the panel. The defaults below are
/// **starting guesses**, not measurements.
struct GestureConfiguration: Equatable {

    // MARK: Tap

    /// How far a contact may wander, in screen pixels, and still count as a tap
    /// rather than the start of something else (spec §7.1).
    var tapMovementThreshold: Double = 8

    /// How long a contact may last and still count as a tap.
    ///
    /// A finger held longer is heading for a long press, even if it never moved.
    var tapMaxDuration: TimeInterval = 0.3

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
