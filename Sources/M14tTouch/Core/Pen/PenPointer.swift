import CoreGraphics

/// What follows the pen on screen.
enum PenPointerStyle: String, CaseIterable, Codable {

    /// Whatever macOS would show anyway. The pointer is the system's.
    case arrow

    /// A dot the driver draws itself, with the arrow hidden underneath.
    ///
    /// One application cannot replace another's cursor image through public
    /// API — `NSCursor` applies only over the setting application's own windows
    /// while it is frontmost, and a touch driver is never the frontmost app. So
    /// the dot is drawn in an overlay and the arrow is hidden by the same
    /// facility the finger modes use.
    case dot

    /// Four arms around an empty centre, drawn the same way.
    ///
    /// The gap is the point of it: a dot covers what it is pointing at, which
    /// matters when the thing being aimed at is a few pixels wide.
    case crosshair

    var title: String {
        switch self {
        case .arrow:     return "System arrow"
        case .dot:       return "Dot"
        case .crosshair: return "Crosshair"
        }
    }

    /// Whether this style is drawn by the app rather than by macOS.
    var isDrawn: Bool { self != .arrow }
}

/// Something that can draw a pointer where the pen is.
///
/// A protocol so the driver can be built and tested without AppKit, and so the
/// pen pipeline never learns that a window is involved. Calls arrive on the
/// touch queue, at the rate the panel reports — an implementation is expected
/// to coalesce rather than to touch the interface once per sample.
protocol PenPointerDisplay: AnyObject {

    /// The pen is here, in Quartz global coordinates — the same space the
    /// events are posted in.
    func moved(to point: CGPoint)

    /// The pen has gone. Whatever was drawn should stop being drawn.
    func left()
}
