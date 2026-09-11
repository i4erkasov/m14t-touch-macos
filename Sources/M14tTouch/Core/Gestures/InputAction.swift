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

    /// Bring whatever is at this point to the front, without clicking it.
    ///
    /// Zoom is delivered as ⌘= , which goes to the frontmost window — so
    /// pinching on the panel zoomed whatever happened to be active elsewhere.
    /// Clicking to fix that would press whatever is under the fingers; asking
    /// the accessibility interface to raise the window does not.
    case focusWindow(position: CGPoint)

    /// Show every open window — what a trackpad does for three fingers up.
    ///
    /// Named for what the user wanted rather than for how it is delivered,
    /// because how it is delivered was not a free choice: macOS's own shortcut
    /// for this cannot be triggered by a synthesised keystroke, and opening
    /// `Mission Control.app` is the route that does work
    /// (`docs/pinch-and-multitouch.md`).
    case showAllWindows

    /// Zoom by whole steps, positive to zoom in.
    ///
    /// Steps rather than a continuous scale, because what carries this is
    /// ⌘ + scroll: a real `.magnify` event cannot be built with public APIs
    /// (`docs/pinch-and-multitouch.md`), and the substitute is discrete by
    /// nature. Quantising in the recognizer keeps the decision — how much
    /// spreading is worth one step — where it can be tested.
    case zoom(steps: Int)

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
