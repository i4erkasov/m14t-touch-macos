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
    var parking = CursorParking()

    func emit(_ action: InputAction) {
        if case .cursorRestore = action {
            parking.restore()
            return
        }

        let events = Self.mouseEvents(for: action)
        guard !events.isEmpty else {
            reportUnsupported(action)
            return
        }

        parking.rememberIfNeeded()
        for event in events {
            poster.post(event.type, at: event.point)
        }
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
        case .rightClick, .scroll, .scrollEnd, .zoom, .showAllWindows, .focusWindow,
             .cursorRestore:
            return []
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
