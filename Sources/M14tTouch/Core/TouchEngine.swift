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

    init(
        recognizer: any GestureRecognizer,
        emitter: EventEmitter,
        cursorVisibility: CursorVisibilityController = CursorVisibilityController(
            enabled: false, visibility: PublicCursorVisibility()
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
        // Before the actions, so a hide is in force by the time an event moves
        // the pointer. Asserted every frame: one request does not hold.
        cursorVisibility.update(isTouching: frame.primaryContact?.isTouching ?? false)

        let actions = recognizer.process(frame)
        actions.forEach(emitter.emit)
        return actions
    }

    /// Abandon any gesture in progress, emitting whatever is needed to leave the
    /// system clean. Called when the device disappears mid-gesture.
    @discardableResult
    func reset() -> [InputAction] {
        // The device vanished mid-gesture; give the pointer back before anything
        // else, since no further frame will arrive to do it.
        cursorVisibility.restore()

        let actions = recognizer.reset()
        actions.forEach(emitter.emit)
        return actions
    }
}
