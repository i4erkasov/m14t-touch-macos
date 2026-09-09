import Foundation

/// Which gesture model interprets the touch stream.
///
/// The extension point v0.1 exists to create (spec §9, §28). Adding the
/// touchscreen mode in v0.2 means writing a recognizer and returning it from
/// `makeRecognizer` — the driver, the engine, the emitters and the CLI stay as
/// they are.
enum TouchMode: String, CaseIterable {

    /// The original behaviour: contact presses the left button, movement drags,
    /// release releases. Kept permanently as the compatibility fallback.
    case mouse

    /// Tap to click, one-finger scroll, long press to drag (spec §7–8).
    /// Not implemented yet.
    case touchscreen

    /// Build the recognizer for this mode, or `nil` if it does not exist yet.
    ///
    /// Deliberately the single place that knows what is implemented, so the
    /// "not yet" answer cannot drift out of step with reality: a mode that
    /// returns a recognizer is available, and one that returns `nil` is not.
    func makeRecognizer(config: TouchConfig) -> (any GestureRecognizer)? {
        switch self {
        case .mouse:
            return MouseModeRecognizer(dragThreshold: config.gestures.dragThreshold)
        case .touchscreen:
            return nil
        }
    }
}
