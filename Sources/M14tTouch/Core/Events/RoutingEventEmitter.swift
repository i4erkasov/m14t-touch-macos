import Foundation

/// Sends each action to the emitter that knows how to produce it.
///
/// Exists because scroll wheel events and mouse button events are built by
/// different CoreGraphics constructors with different rules, and neither
/// emitter should have to ignore actions meant for the other.
struct RoutingEventEmitter: EventEmitter {

    let mouse: EventEmitter
    let scroll: EventEmitter

    /// Zoom is a menu command, not a scroll — established by measurement, see
    /// `KeyboardEventEmitter`. Defaulted so the many places that build one of
    /// these for a test need not know.
    var keyboard: EventEmitter = KeyboardEventEmitter()

    /// Asking the system for something, rather than sending it input.
    var workspace: EventEmitter = WorkspaceEventEmitter()

    /// Putting a window in front, so that a keystroke reaches it.
    var focus: EventEmitter = WindowFocusEmitter()

    func emit(_ action: InputAction) {
        switch action {
        case .showAllWindows:
            workspace.emit(action)
        case .focusWindow:
            focus.emit(action)
        case .zoom:
            keyboard.emit(action)
        case .scroll, .scrollEnd, .scrollMomentum:
            scroll.emit(action)
        case .tap, .pointerMove, .dragBegin, .dragMove, .dragEnd, .rightClick, .cursorRestore:
            mouse.emit(action)
        }
    }
}
