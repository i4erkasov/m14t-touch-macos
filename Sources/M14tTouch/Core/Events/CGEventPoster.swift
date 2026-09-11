import CoreGraphics
import Foundation

/// Posts synthetic mouse events into macOS.
///
/// The bottom of the stack: the single, obvious place where system events
/// originate — which matters because posting these requires Accessibility
/// permission. It knows how to post an event, never which one to post; that is
/// `MouseEventEmitter`'s decision.
struct CGEventPoster {

    /// `kCGEventMouseSubtypeTabletPoint`, which has no Swift constant.
    private static let tabletPointSubtype: Int64 = 1

    /// Emit a left-button event (down, up, or drag) at a screen point.
    ///
    /// - Parameter pressure: 0…1 to send the event as a tablet point carrying
    ///   that pressure, or nil for an ordinary mouse event. Measured: an event
    ///   marked as a tablet point arrives at an application with its pressure
    ///   intact, where a plain mouse event only ever carries 1 or 0
    ///   (`docs/M14t_PEN_CAPABILITIES.md`).
    func post(_ type: CGEventType, at point: CGPoint, pressure: Double? = nil) {
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
        if let pressure {
            event.setIntegerValueField(.mouseEventSubtype, value: Self.tabletPointSubtype)
            // Both fields, because applications read whichever they were written
            // against; they describe the same thing.
            event.setDoubleValueField(.mouseEventPressure, value: pressure)
            event.setDoubleValueField(.tabletEventPointPressure, value: pressure)
        }
        event.post(tap: .cghidEventTap)
    }
}
