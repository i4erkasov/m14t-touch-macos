import CoreGraphics
import Foundation

/// Reads the panel as a touchscreen rather than a large absolute touchpad
/// (spec §7, §22, §35).
///
/// This version recognises taps and long-press drags. Moving far enough still
/// ends the gesture without doing anything; that becomes scrolling in v0.2
/// step 5.
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

        /// The contact moved too far to be a tap. Becomes `scrolling` in step 5;
        /// until then the gesture simply ends.
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
                // Reported at the point the finger landed, not where it left.
                // The landing point is what the user aimed at; the release may
                // have drifted a pixel or two.
                return [.tap(position: origin)]
            }

            // Time is checked before movement. If the deadline has already
            // passed, the gesture is a drag and this frame's movement belongs
            // to it — it is not the start of a scroll. In practice the ~100 Hz
            // tick notices the deadline long before a finger travels far, so
            // the two rarely compete in the same frame.
            if contact.timestamp - startedAt > configuration.longPressDelay {
                // Grabbing at the landing point, as a tap reports its landing
                // point: drift within the threshold is noise, and the user
                // pressed on what was under their finger when it went down.
                state = .dragging(lastPosition: origin)
                return [.dragBegin(position: origin)]
            }

            if distance(from: origin, to: contact.position) > configuration.scrollThreshold {
                state = .abandoned      // → scrolling, step 5
                return []
            }

            return []

        case .dragging(let lastPosition):
            guard contact.isTouching else {
                state = .idle
                // Ends on the last point actually emitted, so the drag path has
                // no final micro-jump. Unlike mouse mode, where the same
                // behaviour is an inherited quirk, here it is a choice.
                return [.dragEnd(position: lastPosition)]
            }

            // The same jitter filter mouse mode uses — a resting finger must not
            // wander the grabbed object around.
            guard distance(from: lastPosition, to: contact.position) > configuration.dragThreshold else {
                return []
            }
            state = .dragging(lastPosition: contact.position)
            return [.dragMove(position: contact.position)]

        case .abandoned:
            if !contact.isTouching { state = .idle }
            return []
        }
    }

    mutating func reset() -> [InputAction] {
        defer { state = .idle }
        // A drag is the only state holding a button down. Without this, unplugging
        // mid-drag would strand it pressed.
        guard case .dragging(let lastPosition) = state else { return [] }
        return [.dragEnd(position: lastPosition)]
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
