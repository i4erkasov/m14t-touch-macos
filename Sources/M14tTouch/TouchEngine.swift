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

    init(recognizer: any GestureRecognizer, emitter: EventEmitter) {
        self.recognizer = recognizer
        self.emitter = emitter
    }

    /// Feed one frame, emitting whatever it completes.
    ///
    /// Returns the emitted actions so the caller can log them. The driver used to
    /// print each press and drag as it posted it; routing that through the return
    /// value keeps the console output intact without giving the engine an opinion
    /// about logging.
    @discardableResult
    func process(_ frame: TouchFrame) -> [InputAction] {
        let actions = recognizer.process(frame)
        actions.forEach(emitter.emit)
        return actions
    }

    /// Abandon any gesture in progress, emitting whatever is needed to leave the
    /// system clean. Called when the device disappears mid-gesture.
    @discardableResult
    func reset() -> [InputAction] {
        let actions = recognizer.reset()
        actions.forEach(emitter.emit)
        return actions
    }
}
