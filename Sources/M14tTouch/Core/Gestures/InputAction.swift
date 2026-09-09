import CoreGraphics

/// An abstract input intent produced by gesture recognition.
///
/// The point of this type is that it is *not* a `CGEvent`. A `GestureRecognizer`
/// decides what the user meant; an `EventEmitter` decides how macOS is told about
/// it. Keeping those apart is what lets gesture semantics be asserted in unit
/// tests — a test can compare `[InputAction]` for equality, which it could never
/// do against events posted into the window server (spec §6, §32).
enum InputAction: Equatable, Sendable {

    /// A completed tap: press and release at one point, no drag in between.
    /// Not produced in v0.1 — mouse mode has no notion of a tap (spec §7.1).
    case tap(position: CGPoint)

    /// Move the cursor without pressing anything.
    /// Not produced in v0.1 (spec §10).
    case pointerMove(position: CGPoint)

    /// Press and hold at a point, starting a drag.
    case dragBegin(position: CGPoint)

    /// Continue a drag that has already begun.
    case dragMove(position: CGPoint)

    /// Release, ending a drag.
    case dragEnd(position: CGPoint)

    /// Scroll by a pixel delta.
    /// Not produced in v0.1 (spec §7.2, §23).
    case scroll(deltaX: CGFloat, deltaY: CGFloat)

    /// Secondary click at a point.
    /// Not produced in v0.1 (spec §11).
    case rightClick(position: CGPoint)
}
