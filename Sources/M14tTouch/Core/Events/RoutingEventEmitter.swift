import Foundation

/// Sends each action to the emitter that knows how to produce it.
///
/// Exists because scroll wheel events and mouse button events are built by
/// different CoreGraphics constructors with different rules, and neither
/// emitter should have to ignore actions meant for the other.
struct RoutingEventEmitter: EventEmitter {

    let mouse: EventEmitter
    let scroll: EventEmitter

    func emit(_ action: InputAction) {
        switch action {
        case .scroll, .scrollEnd:
            scroll.emit(action)
        case .tap, .pointerMove, .dragBegin, .dragMove, .dragEnd, .rightClick, .cursorRestore:
            mouse.emit(action)
        }
    }
}
