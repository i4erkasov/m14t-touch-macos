import CoreGraphics
@testable import M14tTouch

/// An `EventEmitter` that records instead of posting.
///
/// Shared across the emitter and recognizer tests. Substituting this for
/// `MouseEventEmitter` is what makes the pipeline observable: real emission
/// vanishes into the window server, and running it in a test would move the
/// machine's actual cursor.
final class RecordingEventEmitter: EventEmitter {

    private(set) var actions: [InputAction] = []

    func emit(_ action: InputAction) {
        actions.append(action)
    }

    func reset() {
        actions.removeAll()
    }
}
