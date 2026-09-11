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

    /// `kVK_ANSI_Equal` and `kVK_ANSI_Minus`. Named by position on the keyboard,
    /// not by character, so they are the same keys on any layout.
    private static let equal: CGKeyCode = 0x18
    private static let minus: CGKeyCode = 0x1B

    /// A bound on one gesture's worth of steps.
    ///
    /// Applications have perhaps ten zoom levels; a spread that produced fifty
    /// keystrokes would slam to the limit and take the keyboard with it for as
    /// long as it took. Beyond this many, the extra steps say nothing new.
    private static let maximumStepsAtOnce = 8

    func emit(_ action: InputAction) {
        guard case .zoom(let steps) = action, steps != 0 else { return }

        let key = steps > 0 ? Self.equal : Self.minus
        let count = min(abs(steps), Self.maximumStepsAtOnce)
        for _ in 0..<count { press(key) }
    }

    private func press(_ key: CGKeyCode) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
        else {
            FileHandle.standardError.write(
                Data("⚠️  Zoom CGEvent creation failed — is Accessibility permission granted?\n".utf8)
            )
            return
        }
        // The modifier travels on the key events themselves. Pressing Command
        // for real would leave a window in which any other keystroke — the
        // user's own — became a shortcut.
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
