import CoreGraphics
import Foundation

/// Remembers where the pointer was before the driver moved it, and puts it back.
///
/// Both input paths need this and for the same reason: a click carries its
/// position, so reaching the panel means taking the pointer there, and leaving
/// it parked on a touchscreen is not where the user put it. The finger returns
/// it at the end of a gesture, the pen when it leaves the panel.
///
/// The two calls that touch the pointer are injected rather than called
/// directly, so the logic — when to remember, when to give back, when to do
/// nothing — can be tested without moving the pointer of whoever runs the
/// suite. That is the same reason `MouseEventEmitter` keeps its mapping pure.
struct CursorParking {

    /// Where the pointer is now.
    var readLocation: () -> CGPoint? = { CGEvent(source: nil)?.location }

    /// Put the pointer there.
    var warp: (CGPoint) -> Void = { point in
        CGWarpMouseCursorPosition(point)
        // Without this the hardware mouse stays decoupled from the pointer and
        // the next trackpad movement snaps it back to where the warp came from.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private var parked: CGPoint?

    /// Whether somewhere to go back to is being held.
    var isParked: Bool { parked != nil }

    /// Called before every move. Captured at the first one rather than when a
    /// contact begins, because until something has been displaced there is
    /// nothing to remember — and capturing it twice would remember the panel.
    mutating func rememberIfNeeded() {
        guard parked == nil, let current = readLocation() else { return }
        parked = current
    }

    /// Give the pointer back, once. Does nothing if nothing was taken.
    mutating func restore() {
        guard let destination = parked else { return }
        parked = nil
        warp(destination)
    }

    /// Drop what was remembered without moving anything.
    ///
    /// For the case where returning the pointer is switched off: the next visit
    /// must still start from a fresh memory, or turning the setting back on
    /// would send the pointer somewhere it has not been for hours.
    mutating func forget() {
        parked = nil
    }
}
