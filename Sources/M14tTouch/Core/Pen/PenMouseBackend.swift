import CoreGraphics
import Foundation

/// Where pen actions become macOS events (pen spec §19).
protocol PenEventBackend {
    func handle(_ action: PenAction)
}

/// The fallback backend from pen spec §21: pen actions as ordinary mouse events.
///
/// Called a fallback because it cannot carry pressure — a mouse event has
/// nowhere to put it — nor say that a stroke came from the eraser end. Tablet
/// events can do both and turn out to be public API, but whether applications
/// honour synthesised ones is still unmeasured, so the thing that works
/// everywhere is what ships first.
final class PenMouseBackend: PenEventBackend {

    private let poster = CGEventPoster()
    private var configuration: PenConfiguration
    private var heldButtons: PenButtons = []

    init(configuration: PenConfiguration = PenConfiguration()) {
        self.configuration = configuration
    }

    func apply(_ configuration: PenConfiguration) {
        // Release anything the old mapping was holding, or a button mapped away
        // mid-press would stay down with nothing left to release it.
        if heldButtons.contains(.barrel) {
            release(self.configuration.barrelButton, at: lastPosition)
        }
        heldButtons = []
        self.configuration = configuration
    }

    private var lastPosition: CGPoint = .zero

    func handle(_ action: PenAction) {
        if let position = Self.position(of: action) { lastPosition = position }

        switch action {
        case .buttonsChanged(let buttons, let position):
            // Only the far button is mapped. The near one is not a button at all
            // — it is what makes a stroke an eraser stroke — and giving it an
            // action of its own would fight the tool it selects.
            let wasHeld = heldButtons.contains(.barrel)
            let isHeld = buttons.contains(.barrel)
            heldButtons = buttons
            if isHeld, !wasHeld { press(configuration.barrelButton, at: position) }
            if wasHeld, !isHeld { release(configuration.barrelButton, at: position) }

        default:
            for event in Self.mouseEvents(for: action, eraser: configuration.eraser) {
                poster.post(event.type, at: event.point)
            }
        }
    }

    // MARK: - Mapping

    /// The events an action becomes. Pure, and therefore tested.
    ///
    /// Proximity is the interesting one. Moving the pointer the moment the pen
    /// arrives is the whole fix: without it the pointer stays wherever it was —
    /// on the MacBook, most likely — and hovering over the panel drags it around
    /// a screen the pen is not near (pen spec §11).
    static func mouseEvents(
        for action: PenAction,
        eraser: PenButtonMapping = .none
    ) -> [(type: CGEventType, point: CGPoint)] {
        switch action {
        case .proximityEntered(let position), .hover(let position):
            return [(.mouseMoved, position)]

        case .contactBegan(.tip, let position, _):
            return [(.leftMouseDown, position)]
        case .contactMoved(.tip, let position, _):
            return [(.leftMouseDragged, position)]
        case .contactEnded(.tip, let position):
            return [(.leftMouseUp, position)]

        case .contactBegan(.eraser, let position, _):
            return down(eraser).map { [($0, position)] } ?? []
        case .contactMoved(.eraser, let position, _):
            return dragged(eraser).map { [($0, position)] } ?? []
        case .contactEnded(.eraser, let position):
            return up(eraser).map { [($0, position)] } ?? []

        case .proximityExited, .buttonsChanged:
            return []
        }
    }

    private func press(_ mapping: PenButtonMapping, at position: CGPoint) {
        guard let type = Self.down(mapping) else { return }
        poster.post(type, at: position)
    }

    private func release(_ mapping: PenButtonMapping, at position: CGPoint) {
        guard let type = Self.up(mapping) else { return }
        poster.post(type, at: position)
    }

    /// Down and up rather than a synthetic click pair, so holding the button
    /// holds the button — which is what a context menu expects.
    static func down(_ mapping: PenButtonMapping) -> CGEventType? {
        switch mapping {
        case .none:        return nil
        case .leftClick:   return .leftMouseDown
        case .rightClick:  return .rightMouseDown
        case .middleClick: return .otherMouseDown
        }
    }

    static func up(_ mapping: PenButtonMapping) -> CGEventType? {
        switch mapping {
        case .none:        return nil
        case .leftClick:   return .leftMouseUp
        case .rightClick:  return .rightMouseUp
        case .middleClick: return .otherMouseUp
        }
    }

    static func dragged(_ mapping: PenButtonMapping) -> CGEventType? {
        switch mapping {
        case .none:        return nil
        case .leftClick:   return .leftMouseDragged
        case .rightClick:  return .rightMouseDragged
        case .middleClick: return .otherMouseDragged
        }
    }

    private static func position(of action: PenAction) -> CGPoint? {
        switch action {
        case .proximityEntered(let p), .hover(let p),
             .contactBegan(_, let p, _), .contactMoved(_, let p, _),
             .contactEnded(_, let p), .buttonsChanged(_, let p):
            return p
        case .proximityExited:
            return nil
        }
    }
}
