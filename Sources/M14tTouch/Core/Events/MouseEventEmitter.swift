import CoreGraphics
import Foundation

/// Translates `InputAction`s into left-button mouse events.
///
/// Deliberately split in two: `mouseEvent(for:)` is a pure function deciding
/// *which* event an action corresponds to, and is unit tested; the posting
/// itself is delegated to `CGEventPoster`. That split matters because posting
/// cannot be tested — a test that exercised it would really move the user's
/// cursor.
struct MouseEventEmitter: EventEmitter {

    private let poster = CGEventPoster()

    func emit(_ action: InputAction) {
        guard let event = Self.mouseEvent(for: action) else {
            reportUnsupported(action)
            return
        }
        poster.post(event.type, at: event.point)
    }

    /// The mouse event an action maps to, or `nil` if this emitter does not
    /// handle it.
    ///
    /// The drag triad is the whole of v0.1: it reproduces the original driver's
    /// touch model exactly — finger down is a press, movement past the threshold
    /// is a drag, release is a release.
    ///
    /// The remaining cases return `nil` on purpose rather than being guessed at
    /// now. `scroll` belongs to a future `ScrollEventEmitter` (spec §23), and
    /// `tap` / `pointerMove` / `rightClick` cannot be settled until v0.2 decides
    /// the cursor policy — whether a tap moves the cursor to the touch point or
    /// clicks without disturbing it is a user-facing choice that spec §10 leaves
    /// open.
    static func mouseEvent(for action: InputAction) -> (type: CGEventType, point: CGPoint)? {
        switch action {
        case .dragBegin(let position): return (.leftMouseDown, position)
        case .dragMove(let position):  return (.leftMouseDragged, position)
        case .dragEnd(let position):   return (.leftMouseUp, position)
        case .tap, .pointerMove, .rightClick, .scroll: return nil
        }
    }

    /// Complain loudly rather than dropping the action silently — a recognizer
    /// emitting something no emitter handles is a wiring bug, and a silent no-op
    /// would present as "touch just does nothing".
    private func reportUnsupported(_ action: InputAction) {
        FileHandle.standardError.write(
            Data("⚠️  MouseEventEmitter cannot handle \(action) — not implemented until v0.2\n".utf8)
        )
    }
}
