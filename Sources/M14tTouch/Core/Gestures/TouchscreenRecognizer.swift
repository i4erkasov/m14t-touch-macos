import CoreGraphics
import Foundation

/// Reads the panel as a touchscreen rather than a large absolute touchpad
/// (spec §7, §22, §35).
///
/// Recognises taps, one-finger scrolling and long-press drags (spec §7–8).
///
/// The gesture lock is the load-bearing rule: once a contact has committed to
/// scrolling it stays scrolling until release, and the long-press deadline is
/// never consulted again. Without it a slow scroll turns into a drag partway
/// through and starts selecting text.
struct TouchscreenRecognizer: GestureRecognizer {

    let configuration: GestureConfiguration

    /// Spec §22 asks for an explicit state machine. This is the part of it that
    /// exists so far.
    private enum State {
        case idle

        /// A finger is down and could still turn out to be a tap.
        case possibleTap(origin: CGPoint, startedAt: TimeInterval)

        /// Held long enough to become a drag. Carries the last emitted point,
        /// which makes it impossible to consult a stale one while idle.
        case dragging(lastPosition: CGPoint)

        /// Committed to scrolling. Carries the point the last delta was
        /// measured from.
        case scrolling(lastPosition: CGPoint)

        /// The contact did something this configuration does not recognise, and
        /// nothing more will come of it until the finger lifts.
        case abandoned
    }

    private var state: State = .idle

    init(configuration: GestureConfiguration) {
        self.configuration = configuration
    }

    mutating func process(_ frame: TouchFrame) -> [InputAction] {
        guard let contact = frame.primaryContact else { return [] }

        switch state {

        case .idle:
            guard contact.isTouching else { return [] }
            state = .possibleTap(origin: contact.position, startedAt: contact.timestamp)
            // Nothing is emitted on contact. That is the whole difference from
            // mouse mode: a touch commits to nothing until it is understood.
            return []

        case .possibleTap(let origin, let startedAt):
            guard contact.isTouching else {
                state = .idle
                guard configuration.tapEnabled else { return finishing(with: nil) }
                // Reported at the point the finger landed, not where it left.
                // The landing point is what the user aimed at; the release may
                // have drifted a pixel or two.
                return finishing(with: .tap(position: origin))
            }

            // Time is checked before movement. If the deadline has already
            // passed, the gesture is a drag and this frame's movement belongs
            // to it — it is not the start of a scroll. In practice the ~100 Hz
            // tick notices the deadline long before a finger travels far, so
            // the two rarely compete in the same frame.
            if configuration.longPressDragEnabled,
               contact.timestamp - startedAt > configuration.longPressDelay {
                // Grabbing at the landing point, as a tap reports its landing
                // point: drift within the threshold is noise, and the user
                // pressed on what was under their finger when it went down.
                state = .dragging(lastPosition: origin)
                return [.dragBegin(position: origin)]
            }

            if distance(from: origin, to: contact.position) > configuration.scrollThreshold {
                guard configuration.oneFingerScrollEnabled else {
                    // Travelled too far to be a tap, and scrolling is switched
                    // off, so nothing happens until the finger lifts.
                    state = .abandoned
                    return []
                }

                // Measured from where the finger is now, so the movement that
                // committed to the scroll is consumed by the commitment rather
                // than scrolling the page by the threshold distance.
                state = .scrolling(lastPosition: contact.position)

                // A scroll event carries no destination — it goes wherever the
                // cursor is. So the cursor has to be put on the target once, at
                // the start; it is not moved again for the rest of the gesture.
                // See the cursor policy in docs/v0.2-touchscreen-plan.md.
                return [.pointerMove(position: origin)]
            }

            return []

        case .dragging(let lastPosition):
            guard contact.isTouching else {
                state = .idle
                // Ends on the last point actually emitted, so the drag path has
                // no final micro-jump. Unlike mouse mode, where the same
                // behaviour is an inherited quirk, here it is a choice.
                return finishing(with: .dragEnd(position: lastPosition))
            }

            // The same jitter filter mouse mode uses — a resting finger must not
            // wander the grabbed object around.
            guard distance(from: lastPosition, to: contact.position) > configuration.dragThreshold else {
                return []
            }
            state = .dragging(lastPosition: contact.position)
            return [.dragMove(position: contact.position)]

        case .scrolling(let lastPosition):
            guard contact.isTouching else {
                state = .idle
                return finishing(with: nil)
            }

            // Note what is *not* here: the long-press deadline. That is the lock.
            let deltaX = contact.position.x - lastPosition.x
            let deltaY = contact.position.y - lastPosition.y
            guard deltaX != 0 || deltaY != 0 else { return [] }

            state = .scrolling(lastPosition: contact.position)

            // Deltas describe how the finger moved, scaled by sensitivity and
            // flipped when natural scrolling is off. Turning that into the sign
            // a CGEvent wants is the emitter's business — spec §23 requires the
            // wheel direction be established on the device, not assumed here.
            let sign = configuration.naturalScroll ? 1.0 : -1.0
            let scale = configuration.scrollSensitivity * sign
            return [.scroll(deltaX: deltaX * scale, deltaY: deltaY * scale)]

        case .abandoned:
            if !contact.isTouching { state = .idle }
            return []
        }
    }

    /// Close out a gesture, adding the cursor restore when it is switched on.
    ///
    /// Always last, so the pointer goes home only after the click or release it
    /// was moved for has actually been posted.
    private func finishing(with action: InputAction?) -> [InputAction] {
        var actions = action.map { [$0] } ?? []
        if configuration.restoreCursor { actions.append(.cursorRestore) }
        return actions
    }

    mutating func reset() -> [InputAction] {
        defer { state = .idle }
        // A drag is the only state holding a button down. Without this, unplugging
        // mid-drag would strand it pressed.
        guard case .dragging(let lastPosition) = state else { return [] }
        return finishing(with: .dragEnd(position: lastPosition))
    }

    /// Straight-line distance, unlike mouse mode's per-axis comparison.
    ///
    /// Mouse mode measures each axis separately because that is what the
    /// original driver did, and changing it would have been a behaviour change.
    /// Here there is nothing to preserve, and "how far did the finger wander" is
    /// a distance — judging the axes separately would let a diagonal drift
    /// travel 1.4× the threshold and still count as stationary.
    private func distance(from origin: CGPoint, to point: CGPoint) -> Double {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
