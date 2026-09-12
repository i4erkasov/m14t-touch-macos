import CoreGraphics
import Foundation

/// Sends keystrokes.
///
/// Shared by the zoom gesture and the pen's buttons, which want the same thing
/// for different reasons. Keyed by position rather than by character — the
/// codes are physical keys, so a mapping means the same thing on any layout.
struct KeyboardPoster {

    /// `kVK_*`, by the name the key has on a US keyboard.
    enum Key: CGKeyCode {
        case z = 0x06
        case c = 0x08
        case v = 0x09
        case equal = 0x18
        case minus = 0x1B
        case space = 0x31
        case escape = 0x35
        case delete = 0x33
    }

    /// Press and release, with the modifiers riding on the key events.
    ///
    /// The modifier travels on the events rather than being held down for real:
    /// a genuine Command press would leave a window in which the user's own
    /// next keystroke became a shortcut.
    func press(_ key: Key, flags: CGEventFlags = []) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: false)
        else {
            FileHandle.standardError.write(
                Data("⚠️  Keyboard CGEvent creation failed — is Accessibility permission granted?\n".utf8)
            )
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
