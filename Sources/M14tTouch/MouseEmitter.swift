import CoreGraphics
import Foundation

/// Posts synthetic mouse events into macOS.
///
/// Wrapping `CGEvent` here keeps the driver's touch logic free of CoreGraphics
/// boilerplate and gives a single, obvious place where system events originate —
/// which matters because posting these requires Accessibility permission.
struct MouseEmitter {

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
