import CoreGraphics
import Foundation

/// Turns actions that are really menu commands into keystrokes.
///
/// Zoom is the first of them, and it arrived here by measurement. The obvious
/// route was ⌘ + scroll, which is what a mouse wheel with Command held sends —
/// but on this machine the browser read it as a plain scroll and ran to the top
/// of the page, both with the Command flag set on the event and with the key
/// genuinely held down. `⌘=` and `⌘-` zoomed immediately.
///
/// The consequence worth stating: a keystroke goes to the **frontmost window**,
/// not to whatever is under the fingers. For zoom that is usually the same
/// thing — people zoom what they are looking at — but it is a real difference
/// from scrolling, which is delivered under the pointer.
struct KeyboardEventEmitter: EventEmitter {

    /// A bound on one gesture's worth of steps.
    ///
    /// Applications have perhaps ten zoom levels; a spread that produced fifty
    /// keystrokes would slam to the limit and take the keyboard with it for as
    /// long as it took. Beyond this many, the extra steps say nothing new.
    private static let maximumStepsAtOnce = 8

    private let keyboard = KeyboardPoster()

    func emit(_ action: InputAction) {
        guard case .zoom(let steps) = action, steps != 0 else { return }

        let key: KeyboardPoster.Key = steps > 0 ? .equal : .minus
        let count = min(abs(steps), Self.maximumStepsAtOnce)
        for _ in 0..<count { keyboard.press(key, flags: .maskCommand) }
    }
}
