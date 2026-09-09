import CoreGraphics
import Foundation

/// Reads the panel as a touchscreen rather than a large absolute touchpad
/// (spec §7, §22, §35).
///
/// This version recognises taps and nothing else. The two ways a contact stops
/// being a tap — moving too far, or being held too long — are already here, but
/// what they turn into arrives in later steps: scrolling in v0.2 step 5,
/// long-press dragging in step 4.
struct TouchscreenRecognizer: GestureRecognizer {

    let configuration: GestureConfiguration

    /// Spec §22 asks for an explicit state machine. This is the part of it that
    /// exists so far.
    private enum State {
        case idle

        /// A finger is down and could still turn out to be a tap.
        case possibleTap(origin: CGPoint, startedAt: TimeInterval)

        /// The contact left `possibleTap` and this version has nothing further
        /// to do with it. Replaced by `scrolling` and `dragging` in steps 4–5.
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

            if distance(from: origin, to: contact.position) > configuration.scrollThreshold {
                state = .abandoned      // → scrolling, step 5
                return []
            }

            if contact.timestamp - startedAt > configuration.longPressDelay {
                state = .abandoned      // → dragging, step 4
                return []
            }

            return []

        case .abandoned:
            if !contact.isTouching { state = .idle }
            return []
        }
    }

    mutating func reset() -> [InputAction] {
        // Nothing to release: this version never presses anything until the
        // gesture is already over.
        state = .idle
        return []
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
