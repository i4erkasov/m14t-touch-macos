import Foundation

/// Everything a recognizer needs to tune how it reads a gesture (spec §4).
///
/// One home for these values rather than scattering them across recognizers,
/// because they are what the Settings window will edit in v0.3 — and because
/// step 8 of v0.2 exists to tune them against the panel. The defaults below are
/// **starting guesses**, not measurements.
struct GestureConfiguration: Equatable, Codable {

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

    // MARK: Which gestures are recognised at all (spec §14, §21)

    /// A short touch clicks.
    var tapEnabled: Bool = true

    /// A swipe scrolls.
    ///
    /// With this off a swipe does **nothing**: the contact is abandoned the
    /// moment it travels past the threshold, and releasing produces no click.
    /// That is deliberate rather than a gap — switching scrolling off is usually
    /// a wish for swipes to have no effect, and turning them into clicks instead
    /// would be a surprise.
    var oneFingerScrollEnabled: Bool = true

    /// Holding still becomes a drag.
    ///
    /// With this off the deadline is simply never reached, so a held contact
    /// stays a possible tap however long it lasts and releasing still clicks.
    /// Deliberately *not* the same treatment as scrolling: moving away is a
    /// different gesture, whereas holding still is the same gesture done slowly,
    /// and losing a click for being slow would be a poor trade.
    var longPressDragEnabled: Bool = true

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
    ///
    /// On by default. Judged on the panel: the arrow is visible arriving and
    /// leaving, which is unavoidable — the window server draws it wherever the
    /// click put it — but the round trip reads as acceptable, and leaving an
    /// arrow parked on a touchscreen does not.
    var restoreCursor: Bool = true

    /// Spread two fingers to zoom.
    ///
    /// On by default now that the panel is known to report five contacts. What
    /// it sends is ⌘ + scroll rather than a true magnification, which every
    /// browser, Preview, Photos and Finder understand — and some applications
    /// do not.
    var pinchToZoom: Bool = true

    /// How much the fingers must separate, in panel-mapped points, for one
    /// zoom step.
    ///
    /// Quantised deliberately, and coarsely. Each step is one press of ⌘=,
    /// which is a whole zoom level in the application receiving it — and
    /// applications have about ten of those. Fingers can separate by most of
    /// the panel's width, so a fine step would run from minimum to maximum in
    /// one spread.
    var zoomStep: Double = 120

    /// Swipe up with three fingers to show every window.
    ///
    /// Only up, and only this one gesture. The others a trackpad offers —
    /// application windows, switching desktops — are system shortcuts, and
    /// system shortcuts do not answer synthesised keystrokes. Offering a swipe
    /// that silently did nothing would be worse than not offering it.
    /// Hold one finger on something and tap with a second for a secondary
    /// click.
    ///
    /// The tap lands where the *first* finger is, not where the second one
    /// touched: the first finger is what the user is pointing at, and the
    /// second is only the instruction. That is what makes this better suited to
    /// a touchscreen than a trackpad's two-finger tap, which has no position of
    /// its own to speak of.
    ///
    /// A second finger that stays longer than `longPressDelay`, or that moves
    /// far enough to be spreading, is not a tap — it is a pinch, and is treated
    /// as one.
    var twoFingerSecondaryClick: Bool = true

    var threeFingerSwipe: Bool = true

    /// How far three fingers must travel before the swipe counts, in points.
    var swipeThreshold: Double = 120

    /// Keep scrolling after the finger lifts, slowing to a stop.
    ///
    /// What a trackpad does, and what the panel does not get for free: macOS
    /// generates the glide for its own devices, and a driver in user space has
    /// to produce it itself.
    var scrollMomentum: Bool = true

    /// When to hide the system pointer — the spec amendment's "Cursor during
    /// touch" setting.
    ///
    /// Worth knowing before switching it on: the window server makes the pointer
    /// visible again the moment it moves, so hiding only takes effect while the
    /// pointer is still. A scroll qualifies once under way; a tap and a drag do
    /// not, because they move the pointer by design.
    ///
    /// Requires a private API. When it is unavailable the setting is inert
    /// rather than an error.
    var cursorHiding: CursorHiding = .never

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

// MARK: - Storage

extension GestureConfiguration {

    /// Decoded field by field, each falling back to its default.
    ///
    /// The synthesised decoder would require every field to be present, so
    /// adding one setting in a later version would make an older saved file
    /// undecodable and silently reset *all* of them. Spec §28 schedules settings
    /// migration for v0.6; not creating the problem is cheaper than migrating it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = GestureConfiguration()

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) as? T ?? fallback
        }

        tapEnabled = value(.tapEnabled, fallback.tapEnabled)
        oneFingerScrollEnabled = value(.oneFingerScrollEnabled, fallback.oneFingerScrollEnabled)
        longPressDragEnabled = value(.longPressDragEnabled, fallback.longPressDragEnabled)
        scrollThreshold = value(.scrollThreshold, fallback.scrollThreshold)
        scrollSensitivity = value(.scrollSensitivity, fallback.scrollSensitivity)
        naturalScroll = value(.naturalScroll, fallback.naturalScroll)
        restoreCursor = value(.restoreCursor, fallback.restoreCursor)
        pinchToZoom = value(.pinchToZoom, fallback.pinchToZoom)
        zoomStep = value(.zoomStep, fallback.zoomStep)
        twoFingerSecondaryClick = value(.twoFingerSecondaryClick, fallback.twoFingerSecondaryClick)
        threeFingerSwipe = value(.threeFingerSwipe, fallback.threeFingerSwipe)
        swipeThreshold = value(.swipeThreshold, fallback.swipeThreshold)
        scrollMomentum = value(.scrollMomentum, fallback.scrollMomentum)
        cursorHiding = value(.cursorHiding, fallback.cursorHiding)
        longPressDelay = value(.longPressDelay, fallback.longPressDelay)
        dragThreshold = value(.dragThreshold, fallback.dragThreshold)
    }
}
