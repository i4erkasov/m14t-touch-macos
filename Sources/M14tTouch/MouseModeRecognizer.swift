import CoreGraphics
import Foundation

/// The original driver's touch model, as a recognizer.
///
/// One contact maps straight onto the left mouse button: contact is a press,
/// movement past a threshold is a drag, release is a release. A press-release
/// without movement is therefore a click and a press-move-release is a drag.
///
/// This is `Mouse Mode` from spec §9, kept permanently as the compatibility
/// fallback for the touchscreen mode arriving in v0.2. It reproduces the
/// pre-refactor behaviour of `HIDTouchDriver` exactly — including two quirks
/// that are preserved deliberately so any regression is unambiguously the
/// refactor's fault (see docs/v0.1-refactor-plan.md):
///
/// - **Release fires at the last emitted point**, not at the position reported
///   with the release itself.
/// - **Movement is judged per axis**, against a strict `>` threshold.
struct MouseModeRecognizer: GestureRecognizer {

    /// Minimum movement, in screen pixels, before a held contact counts as a
    /// drag. Filters panel jitter so a stationary press stays a clean click.
    let dragThreshold: Double

    /// Mouse mode has only two states. The richer machine spec §22 describes —
    /// `possibleTap`, `scrolling`, `waitingForLongPress` — belongs to the
    /// touchscreen recognizer in v0.2; modelling it here would be pretending to
    /// distinctions this mode does not make.
    ///
    /// `dragging` carries the last emitted position, which makes it structurally
    /// impossible to consult a stale point while idle.
    private enum State {
        case idle
        case dragging(lastPosition: CGPoint)
    }

    private var state: State = .idle

    init(dragThreshold: Double) {
        self.dragThreshold = dragThreshold
    }

    mutating func process(_ frame: TouchFrame) -> [InputAction] {
        guard let contact = frame.primaryContact else { return [] }

        switch (state, contact.isTouching) {

        case (.idle, true):
            state = .dragging(lastPosition: contact.position)
            return [.dragBegin(position: contact.position)]

        case (.dragging(let lastPosition), false):
            state = .idle
            // Deliberately `lastPosition`, not `contact.position` — matches the
            // original driver, which released wherever the last event landed.
            return [.dragEnd(position: lastPosition)]

        case (.dragging(let lastPosition), true):
            guard moved(from: lastPosition, to: contact.position) else { return [] }
            state = .dragging(lastPosition: contact.position)
            return [.dragMove(position: contact.position)]

        case (.idle, false):
            return []
        }
    }

    mutating func reset() -> [InputAction] {
        guard case .dragging(let lastPosition) = state else { return [] }
        state = .idle
        return [.dragEnd(position: lastPosition)]
    }

    /// Per-axis comparison against a strict threshold, as the original driver
    /// did. Diagonal movement is therefore *not* judged by distance: a contact
    /// can travel further than the threshold overall while moving less than it
    /// on both axes, and that does not count as a drag.
    private func moved(from origin: CGPoint, to destination: CGPoint) -> Bool {
        abs(destination.x - origin.x) > dragThreshold
            || abs(destination.y - origin.y) > dragThreshold
    }
}
