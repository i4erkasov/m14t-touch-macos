import Foundation

/// A way of making the system pointer invisible while a finger is on the panel.
///
/// Split behind a protocol because the only implementation that actually works
/// needs a private API, and that has to stay quarantined: nothing outside this
/// folder may know it exists, and the driver must run correctly when it does
/// not (spec amendment, requirement 1 and 2).
protocol CursorVisibility {

    /// Whether this implementation can do anything at all.
    var isAvailable: Bool { get }

    /// Ask for the pointer to be hidden. Called repeatedly, once per frame,
    /// because the window server does not honour a single request for long.
    func assertHidden()

    /// Undo every hide this implementation has asserted, exactly.
    func release()
}

/// The public-API implementation, which cannot hide anything.
///
/// `NSCursor.hide()` and `CGDisplayHideCursor()` only take effect while the
/// calling application is frontmost, and a touch driver never is — the user is
/// touching some other app. So this exists to be the honest answer when hiding
/// is switched off or unavailable, and to keep the rest of the code from having
/// to special-case a missing strategy.
struct PublicCursorVisibility: CursorVisibility {
    var isAvailable: Bool { false }
    func assertHidden() {}
    func release() {}
}
