import CoreGraphics
import Foundation

/// Where pen actions become macOS events (pen spec §19).
protocol PenEventBackend {
    func handle(_ action: PenAction)
}

/// The fallback backend from pen spec §21: pen actions as ordinary mouse events.
///
/// Called a fallback because it cannot carry pressure — a mouse event has
/// nowhere to put it. Tablet events can, and they turn out to be public API, but
/// whether applications honour synthesised ones is still unmeasured, so the
/// thing that works everywhere is what ships first.
struct PenMouseBackend: PenEventBackend {

    private let poster = CGEventPoster()

    func handle(_ action: PenAction) {
        for event in Self.mouseEvents(for: action) {
            poster.post(event.type, at: event.point)
        }
    }

    /// The events an action becomes. Pure, and therefore tested.
    ///
    /// Proximity is the interesting one. Moving the pointer the moment the pen
    /// arrives is the whole fix: without it the pointer stays wherever it was —
    /// on the MacBook, most likely — and hovering over the panel drags it around
    /// a screen the pen is not near (pen spec §11).
    ///
    /// The eraser is deliberately unmapped. Turning a stroke of it into a left
    /// click would be a guess, and what it should do is a setting that arrives
    /// with the other button mappings.
    static func mouseEvents(for action: PenAction) -> [(type: CGEventType, point: CGPoint)] {
        switch action {
        case .proximityEntered(let position):
            return [(.mouseMoved, position)]

        case .hover(let position):
            return [(.mouseMoved, position)]

        case .contactBegan(.tip, let position, _):
            return [(.leftMouseDown, position)]

        case .contactMoved(.tip, let position, _):
            return [(.leftMouseDragged, position)]

        case .contactEnded(.tip, let position):
            return [(.leftMouseUp, position)]

        case .contactBegan(.eraser, _, _),
             .contactMoved(.eraser, _, _),
             .contactEnded(.eraser, _):
            return []

        case .proximityExited, .buttonsChanged:
            return []
        }
    }
}
