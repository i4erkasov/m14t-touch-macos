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

    /// The scrolling gesture is over — the finger has lifted.
    ///
    /// A separate action because macOS distinguishes a scroll *gesture* from a
    /// wheel *turn*, and only the former gets rubber-banding and smooth
    /// continuous scrolling. Telling it where the gesture ends is the price of
    /// being treated as the first kind.
    case scrollEnd

    /// Secondary click at a point.
    /// Not produced in v0.1 (spec §11).
    case rightClick(position: CGPoint)

    /// Return the pointer to wherever it was before this gesture moved it.
    ///
    /// Touchscreen mode has to put the cursor on the target — a scroll event
    /// has no destination of its own, and a click carries its position as a
    /// warp. Hiding the cursor instead is not possible with public APIs and is
    /// forbidden by spec §10 and §32, so the next best thing is to put it back
    /// afterwards and leave the arrow where the user parked it.
    case cursorRestore
}
