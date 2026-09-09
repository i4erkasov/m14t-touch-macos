import CoreGraphics
import Foundation

/// Posts synthetic mouse events into macOS.
///
/// The bottom of the stack: the single, obvious place where system events
/// originate — which matters because posting these requires Accessibility
/// permission. It knows how to post an event, never which one to post; that is
/// `MouseEventEmitter`'s decision.
struct CGEventPoster {

    /// Emit a left-button event (down, up, or drag) at a screen point.
    func post(_ type: CGEventType, at point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            FileHandle.standardError.write(
                Data("⚠️  CGEvent creation failed — is Accessibility permission granted?\n".utf8)
            )
            return
        }
        event.post(tap: .cghidEventTap)
    }
}
