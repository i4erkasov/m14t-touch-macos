import Foundation

/// Interprets a stream of `TouchFrame`s as user intent.
///
/// Conforming types are the only place that decides what a finger *means*. They
/// see nothing but frames and produce nothing but `InputAction`s — no IOKit, no
/// CoreGraphics, no calibration — which is what allows gesture semantics to be
/// asserted in unit tests with no hardware attached (spec §32).
///
/// Implementations are stateful by nature: a gesture is a shape traced over
/// several frames, so `process` is `mutating` and the caller must feed frames in
/// order.
protocol GestureRecognizer {

    /// Consume one frame and return the actions it completes, in order.
    ///
    /// Returns an array rather than a single action because a frame can complete
    /// more than one — v0.2's touchscreen mode resolves a held contact into
    /// `dragBegin` followed immediately by `dragMove`. v0.1 returns zero or one.
    mutating func process(_ frame: TouchFrame) -> [InputAction]

    /// Abandon any gesture in progress, returning whatever is needed to leave
    /// the system in a clean state.
    ///
    /// Called when the device disappears mid-gesture. Without it a contact held
    /// at unplug would leave the mouse button stuck down with no finger left to
    /// release it.
    mutating func reset() -> [InputAction]
}
