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
    case touchscreen

    /// Build the recognizer for this mode.
    ///
    /// The extension point: a new gesture model is a new case here and a type
    /// implementing `GestureRecognizer`. The driver, the engine, the emitters
    /// and the CLI need no changes.
    func makeRecognizer(config: TouchConfig) -> any GestureRecognizer {
        switch self {
        case .mouse:
            return MouseModeRecognizer(dragThreshold: config.gestures.dragThreshold)
        case .touchscreen:
            return TouchscreenRecognizer(configuration: config.gestures)
        }
    }
}
