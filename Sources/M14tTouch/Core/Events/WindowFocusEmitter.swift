import AppKit
import ApplicationServices
import Foundation

/// Brings the window under a point to the front, without clicking it.
///
/// Needed because of how zoom has to be delivered. `⌘=` is a menu command and
/// goes to the frontmost window, so pinching on the panel zoomed whatever was
/// active on another screen — the gesture and its effect in different places.
/// A click would fix the focus and press something on the way; the
/// accessibility interface raises a window without touching it.
///
/// Uses the permission the driver already requires. Where Accessibility is not
/// granted this simply does nothing, which is the same outcome as before.
struct WindowFocusEmitter: EventEmitter {

    /// How long to wait on an application that may be busy.
    ///
    /// Bounded because this asks *other* processes questions, and one of them
    /// being wedged must not become the touch pipeline being wedged. A tenth of
    /// a second is far longer than a healthy answer takes.
    private static let timeout: Float = 0.1

    func emit(_ action: InputAction) {
        guard case .focusWindow(let position) = action else { return }

        // Off the touch queue: even bounded, a round trip to another process
        // does not belong on the path that moves the pointer.
        DispatchQueue.global(qos: .userInitiated).async { Self.raiseWindow(at: position) }
    }

    private static func raiseWindow(at point: CGPoint) {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)

        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            system, Float(point.x), Float(point.y), &found
        ) == .success, let element = found else { return }
        AXUIElementSetMessagingTimeout(element, timeout)

        // Raising sorts the windows within the application…
        var container: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element, kAXWindowAttribute as CFString, &container
        ) == .success, let container, CFGetTypeID(container) == AXUIElementGetTypeID() {
            // swiftlint:disable:next force_cast
            AXUIElementPerformAction(container as! AXUIElement, kAXRaiseAction as CFString)
        }

        // …and activating brings the application itself forward, which is what
        // decides where a keystroke lands.
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        NSRunningApplication(processIdentifier: pid)?.activate()
    }
}
