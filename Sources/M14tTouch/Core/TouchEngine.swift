import Foundation

/// Joins gesture recognition to event emission.
///
/// Small on purpose. Its whole job is to own the pairing of a recognizer with an
/// emitter and to pump one into the other, so that `HIDTouchDriver` can hand off
/// a frame without knowing which gesture model is active or how events reach
/// macOS. Swapping mouse mode for the v0.2 touchscreen mode is then a matter of
/// constructing this with a different recognizer.
final class TouchEngine {

    private var recognizer: any GestureRecognizer
    private let emitter: EventEmitter
    private let cursorVisibility: CursorVisibilityController

    /// Whether touch is being translated at all — the menu's "Enable touch".
    ///
    /// Queue-confined like everything else here; the app changes it through the
    /// driver, which hops onto the queue to do so.
    private var isEnabled = true

    /// Whether the gesture in progress has committed to scrolling.
    ///
    /// Read from the actions rather than asked of the recognizer, so mouse mode
    /// does not have to answer a question it has no notion of. A scroll action
    /// says the phase began; a frame without contact says it ended.
    private var isScrolling = false

    init(
        recognizer: any GestureRecognizer,
        emitter: EventEmitter,
        cursorVisibility: CursorVisibilityController = CursorVisibilityController(
            policy: .never, visibility: PublicCursorVisibility()
        )
    ) {
        self.recognizer = recognizer
        self.emitter = emitter
        self.cursorVisibility = cursorVisibility
    }

    /// Feed one frame, emitting whatever it completes.
    ///
    /// Returns the emitted actions so the caller can log them. The driver used to
    /// print each press and drag as it posted it; routing that through the return
    /// value keeps the console output intact without giving the engine an opinion
    /// about logging.
    @discardableResult
    func process(_ frame: TouchFrame) -> [InputAction] {
        guard isEnabled else { return [] }

        let isTouching = frame.primaryContact?.isTouching ?? false
        if !isTouching { isScrolling = false }

        // Before the actions, so a hide is in force by the time an event moves
        // the pointer. Asserted every frame: one request does not hold.
        cursorVisibility.update(isTouching: isTouching, isScrolling: isScrolling)

        let actions = recognizer.process(frame)
        if actions.contains(where: { if case .scroll = $0 { return true } else { return false } }) {
            isScrolling = true
        }
        actions.forEach(emitter.emit)
        return actions
    }

    /// Turn translation on or off.
    ///
    /// Switching off abandons whatever is in progress rather than freezing it:
    /// a gesture interrupted halfway must not leave a button held or the pointer
    /// hidden, and resuming into the middle of a gesture whose finger has long
    /// since lifted would be worse than starting fresh.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if !enabled { reset() }
        isEnabled = enabled
    }

    /// Swap the gesture model without restarting the driver.
    ///
    /// The outgoing recognizer is reset first, for the same reason: its state
    /// describes a gesture the new one knows nothing about, and anything it is
    /// holding has to be given back before it is discarded.
    func setRecognizer(_ replacement: any GestureRecognizer) {
        reset()
        recognizer = replacement
    }

    /// Abandon any gesture in progress, emitting whatever is needed to leave the
    /// system clean. Called when the device disappears mid-gesture.
    @discardableResult
    func reset() -> [InputAction] {
        // The device vanished mid-gesture; give the pointer back before anything
        // else, since no further frame will arrive to do it.
        cursorVisibility.restore()
        isScrolling = false

        let actions = recognizer.reset()
        actions.forEach(emitter.emit)
        return actions
    }
}
