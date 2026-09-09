import CoreGraphics
import Foundation

/// Translates `InputAction`s into mouse events.
///
/// Deliberately split in two: `mouseEvents(for:)` is a pure function deciding
/// *which* events an action corresponds to, and is unit tested; the posting
/// itself is delegated to `CGEventPoster`. That split matters because posting
/// cannot be tested — a test that exercised it would really move the user's
/// cursor.
final class MouseEventEmitter: EventEmitter {

    private let poster = CGEventPoster()

    /// Where the pointer was before the current gesture moved it.
    ///
    /// Captured at the moment of the first move rather than when the finger
    /// lands, because until then nothing has displaced it and there is nothing
    /// to remember.
    private var parkedCursor: CGPoint?

    func emit(_ action: InputAction) {
        if case .cursorRestore = action {
            restoreCursor()
            return
        }

        let events = Self.mouseEvents(for: action)
        guard !events.isEmpty else {
            reportUnsupported(action)
            return
        }

        if parkedCursor == nil, let current = CGEvent(source: nil)?.location {
            parkedCursor = current
        }
        for event in events {
            poster.post(event.type, at: event.point)
        }
    }

    private func restoreCursor() {
        guard let parked = parkedCursor else { return }
        parkedCursor = nil
        CGWarpMouseCursorPosition(parked)
        // Without this the hardware mouse stays decoupled from the pointer and
        // the next trackpad movement snaps it back to where the warp came from.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// The mouse events an action maps to, in order. Empty when this emitter
    /// does not handle it.
    ///
    /// A tap is a press and a release at one point — the two are emitted back to
    /// back rather than the recognizer holding a button between them, because in
    /// touchscreen mode a tap is only *known* to be a tap once the finger has
    /// already left.
    ///
    /// `pointerMove` exists to place the cursor before a scroll: a scroll event
    /// has no destination and goes wherever the cursor is. A mouse-moved event
    /// is used rather than warping the pointer so that applications see a normal
    /// move and update hover state accordingly.
    ///
    /// `scroll` returns empty on purpose — `ScrollEventEmitter` owns it, and
    /// `RoutingEventEmitter` sends it there. `rightClick` waits for two-finger
    /// gestures (spec §11).
    static func mouseEvents(for action: InputAction) -> [(type: CGEventType, point: CGPoint)] {
        switch action {
        case .dragBegin(let position):  return [(.leftMouseDown, position)]
        case .dragMove(let position):   return [(.leftMouseDragged, position)]
        case .dragEnd(let position):    return [(.leftMouseUp, position)]
        case .tap(let position):        return [(.leftMouseDown, position), (.leftMouseUp, position)]
        case .pointerMove(let position): return [(.mouseMoved, position)]
        case .rightClick, .scroll, .cursorRestore: return []
        }
    }

    /// Complain loudly rather than dropping the action silently — a recognizer
    /// emitting something no emitter handles is a wiring bug, and a silent no-op
    /// would present as "touch just does nothing".
    private func reportUnsupported(_ action: InputAction) {
        FileHandle.standardError.write(
            Data("⚠️  MouseEventEmitter cannot handle \(action)\n".utf8)
        )
    }
}
