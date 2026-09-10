import Foundation

/// When the system pointer should be hidden while the panel is in use.
///
/// The spec amendment's "Cursor during touch" setting.
enum CursorHiding: String, CaseIterable, Codable {

    /// Leave the pointer alone.
    case never

    /// Hide only once a gesture has committed to scrolling.
    ///
    /// The case that actually works well: during a scroll the pointer is placed
    /// once and then stays put, and the window server only keeps it hidden while
    /// it is still.
    case scrolling

    /// Hide whenever a finger is on the panel.
    ///
    /// Honest about its limits: a tap is over in a moment, and a drag moves the
    /// pointer continuously, so both make it visible again regardless. This
    /// setting mostly differs from `scrolling` by also hiding during the pause
    /// before a long press resolves.
    case touching

    var hidesAnything: Bool { self != .never }
}
